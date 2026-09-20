import XCTest
@testable import ForgeCore

/// The router decides which existing handler a sentence belongs to. These tests are about
/// what it REFUSES: a routed candidate must never become a change on its own.
final class SemanticRouterTests: XCTestCase {

  // MARK: - Builders

  private func strong<C: RawRepresentable & Sendable & Equatable>(
    _ choice: C, _ others: [C]
  ) -> SemanticEvidence<C> where C.RawValue == String {
    var probabilities = [choice.rawValue: 0.95]
    let share = 0.05 / Double(max(others.count, 1))
    for other in others { probabilities[other.rawValue] = share }
    return SemanticEvidence(choice: choice, confidence: 0.95, probabilities: probabilities)
  }

  private func weak<C: RawRepresentable & Sendable & Equatable>(
    _ choice: C, _ other: C
  ) -> SemanticEvidence<C> where C.RawValue == String {
    SemanticEvidence(
      choice: choice, confidence: 0.55,
      probabilities: [choice.rawValue: 0.55, other.rawValue: 0.45])
  }

  private func answers(
    form: SemanticEvidence<SemanticForm>? = nil,
    shorten: SemanticEvidence<SemanticTri>? = nil,
    equipment: SemanticEvidence<SemanticTri>? = nil,
    explain: SemanticEvidence<SemanticTri>? = nil,
    scope: SemanticEvidence<SemanticScope>? = nil,
    remaining: SemanticEvidence<SemanticRemaining>? = nil
  ) -> SemanticAnswers {
    SemanticAnswers(
      form: form ?? strong(.currentRequest, [.questionOnly, .hypotheticalOrQuoted, .unclear]),
      shorten: shorten ?? strong(.notRequested, [.requested, .unclear]),
      equipment: equipment ?? strong(.notRequested, [.requested, .unclear]),
      explain: explain ?? strong(.notRequested, [.requested, .unclear]),
      scope: scope ?? strong(.notApplicable, [.currentSession, .ongoing, .mixed, .unclear]),
      remaining: remaining ?? strong(.none, [.other, .unclear]))
  }

  private func context(
    hasWorkout: Bool = true,
    duration: Bool = true,
    equipment: Bool = true,
    decision: Bool = true,
    composer: Bool = true,
    capabilities: Set<SemanticIntent> = Set(SemanticIntent.allCases)
  ) -> SemanticLocalContext {
    SemanticLocalContext(
      hasWorkout: hasWorkout, hasValidDuration: duration, hasUniqueEquipment: equipment,
      hasUniqueDecision: decision, hasVerifiedAtomicComposer: composer, capabilities: capabilities)
  }

  // MARK: - AT-01 .. AT-12

  func testTimeAndEquipmentTogetherBecomeOnePreview() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context())
    XCTAssertEqual(outcome, .preview([.shortenSession, .equipmentConstraint]))
  }

  func testTwoConstraintsWithoutAnAtomicComposerUseGuidedControls() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(composer: false))
    XCTAssertEqual(outcome, .fallback(reason: "use_guided_controls"))
  }

  func testAnExplicitlyRefusedShorteningOnlyChangesEquipment() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.notRequested, [.requested, .unclear]),
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context())
    XCTAssertEqual(outcome, .preview([.equipmentConstraint]))
  }

  func testAnExplanationIsReadOnlyAndNeverAnotherChange() {
    let outcome = SemanticRouter.decide(
      answers(
        form: strong(.questionOnly, [.currentRequest, .hypotheticalOrQuoted, .unclear]),
        explain: strong(.requested, [.notRequested, .unclear])),
      context: context())
    XCTAssertEqual(outcome, .read(.explainChange))
  }

  func testAnOngoingConstraintOpensTheEditorAndNeverPreviews() {
    let outcome = SemanticRouter.decide(
      answers(
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.ongoing, [.currentSession, .mixed, .unclear, .notApplicable])),
      context: context())
    XCTAssertEqual(outcome, .openEditor)
  }

  func testMixedScopeAsksRatherThanApplyingHalfOfIt() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.mixed, [.currentSession, .ongoing, .unclear, .notApplicable])),
      context: context())
    XCTAssertEqual(outcome, .clarify(.scope))
  }

  func testAmbiguousWeightAsksForTheExplanationTarget() {
    let outcome = SemanticRouter.decide(
      answers(
        form: strong(.questionOnly, [.currentRequest, .hypotheticalOrQuoted, .unclear]),
        explain: strong(.requested, [.notRequested, .unclear])),
      context: context(decision: false))
    XCTAssertEqual(outcome, .clarify(.explanationTarget))
  }

  func testAnUncoveredRequestIsNeverForcedIntoASupportedCategory() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable]),
        remaining: strong(.other, [.none, .unclear])),
      context: context())
    XCTAssertEqual(outcome, .fallback(reason: "uncovered_request"))
  }

  func testAQuotedExampleIsDiscussionNotAnAction() {
    let outcome = SemanticRouter.decide(
      answers(
        form: strong(.hypotheticalOrQuoted, [.currentRequest, .questionOnly, .unclear]),
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context())
    XCTAssertEqual(outcome, .fallback(reason: "discussion_not_action"))
  }

  func testAMissingDurationAsksInsteadOfInventingMinutes() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(duration: false))
    XCTAssertEqual(outcome, .clarify(.duration))
  }

  func testAnUnresolvedPieceOfEquipmentAsksWhichOne() {
    let outcome = SemanticRouter.decide(
      answers(
        equipment: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(equipment: false))
    XCTAssertEqual(outcome, .clarify(.equipment))
  }

  func testNoWorkoutMeansThereIsNothingToShorten() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(hasWorkout: false))
    XCTAssertEqual(outcome, .fallback(reason: "no_workout"))
  }

  func testACapabilityThisBuildLacksFallsBackRatherThanPretending() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(capabilities: [.explainChange]))
    XCTAssertEqual(outcome, .fallback(reason: "unavailable_capability"))
  }

  // MARK: - Confidence is a diagnostic, not permission

  func testLowConfidenceAsksOneFocusedQuestion() {
    let outcome = SemanticRouter.decide(
      answers(shorten: weak(.requested, .notRequested)), context: context())
    XCTAssertEqual(outcome, .clarify(.request))
  }

  func testASmallMarginIsNotDecisiveEvenAtHighConfidence() {
    let split = SemanticEvidence(
      choice: SemanticTri.requested, confidence: 0.99,
      probabilities: ["requested": 0.52, "not_requested": 0.48])
    XCTAssertFalse(SemanticRouter.isDecisive(split, SemanticPolicyConfig()))
  }

  func testADistributionThatDoesNotSumToOneIsRejected() {
    let broken = SemanticEvidence(
      choice: SemanticTri.requested, confidence: 0.99,
      probabilities: ["requested": 0.95, "not_requested": 0.30])
    XCTAssertFalse(SemanticRouter.isDecisive(broken, SemanticPolicyConfig()))
  }

  func testASingleOptionDistributionIsNotADistribution() {
    let lonely = SemanticEvidence(
      choice: SemanticTri.requested, confidence: 1.0, probabilities: ["requested": 1.0])
    XCTAssertFalse(SemanticRouter.isDecisive(lonely, SemanticPolicyConfig()))
  }

  func testNonFiniteNumbersCannotPassTheGate() {
    let nan = SemanticEvidence(
      choice: SemanticTri.requested, confidence: Double.nan,
      probabilities: ["requested": 0.95, "not_requested": 0.05])
    XCTAssertFalse(SemanticRouter.isDecisive(nan, SemanticPolicyConfig()))
  }

  func testAnInvalidThresholdDisablesRoutingInsteadOfOpeningIt() {
    let outcome = SemanticRouter.decide(
      answers(
        shorten: strong(.requested, [.notRequested, .unclear]),
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context(),
      config: SemanticPolicyConfig(minConfidence: Double.nan))
    XCTAssertEqual(outcome, .fallback(reason: "invalid_config"))
  }

  func testPerfectConfidenceStillOnlyEarnsAPreview() {
    let certain = SemanticEvidence(
      choice: SemanticTri.requested, confidence: 1.0,
      probabilities: ["requested": 1.0, "not_requested": 0.0, "unclear": 0.0])
    let outcome = SemanticRouter.decide(
      answers(
        shorten: certain,
        scope: strong(.currentSession, [.ongoing, .mixed, .unclear, .notApplicable])),
      context: context())
    // A preview, never a commit: approval lives in the app, not in a probability.
    XCTAssertEqual(outcome, .preview([.shortenSession]))
  }

  func testNoSupportedIntentFallsBackInsteadOfGuessing() {
    XCTAssertEqual(
      SemanticRouter.decide(answers(), context: context()),
      .fallback(reason: "no_supported_intent"))
  }
}
