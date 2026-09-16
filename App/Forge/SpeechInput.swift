import Foundation
import Speech
import AVFoundation
import Observation

/// Wraps SFSpeechRecognizer + AVAudioEngine for hands-free dictation in the coach chat.
@MainActor @Observable final class SpeechInput {
  var transcript = ""
  var isListening = false
  var errorText: String?

  private let recognizer = SFSpeechRecognizer(locale: .current)
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var autoStop: Task<Void, Never>?

  private static let permissionMessage = "Microphone or speech permission is off. Enable it in Settings."

  var isAvailable: Bool {
    recognizer?.isAvailable ?? false
  }

  func start() async {
    guard let recognizer, recognizer.isAvailable else {
      errorText = Self.permissionMessage
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
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      errorText = Self.permissionMessage
      return
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
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
      errorText = Self.permissionMessage
      stop()
      return
    }

    transcript = ""
    isListening = true
    errorText = nil

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor in
        guard let self else { return }
        if let result {
          self.transcript = result.bestTranscription.formattedString
        }
        if error != nil {
          self.errorText = Self.permissionMessage
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
    autoStop?.cancel()
    autoStop = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    request?.endAudio()
    request = nil
    isListening = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
