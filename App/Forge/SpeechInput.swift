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
  /// Mic input level while listening, 0...1; 0 when idle.
  var level: Double = 0
  /// Trailing words of `transcript` the recognizer may still revise; always a suffix of `transcript`.
  var pending = ""

  private var recognizer: SFSpeechRecognizer?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var autoStop: Task<Void, Never>?
  private var stopping = false
  /// Polls the cloud recorder meter while it records.
  @ObservationIgnored private var meterTask: Task<Void, Never>?
  /// DEBUG scripted-speech replay task; nil in release.
  @ObservationIgnored private var scriptTask: Task<Void, Never>?
  @ObservationIgnored private var scriptWords: [String] = []
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

  /// Actionable refusal for a language with no on-device model: names the language and
  /// the Settings switch that turns on Apple's server-based recognition.
  static func noOnDeviceModelMessage() -> String {
    let name = Locale.current.localizedString(forLanguageCode: recognizerLocale().language.languageCode?.identifier ?? "") ?? "This language"
    return String(localized: "\(name) has no on-device speech model. Turn on Settings → Voice → Use Apple's speech service to dictate in \(name).", bundle: L10n.bundle)
  }

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
    let requested = stored == "auto" ? L10n.languageCode : stored
    switch requested.lowercased() {
    case "zh-hans", "zh-cn": return "zh"
    case "zh-hant", "zh-tw": return "zh"
    default: return requested.split(separator: "-").first.map(String.init)
    }
  }

  /// Maps an RMS value to 0...1 (-50 dBFS -> 0, -10 dBFS -> 1).
  nonisolated static func level(rms: Float) -> Double {
    level(decibels: 20 * log10(max(rms, 1e-7)))
  }

  /// Maps an AVAudioRecorder averagePower value to 0...1 (-50 dB -> 0, -10 dB -> 1).
  nonisolated static func level(decibels: Float) -> Double {
    min(1, max(0, (Double(decibels) + 50) / 40))
  }

  /// Root-mean-square of channel 0; 0 for an empty buffer.
  nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
    let n = Int(buffer.frameLength)
    guard n > 0 else { return 0 }
    if let floats = buffer.floatChannelData {
      var acc: Float = 0
      for i in 0..<n { acc += floats[0][i] * floats[0][i] }
      return (acc / Float(n)).squareRoot()
    }
    if let ints = buffer.int16ChannelData {
      var acc: Float = 0
      for i in 0..<n { let v = Float(ints[0][i]) / 32768; acc += v * v }
      return (acc / Float(n)).squareRoot()
    }
    return 0
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

  /// The ISO code Whisper decodes with, or nil to let it detect. Taken from the same
  /// dictation preference the OS recognizers follow, so one setting drives every engine.
  static func whisperLanguage() -> String? {
    let stored = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "auto"
    let code = stored == "auto" ? L10n.languageCode : stored
    let base = Locale(identifier: code).language.languageCode?.identifier ?? code
    return base.isEmpty ? nil : base
  }

  static func recognizerLocale() -> Locale {
    requestedLocale() ?? appLanguageLocale() ?? bestLocale()
  }

  /// The app's chosen language as a concrete recognizer locale, or nil when it has no
  /// known voice mapping. Voice follows the app language, not the device locale.
  static func appLanguageLocale() -> Locale? {
    guard let id = dictationLocaleIDs[L10n.languageCode] else { return nil }
    return Locale(identifier: id)
  }

  @available(iOS 26, *)
  static func analyzerBestLocale() async -> Locale {
    if let forced = requestedLocale() { return forced }
    if let app = appLanguageLocale() { return app }
    return pickLocale(from: await SpeechTranscriber.supportedLocales)
  }

  /// True when `SpeechTranscriber` has an on-device model for `locale` (identifiers
  /// compared with `_`/`-` normalised). The one support probe for dictation and voice control.
  @available(iOS 26, *)
  static func analyzerSupports(_ locale: Locale) async -> Bool {
    let id = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    return await SpeechTranscriber.supportedLocales.contains {
      $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == id
    }
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
#if DEBUG
    if Self.debugUnavailable { errorText = Self.permissionMessage; return }
    if let script = Self.debugScript { startScripted(script); return }
#endif
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
    if #available(iOS 26, *), await Self.analyzerSupports(Self.analyzerBestLocale()) {
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
      recorder.isMeteringEnabled = true
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
    pending = ""
    level = 0
    isListening = true
    errorText = nil
    stopping = false
    meterTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled, let self, let recorder = self.recorder else { return }
        recorder.updateMeters()
        self.level = Self.level(decibels: recorder.averagePower(forChannel: 0))
      }
    }
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
    let analyzerLocaleSupported = await Self.analyzerSupports(locale)
    SpeechLog.shared.add("speech: analyzer locale \(locale.identifier) supported=\(analyzerLocaleSupported) assets \(await AssetInventory.status(forModules: [transcriber]))")
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

    guard let pipeline = AnalyzerAudioPipeline(engine: engine, format: format, onLevel: { [weak self] value in
      Task { @MainActor in self?.level = value }
    }) else {
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
    pending = ""
    level = 0
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
        self.pending = ""
      } else {
        self.transcript = finalized + text
        self.pending = text
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
    // No on-device model for this language: only continue when the lifter opted into
    // Apple's server-based recognition (Settings → Voice → Use Apple's speech service).
    if !recognizer.supportsOnDeviceRecognition {
      guard UserDefaults.standard.bool(forKey: "voiceAllowServerRecognition") else {
        errorText = Self.noOnDeviceModelMessage()
        return
      }
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
    if !vocabulary.isEmpty {
      request.contextualStrings = Array(vocabulary.prefix(100))
    }
    self.request = request

    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      let value = SpeechInput.level(rms: SpeechInput.rms(buffer))
      Task { @MainActor in
        self?.request?.append(buffer)
        self?.level = value
      }
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
    pending = ""
    level = 0
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
#if DEBUG
    if scriptTask != nil {
      scriptTask?.cancel()
      scriptTask = nil
      transcript = scriptWords.joined(separator: " ")
      pending = ""
      level = 0
      isListening = false
      isPreparing = false
      return
    }
#endif
    stopping = true
    autoStop?.cancel()
    autoStop = nil
    if isCloud {
      isCloud = false
      recorder?.stop()
      recorder = nil
      let url = recordingURL
      recordingURL = nil
      meterTask?.cancel()
      meterTask = nil
      isListening = false
      isPreparing = false
      isTranscribing = true
      level = 0
      pending = ""
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
    meterTask?.cancel()
    meterTask = nil
    isPreparing = false
    isListening = false
    level = 0
    pending = ""
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  /// Stops listening and drops the recording: no cloud upload, no transcript.
  func cancel() {
#if DEBUG
    if scriptTask != nil {
      scriptTask?.cancel()
      scriptTask = nil
      transcript = ""
      pending = ""
      level = 0
      isListening = false
      isPreparing = false
      return
    }
#endif
    if isCloud {
      stopping = true
      autoStop?.cancel()
      autoStop = nil
      meterTask?.cancel()
      meterTask = nil
      isCloud = false
      recorder?.stop()
      recorder = nil
      if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
      recordingURL = nil
      isListening = false
      isPreparing = false
      level = 0
      pending = ""
      transcript = ""
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      return
    }
    stop()
    transcript = ""
    pending = ""
  }

#if DEBUG
  /// UI tests: `-coachVoiceScript "<sentence>"` speaks that sentence instead of opening the microphone.
  private static var debugScript: String? {
    guard let value = UserDefaults.standard.string(forKey: "coachVoiceScript"), !value.isEmpty else { return nil }
    return value
  }

  /// UI tests: a launch argument containing "voiceUnavailable" fails `start()` with the permission message.
  private static var debugUnavailable: Bool {
    ProcessInfo.processInfo.arguments.contains { $0.contains("voiceUnavailable") } || UserDefaults.standard.bool(forKey: "voiceUnavailable")
  }

  /// DEBUG: replays the scripted sentence with a fake level, never touching audio hardware.
  private func startScripted(_ sentence: String) {
    let words = sentence.split(separator: " ").map(String.init)
    scriptWords = words
    transcript = ""
    pending = ""
    level = 0
    errorText = nil
    isListening = true
    scriptTask = Task { [weak self] in
      var spoken: [String] = []
      for word in words {
        for step in 0..<6 {
          guard !Task.isCancelled else { return }
          try? await Task.sleep(nanoseconds: 50_000_000)
          guard !Task.isCancelled else { return }
          self?.level = 0.45 + 0.4 * abs(sin(Double(step) * 1.1))
        }
        guard !Task.isCancelled else { return }
        spoken.append(word)
        self?.transcript = spoken.joined(separator: " ")
        self?.pending = word
      }
      guard !Task.isCancelled else { return }
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard !Task.isCancelled else { return }
      self?.pending = ""
      self?.level = 0.06
    }
  }
#endif

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
      SpeechLog.shared.add("speech: buffer #\(buffersYielded) in=\(buffer.frameLength)f rms=\(String(format: "%.4f", SpeechInput.rms(buffer))) out=\(output.frameLength)f rms=\(String(format: "%.4f", SpeechInput.rms(output)))")
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

  init?(engine: AVAudioEngine, format: AVAudioFormat, onLevel: (@Sendable (Double) -> Void)? = nil) {
    let inputNode = engine.inputNode
    let nodeFormat = inputNode.outputFormat(forBus: 0)
    guard let converter = AVAudioConverter(from: nodeFormat, to: format) else { return nil }
    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    let feeder = AudioFeeder(converter: converter, continuation: continuation)
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: nodeFormat) { buffer, _ in
      onLevel?(SpeechInput.level(rms: SpeechInput.rms(buffer)))
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
