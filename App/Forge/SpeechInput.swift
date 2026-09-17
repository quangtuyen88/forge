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
  /// True while a cloud clip is being sent to the coach service and transcribed.
  var isTranscribing = false
  /// Words the recognizer should favour (exercise names, lifting terms); set by the caller before `start()`.
  var vocabulary: [String] = []

  private var recognizer: SFSpeechRecognizer?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var autoStop: Task<Void, Never>?
  private var stopping = false
  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var isCloud = false
  private var preferDevice = false

  /// Boxed `SpeechAnalyzerSession` (iOS 26+). `AnyObject` keeps this stored property
  /// free of an `@available` attribute, which `@Observable` forbids on stored properties.
  @ObservationIgnored private var analyzerSession: AnyObject?

  static let permissionMessage = "Microphone or speech permission is off. Enable it in Settings."
  static let modelDownloadMessage = "Couldn't download the speech model. Check your connection and try again."
  static let dictationOffMessage = "Turn on Dictation: Settings → General → Keyboard → Enable Dictation."
  private static let cloudUnavailableMessage = "Couldn't reach the coach service; try on-device dictation in Settings."

  init() {
    recognizer = SFSpeechRecognizer(locale: Self.bestLocale())
  }

  var isAvailable: Bool {
    dictationEngine == "cloud" || devicePathAvailable
  }

  private var devicePathAvailable: Bool {
    if #available(iOS 26, *) {
      return true
    }
    return recognizer?.isAvailable ?? false
  }

  private var dictationEngine: String {
    UserDefaults.standard.string(forKey: "dictationEngine") ?? "cloud"
  }

  private var cloudLanguage: String? {
    let stored = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "auto"
    return stored == "auto" ? nil : stored
  }

  // MARK: locale selection

  /// Picks the best locale from `supported` for speech recognition.
  ///
  /// If the user's current locale is directly supported, use it. Otherwise fall
  /// back to a supported locale sharing the same language, preferring well-known
  /// variants, and finally to `en-US`.
  static func pickLocale<S: Sequence>(from supported: S) -> Locale where S.Element == Locale {
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

  static func bestLocale() -> Locale {
    pickLocale(from: SFSpeechRecognizer.supportedLocales())
  }

  static let dictationLocaleIDs: [String: String] = [
    "en": "en-US",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "zh-Hans": "zh-CN",
    "vi": "vi-VN",
  ]

  /// Returns the locale forced by the Dictation language setting, or nil for "auto".
  static func requestedLocale() -> Locale? {
    let stored = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "auto"
    guard stored != "auto" else { return nil }
    return Locale(identifier: dictationLocaleIDs[stored] ?? stored)
  }

  static func recognizerLocale() -> Locale {
    requestedLocale() ?? bestLocale()
  }

  @available(iOS 26, *)
  static func analyzerBestLocale() async -> Locale {
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
        errorText = String(localized: "Couldn't start listening. Try again.", bundle: L10n.bundle) + " (\(error.localizedDescription))"
      } else {
        errorText = String(localized: "Couldn't start listening. Try again.", bundle: L10n.bundle)
      }
#else
      errorText = String(localized: "Couldn't start listening. Try again.", bundle: L10n.bundle)
#endif
    }
  }

  // MARK: start / stop

  func start() async {
    guard !isListening, !isPreparing, !isTranscribing else { return }
    if dictationEngine == "device" {
      await startDevice()
    } else if preferDevice && devicePathAvailable {
      preferDevice = false
      await startDevice()
    } else {
      await startCloud()
    }
  }

  private func startDevice() async {
    recognizer = SFSpeechRecognizer(locale: Self.recognizerLocale())
    if #available(iOS 26, *) {
      await startAnalyzer()
    } else {
      await startLegacy()
    }
  }

  /// Records to a temp `.m4a` (AAC, 16 kHz mono) and leaves transcription to the coach service.
  private func startCloud() async {
    let micGranted = await AVAudioApplication.requestRecordPermission()
    guard micGranted else {
      errorText = Self.permissionMessage
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      setNonPermissionError(error)
      return
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("forge-dictation-\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]
    do {
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      guard recorder.record() else {
        try? FileManager.default.removeItem(at: url)
        setNonPermissionError()
        return
      }
      self.recorder = recorder
      self.recordingURL = url
      isCloud = true
    } catch {
      try? FileManager.default.removeItem(at: url)
      setNonPermissionError(error)
      return
    }
    transcript = ""
    isListening = true
    errorText = nil
    stopping = false
    autoStop = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      guard !Task.isCancelled else { return }
      self?.stop()
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
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    #if DEBUG
    SpeechLog.shared.add("speech: analyzer locale \(locale.identifier) assets \(await AssetInventory.status(forModules: [transcriber]))")
    #endif

    isPreparing = true
    do {
      try await SpeechAssets.installIfNeeded(for: [transcriber])
      isPreparing = false
    } catch {
      isPreparing = false
      errorText = Self.modelDownloadMessage
      return
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    await analyzer.applyVocabulary(vocabulary)

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      setNonPermissionError()
      return
    }
    #if DEBUG
    SpeechLog.shared.add("speech: analyzer format \(format)")
    #endif

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      #if DEBUG
      SpeechLog.shared.add("speech: route in=\(session.currentRoute.inputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")) gain=\(session.inputGain)")
      #endif
    } catch {
      setNonPermissionError(error)
      return
    }

    #if DEBUG
    SpeechLog.shared.add("speech: input node \(engine.inputNode.outputFormat(forBus: 0))")
    #endif

    guard let pipeline = AnalyzerAudioPipeline(engine: engine, format: format) else {
      setNonPermissionError()
      return
    }

    let session = SpeechAnalyzerSession(analyzer: analyzer, transcriber: transcriber)
    session.converter = pipeline.converter
    session.inputContinuation = pipeline.continuation
    analyzerSession = session

    do {
      try pipeline.start()
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
      try await analyzer.start(inputSequence: pipeline.stream)
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
    if isCloud {
      isCloud = false
      recorder?.stop()
      recorder = nil
      let url = recordingURL
      recordingURL = nil
      isListening = false
      isPreparing = false
      isTranscribing = true
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      if let url { Task { await finishCloudRecording(from: url) } }
      return
    }
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

  private func finishCloudRecording(from url: URL) async {
    defer {
      isTranscribing = false
      try? FileManager.default.removeItem(at: url)
    }
    do {
      let audio = try Data(contentsOf: url)
      let text = try await CoachAPI.transcribe(
        audio: audio,
        mimeType: "audio/mp4",
        language: cloudLanguage,
        prompt: Array(vocabulary.prefix(80)))
      transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      errorText = Self.cloudUnavailableMessage
      preferDevice = devicePathAvailable
    }
  }
}


/// Converts tap buffers and feeds the analyzer synchronously on the audio thread
/// (the engine reuses tap buffers right after the callback returns).
@available(iOS 26, *)
final class AudioFeeder: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let continuation: AsyncStream<AnalyzerInput>.Continuation
  private var count = 0

  init(converter: AVAudioConverter, continuation: AsyncStream<AnalyzerInput>.Continuation) {
    self.converter = converter
    self.continuation = continuation
  }

  func feed(_ buffer: AVAudioPCMBuffer) {
    let outputFormat = converter.outputFormat
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
    var error: NSError?
    var supplied = false
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      if supplied { outStatus.pointee = .noDataNow; return nil }
      supplied = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, output.frameLength > 0 else { return }
    count += 1
    #if DEBUG
    if count % 50 == 1 {
      var acc: Float = 0
      if let f = buffer.floatChannelData { for i in 0..<Int(buffer.frameLength) { acc += f[0][i] * f[0][i] } }
      let rms = (acc / Float(max(1, buffer.frameLength))).squareRoot()
      let msg = String(format: "speech: buffer #%d in=%df rms=%.4f out=%df", count, Int(buffer.frameLength), rms, Int(output.frameLength))
      Task { @MainActor in SpeechLog.shared.add(msg) }
    }
    #endif
    continuation.yield(AnalyzerInput(buffer: output))
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
    if buffersYielded % 50 == 1 {
      func rms(_ b: AVAudioPCMBuffer) -> String {
        let n = Int(b.frameLength); guard n > 0 else { return "empty" }
        if let f = b.floatChannelData { var acc: Float = 0; for i in 0..<n { acc += f[0][i] * f[0][i] }; return String(format: "%.4f", (acc / Float(n)).squareRoot()) }
        if let i16 = b.int16ChannelData { var acc: Double = 0; for i in 0..<n { let v = Double(i16[0][i]) / 32768; acc += v * v }; return String(format: "%.4f", (acc / Double(n)).squareRoot()) }
        return "?"
      }
      SpeechLog.shared.add("speech: buffer #\(buffersYielded) in=\(buffer.frameLength)f rms=\(rms(buffer)) out=\(output.frameLength)f rms=\(rms(output))")
    }
    #endif
    inputContinuation.yield(AnalyzerInput(buffer: output))
  }

  private var buffersYielded = 0

  func startResults(consume: @escaping (SpeechTranscriber.Result) -> Void) {
    let transcriber = self.transcriber
    resultsTask = Task {
      SpeechLog.shared.add("speech: results reader started")
      do {
        for try await result in transcriber.results {
          consume(result)
        }
        SpeechLog.shared.add("speech: results reader ended")
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
      try? await Task.sleep(for: .seconds(3))
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

/// Downloads and installs speech models if any of `modules` still need them.
@available(iOS 26, *)
enum SpeechAssets {
  static func installIfNeeded(for modules: [any SpeechModule]) async throws {
    if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
      try await request.downloadAndInstall()
    }
  }
}

/// Feeds contextual vocabulary (exercise names, lifting terms) so they transcribe correctly.
@available(iOS 26, *)
extension SpeechAnalyzer {
  func applyVocabulary(_ vocabulary: [String]) async {
    guard !vocabulary.isEmpty else { return }
    let context = AnalysisContext()
    context.contextualStrings[.general] = Array(vocabulary.prefix(400))
    try? await setContext(context)
  }
}

/// Installs the mic tap, converts to the analyzer's format, and exposes the audio stream.
@available(iOS 26, *)
@MainActor
final class AnalyzerAudioPipeline {
  let stream: AsyncStream<AnalyzerInput>
  let continuation: AsyncStream<AnalyzerInput>.Continuation
  let converter: AVAudioConverter
  private let engine: AVAudioEngine

  init?(engine: AVAudioEngine, format: AVAudioFormat) {
    let inputNode = engine.inputNode
    let nodeFormat = inputNode.outputFormat(forBus: 0)
    guard let converter = AVAudioConverter(from: nodeFormat, to: format) else { return nil }
    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    let feeder = AudioFeeder(converter: converter, continuation: continuation)
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: nodeFormat) { buffer, _ in
      feeder.feed(buffer)
    }
    self.engine = engine
    self.stream = stream
    self.continuation = continuation
    self.converter = converter
  }

  func start() throws {
    engine.prepare()
    try engine.start()
  }
}
