import Foundation

/// The clarification lifecycle, lifted out of the view.
///
/// The resolver is pure and was already tested; what actually broke in production was
/// *when the pending clarification is cleared and when the retry counter resets*. Holding
/// that in view `@State` put the one part with real branching out of reach of every test,
/// so it lives here instead.
public struct CoachConversation: Sendable, Equatable {
  public private(set) var pending: CoachClarification?

  public init(pending: CoachClarification? = nil) {
    self.pending = pending
  }

  /// What the view should do with the lifter's next message.
  public enum Step: Sendable, Equatable {
    /// Send this to the model. `skipClassification` is true when the text was already
    /// resolved from a clarification and must not be re-classified into the same question.
    case ask(String, skipClassification: Bool)
    /// Answer locally with this prompt and keep waiting.
    case reAsk(options: [String])
  }

  /// One reply in, one step out. Every path that leaves a clarification behind clears it
  /// here — there is no way to route a message and forget to.
  public mutating func step(reply: String, resolvedQuestion: (String, String) -> String) -> Step {
    guard let pending else {
      return .ask(reply, skipClassification: false)
    }
    switch CoachClarificationResolver.resolve(reply: reply, pending: pending) {
    case .resolved(let original, let choice):
      self.pending = nil
      return .ask(resolvedQuestion(original, choice), skipClassification: true)
    case .repeatOptions(let next):
      self.pending = next
      return .reAsk(options: next.options)
    case .fallbackToOriginal(let original):
      self.pending = nil
      return .ask(original, skipClassification: true)
    case .newQuestion(let fresh):
      // The lifter moved on. The old clarification — and its retry count — go with it.
      self.pending = nil
      return .ask(fresh, skipClassification: false)
    }
  }

  /// A fresh clarification always starts at zero retries, whatever came before it.
  public mutating func clarify(question: String, options: [String]) {
    pending = CoachClarification(question: question, options: options)
  }

  public mutating func reset() {
    pending = nil
  }

  public var isAwaitingChoice: Bool { pending != nil }
  public var options: [String] { pending?.options ?? [] }
}
