import AVFoundation
import Foundation
import ForgeCore
import UIKit
import WhisperKit

/// On-device Whisper behind the same seam as the OS adapters.
///
/// **Finals only.** Whisper re-decodes each window and can rewrite words it already emitted,
/// so its intermediate output is not the prefix-stable stream `SFSpeechRecognizer` produces.
/// Publishing those as `.partialTranscript` would make `VoiceControl` act on text that is
/// about to change, so this adapter segments with its own energy VAD and emits exactly one
/// `.finalTranscript` per utterance. Command parsing in ForgeCore is unchanged.
///
/// **Order matters.** `VoiceControl` finalizes `silenceToFinalize` after `.speechEnded`, so
/// the transcript is yielded *before* that event — never after it, where it would arrive to
/// an utterance that has already been closed.
@MainActor
final class WhisperKitPipeline: VoiceInputPipeline {
  private let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
  var events: AsyncStream<VoiceEvent> { stream }

  /// 16 kHz mono Float is what Whisper consumes; everything else is a conversion away.
  private static let sampleRate: Double = 16_000
  /// Start speaking above this RMS, stop below it. Two thresholds, so a breath between
  /// words does not end the utterance.
  private static let speechThreshold: Float = 0.018
  private static let silenceThreshold: Float = 0.010
  /// Hard bound on one utterance's audio, and therefore on memory: 20 s at 16 kHz mono.
  private static let maxUtteranceSamples = Int(sampleRate * VoiceTiming.askCoachHardCap)

  private let modelFolder: URL
  private let language: String?
  private let engine = AVAudioEngine()
  private var whisper: WhisperKit?
  private var sessionGuard: AudioSessionGuard?
  private var converter: AVAudioConverter?
  private var targetFormat: AVAudioFormat?

  private var preRoll: [Float] = []
  private var utterance: [Float] = []
  private var speaking = false
  private var utteranceID: UUID?
  private var silentSeconds: TimeInterval = 0
  private var transcribing = false
  private var transcriptionTask: Task<Void, Never>?
  private var memoryObserver: NSObjectProtocol?
  private var stopped = false

  init(modelFolder: URL, language: String?) {
    self.modelFolder = modelFolder
    self.language = language
  }

  func start(vocabulary: [String]) async {
    guard await AVAudioApplication.requestRecordPermission() else {
      continuation.yield(.unavailable(reason: .permissionDenied))
      return
    }

    do {
      // Nothing is downloaded here: the model is either on disk or this adapter is not used.
      whisper = try await WhisperKit(
        WhisperKitConfig(
          modelFolder: modelFolder.path, verbose: false, logLevel: .error,
          prewarm: true, load: true, download: false))
    } catch {
      SpeechLog.shared.add("voice: whisper load failed \(error)")
      continuation.yield(.unavailable(reason: .noOnDeviceModel))
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      return
    }

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: inputFormat, to: target)
    else {
      continuation.yield(.unavailable(reason: .audioSessionFailed("no 16 kHz converter")))
      return
    }
    self.targetFormat = target
    self.converter = converter

    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      guard let samples = WhisperKitPipeline.convert(buffer, using: converter, to: target) else { return }
      let level = WhisperKitPipeline.rms(samples)
      let seconds = Double(samples.count) / Self.sampleRate
      Task { @MainActor in self?.ingest(samples, level: level, seconds: seconds) }
    }

    let sessionGuard = AudioSessionGuard { [weak self] in try? self?.engine.start() }
    self.sessionGuard = sessionGuard
    sessionGuard.install()

    // A jetsam mid-workout loses logged sets. Under pressure the model is dropped and the
    // session ends cleanly rather than being killed with the app.
    memoryObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        SpeechLog.shared.add("voice: whisper unloaded under memory pressure")
        // Stand down for this session only. The next arm picks the OS recognizer, so voice
        // survives the rest of the workout instead of being gone until relaunch.
        WhisperModelStore.shared.suppressForThisSession()
        self?.continuation.yield(.unavailable(reason: .noOnDeviceModel))
        await self?.stop()
      }
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      continuation.yield(.unavailable(reason: .audioSessionFailed(String(describing: error))))
      await stop()
    }
  }

  func stop() async {
    guard !stopped else { return }
    stopped = true
    // An utterance that announced itself must always end. Cancelling a decode in flight
    // without this leaves VoiceControl waiting on a `.speechEnded` that never comes.
    if transcribing {
      transcriptionTask?.cancel()
      transcriptionTask = nil
      transcribing = false
      continuation.yield(.speechEnded)
    }
    if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    memoryObserver = nil
    sessionGuard?.remove()
    sessionGuard = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    converter = nil
    whisper = nil
    preRoll = []
    utterance = []
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    continuation.finish()
  }

  // MARK: - Segmentation

  private func ingest(_ samples: [Float], level: Float, seconds: TimeInterval) {
    guard !stopped else { return }
    if speaking {
      utterance.append(contentsOf: samples)
      if level < Self.silenceThreshold {
        silentSeconds += seconds
        if silentSeconds >= VoiceTiming.silenceToFinalize { finish() }
      } else {
        silentSeconds = 0
      }
      if utterance.count >= Self.maxUtteranceSamples { finish() }
      return
    }

    // Not speaking yet: keep a rolling pre-roll so the first word is never clipped.
    preRoll.append(contentsOf: samples)
    let keep = Int(Self.sampleRate * VoiceTiming.preRoll)
    if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }

    if level >= Self.speechThreshold {
      speaking = true
      silentSeconds = 0
      utteranceID = UUID()
      utterance = preRoll
      preRoll = []
      continuation.yield(.speechStarted)
    }
  }

  private func finish() {
    guard speaking, let id = utteranceID else { return }
    let audio = utterance
    speaking = false
    utterance = []
    silentSeconds = 0
    utteranceID = nil

    // Too short to be a command: report the end and transcribe nothing.
    guard Double(audio.count) / Self.sampleRate >= VoiceTiming.minSpeech else {
      continuation.yield(.speechEnded)
      return
    }
    guard let whisper, !transcribing else {
      continuation.yield(.speechEnded)
      return
    }
    transcribing = true
    // Speaking is over; decoding is not. Say so, or VoiceControl's command cap counts
    // inference time against the lifter.
    continuation.yield(.transcribing)
    transcriptionTask = Task { [weak self] in
      let text = await Self.transcribe(audio, with: whisper, language: self?.language)
      await MainActor.run {
        guard let self else { return }
        self.transcriptionTask = nil
        self.transcribing = false
        guard !self.stopped else { return }
        if !text.isEmpty { self.continuation.yield(.finalTranscript(text, utteranceID: id)) }
        // Exactly one terminal event per utterance that started. `stop()` synthesizes it
        // when it cancels this task, so the UI can never be left in "hearing" forever.
        self.continuation.yield(.speechEnded)
      }
    }
  }

  private nonisolated static func transcribe(_ audio: [Float], with whisper: WhisperKit, language: String?) async -> String {
    do {
      let options = DecodingOptions(
        verbose: false, task: .transcribe, language: language,
        temperature: 0, detectLanguage: language == nil,
        skipSpecialTokens: true, withoutTimestamps: true)
      let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
      // Whisper invents subtitle boilerplate out of near-silence — "Thank you." in English,
      // "Cảm ơn các bạn đã theo dõi" in Vietnamese. With fast logging on, one of those
      // parsing as a set would write a lift nobody did, so the model's own no-speech and
      // log-probability estimates decide before any text leaves here.
      let usable = results.filter { result in
        let noSpeech = result.segments.map(\.noSpeechProb).max() ?? 0
        let logProb = result.segments.map(\.avgLogprob).min() ?? 0
        return noSpeech < 0.6 && logProb > -1.0
      }
      return usable.map(\.text).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      await MainActor.run { SpeechLog.shared.add("voice: whisper transcribe failed \(error)") }
      return ""
    }
  }

  // MARK: - Audio helpers

  /// Converts one tap buffer into 16 kHz mono Float. Runs on the audio thread; the
  /// converter is touched from nowhere else.
  private nonisolated static func convert(
    _ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat
  ) -> [Float]? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    nonisolated(unsafe) var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return buffer
    }
    guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return nil }
    return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
  }

  private nonisolated static func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for sample in samples { sum += sample * sample }
    return (sum / Float(samples.count)).squareRoot()
  }
}
