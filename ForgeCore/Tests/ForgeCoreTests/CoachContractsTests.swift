import XCTest
@testable import ForgeCore

final class CoachContractsTests: XCTestCase {

  // MARK: - Plan identity

  func testDigestIsStableAndOrderSensitive() {
    XCTAssertEqual(PlanRevision.digest(["a", "b"]), PlanRevision.digest(["a", "b"]))
    XCTAssertNotEqual(PlanRevision.digest(["a", "b"]), PlanRevision.digest(["b", "a"]))
  }

  func testDigestSeparatesComponentsSoConcatenationCannotCollide() {
    XCTAssertNotEqual(PlanRevision.digest(["ab", "c"]), PlanRevision.digest(["a", "bc"]))
  }

  // MARK: - Read envelope

  func testFreshOnlyWhenOkAndSameRevision() {
    let now = Date(timeIntervalSince1970: 1_000)
    let ok = CoachEnvelope<String>.ok("x", asOf: now, planRevision: "r1")
    XCTAssertTrue(ok.isFresh(against: "r1"))
    XCTAssertFalse(ok.isFresh(against: "r2"))
    XCTAssertFalse(CoachEnvelope<String>.failure(.unavailable, asOf: now, planRevision: "r1").isFresh(against: "r1"))
  }

  func testHealthDerivedDecisionIsNotShared() {
    let now = Date(timeIntervalSince1970: 1_000)
    let record = DecisionRecord(
      id: "d1", date: now, type: "load", exerciseID: "bench", muscle: nil,
      fromValue: 80, toValue: 80, reasonCodes: [DecisionSignal.readinessLow.code],
      evidence: ["readiness 61"], humanSummary: "held the load")
    let envelope = CoachReadContracts.decision(record, asOf: now, planRevision: "r1")
    XCTAssertEqual(envelope.status, .notShared)
    XCTAssertNil(envelope.data)
  }

  func testWorkoutOnlyDecisionIsReadable() {
    let now = Date(timeIntervalSince1970: 1_000)
    let record = DecisionRecord(
      id: "d2", date: now, type: "load", exerciseID: "bench", muscle: nil,
      fromValue: 80, toValue: 82.5, reasonCodes: [DecisionSignal.repsAtTopOfRange.code],
      evidence: ["8 reps"], humanSummary: "added 2.5 kg")
    let envelope = CoachReadContracts.decision(record, asOf: now, planRevision: "r1")
    XCTAssertEqual(envelope.status, .ok)
    XCTAssertEqual(envelope.data?.decisionID, "d2")
    XCTAssertEqual(envelope.data?.reasonCode, DecisionSignal.repsAtTopOfRange.code)
  }

  func testMissingDecisionIsNotFoundNotEmptySuccess() {
    let now = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(CoachReadContracts.decision(nil, asOf: now, planRevision: "r1").status, .notFound)
  }

  func testAmbiguousExerciseNameAsksInsteadOfChoosing() {
    let now = Date(timeIntervalSince1970: 1_000)
    let candidates = [("bench_bb", "Barbell Bench Press"), ("bench_db", "Dumbbell Bench Press")]
    let envelope = CoachReadContracts.resolveExercise("bench", candidates: candidates, asOf: now, planRevision: "r1")
    XCTAssertEqual(envelope.status, .needsClarification)
  }

  func testUnambiguousExerciseNameResolves() {
    let now = Date(timeIntervalSince1970: 1_000)
    let candidates = [("bench_bb", "Barbell Bench Press"), ("squat_bb", "Back Squat")]
    let envelope = CoachReadContracts.resolveExercise("back squat", candidates: candidates, asOf: now, planRevision: "r1")
    XCTAssertEqual(envelope.data, "squat_bb")
  }

  // MARK: - Bound consent

  private func preview(
    digest: String = "diff-1", revision: String = "r1", expires: TimeInterval = 300
  ) -> CommitPreview {
    CommitPreview(
      recommendationID: RecommendationID("rec-1"),
      programVersion: ProgramVersionID("v1"),
      planRevision: revision,
      previewDigest: digest,
      expiresAt: Date(timeIntervalSince1970: 1_000 + expires))
  }

  private func check(
    approval: CommitApproval, stored: CommitPreview?, owner: String = "me", expected: String = "me",
    revision: String = "r1", version: String = "v1", receipt: String? = nil,
    now: TimeInterval = 1_000
  ) -> CommitRejection? {
    CoachCommitPolicy.check(
      approval: approval, storedProposal: stored, ownerKey: owner, expectedOwnerKey: expected,
      currentPlanRevision: revision, currentProgramVersion: ProgramVersionID(version),
      existingReceiptDigest: receipt, now: Date(timeIntervalSince1970: now))
  }

  func testMatchingApprovalPasses() {
    let stored = preview()
    let approval = CommitApproval(preview: stored, approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertNil(check(approval: approval, stored: stored))
  }

  func testExpiredPreviewIsRejected() {
    let stored = preview(expires: 10)
    let approval = CommitApproval(preview: stored, approvedAt: Date(timeIntervalSince1970: 1_005))
    XCTAssertEqual(check(approval: approval, stored: stored, now: 1_020), .expired)
  }

  func testDifferentDiffWithTheSameIDIsADigestMismatch() {
    let stored = preview(digest: "diff-1")
    let approval = CommitApproval(preview: preview(digest: "diff-2"), approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(check(approval: approval, stored: stored), .digestMismatch)
  }

  func testPlanMovedAfterThePreviewIsStale() {
    let stored = preview(revision: "r1")
    let approval = CommitApproval(preview: stored, approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(check(approval: approval, stored: stored, revision: "r2"), .staleRevision)
  }

  func testAnotherOwnersResourceIsRejectedBeforeAnythingElse() {
    let approval = CommitApproval(preview: preview(), approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(check(approval: approval, stored: nil, owner: "someone-else"), .wrongOwner)
  }

  func testUnknownProposalIsRejected() {
    let approval = CommitApproval(preview: preview(), approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(check(approval: approval, stored: nil), .unknownProposal)
  }

  func testReplayOfTheSameOperationReturnsTheOriginalReceipt() {
    let stored = preview()
    let approval = CommitApproval(preview: stored, approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertNil(check(approval: approval, stored: stored, receipt: "diff-1", now: 9_999))
  }

  func testReplayWithDifferentContentIsAConflict() {
    let stored = preview()
    let approval = CommitApproval(preview: stored, approvedAt: Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(
      check(approval: approval, stored: stored, receipt: "diff-old"), .replayedWithDifferentContent)
  }

  func testRejectionsMapOntoExistingLedgerStates() {
    XCTAssertEqual(CommitRejection.expired.ledgerState, .stale)
    XCTAssertEqual(CommitRejection.staleRevision.ledgerState, .stale)
    XCTAssertEqual(CommitRejection.digestMismatch.ledgerState, .conflict)
    XCTAssertEqual(CommitRejection.replayedWithDifferentContent.ledgerState, .conflict)
    XCTAssertEqual(CommitRejection.wrongOwner.ledgerState, .failed)
    XCTAssertEqual(CommitRejection.unknownProposal.ledgerState, .failed)
  }

  func testPreviewDigestSeparatesDifferentChanges() {
    let a = CommitPreview.digest(
      ownerKey: "me", recommendationID: RecommendationID("rec-1"), components: ["swap", "bench", "db_bench"])
    let b = CommitPreview.digest(
      ownerKey: "me", recommendationID: RecommendationID("rec-1"), components: ["swap", "bench", "machine_press"])
    XCTAssertNotEqual(a, b)
  }

  /// The app switches language in place and formats numbers by region. Neither is a change
  /// to the plan, so neither may turn a legitimate apply into a mismatch.
  func testALanguageOrRegionChangeDoesNotInvalidateAnApproval() {
    let english = CommitPreview(
      recommendationID: RecommendationID("rec-1"), programVersion: ProgramVersionID("v1"),
      planRevision: "r1",
      previewDigest: CommitPreview.digest(
        ownerKey: "me", recommendationID: RecommendationID("rec-1"), components: ["swap", "bench", "db_bench"]),
      displayedLines: ["Swap Bench Press", "82.5 kg → 85 kg"],
      expiresAt: Date(timeIntervalSince1970: 1_300))
    let vietnamese = CommitPreview(
      recommendationID: english.recommendationID, programVersion: english.programVersion,
      planRevision: english.planRevision,
      previewDigest: CommitPreview.digest(
        ownerKey: "me", recommendationID: RecommendationID("rec-1"), components: ["swap", "bench", "db_bench"]),
      displayedLines: ["Đổi Bench Press", "82,5 kg → 85 kg"],
      expiresAt: english.expiresAt)
    XCTAssertEqual(english.previewDigest, vietnamese.previewDigest)
    XCTAssertNil(
      check(
        approval: CommitApproval(preview: vietnamese, approvedAt: Date(timeIntervalSince1970: 1_001)),
        stored: english))
  }

  func testTheLinesTheLifterSawAreKeptVerbatim() {
    let preview = CommitPreview(
      recommendationID: RecommendationID("rec-1"), programVersion: ProgramVersionID("v1"),
      planRevision: "r1", previewDigest: "d", displayedLines: ["Swap Bench Press"],
      expiresAt: Date(timeIntervalSince1970: 1_300))
    XCTAssertEqual(preview.displayedLines, ["Swap Bench Press"])
  }

  // MARK: - Clarification lifecycle
  //
  // The resolver is pure and was always testable. What actually broke in the app was the
  // lifecycle around it, so that is what these pin.

  private func resolved(_ original: String, _ choice: String) -> String { "\(original) [\(choice)]" }

  func testAnUnrelatedFollowUpDropsTheClarificationAndIsAskedVerbatim() {
    var conversation = CoachConversation()
    conversation.clarify(question: "how heavy should i go", options: ["Body weight", "The load for an exercise"])
    let step = conversation.step(reply: "when is my deload", resolvedQuestion: resolved)
    XCTAssertEqual(step, .ask("when is my deload", skipClassification: false))
    XCTAssertFalse(conversation.isAwaitingChoice)
  }

  func testChoosingAnOptionAsksTheOriginalQuestionNotTheReply() {
    var conversation = CoachConversation()
    conversation.clarify(question: "why is it down", options: ["Body weight", "The load for an exercise"])
    let step = conversation.step(reply: "body weight", resolvedQuestion: resolved)
    XCTAssertEqual(step, .ask("why is it down [Body weight]", skipClassification: true))
    XCTAssertFalse(conversation.isAwaitingChoice)
  }

  func testABareYesReAsksOnceThenAnswersTheOriginalQuestion() {
    var conversation = CoachConversation()
    conversation.clarify(question: "why is it down", options: ["Body weight", "The load for an exercise"])
    XCTAssertEqual(
      conversation.step(reply: "Yes", resolvedQuestion: resolved),
      .reAsk(options: ["Body weight", "The load for an exercise"]))
    XCTAssertEqual(
      conversation.step(reply: "yes", resolvedQuestion: resolved),
      .ask("why is it down", skipClassification: true))
    XCTAssertFalse(conversation.isAwaitingChoice)
  }

  /// The retry counter is per clarification. A second ambiguous question in the same
  /// conversation must get its own re-ask, not inherit the first one's exhausted count.
  func testASecondClarificationStartsItsOwnRetryCount() {
    var conversation = CoachConversation()
    conversation.clarify(question: "first", options: ["A", "B"])
    _ = conversation.step(reply: "yes", resolvedQuestion: resolved)
    _ = conversation.step(reply: "yes", resolvedQuestion: resolved)
    conversation.clarify(question: "second", options: ["A", "B"])
    XCTAssertEqual(conversation.step(reply: "yes", resolvedQuestion: resolved), .reAsk(options: ["A", "B"]))
  }

  func testWithNoClarificationEveryMessageIsJustTheQuestion() {
    var conversation = CoachConversation()
    XCTAssertEqual(
      conversation.step(reply: "why did bench drop", resolvedQuestion: resolved),
      .ask("why did bench drop", skipClassification: false))
  }

  func testResetClearsAPendingClarification() {
    var conversation = CoachConversation()
    conversation.clarify(question: "q", options: ["A", "B"])
    conversation.reset()
    XCTAssertFalse(conversation.isAwaitingChoice)
    XCTAssertTrue(conversation.options.isEmpty)
  }

  // MARK: - Two devices, one progression

  func testTheSameStartFromTwoDevicesIsOneOperation() {
    let phone = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-20",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d1", "d2"]))
    let watch = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-20",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d2", "d1"]))
    XCTAssertEqual(phone, watch, "device and arrival order must not change identity")
  }

  func testADifferentDecisionSetIsADifferentOperation() {
    let first = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-20",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d1"]))
    let second = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-20",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d1", "d2"]))
    XCTAssertNotEqual(first, second)
  }

  func testTheSameDayOnTwoDatesIsNotTheSameOperation() {
    let monday = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-20",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d1"]))
    let tuesday = TrainingFingerprint.make(
      kind: .applyDecisionLedger, resourceID: "day-1#2026-09-21",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["d1"]))
    XCTAssertNotEqual(monday, tuesday)
  }
}
