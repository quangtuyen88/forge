import Foundation
import Observation
import UIKit
import ForgeCore

/// Hands-free continuous listening. Consumes a `VoiceInputPipeline` — the OS seam — and
/// owns state, endpointing and telemetry. No `Speech` or `AVFoundation` type appears in
/// this file's command handling; the pipeline adapters own the OS APIs.
///
/// Pre-roll: the pipeline adapters feed the analyzer continuously, so the
/// `VoiceTiming.preRoll` of audio before speech is already in the stream (the iOS 27
/// capture provider buffers it, and the iOS 26 manual tap is also continuous). There is
/// deliberately no buffer-and-flush here — re-yielding that window would transcribe the
/// onset twice.
@Observable
@MainActor
final class VoiceControl {
  enum State: Equatable {
    case off, arming, listening, hearing, thinking
    case failed(String)
  }

  private(set) var state: State = .off
  /// Live text while the lifter speaks; empty between utterances.
  private(set) var partial: String = ""
  /// Set when the microphone is unavailable or permission is refused.
  private(set) var unavailableReason: String?

  var onPartial: ((String) -> Void)?
  /// The finished utterance plus the id the pipeline assigned it, so the caller can
  /// commit each utterance exactly once.
  var onUtterance: ((String, UUID) -> Void)?

  private var currentUtteranceID: UUID?
  private var pipeline: (any VoiceInputPipeline)?
  /// True when the factory picked an analyzer pipeline — it only does for analyzer-supported
  /// locales — so a `.noOnDeviceModel` from it means a genuine model-download failure.
  private var usesAnalyzerPipeline = false
  private var eventTask: Task<Void, Never>?
  private var backgroundObserver: NSObjectProtocol?

  // Endpointer state.
  private var finalized = ""
  private var lastPartial = ""
  private var speechStartedAt: Date?
  private var speechEndedAt: Date?
  private var silenceTask: Task<Void, Never>?
  private var hardCapTask: Task<Void, Never>?

  // Telemetry, reported once per session on stop.
  private var utterancesHeard = 0
  private var commandsParsed = 0
  private var unrecognised = 0
  private var readyLatencyMs: [Int] = []

  // MARK: start / stop

  func start(vocabulary: [String]) async {
    switch state {
    case .off, .failed:
      break
    default:
      return
    }
    state = .arming
    unavailableReason = nil
    utterancesHeard = 0
    commandsParsed = 0
    unrecognised = 0
    readyLatencyMs = []

    installBackgroundObserver()

    let pipeline = await VoicePipelineFactory.make()
    self.pipeline = pipeline
    if #available(iOS 26, *) {
      usesAnalyzerPipeline = await VoicePipelineFactory.hasOnDeviceAnalyzerModel()
    }

    eventTask = Task { [weak self] in
      for await event in pipeline.events {
        guard !Task.isCancelled else { return }
        self?.handle(event)
      }
    }

    await pipeline.start(vocabulary: vocabulary)
    // The pipeline reports failure through `.unavailable`; only reach `.listening` if no
    // failure has been signalled by the time setup returns.
    if case .arming = state {
      state = .listening
    }
  }

  func stop() {
    silenceTask?.cancel()
    hardCapTask?.cancel()
    eventTask?.cancel()
    if let backgroundObserver {
      NotificationCenter.default.removeObserver(backgroundObserver)
    }
    backgroundObserver = nil

    let hadSession = pipeline != nil
    let pipeline = self.pipeline
    self.pipeline = nil
    Task { await pipeline?.stop() }

    if hadSession {
      reportTelemetry()
    }

    resetUtterance()
    state = .off
  }

  /// The app reports whether a finalized utterance parsed into a command, for tuning.
  func noteParseResult(recognised: Bool) {
    if recognised { commandsParsed += 1 } else { unrecognised += 1 }
  }

  // MARK: events → state + endpointing

  private func handle(_ event: VoiceEvent) {
    switch event {
    case .speechStarted:
      speechStartedAt = .now
      speechEndedAt = nil
      silenceTask?.cancel()
      hardCapTask?.cancel()
      hardCapTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(VoiceTiming.commandHardCap))
        guard !Task.isCancelled else { return }
        self?.finalizeUtterance()
      }
      state = .hearing

    case .partialTranscript(let text, let id):
      currentUtteranceID = id
      lastPartial = text
      publishPartial()
      onPartial?(partial)

    case .finalTranscript(let text, let id):
      currentUtteranceID = id
      finalized += text.isEmpty ? "" : text + " "
      publishPartial()
      onPartial?(partial)

    case .speechEnded:
      speechEndedAt = .now
      hardCapTask?.cancel()
      state = .listening
      silenceTask?.cancel()
      silenceTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(VoiceTiming.silenceToFinalize))
        guard !Task.isCancelled else { return }
        self?.finalizeUtterance()
      }

    case .unavailable(let reason):
      let message = message(for: reason)
      unavailableReason = message
      state = .failed(message)
    }
  }

  private func publishPartial() {
    partial = (finalized + lastPartial).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func finalizeUtterance() {
    silenceTask?.cancel()
    hardCapTask?.cancel()
    silenceTask = nil
    hardCapTask = nil

    // Ignore utterances shorter than minSpeech of actual speech.
    if let start = speechStartedAt {
      let end = speechEndedAt ?? .now
      if end.timeIntervalSince(start) < VoiceTiming.minSpeech {
        resetUtterance()
        return
      }
    }

    let text = (finalized + lastPartial).trimmingCharacters(in: .whitespacesAndNewlines)
    let ended = speechEndedAt
    let id = currentUtteranceID ?? UUID()
    resetUtterance()
    guard !text.isEmpty else { return }

    utterancesHeard += 1
    if let ended {
      readyLatencyMs.append(Int(Date.now.timeIntervalSince(ended) * 1000))
    }
    state = .listening
    onUtterance?(text, id)
  }

  private func resetUtterance() {
    currentUtteranceID = nil
    finalized = ""
    lastPartial = ""
    partial = ""
    speechStartedAt = nil
    speechEndedAt = nil
  }

  private func message(for reason: VoiceUnavailableReason) -> String {
    switch reason {
    case .permissionDenied:
      return SpeechInput.permissionMessage
    case .noOnDeviceModel:
      // Analyzer pipelines run only for supported locales; their `.noOnDeviceModel` is a
      // download failure. From the legacy pipeline it means the language has no model.
      return usesAnalyzerPipeline ? SpeechInput.modelDownloadMessage : SpeechInput.noOnDeviceModelMessage()
    case .unsupportedLocale:
      return SpeechInput.dictationOffMessage
    case .audioSessionFailed:
      return "Couldn't start listening. Try again."
    }
  }

  private func installBackgroundObserver() {
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.stop() }
    }
  }

  private func reportTelemetry() {
    let avgMs = readyLatencyMs.isEmpty ? 0 : readyLatencyMs.reduce(0, +) / readyLatencyMs.count
    Analytics.track("voice_session", [
      "utterances": "\(utterancesHeard)",
      "commandsParsed": "\(commandsParsed)",
      "unrecognised": "\(unrecognised)",
      "speechEndToReadyMs": "\(avgMs)",
    ])
  }
}
