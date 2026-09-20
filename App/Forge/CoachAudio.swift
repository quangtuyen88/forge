import AVFoundation
import Foundation
import Observation
import SwiftUI

/// The three spoken-guidance levels. Stored under `@AppStorage("coachAudioMode")`.
enum CoachAudioMode: String, CaseIterable, Identifiable, Sendable {
  case off, minimal, standard

  var id: String { rawValue }

  var name: String {
    switch self {
    case .off: return String(localized: "Off", bundle: L10n.bundle)
    case .minimal: return String(localized: "Minimal", bundle: L10n.bundle)
    case .standard: return String(localized: "Standard", bundle: L10n.bundle)
    }
  }
}

/// Speaks already-committed workout state back to the lifter with on-device speech.
///
/// It is a pure narrator: every utterance is built from values the caller passes in and
/// has already shown on screen. It never computes a load, never reads the training engine
/// and never speaks a draft as if it were applied.
@MainActor
@Observable
final class CoachAudioCoordinator {
  enum Priority: Int, Comparable {
    case low = 0, normal = 1, high = 2
    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  private struct Cue {
    let id: String
    let revision: Int
    let priority: Priority
    let expiresAt: Date
    let speech: String
  }

  static let modeKey = "coachAudioMode"
  static let muteKey = "coachAudioMuted"
  static let maxQueue = 6

  private var synthesizer = AVSpeechSynthesizer()
  private var delegate: SynthDelegate?
  private var queue: [Cue] = []
  private var spokenIDs: Set<String> = []
  private var currentRevision = 0
  private var sessionActive = false
  private var paused = false
  private var observers: [NSObjectProtocol] = []

  /// The last utterance handed to the synthesizer, kept for repeat.
  private(set) var lastSpeech: String?
  private(set) var isSpeaking = false
  private(set) var muted = UserDefaults.standard.bool(forKey: CoachAudioCoordinator.muteKey)

  var mode: CoachAudioMode {
    CoachAudioMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .off
  }

  init() {
    let delegate = SynthDelegate(coordinator: self)
    self.delegate = delegate
    synthesizer.delegate = delegate
    installObservers()
  }

  // MARK: - Public API

  /// "Bench press. Set two. 85 kilograms, six to eight reps." The prescription that just
  /// became current. Minimal and Standard.
  func announceNextSet(
    eventID: String,
    revision: Int,
    exercise: String,
    setIndex: Int,
    load: String,
    minReps: Int,
    maxReps: Int
  ) {
    let speech = String(
      localized: "\(exercise). Set \(setIndex). \(load), \(minReps) to \(maxReps) reps.",
      bundle: L10n.bundle)
    enqueue(id: eventID, revision: revision, priority: .high, speech: speech)
  }

  /// "Next set is ready." Spoken when the rest timer hits zero. Minimal and Standard.
  func announceRestFinished(eventID: String, revision: Int) {
    enqueue(
      id: eventID, revision: revision, priority: .high,
      speech: String(localized: "Next set is ready.", bundle: L10n.bundle))
  }

  /// Short acknowledgement after a committed set. Standard only.
  func announceSetLogged(eventID: String, revision: Int, setIndex: Int) {
    guard mode == .standard else { return }
    enqueue(
      id: eventID, revision: revision, priority: .low,
      speech: String(localized: "Set \(setIndex) logged.", bundle: L10n.bundle))
  }

  /// Brief next-exercise introduction. Standard only.
  func announceExerciseChange(
    eventID: String,
    revision: Int,
    exercise: String,
    sets: Int,
    minReps: Int,
    maxReps: Int
  ) {
    guard mode == .standard else { return }
    let speech = String(
      localized: "Next: \(exercise). \(sets) sets of \(minReps) to \(maxReps) reps.",
      bundle: L10n.bundle)
    enqueue(id: eventID, revision: revision, priority: .normal, speech: speech)
  }

  func setMuted(_ value: Bool) {
    muted = value
    UserDefaults.standard.set(value, forKey: Self.muteKey)
    if value { stop() }
  }

  func toggleMuted() { setMuted(!muted) }

  /// Re-speaks the most recent utterance immediately, bypassing the dedup queue.
  func repeatLast() {
    guard mode != .off, !muted, let lastSpeech, !lastSpeech.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    queue.removeAll()
    isSpeaking = true
    activateSession()
    synthesizer.speak(makeUtterance(lastSpeech))
  }

  /// Drops every queued cue and the current utterance. Used when the workout is discarded,
  /// finished, a rest is skipped, or the prescription changed so stale speech must stop.
  func clear() { stop() }

  func scenePhaseChanged(_ phase: ScenePhase) {
    if phase == .background { stop() }
  }

  /// Stops speech and removes notification observers. Call once when the workout leaves.
  func tearDown() {
    stop()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
  }

  // MARK: - Queue

  private func enqueue(
    id: String,
    revision: Int,
    priority: Priority,
    expiresIn: TimeInterval = 30,
    speech: String
  ) {
    guard mode != .off, !muted, !speech.isEmpty else { return }
    // Duplicate event ids never speak twice.
    guard !spokenIDs.contains(id), !queue.contains(where: { $0.id == id }) else { return }
    // A cue older than the newest plan/session revision is superseded and dropped.
    guard revision >= currentRevision else { return }
    if revision > currentRevision {
      currentRevision = revision
      queue.removeAll { $0.revision < revision }
    }
    let cue = Cue(
      id: id, revision: revision, priority: priority,
      expiresAt: Date.now.addingTimeInterval(expiresIn), speech: speech)
    if queue.count >= Self.maxQueue {
      // Bounded queue: evict the oldest low-priority cue, else the oldest.
      if let stale = queue.firstIndex(where: { $0.priority == .low }) {
        queue.remove(at: stale)
      } else {
        queue.removeFirst()
      }
    }
    queue.append(cue)
    pump()
  }

  private func pump() {
    guard !isSpeaking, !paused else { return }
    speakNext()
  }

  private func speakNext() {
    let now = Date.now
    while let first = queue.first, first.expiresAt <= now {
      queue.removeFirst()
    }
    guard let cue = queue.first else {
      isSpeaking = false
      deactivateSession()
      return
    }
    queue.removeFirst()
    spokenIDs.insert(cue.id)
    isSpeaking = true
    lastSpeech = cue.speech
    activateSession()
    synthesizer.speak(makeUtterance(cue.speech))
  }

  private func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    queue.removeAll()
    isSpeaking = false
    paused = false
    deactivateSession()
  }

  fileprivate func didFinishUtterance() {
    isSpeaking = false
    speakNext()
  }

  // MARK: - Utterances & voices

  private func makeUtterance(_ text: String) -> AVSpeechUtterance {
    let utterance = AVSpeechUtterance(string: text)
    if let voice = Self.voice(for: L10n.languageCode) {
      utterance.voice = voice
    }
    return utterance
  }

  /// The device voice for the app language, or nil to fall back silently to the system voice.
  private static func voice(for languageCode: String) -> AVSpeechSynthesisVoice? {
    let tag: String
    switch languageCode {
    case "ja": tag = "ja-JP"
    case "ko": tag = "ko-KR"
    case "vi": tag = "vi-VN"
    default: tag = "en-US"
    }
    return AVSpeechSynthesisVoice(language: tag)
  }

  // MARK: - Audio session

  private func activateSession() {
    guard !sessionActive else { return }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
    try? session.setActive(true)
    sessionActive = true
  }

  private func deactivateSession() {
    guard sessionActive else { return }
    sessionActive = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Notifications

  private func installObservers() {
    let nc = NotificationCenter.default
    observers = [
      nc.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        Task { @MainActor in self?.handleInterruption(note) }
      },
      nc.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] note in
        Task { @MainActor in self?.handleRouteChange(note) }
      },
      nc.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.rebuildSynthesizer() }
      },
    ]
  }

  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    if type == .began {
      paused = true
      synthesizer.pauseSpeaking(at: .word)
      isSpeaking = false
      return
    }
    let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
    if options.contains(.shouldResume), !muted {
      paused = false
      synthesizer.continueSpeaking()
      isSpeaking = true
    } else {
      stop()
    }
  }

  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
      reason == .oldDeviceUnavailable
    else { return }
    stop()
  }

  private func rebuildSynthesizer() {
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer = AVSpeechSynthesizer()
    synthesizer.delegate = delegate
    queue.removeAll()
    isSpeaking = false
    paused = false
    deactivateSession()
  }
}

/// Non-isolated trampoline so `AVSpeechSynthesizer` callbacks — which may arrive on an
/// arbitrary thread — hop back onto the coordinator's main actor.
private final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
  weak var coordinator: CoachAudioCoordinator?

  init(coordinator: CoachAudioCoordinator) {
    self.coordinator = coordinator
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard let coordinator else { return }
    Task { @MainActor in coordinator.didFinishUtterance() }
  }
}
