import Foundation
import Speech
import AVFoundation
import Observation

/// Wraps SFSpeechRecognizer + AVAudioEngine for hands-free dictation in the coach chat.
@MainActor @Observable final class SpeechInput {
  var transcript = ""
  var isListening = false
  var errorText: String?

  private let recognizer: SFSpeechRecognizer?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var autoStop: Task<Void, Never>?
  private var stopping = false

  private static let permissionMessage = "Microphone or speech permission is off. Enable it in Settings."

  init() {
    recognizer = SFSpeechRecognizer(locale: Self.bestLocale())
  }

  var isAvailable: Bool {
    recognizer?.isAvailable ?? false
  }

  /// Returns the best available locale for speech recognition.
  ///
  /// If the user's current locale is directly supported, use it. Otherwise fall
  /// back to a supported locale sharing the same language, preferring well-known
  /// variants, and finally to `en-US`.
  private static func bestLocale() -> Locale {
    let supported = SFSpeechRecognizer.supportedLocales()
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

  private func setNonPermissionError(_ error: Error? = nil) {
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

  func start() async {
    guard !isListening else { return }
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
    request?.endAudio()
    recognitionTask?.finish()
    recognitionTask = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    request = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
