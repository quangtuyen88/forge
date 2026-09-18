import Foundation
import Speech
import AVFoundation
import ForgeCore

// MARK: - Factory

/// Picks the richest adapter whose capability is actually present on this device, never
/// by OS version alone. Each probe is side-effect free; permission and audio startup
/// happen in `start()`, where failures surface as `.unavailable` events.
@MainActor
enum VoicePipelineFactory {
  static func make() async -> VoiceInputPipeline {
    if #available(iOS 27, *), await hasOnDeviceAnalyzerModel() {
      return iOS27CapturePipeline()
    }
    if #available(iOS 26, *), await hasOnDeviceAnalyzerModel() {
      return iOS26AnalyzerPipeline()
    }
    return LegacySFSpeechPipeline()
  }

  /// An empty `supportedLocales` means this device has no on-device speech models.
  /// Otherwise `analyzerBestLocale()` returns a member of that set by construction.
  /// Also read by `VoiceControl`: an analyzer pipeline is returned only when this is
  /// true, so `.noOnDeviceModel` from it means a genuine download failure.
  @available(iOS 26, *)
  static func hasOnDeviceAnalyzerModel() async -> Bool {
    await SpeechInput.analyzerSupports(SpeechInput.analyzerBestLocale())
  }
}

// MARK: - Shared pieces

/// Reads `SpeechTranscriber` and `SpeechDetector` results and translates them into the
/// common `VoiceEvent` stream. One utteranceID is minted at the false→true speech
/// transition and reused for every partial and final until the next utterance.
@available(iOS 26, *)
@MainActor
final class AnalyzerEventReader {
  private let continuation: AsyncStream<VoiceEvent>.Continuation
  private let transcriber: SpeechTranscriber
  private let detector: SpeechDetector
  private var currentUtteranceID: UUID?
  private var lastSpeechDetected: Bool?
  private var transcriberTask: Task<Void, Never>?
  private var detectorTask: Task<Void, Never>?

  init(continuation: AsyncStream<VoiceEvent>.Continuation, transcriber: SpeechTranscriber, detector: SpeechDetector) {
    self.continuation = continuation
    self.transcriber = transcriber
    self.detector = detector
  }

  func start() {
    let transcriber = self.transcriber
    transcriberTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self else { return }
          let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
          let id = self.utteranceID()
          if result.isFinal {
            self.continuation.yield(.finalTranscript(text, utteranceID: id))
          } else {
            self.continuation.yield(.partialTranscript(text, utteranceID: id))
          }
        }
      } catch {
        SpeechLog.shared.add("voice: transcriber results ended \(error)")
      }
    }
    let detector = self.detector
    detectorTask = Task { [weak self] in
      do {
        for try await result in detector.results {
          guard let self else { return }
          let speaking = result.speechDetected
          if speaking, self.lastSpeechDetected != true {
            self.currentUtteranceID = UUID()
            self.continuation.yield(.speechStarted)
          } else if !speaking, self.lastSpeechDetected == true {
            self.continuation.yield(.speechEnded)
          }
          self.lastSpeechDetected = speaking
        }
      } catch {
        SpeechLog.shared.add("voice: detector results ended \(error)")
      }
    }
  }

  func finish() {
    transcriberTask?.cancel()
    detectorTask?.cancel()
    transcriberTask = nil
    detectorTask = nil
  }

  private func utteranceID() -> UUID {
    if let currentUtteranceID { return currentUtteranceID }
    let id = UUID()
    currentUtteranceID = id
    return id
  }
}

/// Re-activates the audio session when an interruption or route change ends.
@MainActor
final class AudioSessionGuard {
  private var observers: [NSObjectProtocol] = []
  private let resume: @MainActor () -> Void

  init(resume: @escaping @MainActor () -> Void) {
    self.resume = resume
  }

  func install() {
    remove()
    let nc = NotificationCenter.default
    observers = [
      nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
        Task { @MainActor in self?.handleInterruption(note) }
      },
      nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
        Task { @MainActor in self?.handleRouteChange(note) }
      },
    ]
  }

  func remove() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
  }

  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw), type == .ended else { return }
    try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    resume()
  }

  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
          reason == .oldDeviceUnavailable else { return }
    resume()
  }
}

// MARK: - iOS 27 capture provider

@available(iOS 27, *)
@MainActor
final class iOS27CapturePipeline: VoiceInputPipeline {
  private let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
  var events: AsyncStream<VoiceEvent> { stream }

  private var provider: CaptureInputSequenceProvider?
  private var analyzer: SpeechAnalyzer?
  private var reader: AnalyzerEventReader?
  private var sessionGuard: AudioSessionGuard?

  func start(vocabulary: [String]) async {
    guard await AVAudioApplication.requestRecordPermission() else {
      continuation.yield(.unavailable(reason: .permissionDenied))
      return
    }
    guard let device = AVCaptureDevice.default(for: .audio) else {
      continuation.yield(.unavailable(reason: .audioSessionFailed("no audio input")))
      return
    }

    let locale = await SpeechInput.analyzerBestLocale()
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)

    do {
      try await SpeechAssets.installIfNeeded(for: [transcriber, detector])
    } catch {
      continuation.yield(.unavailable(reason: .noOnDeviceModel))
      return
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
    await analyzer.applyVocabulary(vocabulary)

    do {
      let provider = try await CaptureInputSequenceProvider.providerWithSession(
        from: device, compatibleWith: [transcriber, detector], priority: nil)
      self.provider = provider
      self.analyzer = analyzer
      // Pre-roll is inherent: the capture provider supplies continuous audio, so the
      // ~VoiceTiming.preRoll before speech is already buffered — no manual double-buffer.
      let reader = AnalyzerEventReader(continuation: continuation, transcriber: transcriber, detector: detector)
      self.reader = reader
      let sessionGuard = AudioSessionGuard { [weak self] in self?.provider?.captureSession.startRunning() }
      self.sessionGuard = sessionGuard
      sessionGuard.install()
      provider.captureSession.startRunning()
      reader.start()
      try await analyzer.start(inputSequence: provider.analyzerInputs)
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      await stop()
    }
  }

  func stop() async {
    reader?.finish()
    reader = nil
    sessionGuard?.remove()
    sessionGuard = nil
    provider?.captureSession.stopRunning()
    provider = nil
    if let analyzer {
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }
    analyzer = nil
    continuation.finish()
  }
}

// MARK: - iOS 26 manual engine

@available(iOS 26, *)
@MainActor
final class iOS26AnalyzerPipeline: VoiceInputPipeline {
  private let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
  var events: AsyncStream<VoiceEvent> { stream }

  private let engine = AVAudioEngine()
  private var analyzer: SpeechAnalyzer?
  private var reader: AnalyzerEventReader?
  private var audioPipeline: AnalyzerAudioPipeline?
  private var sessionGuard: AudioSessionGuard?

  func start(vocabulary: [String]) async {
    guard await AVAudioApplication.requestRecordPermission() else {
      continuation.yield(.unavailable(reason: .permissionDenied))
      return
    }

    let locale = await SpeechInput.analyzerBestLocale()
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)

    do {
      try await SpeechAssets.installIfNeeded(for: [transcriber, detector])
    } catch {
      continuation.yield(.unavailable(reason: .noOnDeviceModel))
      return
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber, detector])
    await analyzer.applyVocabulary(vocabulary)

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber, detector]) else {
      continuation.yield(.unavailable(reason: .noOnDeviceModel))
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      return
    }

    guard let audioPipeline = AnalyzerAudioPipeline(engine: engine, format: format) else {
      continuation.yield(.unavailable(reason: .audioSessionFailed("no converter")))
      return
    }
    self.audioPipeline = audioPipeline
    // Pre-roll is inherent: the tap feeds the analyzer continuously, so the
    // ~VoiceTiming.preRoll before speech is already in the stream — re-yielding it
    // (a buffer-and-flush) would feed the transcriber the onset twice.

    let reader = AnalyzerEventReader(continuation: continuation, transcriber: transcriber, detector: detector)
    self.reader = reader

    let sessionGuard = AudioSessionGuard { [weak self] in self?.resumeEngine() }
    self.sessionGuard = sessionGuard
    sessionGuard.install()

    do {
      try audioPipeline.start()
      reader.start()
      try await analyzer.start(inputSequence: audioPipeline.stream)
      self.analyzer = analyzer
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      await stop()
    }
  }

  func stop() async {
    reader?.finish()
    reader = nil
    sessionGuard?.remove()
    sessionGuard = nil
    audioPipeline?.continuation.finish()
    audioPipeline = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    if let analyzer {
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }
    analyzer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    continuation.finish()
  }

  private func resumeEngine() {
    try? engine.start()
  }
}

// MARK: - Legacy SFSpeechRecognizer

@MainActor
final class LegacySFSpeechPipeline: VoiceInputPipeline {
  private let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
  var events: AsyncStream<VoiceEvent> { stream }

  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var vocabulary: [String] = []
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var sessionGuard: AudioSessionGuard?
  private var currentUtteranceID: UUID?
  private var speaking = false
  private var vadTask: Task<Void, Never>?
  private var generation = 0

  func start(vocabulary: [String]) async {
    guard await AVAudioApplication.requestRecordPermission() else {
      continuation.yield(.unavailable(reason: .permissionDenied))
      return
    }

    let recognizer = SFSpeechRecognizer(locale: SpeechInput.recognizerLocale())
    guard let recognizer, recognizer.isAvailable else {
      continuation.yield(.unavailable(reason: .unsupportedLocale))
      return
    }
    // Server-based recognition is opt-in: audio leaving the device is the lifter's business.
    guard recognizer.supportsOnDeviceRecognition
            || UserDefaults.standard.bool(forKey: "voiceAllowServerRecognition") else {
      continuation.yield(.unavailable(reason: .noOnDeviceModel))
      return
    }
    self.recognizer = recognizer
    self.vocabulary = vocabulary

    let auth = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
    }
    guard auth == .authorized else {
      continuation.yield(.unavailable(reason: .permissionDenied))
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      return
    }

    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      Task { @MainActor in self?.request?.append(buffer) }
    }

    let sessionGuard = AudioSessionGuard { [weak self] in self?.resumeEngine() }
    self.sessionGuard = sessionGuard
    sessionGuard.install()

    engine.prepare()
    do {
      try engine.start()
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      await stop()
      return
    }

    startRequest()
  }

  func stop() async {
    vadTask?.cancel()
    vadTask = nil
    sessionGuard?.remove()
    sessionGuard = nil
    request?.endAudio()
    recognitionTask?.finish()
    recognitionTask = nil
    request = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    recognizer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    continuation.finish()
  }

  private func resumeEngine() {
    try? engine.start()
  }

  private func startRequest() {
    guard let recognizer else { return }
    generation += 1
    let gen = generation
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.taskHint = .dictation
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    if !vocabulary.isEmpty {
      request.contextualStrings = Array(vocabulary.prefix(100))
    }
    self.request = request

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor in self?.handleRecognition(result: result, error: error, generation: gen) }
    }
  }

  private func restartRequest() {
    request?.endAudio()
    recognitionTask?.finish()
    recognitionTask = nil
    request = nil
    startRequest()
  }

  private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, generation gen: Int) {
    guard gen == generation else { return }  // stale callback from a superseded request
    if let result {
      let text = result.bestTranscription.formattedString
      if !speaking {
        speaking = true
        currentUtteranceID = UUID()
        continuation.yield(.speechStarted)
      }
      if let id = currentUtteranceID {
        if result.isFinal {
          continuation.yield(.finalTranscript(text, utteranceID: id))
        } else {
          continuation.yield(.partialTranscript(text, utteranceID: id))
        }
      }
      scheduleVAD()
    }
    if let error, result?.isFinal != true {
      SpeechLog.shared.add("voice: recognition error \(error)")
      restartRequest()
    }
  }

  /// Software voice-activity detection: speech ends when no new partial has arrived for
  /// `VoiceTiming.minSpeech`. Final endpointing (the silence window) still lives in VoiceControl.
  /// Appends are MainActor-deferred, so the per-utterance request restart below has no gap
  /// in which audio is lost — pre-roll is effectively inherent on this path.
  private func scheduleVAD() {
    vadTask?.cancel()
    vadTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(VoiceTiming.minSpeech))
      guard !Task.isCancelled, let self else { return }
      if self.speaking {
        self.speaking = false
        self.continuation.yield(.speechEnded)
        // SFSpeechRecognizer accumulates bestTranscription for a request's whole lifetime;
        // reset so the next utterance starts fresh.
        self.restartRequest()
      }
    }
  }
}
