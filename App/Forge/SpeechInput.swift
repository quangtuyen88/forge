import Foundation
import Speech
import AVFoundation
import Observation

/// Wraps speech recognition + AVAudioEngine for hands-free dictation in the coach chat.
///
/// On iOS 26+ this uses `SpeechAnalyzer` + `SpeechTranscriber` (on-device, app-managed
/// assets) so dictation keeps working when the system Dictation switch is off. Older
/// iOS keeps the `SFSpeechRecognizer` path unchanged.
@MainActor @Observable final class SpeechInput {
  var transcript = ""
  var isListening = false
  var errorText: String?
  var isPreparing = false

  private var recognizer: SFSpeechRecognizer?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var autoStop: Task<Void, Never>?
  private var stopping = false

  /// Boxed `SpeechAnalyzerSession` (iOS 26+). `AnyObject` keeps this stored property
  /// free of an `@available` attribute, which `@Observable` forbids on stored properties.
  @ObservationIgnored private var analyzerSession: AnyObject?

  private static let permissionMessage = "Microphone or speech permission is off. Enable it in Settings."
  private static let modelDownloadMessage = "Couldn't download the speech model. Check your connection and try again."
  private static let dictationOffMessage = "Turn on Dictation: Settings → General → Keyboard → Enable Dictation."

  init() {
    recognizer = SFSpeechRecognizer(locale: Self.bestLocale())
  }

  var isAvailable: Bool {
    if #available(iOS 26, *) {
      return true
    }
    return recognizer?.isAvailable ?? false
  }

  // MARK: locale selection

  /// Picks the best locale from `supported` for speech recognition.
  ///
  /// If the user's current locale is directly supported, use it. Otherwise fall
  /// back to a supported locale sharing the same language, preferring well-known
  /// variants, and finally to `en-US`.
  private static func pickLocale<S: Sequence>(from supported: S) -> Locale where S.Element == Locale {
    let normalizedID: (Locale) -> String = {
      $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    let current = Locale.current
    if supported.contains(where: { normalizedID($0) == normalizedID(current) }) {
      return current
    }

    let currentLanguage = current.language.languageCode?.identifier.lowercased()
    let preferred: [String: String] = [
      "en": "en-US",
      "ja": "ja-JP",
      "ko": "ko-KR",
      "zh": "zh-CN",
      "zh-hans": "zh-CN",
      "vi": "vi-VN",
    ]

    if let currentLanguage {
      if let preferredID = preferred[currentLanguage],
         let match = supported.first(where: { normalizedID($0) == preferredID.lowercased() }) {
        return match
      }
      if let match = supported.first(where: { $0.language.languageCode?.identifier.lowercased() == currentLanguage }) {
        return match
      }
    }

    if let enUS = supported.first(where: { normalizedID($0) == "en-us" }) {
      return enUS
    }
    return Locale(identifier: "en-US")
  }

  private static func bestLocale() -> Locale {
    pickLocale(from: SFSpeechRecognizer.supportedLocales())
  }

  private static let dictationLocaleIDs: [String: String] = [
    "en": "en-US",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "zh-Hans": "zh-CN",
    "vi": "vi-VN",
  ]

  /// Returns the locale forced by the Dictation language setting, or nil for "auto".
  private static func requestedLocale() -> Locale? {
    let stored = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "auto"
    guard stored != "auto" else { return nil }
    return Locale(identifier: dictationLocaleIDs[stored] ?? stored)
  }

  private static func recognizerLocale() -> Locale {
    requestedLocale() ?? bestLocale()
  }

  @available(iOS 26, *)
  private static func analyzerBestLocale() async -> Locale {
    if let forced = requestedLocale() { return forced }
    return pickLocale(from: await SpeechTranscriber.supportedLocales)
  }

  // MARK: errors

  private func setNonPermissionError(_ error: Error? = nil) {
    if let error,
       error.localizedDescription.localizedCaseInsensitiveContains("Dictation")
        || error.localizedDescription.localizedCaseInsensitiveContains("Siri") {
      errorText = Self.dictationOffMessage
    } else {
#if DEBUG
      if let error {
        errorText = String(localized: "Couldn't start listening. Try again.") + " (\(error.localizedDescription))"
      } else {
        errorText = String(localized: "Couldn't start listening. Try again.")
      }
#else
      errorText = String(localized: "Couldn't start listening. Try again.")
#endif
    }
  }

  // MARK: start / stop

  func start() async {
    guard !isListening, !isPreparing else { return }
    recognizer = SFSpeechRecognizer(locale: Self.recognizerLocale())
    if #available(iOS 26, *) {
      await startAnalyzer()
    } else {
      await startLegacy()
    }
  }

  @available(iOS 26, *)
  private func startAnalyzer() async {
    let micGranted = await AVAudioApplication.requestRecordPermission()
    guard micGranted else {
      errorText = Self.permissionMessage
      return
    }

    let locale = await Self.analyzerBestLocale()
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    #if DEBUG
    SpeechLog.shared.add("speech: analyzer locale \(locale.identifier)")
    #endif

    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        errorText = nil
        isPreparing = true
        try await request.downloadAndInstall()
        isPreparing = false
      }
    } catch {
      isPreparing = false
      errorText = Self.modelDownloadMessage
      return
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      setNonPermissionError()
      return
    }
    #if DEBUG
    SpeechLog.shared.add("speech: analyzer format \(format)")
    #endif

    do {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      } catch {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
      }
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      setNonPermissionError(error)
      return
    }

    let inputNode = engine.inputNode
    let nodeFormat = inputNode.outputFormat(forBus: 0)

    guard let converter = AVAudioConverter(from: nodeFormat, to: format) else {
      setNonPermissionError()
      return
    }

    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    let session = SpeechAnalyzerSession(analyzer: analyzer, transcriber: transcriber)
    session.converter = converter
    session.inputContinuation = continuation
    analyzerSession = session

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: nodeFormat) { [weak session] buffer, _ in
      Task { @MainActor in session?.handleBuffer(buffer) }
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      setNonPermissionError(error)
      stop()
      return
    }

    transcript = ""
    isListening = true
    errorText = nil
    stopping = false

    var finalized = ""
    session.startResults { [weak self] result in
      guard let self else { return }
      let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
      #if DEBUG
      SpeechLog.shared.add("speech: result final=\(result.isFinal) '\(text)'")
      #endif
      if result.isFinal {
        finalized += text.isEmpty ? "" : text + " "
        self.transcript = finalized
      } else {
        self.transcript = finalized + text
      }
    }

    do {
      try await analyzer.start(inputSequence: stream)
      #if DEBUG
      SpeechLog.shared.add("speech: analyzer started")
      #endif
    } catch {
      #if DEBUG
      SpeechLog.shared.add("speech: analyzer start failed \(error)")
      #endif
      setNonPermissionError(error)
      stop()
      return
    }

    autoStop = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      guard !Task.isCancelled else { return }
      self?.stop()
    }
  }

  private func startLegacy() async {
    guard let recognizer, recognizer.isAvailable else {
      setNonPermissionError()
      return
    }
    let speechAuth = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    let micGranted = await AVAudioApplication.requestRecordPermission()
    guard speechAuth == .authorized, micGranted else {
      errorText = Self.permissionMessage
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      } catch {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
      }
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      setNonPermissionError(error)
      return
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.taskHint = .dictation
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    self.request = request

    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      Task { @MainActor in self?.request?.append(buffer) }
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      setNonPermissionError(error)
      stop()
      return
    }

    transcript = ""
    isListening = true
    errorText = nil
    stopping = false

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor in
        guard let self else { return }
        if let result {
          self.transcript = result.bestTranscription.formattedString
        }
        if let error, !self.stopping, result?.isFinal != true {
          self.setNonPermissionError(error)
          self.stop()
        }
      }
    }

    autoStop = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      guard !Task.isCancelled else { return }
      self?.stop()
    }
  }

  func stop() {
    stopping = true
    autoStop?.cancel()
    autoStop = nil
    if #available(iOS 26, *) {
      (analyzerSession as? SpeechAnalyzerSession)?.finish()
      analyzerSession = nil
    }
    request?.endAudio()
    recognitionTask?.finish()
    recognitionTask = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    request = nil
    isPreparing = false
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

/// Holds the iOS 26+ `SpeechAnalyzer` / `SpeechTranscriber` machinery.
@available(iOS 26, *)
@MainActor
final class SpeechAnalyzerSession {
  let analyzer: SpeechAnalyzer
  let transcriber: SpeechTranscriber
  var converter: AVAudioConverter?
  var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultsTask: Task<Void, Never>?

  init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber) {
    self.analyzer = analyzer
    self.transcriber = transcriber
  }

  func handleBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let converter, let inputContinuation else { return }
    let outputFormat = converter.outputFormat
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

    var error: NSError?
    var supplied = false
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      if supplied {
        outStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard error == nil, status != .error else {
      #if DEBUG
      SpeechLog.shared.add("speech: convert failed status=\(status.rawValue) error=\(String(describing: error))")
      #endif
      return
    }
    buffersYielded += 1
    #if DEBUG
    if buffersYielded % 50 == 1 { SpeechLog.shared.add("speech: buffer #\(buffersYielded) frames=\(output.frameLength)") }
    #endif
    inputContinuation.yield(AnalyzerInput(buffer: output))
  }

  private var buffersYielded = 0

  func startResults(consume: @escaping (SpeechTranscriber.Result) -> Void) {
    let transcriber = self.transcriber
    resultsTask = Task {
      do {
        for try await result in transcriber.results {
          consume(result)
        }
      } catch {
        #if DEBUG
        SpeechLog.shared.add("speech: results ended \(error)")
        #endif
      }
    }
  }

  func finish() {
    inputContinuation?.finish()
    inputContinuation = nil
    let analyzer = self.analyzer
    let task = resultsTask
    resultsTask = nil
    Task {
      do {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        SpeechLog.shared.add("speech: finalized")
      } catch {
        SpeechLog.shared.add("speech: finalize failed \(error)")
      }
      task?.cancel()
    }
  }
}

/// Debug-only trace of the dictation pipeline, shown under the mic in Debug builds.
@MainActor @Observable final class SpeechLog {
  static let shared = SpeechLog()
  var text = ""
  func add(_ line: String) {
    #if DEBUG
    print(line)
    text = String((text + line + "\n").suffix(700))
    #endif
  }
}
