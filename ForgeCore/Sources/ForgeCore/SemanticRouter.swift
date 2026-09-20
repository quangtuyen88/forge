import Foundation

// MARK: - Semantic routing
//
// A router, not a decision maker. The model answers six independent classification
// questions about one message; the *policy* combines them, and the local context decides
// whether anything can actually be prepared. Nothing here writes, previews or approves —
// a routed candidate is untrusted input that selects a handler the app already has.

/// The three request families the router covers. Anything else is an uncovered request and
/// falls back to the controls that already exist.
public enum SemanticIntent: String, Sendable, Equatable, CaseIterable {
  case shortenSession = "shorten_session"
  case equipmentConstraint = "equipment_constraint"
  case explainChange = "explain_change"

  /// Only `explainChange` is read-only; the other two can lead to a preview.
  public var isReadOnly: Bool { self == .explainChange }
}

public enum SemanticForm: String, Sendable, Equatable {
  case currentRequest = "current_request"
  case questionOnly = "question_only"
  case hypotheticalOrQuoted = "hypothetical_or_quoted"
  case unclear
}

public enum SemanticTri: String, Sendable, Equatable {
  case requested
  case notRequested = "not_requested"
  case unclear
}

public enum SemanticScope: String, Sendable, Equatable {
  case currentSession = "current_session"
  case ongoing
  case mixed
  case unclear
  case notApplicable = "not_applicable"
}

public enum SemanticRemaining: String, Sendable, Equatable {
  case none
  case other
  case unclear
}

/// One classification answer with its distribution. Confidence is a diagnostic about the
/// answer, never a claim that a training change is safe or correct.
public struct SemanticEvidence<Choice: RawRepresentable & Sendable & Equatable>: Sendable, Equatable
where Choice.RawValue == String {
  public let choice: Choice
  public let confidence: Double
  public let probabilities: [String: Double]

  public init(choice: Choice, confidence: Double, probabilities: [String: Double]) {
    self.choice = choice
    self.confidence = confidence
    self.probabilities = probabilities
  }
}

public struct SemanticAnswers: Sendable, Equatable {
  public let form: SemanticEvidence<SemanticForm>
  public let shorten: SemanticEvidence<SemanticTri>
  public let equipment: SemanticEvidence<SemanticTri>
  public let explain: SemanticEvidence<SemanticTri>
  public let scope: SemanticEvidence<SemanticScope>
  public let remaining: SemanticEvidence<SemanticRemaining>

  public init(
    form: SemanticEvidence<SemanticForm>,
    shorten: SemanticEvidence<SemanticTri>,
    equipment: SemanticEvidence<SemanticTri>,
    explain: SemanticEvidence<SemanticTri>,
    scope: SemanticEvidence<SemanticScope>,
    remaining: SemanticEvidence<SemanticRemaining>
  ) {
    self.form = form
    self.shorten = shorten
    self.equipment = equipment
    self.explain = explain
    self.scope = scope
    self.remaining = remaining
  }
}

/// Thresholds. Provisional engineering choices for replay experiments, not vendor
/// guarantees and not rollout criteria — tune per locale on a calibration split, then
/// freeze before held-out evaluation.
public struct SemanticPolicyConfig: Sendable, Equatable {
  public let minConfidence: Double
  public let minTopProbability: Double
  public let minMargin: Double
  /// Distributions are floats over the wire; they will not sum to exactly 1.
  public let sumTolerance: Double

  public init(
    minConfidence: Double = 0.85,
    minTopProbability: Double = 0.90,
    minMargin: Double = 0.25,
    sumTolerance: Double = 0.02
  ) {
    self.minConfidence = minConfidence
    self.minTopProbability = minTopProbability
    self.minMargin = minMargin
    self.sumTolerance = sumTolerance
  }

  var isValid: Bool {
    [minConfidence, minTopProbability, minMargin].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
      && sumTolerance.isFinite && sumTolerance >= 0 && sumTolerance <= 1
  }
}

/// What the phone knows and the model never sees: whether there is a workout, whether the
/// slots actually resolved, and which handlers this build really has.
public struct SemanticLocalContext: Sendable, Equatable {
  public let hasWorkout: Bool
  public let hasValidDuration: Bool
  public let hasUniqueEquipment: Bool
  public let hasUniqueDecision: Bool
  /// True only when time and equipment constraints can be composed into ONE engine preview.
  /// False means guided controls — never half the request applied silently.
  public let hasVerifiedAtomicComposer: Bool
  public let capabilities: Set<SemanticIntent>

  public init(
    hasWorkout: Bool,
    hasValidDuration: Bool,
    hasUniqueEquipment: Bool,
    hasUniqueDecision: Bool,
    hasVerifiedAtomicComposer: Bool,
    capabilities: Set<SemanticIntent>
  ) {
    self.hasWorkout = hasWorkout
    self.hasValidDuration = hasValidDuration
    self.hasUniqueEquipment = hasUniqueEquipment
    self.hasUniqueDecision = hasUniqueDecision
    self.hasVerifiedAtomicComposer = hasVerifiedAtomicComposer
    self.capabilities = capabilities
  }
}

/// Which local clarification to ask. One focused question, from the existing chip set.
public enum SemanticClarification: String, Sendable, Equatable {
  case request
  case scope
  case duration
  case equipment
  case explanationTarget = "explanation_target"
}

/// The only outcomes. `preview` authorizes *attempting* to prepare a preview — it is never
/// a write, and the user still approves the exact diff.
public enum SemanticOutcome: Sendable, Equatable {
  case fallback(reason: String)
  case clarify(SemanticClarification)
  case openEditor
  case read(SemanticIntent)
  case preview([SemanticIntent])
}

public enum SemanticRouter {
  /// Run only after privacy, permission, schema, model-version, deadline and freshness
  /// checks have passed. This function authorizes nothing.
  public static func decide(
    _ answers: SemanticAnswers,
    context: SemanticLocalContext,
    config: SemanticPolicyConfig = SemanticPolicyConfig()
  ) -> SemanticOutcome {
    // An invalid threshold must never enable a route.
    guard config.isValid else { return .fallback(reason: "invalid_config") }

    let decisive = [
      isDecisive(answers.form, config), isDecisive(answers.shorten, config),
      isDecisive(answers.equipment, config), isDecisive(answers.explain, config),
      isDecisive(answers.scope, config), isDecisive(answers.remaining, config),
    ]
    guard decisive.allSatisfy({ $0 }) else { return .clarify(.request) }

    // A request we do not cover is never forced into one we do.
    guard answers.remaining.choice == .none else { return .fallback(reason: "uncovered_request") }
    if answers.form.choice == .hypotheticalOrQuoted {
      return .fallback(reason: "discussion_not_action")
    }
    let anyUnclear = answers.form.choice == .unclear
      || [answers.shorten.choice, answers.equipment.choice, answers.explain.choice].contains(.unclear)
    if anyUnclear { return .clarify(.request) }

    var intents: [SemanticIntent] = []
    if answers.shorten.choice == .requested { intents.append(.shortenSession) }
    if answers.equipment.choice == .requested { intents.append(.equipmentConstraint) }
    if answers.explain.choice == .requested { intents.append(.explainChange) }
    guard !intents.isEmpty else { return .fallback(reason: "no_supported_intent") }
    guard intents.allSatisfy({ context.capabilities.contains($0) }) else {
      return .fallback(reason: "unavailable_capability")
    }

    // Read-only: the recorded reason is read locally. Nothing is proposed.
    if intents.allSatisfy(\.isReadOnly) {
      guard answers.scope.choice == .notApplicable else { return .clarify(.request) }
      return context.hasUniqueDecision ? .read(.explainChange) : .clarify(.explanationTarget)
    }

    guard answers.form.choice == .currentRequest else { return .clarify(.request) }
    // "My new gym has no cables" opens the editor. Opening is not saving.
    if answers.scope.choice == .ongoing { return .openEditor }
    guard answers.scope.choice == .currentSession else { return .clarify(.scope) }
    guard context.hasWorkout else { return .fallback(reason: "no_workout") }
    if intents.contains(.shortenSession) && !context.hasValidDuration { return .clarify(.duration) }
    if intents.contains(.equipmentConstraint) && !context.hasUniqueEquipment {
      return .clarify(.equipment)
    }
    if intents.contains(.explainChange) && !context.hasUniqueDecision {
      return .clarify(.explanationTarget)
    }
    // Two constraints, one preview — or guided controls. Never half the request.
    if intents.count > 1 && !context.hasVerifiedAtomicComposer {
      return .fallback(reason: "use_guided_controls")
    }
    return .preview(intents)
  }

  /// A distribution is usable only when it is a real distribution *and* clears the
  /// selected-probability and margin checks separately. Related answers are never
  /// multiplied together as though they were independent.
  static func isDecisive<Choice>(
    _ evidence: SemanticEvidence<Choice>, _ config: SemanticPolicyConfig
  ) -> Bool {
    let values = Array(evidence.probabilities.values)
    guard values.count >= 2 else { return false }
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return false }
    guard abs(values.reduce(0, +) - 1) <= config.sumTolerance else { return false }
    guard evidence.confidence.isFinite,
          evidence.confidence >= config.minConfidence,
          evidence.confidence <= 1
    else { return false }
    guard let selected = evidence.probabilities[evidence.choice.rawValue], selected.isFinite else {
      return false
    }
    let runnerUp = evidence.probabilities
      .filter { $0.key != evidence.choice.rawValue }
      .values.max() ?? 0
    return selected >= config.minTopProbability && selected - runnerUp >= config.minMargin
  }
}
