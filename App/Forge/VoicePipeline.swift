import Foundation

/// One event in a voice pipeline's stream. The pipeline reports speech activity and
/// transcripts; the consumer (VoiceControl) owns state, endpointing and commands.
enum VoiceEvent: Sendable {
  case speechStarted
  case partialTranscript(String, utteranceID: UUID)
  case finalTranscript(String, utteranceID: UUID)
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
protocol VoiceInputPipeline: AnyObject, Sendable {
  var events: AsyncStream<VoiceEvent> { get }
  func start(vocabulary: [String]) async
  func stop() async
}
