import Foundation

/// One event in a voice pipeline's stream. The pipeline reports speech activity and
/// transcripts; the consumer (VoiceControl) owns state, endpointing and commands.
enum VoiceEvent: Sendable {
  case speechStarted
  case partialTranscript(String, utteranceID: UUID)
  case finalTranscript(String, utteranceID: UUID)
  /// Speech is over and the transcript is being produced. Only a pipeline that transcribes
  /// *after* the utterance ends emits this — the OS recognizers stream as the lifter talks,
  /// so their text is already in hand. It exists so the command time cap measures speaking,
  /// not inference: without it a 4 s command plus 2 s of decoding trips the 6 s cap and a
  /// perfectly good set is silently dropped.
  case transcribing
  case speechEnded
  case unavailable(reason: VoiceUnavailableReason)
}

enum VoiceUnavailableReason: Sendable, Equatable {
  case permissionDenied
  case noOnDeviceModel
  case unsupportedLocale
  case audioSessionFailed(String)
}

/// The OS seam. VoiceControl consumes only this — no Speech or AVFoundation types leak
/// past it. Each adapter emits the same event stream, one `utteranceID` per utterance.
@MainActor
protocol VoiceInputPipeline: AnyObject, Sendable {
  var events: AsyncStream<VoiceEvent> { get }
  func start(vocabulary: [String]) async
  func stop() async
}
