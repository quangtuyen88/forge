import Observation

/// A question another screen wants the coach to answer. Survives until the Coach tab consumes it,
/// so it works even when the Coach tab has never been opened yet.
@Observable @MainActor final class CoachHandoff {
  static let shared = CoachHandoff()
  var question: String?
  /// Bumped on every ask, so the tab switch never depends on when the question is consumed.
  private(set) var requests = 0
  func ask(_ text: String) {
    question = text
    requests += 1
  }
  func take() -> String? { defer { question = nil }; return question }
}
