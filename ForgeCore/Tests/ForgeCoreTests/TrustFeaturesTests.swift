import XCTest

@testable import ForgeCore

// MARK: - deterministic fixtures

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func timeOffset(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

private func makeRecord(
  id: String,
  exerciseID: String? = "back_squat",
  type: String = "load_change",
  from: Double? = 80,
  to: Double? = 85,
  evidence: [String] = ["80 kg × 8 @ 7.5"],
  summary: String = "Increase Back squat to 85 kg"
) -> DecisionRecord {
  DecisionRecord(
    id: id, date: t0, type: type, exerciseID: exerciseID, muscle: exerciseID == nil ? "quads" : nil,
    fromValue: from, toValue: to,
    reasonCodes: ["completed_all_sets"], evidence: evidence, humanSummary: summary)
}

private let fullCoverage = EvidenceCoverage(required: [.completedAllSets], present: [.completedAllSets])

private func makeSnapshot(
  _ id: String,
  version: String = "v1",
  exerciseID: String? = "back_squat",
  coverage: EvidenceCoverage = fullCoverage,
  authorization: UserAuthorization = .granted,
  policy: RecommendationEligibilityPolicy = .consequential,
  expiresAt: Date? = nil,
  type: String = "load_change",
  to: Double? = 85,
  evidence: [String] = ["80 kg × 8 @ 7.5"]
) -> RecommendationSnapshot {
  RecommendationSnapshot(
    id: RecommendationID(id),
    programVersion: ProgramVersionID(version),
    createdAt: t0,
    expiresAt: expiresAt,
    record: makeRecord(id: id, exerciseID: exerciseID, type: type, to: to, evidence: evidence),
    coverage: coverage,
    policy: policy,
    authorization: authorization)
}

private func makeEntry(_ id: String, sets: Int = 3, low: Int = 5, high: Int = 8, rpe: Double? = 8) -> ProgramExerciseEntry {
  ProgramExerciseEntry(exerciseID: id, sets: sets, repRangeLower: low, repRangeUpper: high, targetRPE: rpe)
}

private func makeDay(_ name: String, _ entries: [ProgramExerciseEntry]) -> ProgramDay {
  ProgramDay(name: name, exercises: entries)
}

private func makeVersion(_ number: Int, _ days: [ProgramDay], note: String? = nil) -> ProgramVersion {
  ProgramVersion(number: number, createdAt: t0, note: note, days: days)
}

private func makeImported(
  formatVersion: Int = 1,
  title: String = "Hypertrophy Block",
  versions: [ProgramVersion],
  active: Int? = nil
) -> ImportedProgram {
  ImportedProgram(
    id: "prog-1", formatVersion: formatVersion, title: title,
    source: ProgramSource(kind: .file, name: "coach.json"), importedAt: t0,
    versions: versions, activeVersionNumber: active)
}

private let knownExercises: (String) -> Bool = { ["back_squat", "bench_press", "deadlift"].contains($0) }

// MARK: - Recommendation ledger: codable

final class RecommendationLedgerCodableTests: XCTestCase {
  func testSnapshotRoundTripsThroughCodable() throws {
    let original = makeSnapshot("rec-1", expiresAt: timeOffset(3600))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RecommendationSnapshot.self, from: data)
    XCTAssertEqual(decoded, original)
    XCTAssertEqual(decoded.id, RecommendationID("rec-1"))
    XCTAssertEqual(decoded.programVersion, ProgramVersionID("v1"))
    XCTAssertEqual(decoded.subjectKey, "exercise:back_squat")
  }

  func testLedgerRoundTripsThroughCodable() throws {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    XCTAssertTrue(ledger.record(makeSnapshot("rec-1")))
    XCTAssertTrue(ledger.record(makeSnapshot("rec-2", exerciseID: "bench_press")))
    _ = ledger.apply(RecommendationID("rec-1"), at: timeOffset(10))
    _ = ledger.expose(RecommendationExposure(
      recommendationID: RecommendationID("rec-2"), programVersion: ProgramVersionID("v1"),
      exposedAt: timeOffset(5), surface: "today", wasConsequential: true))

    let data = try JSONEncoder().encode(ledger)
    let decoded = try JSONDecoder().decode(RecommendationLedger.self, from: data)
    XCTAssertEqual(decoded, ledger)
    XCTAssertEqual(decoded.outcome(for: RecommendationID("rec-1"))?.state, .applied)
    XCTAssertEqual(decoded.exposures.count, 1)
  }

  func testEvidenceCoverageFractionAndMissingSignals() {
    let coverage = EvidenceCoverage(required: [.completedAllSets, .rpeBelowTarget], present: [.completedAllSets])
    XCTAssertEqual(coverage.fraction, 0.5, accuracy: 0.0001)
    XCTAssertEqual(coverage.missingSignals, ["rpe_below_target"])
    XCTAssertFalse(coverage.isComplete)

    let empty = EvidenceCoverage(required: [], present: [])
    XCTAssertEqual(empty.fraction, 1)
    XCTAssertTrue(empty.isComplete)
  }
}

// MARK: - Recommendation ledger: gating

final class RecommendationLedgerGateTests: XCTestCase {
  func testCannotApplyWithoutExplicitAuthorization() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", authorization: .notRequested))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .ineligible([.authorizationMissing]))
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.state, .failed)

    // An out-of-band authorization unblocks it.
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), authorization: .granted, at: timeOffset(2)), .applied)
  }

  func testDeniedAndRevokedAuthorizationAreIneligible() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("a", authorization: .denied))
    _ = ledger.record(makeSnapshot("b", exerciseID: "bench_press", authorization: .revoked))
    XCTAssertEqual(ledger.apply(RecommendationID("a"), at: timeOffset(1)), .ineligible([.authorizationDenied]))
    XCTAssertEqual(ledger.apply(RecommendationID("b"), at: timeOffset(1)), .ineligible([.authorizationRevoked]))
  }

  func testInsufficientEvidenceIsIneligible() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    let partial = EvidenceCoverage(required: [.completedAllSets, .rpeBelowTarget], present: [.completedAllSets])
    _ = ledger.record(makeSnapshot("rec-1", coverage: partial))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .ineligible([.insufficientEvidence]))
  }

  func testInformationalPolicyNeedsNoAuthorization() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", authorization: .notRequested, policy: .informational))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .applied)
  }

  func testUnknownRecommendation() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    XCTAssertEqual(ledger.apply(RecommendationID("nope"), at: timeOffset(1)), .unknownRecommendation)
  }

  func testApplyIsIdempotent() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1"))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .applied)
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(2)), .alreadyApplied)
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(3)), .alreadyApplied)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.appliedCount, 1)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.appliedAt, timeOffset(1))
  }

  func testStaleAfterProgramVersionAdvances() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", version: "v1"))
    ledger.advanceProgramVersion(to: ProgramVersionID("v2"))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .stale)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.state, .stale)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.reason, "version_drift")
  }

  func testStaleAfterExpiry() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", expiresAt: timeOffset(60)))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(59)), .applied)

    var other = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = other.record(makeSnapshot("rec-2", exerciseID: "bench_press", expiresAt: timeOffset(60)))
    XCTAssertEqual(other.apply(RecommendationID("rec-2"), at: timeOffset(60)), .stale)
    XCTAssertEqual(other.outcome(for: RecommendationID("rec-2"))?.reason, "expired")
  }

  func testConflictOnSameSubjectInSameVersion() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1"))
    _ = ledger.record(makeSnapshot("rec-2"))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .applied)
    XCTAssertEqual(ledger.apply(RecommendationID("rec-2"), at: timeOffset(2)), .conflict(RecommendationID("rec-1")))
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-2"))?.state, .conflict)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-2"))?.conflictingRecommendationID, RecommendationID("rec-1"))
  }

  func testDifferentSubjectsDoNotConflict() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", exerciseID: "back_squat"))
    _ = ledger.record(makeSnapshot("rec-2", exerciseID: "bench_press"))
    XCTAssertEqual(ledger.apply(RecommendationID("rec-1"), at: timeOffset(1)), .applied)
    XCTAssertEqual(ledger.apply(RecommendationID("rec-2"), at: timeOffset(2)), .applied)
  }

  func testMalformedSnapshotsFailValidation() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("no-evidence", evidence: []))
    _ = ledger.record(makeSnapshot("bad-type", exerciseID: "deadlift", type: "banana"))
    _ = ledger.record(makeSnapshot("zero-load", exerciseID: "bench_press", to: 0))
    _ = ledger.record(makeSnapshot("no-summary", exerciseID: "row", evidence: ["x"]))

    XCTAssertEqual(ledger.apply(RecommendationID("no-evidence"), at: timeOffset(1)), .failed([.missingEvidence]))
    XCTAssertEqual(ledger.apply(RecommendationID("bad-type"), at: timeOffset(1)), .failed([.unsupportedActionType]))
    XCTAssertEqual(ledger.apply(RecommendationID("zero-load"), at: timeOffset(1)), .failed([.nonPositiveTargetLoad]))
  }

  func testValidationFlagsExpiryBeforeCreation() {
    let bad = RecommendationSnapshot(
      id: RecommendationID("rec-1"), programVersion: ProgramVersionID("v1"),
      createdAt: timeOffset(100), expiresAt: timeOffset(0), record: makeRecord(id: "rec-1"),
      coverage: fullCoverage)
    XCTAssertEqual(RecommendationValidationPolicy.validate(bad), [.expiryBeforeCreation])
  }

  func testMarkFailedRecordsReason() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1"))
    ledger.markFailed(RecommendationID("rec-1"), reason: "executor_error", at: timeOffset(4))
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.state, .failed)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.reason, "executor_error")
  }
}

// MARK: - Recommendation ledger: immutability & exposure

final class RecommendationLedgerImmutabilityTests: XCTestCase {
  func testRecordingIsWriteOnce() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    XCTAssertTrue(ledger.record(makeSnapshot("rec-1", version: "v1")))
    XCTAssertFalse(ledger.record(makeSnapshot("rec-1", version: "v2")))
    XCTAssertEqual(ledger.snapshot(for: RecommendationID("rec-1"))?.programVersion, ProgramVersionID("v1"))
  }

  func testOutcomeStartsProposed() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1"))
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.state, .proposed)
    XCTAssertEqual(ledger.outcome(for: RecommendationID("rec-1"))?.appliedCount, 0)
  }

  func testExposureRequiresRecordedSnapshotAndDeduplicates() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    let exposure = RecommendationExposure(
      recommendationID: RecommendationID("rec-1"), programVersion: ProgramVersionID("v1"),
      exposedAt: timeOffset(1), surface: "today", wasConsequential: true)
    XCTAssertFalse(ledger.expose(exposure))

    _ = ledger.record(makeSnapshot("rec-1"))
    XCTAssertTrue(ledger.expose(exposure))
    XCTAssertFalse(ledger.expose(exposure))
    XCTAssertEqual(ledger.exposures(for: RecommendationID("rec-1")).count, 1)
  }

  func testEligibilityLookupMatchesApply() {
    var ledger = RecommendationLedger(currentProgramVersion: ProgramVersionID("v1"))
    _ = ledger.record(makeSnapshot("rec-1", authorization: .notRequested))
    XCTAssertEqual(ledger.eligibility(for: RecommendationID("rec-1"))?.isEligible, false)
    XCTAssertEqual(ledger.eligibility(for: RecommendationID("rec-1"))?.requiresConfirmation, true)
  }
}

// MARK: - Voice conversation coordinator

final class VoiceConversationCoordinatorTests: XCTestCase {
  private func logSet() -> VoiceCommand {
    .logSet(QuickLogParse(exerciseID: "back_squat", weightKg: 100, reps: 5, rpe: 8))
  }

  func testImmediateCommandAppliesStraightAway() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.beginListening)
    XCTAssertEqual(coordinator.state, .listening)
    let effect = coordinator.reduce(.heard(.changeRPE(8)))
    XCTAssertEqual(effect, .apply(.changeRPE(8)))
    XCTAssertEqual(coordinator.state, .applied)
    XCTAssertEqual(coordinator.appliedCount, 1)
  }

  func testConsequentialCommandRequiresConfirmation() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.beginListening)
    let effect = coordinator.reduce(.heard(logSet()))
    XCTAssertEqual(effect, .requestConfirmation(logSet()))
    XCTAssertEqual(coordinator.state, .proposed)
    XCTAssertTrue(coordinator.isAwaitingConfirmation)
    XCTAssertTrue(coordinator.requiresConfirmation)
    XCTAssertEqual(coordinator.appliedCount, 0)
  }

  func testConfirmationFlowAppliesPendingCommand() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(logSet()))
    XCTAssertEqual(coordinator.reduce(.requestConfirmation), .requestConfirmation(logSet()))
    XCTAssertEqual(coordinator.state, .confirming)
    XCTAssertEqual(coordinator.reduce(.confirm), .apply(logSet()))
    XCTAssertEqual(coordinator.state, .applied)
    XCTAssertEqual(coordinator.appliedCount, 1)
  }

  func testConfirmWithoutPendingCommandIsRejected() {
    var coordinator = VoiceConversationCoordinator()
    XCTAssertEqual(coordinator.reduce(.confirm), .reject("nothing_to_confirm"))
  }

  func testDuplicateConfirmationNeverAppliesTwice() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(logSet()))
    XCTAssertEqual(coordinator.reduce(.confirm), .apply(logSet()))
    XCTAssertEqual(coordinator.reduce(.confirm), .ignoreDuplicate(logSet()))
    XCTAssertEqual(coordinator.appliedCount, 1)
    XCTAssertEqual(coordinator.appliedCommandKeys, [logSet().fingerprint])
  }

  func testDuplicateImmediateCommandIsIgnored() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(.changeRPE(9)))
    XCTAssertEqual(coordinator.reduce(.heard(.changeRPE(9))), .ignoreDuplicate(.changeRPE(9)))
    XCTAssertEqual(coordinator.appliedCount, 1)
    XCTAssertEqual(coordinator.reduce(.heard(.changeRPE(8))), .apply(.changeRPE(8)))
    XCTAssertEqual(coordinator.appliedCount, 2)
  }

  func testAmbiguousCommandAsksForClarification() {
    var coordinator = VoiceConversationCoordinator()
    let effect = coordinator.reduce(.heard(.unrecognised("mumble")))
    guard case .requestClarification(let command, let prompt) = effect else {
      return XCTFail("expected clarification, got \(effect)")
    }
    XCTAssertEqual(command, .unrecognised("mumble"))
    XCTAssertFalse(prompt.isEmpty)
    XCTAssertEqual(coordinator.state, .clarifying)
    XCTAssertFalse(coordinator.isAwaitingConfirmation)
  }

  func testSwapExerciseIsAmbiguousBeforeItIsConsequential() {
    var coordinator = VoiceConversationCoordinator()
    let effect = coordinator.reduce(.heard(.swapExercise(exerciseID: "back_squat")))
    guard case .requestClarification = effect else {
      return XCTFail("swap must clarify, got \(effect)")
    }
    XCTAssertEqual(coordinator.state, .clarifying)
  }

  func testClarificationThenApplies() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(.changeReps(to: nil, delta: nil)))
    XCTAssertEqual(coordinator.state, .clarifying)
    XCTAssertEqual(coordinator.reduce(.clarify(.changeReps(to: 9, delta: nil))), .apply(.changeReps(to: 9, delta: nil)))
    XCTAssertEqual(coordinator.state, .applied)
  }

  func testIncompleteUtteranceClarifies() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.beginListening)
    let effect = coordinator.reduce(.heardIncomplete(logSet()))
    guard case .requestClarification = effect else { return XCTFail("expected clarification") }
    XCTAssertEqual(coordinator.state, .clarifying)
    XCTAssertEqual(coordinator.pendingCommand, logSet())
  }

  func testCancelFromConfirming() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(logSet()))
    _ = coordinator.reduce(.requestConfirmation)
    XCTAssertEqual(coordinator.state, .confirming)
    XCTAssertEqual(coordinator.reduce(.cancel), .none)
    XCTAssertEqual(coordinator.state, .cancelled)
    XCTAssertTrue(coordinator.isTerminal)
  }

  func testFailedState() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.beginListening)
    _ = coordinator.reduce(.failed("recognition_error"))
    XCTAssertEqual(coordinator.state, .failed)
    XCTAssertEqual(coordinator.failureReason, "recognition_error")
    XCTAssertTrue(coordinator.isTerminal)
  }

  func testCancelledTurnIgnoresNewCommandsUntilReset() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.beginListening)
    _ = coordinator.reduce(.cancel)
    XCTAssertEqual(coordinator.state, .cancelled)
    XCTAssertEqual(coordinator.reduce(.heard(.changeWeight(deltaKg: 5))), .none)
    XCTAssertEqual(coordinator.appliedCount, 0)

    XCTAssertEqual(coordinator.reduce(.reset), .none)
    XCTAssertEqual(coordinator.state, .idle)
    XCTAssertEqual(coordinator.reduce(.heard(.changeWeight(deltaKg: 5))), .apply(.changeWeight(deltaKg: 5)))
  }

  func testAppliedTurnAcceptsAFollowUpUtterance() {
    var coordinator = VoiceConversationCoordinator()
    _ = coordinator.reduce(.heard(.changeRPE(8)))
    XCTAssertEqual(coordinator.state, .applied)
    XCTAssertEqual(coordinator.reduce(.heard(.changeWeight(deltaKg: 5))), .apply(.changeWeight(deltaKg: 5)))
    XCTAssertEqual(coordinator.appliedCount, 2)
  }

  func testRequestConfirmationWithoutPendingIsRejected() {
    var coordinator = VoiceConversationCoordinator()
    XCTAssertEqual(coordinator.reduce(.requestConfirmation), .reject("nothing_awaiting_confirmation"))
  }
}

// MARK: - Import contracts: codable

final class ProgramImportCodableTests: XCTestCase {
  func testImportedProgramRoundTrips() throws {
    let program = makeImported(
      versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])], note: "Week 1")], active: 1)
    let data = try JSONEncoder().encode(program)
    let decoded = try JSONDecoder().decode(ImportedProgram.self, from: data)
    XCTAssertEqual(decoded, program)
    XCTAssertEqual(decoded.activeVersion?.number, 1)
    XCTAssertEqual(decoded.activeVersion?.exerciseCount, 1)
  }

  func testWarningRoundTrips() throws {
    let warning = ImportWarning(
      code: .unknownExercise, severity: .warning, message: "Unknown exercise.",
      context: ImportWarningContext(day: "Day A", exerciseID: "zercher_squat"))
    let data = try JSONEncoder().encode(warning)
    XCTAssertEqual(try JSONDecoder().decode(ImportWarning.self, from: data), warning)
    XCTAssertEqual(warning.id, "unknownExercise|Day A|zercher_squat|")
  }

  func testPreviewAndDiffRoundTrip() throws {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat", sets: 4)])])])
    let preview = ProgramImportPreview.make(imported: program, knownExercise: knownExercises)
    let data = try JSONEncoder().encode(preview)
    XCTAssertEqual(try JSONDecoder().decode(ProgramImportPreview.self, from: data), preview)
  }

  func testEntryRepRangeIsNilWhenInverted() {
    XCTAssertNil(makeEntry("back_squat", low: 8, high: 5).repRange)
    XCTAssertEqual(makeEntry("back_squat", low: 5, high: 8).repRange, 5...8)
  }
}

// MARK: - Import contracts: validation warnings

final class ProgramImportValidationTests: XCTestCase {
  func testCleanProgramProducesNoWarnings() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat"), makeEntry("bench_press")])])], active: 1)
    XCTAssertEqual(ProgramImportValidator.validate(program, knownExercise: knownExercises), [])
  }

  func testUnknownExerciseWarns() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("zercher_squat")])])])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertEqual(warnings.count, 1)
    XCTAssertEqual(warnings.first?.code, .unknownExercise)
    XCTAssertEqual(warnings.first?.severity, .warning)
    XCTAssertEqual(warnings.first?.context?.exerciseID, "zercher_squat")
    XCTAssertEqual(warnings.first?.context?.day, "Day A")
  }

  func testInvalidSetCountAndRepRangeAreErrors() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat", sets: 99, low: 8, high: 5)])])])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertEqual(Set(warnings.map(\.code)), Set([ImportWarningCode.invalidRepRange, .invalidSetCount]))
    XCTAssertTrue(warnings.allSatisfy { $0.severity == .error })
  }

  func testOutOfRangeRPEWarns() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("deadlift", rpe: 12)])])])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertEqual(warnings.map(\.code), [.outOfRangeRPE])
    XCTAssertEqual(warnings.first?.severity, .warning)
  }

  func testDuplicateDaysWarnAndDuplicateVersionsError() {
    let program = makeImported(versions: [
      makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")]), makeDay("Day A", [makeEntry("bench_press")])]),
      makeVersion(1, [makeDay("Day B", [makeEntry("deadlift")])]),
    ])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertTrue(warnings.contains { $0.code == .duplicateDay && $0.severity == .warning })
    XCTAssertTrue(warnings.contains { $0.code == .duplicateVersion && $0.severity == .error })
  }

  func testEmptyProgramAndMissingTitle() {
    let program = makeImported(title: "   ", versions: [])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertTrue(warnings.contains { $0.code == .emptyProgram && $0.severity == .error })
    XCTAssertTrue(warnings.contains { $0.code == .missingTitle && $0.severity == .warning })
  }

  func testUnsupportedFormatVersionIsBlocking() {
    let program = makeImported(formatVersion: 7, versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])])
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertEqual(warnings.first?.code, .unsupportedFormatVersion)
    XCTAssertEqual(warnings.first?.severity, .error)
  }

  func testEmptyDayAndMissingActiveVersion() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [])])], active: 9)
    let warnings = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertTrue(warnings.contains { $0.code == .emptyDay })
    XCTAssertTrue(warnings.contains { $0.code == .noActiveVersion })
  }

  func testWarningsAreDeterministicallyOrdered() {
    let program = makeImported(versions: [makeVersion(1, [
      makeDay("B", [makeEntry("unknown_b")]),
      makeDay("A", [makeEntry("unknown_a")]),
    ])])
    let first = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    let second = ProgramImportValidator.validate(program, knownExercise: knownExercises)
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.compactMap { $0.context?.day }, ["A", "B"])
  }
}

// MARK: - Import contracts: preview, diff, activation

final class ProgramImportPreviewTests: XCTestCase {
  func testPreviewCountsActiveVersion() {
    let program = makeImported(versions: [
      makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])]),
      makeVersion(2, [makeDay("Day A", [makeEntry("back_squat")]), makeDay("Day B", [makeEntry("bench_press")])]),
    ], active: 2)
    let preview = ProgramImportPreview.make(imported: program, knownExercise: knownExercises)
    XCTAssertEqual(preview.versionCount, 2)
    XCTAssertEqual(preview.activeVersionNumber, 2)
    XCTAssertEqual(preview.dayCount, 2)
    XCTAssertEqual(preview.exerciseCount, 2)
    XCTAssertTrue(preview.isActivatable)
    XCTAssertFalse(preview.hasBlockingErrors)
  }

  func testPreviewBlocksActivationOnErrors() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat", sets: 0)])])])
    let preview = ProgramImportPreview.make(imported: program, knownExercise: knownExercises)
    XCTAssertFalse(preview.isActivatable)
    XCTAssertEqual(preview.errorCount, 1)
    XCTAssertEqual(preview.warningCount, 0)
  }

  func testDiffBetweenVersions() {
    let previous = makeVersion(1, [makeDay("Day A", [makeEntry("back_squat", sets: 3)])])
    let current = makeVersion(2, [makeDay("Day A", [makeEntry("back_squat", sets: 4), makeEntry("bench_press", sets: 3)])])
    let diff = ProgramVersionDiff.between(previous, current)
    XCTAssertEqual(diff.fromVersion, 1)
    XCTAssertEqual(diff.toVersion, 2)
    XCTAssertEqual(diff.addedExerciseIDs, ["bench_press"])
    XCTAssertEqual(diff.removedExerciseIDs, [])
    XCTAssertEqual(diff.setCountChanges, [ProgramSetChange(day: "Day A", exerciseID: "back_squat", fromSets: 3, toSets: 4)])
    XCTAssertFalse(diff.isEmpty)
  }

  func testDiffFromNothingAddsEverything() {
    let current = makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])
    let diff = ProgramVersionDiff.between(nil, current)
    XCTAssertEqual(diff.addedExerciseIDs, ["back_squat"])
    XCTAssertEqual(diff.removedExerciseIDs, [])
    XCTAssertEqual(diff.fromVersion, nil)
  }

  func testIdenticalVersionsDiffEmpty() {
    let v = makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])
    XCTAssertTrue(ProgramVersionDiff.between(v, v).isEmpty)
  }

  func testExplicitActivation() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])])
    guard case .activated(let activated) = ProgramActivationPolicy.activate(
      program, version: 1, at: timeOffset(30), knownExercise: knownExercises) else {
      return XCTFail("expected activation")
    }
    XCTAssertEqual(activated.activeVersionNumber, 1)
    XCTAssertEqual(activated.importedAt, timeOffset(30))
  }

  func testActivationRejectsUnknownVersion() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])])
    XCTAssertEqual(
      ProgramActivationPolicy.activate(program, version: 9, at: timeOffset(30), knownExercise: knownExercises),
      .versionNotFound(9))
  }

  func testActivationRejectsBlockingErrors() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat", sets: 99)])])])
    guard case .rejected(let blockers) = ProgramActivationPolicy.activate(
      program, version: 1, at: timeOffset(30), knownExercise: knownExercises) else {
      return XCTFail("expected rejection")
    }
    XCTAssertEqual(blockers.map(\.code), [.invalidSetCount])
    XCTAssertTrue(blockers.allSatisfy { $0.severity == .error })
  }

  func testImportDoesNotActivateImplicitly() {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])])
    XCTAssertNil(program.activeVersionNumber)
    XCTAssertEqual(program.activeVersion?.number, 1, "the fallback is only a preview convenience")
    XCTAssertNil(program.activating(version: 4, at: timeOffset(1)))
  }
}

// MARK: - Sharing: redaction & revocable tokens

final class ProgramSharingTests: XCTestCase {
  func testRedactionStripsIdentityAndHistory() {
    let program = makeImported(
      title: "My Block",
      versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])],
      active: 1)
    let shareable = ProgramRedactor.redact(program, note: "4-day upper/lower", at: timeOffset(50))

    XCTAssertEqual(shareable.title, "My Block")
    XCTAssertEqual(shareable.note, "4-day upper/lower")
    XCTAssertEqual(shareable.exerciseIDs, ["back_squat"])
    XCTAssertEqual(shareable.days, program.activeVersion?.days)
  }

  func testSharedPayloadCarriesNoHistoryOrCoachMemory() throws {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])], active: 1)
    let json = ProgramRedactor.redact(program, at: timeOffset(50)).json()

    for key in ["rawHistory", "history", "coachMemory", "loggedSets", "sessionLog", "userName", "token"] {
      XCTAssertFalse(json.contains("\"\(key)\""), "shared payload leaked \(key): \(json)")
    }
  }

  func testDecoderRoundTripsCleanPayload() throws {
    let program = makeImported(versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])], active: 1)
    let data = try JSONEncoder().encode(program)
    XCTAssertEqual(try ProgramImportDecoder.decode(data), program)
  }

  func testRedactedFileReimportsAsStableUnactivatedDraft() throws {
    let program = makeImported(
      versions: [makeVersion(1, [makeDay("Day A", [makeEntry("back_squat")])])], active: 1)
    let share = ProgramRedactor.redact(program, at: timeOffset(50))
    let data = Data(share.json().utf8)
    let draft = try ProgramImportDecoder.decode(data)
    XCTAssertEqual(draft.id, try ProgramImportDecoder.decode(data).id)
    XCTAssertEqual(draft.title, share.title)
    XCTAssertEqual(draft.versions.first?.days, share.days)
    XCTAssertEqual(draft.source.kind, .file)
    XCTAssertNil(draft.source.tokenID)
    XCTAssertNil(draft.activeVersionNumber)
    XCTAssertNotEqual(draft.id, program.id)
  }

  func testRedactedFileStillRejectsPersonalData() throws {
    let share = ShareableProgram(
      formatVersion: 1, title: "Shared", createdAt: t0,
      days: [makeDay("Day A", [makeEntry("back_squat")])])
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(share.json().utf8)) as? [String: Any])
    object["loggedSets"] = [["weightKg": 100]]
    let data = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try ProgramImportDecoder.decode(data)) { error in
      XCTAssertEqual(error as? ProgramImportError, .containsSensitiveContent(["loggedSets"]))
    }
  }

  func testDecoderRejectsOversizedInputBeforeParsing() throws {
    let share = ShareableProgram(
      formatVersion: 1, title: "Shared", createdAt: t0,
      days: [makeDay("Day A", [makeEntry("back_squat")])])
    var data = Data(share.json().utf8)
    data.append(Data(repeating: 32, count: ProgramImportDecoder.maximumBytes))
    XCTAssertThrowsError(try ProgramImportDecoder.decode(data)) { error in
      XCTAssertEqual(error as? ProgramImportError, .malformedJSON)
    }
  }

  func testDecoderRejectsSmuggledHistory() throws {
    let json = """
    {"id":"p","formatVersion":1,"title":"T","importedAt":0,
     "source":{"kind":"file"},
     "versions":[{"number":1,"createdAt":0,"days":[]}],
     "rawHistory":[{"exercise":"back_squat","weightKg":100}],
     "coachMemory":{"note":"knee pain"}}
    """
    XCTAssertThrowsError(try ProgramImportDecoder.decode(Data(json.utf8))) { error in
      XCTAssertEqual(error as? ProgramImportError, .containsSensitiveContent(["coachMemory", "rawHistory"]))
    }
  }

  func testDecoderRejectsMalformedJSON() {
    XCTAssertThrowsError(try ProgramImportDecoder.decode(Data("not json".utf8))) { error in
      XCTAssertEqual(error as? ProgramImportError, .malformedJSON)
    }
  }

  func testDecoderRejectsStructurallyInvalidPayload() {
    let json = #"{"id":"p","formatVersion":1"#
    XCTAssertThrowsError(try ProgramImportDecoder.decode(Data(json.utf8)))
  }

  func testTokenIsActiveBeforeExpiry() {
    let token = ShareTokenMetadata(
      id: "tok-1", programID: "prog-1", scope: .readOnly,
      createdAt: timeOffset(0), expiresAt: timeOffset(3600))
    XCTAssertEqual(token.status(at: timeOffset(0)), .active)
    XCTAssertEqual(token.status(at: timeOffset(3599)), .active)
    XCTAssertTrue(token.isValid(at: timeOffset(3599)))
  }

  func testTokenExpiresInclusively() {
    let token = ShareTokenMetadata(
      id: "tok-1", programID: "prog-1", scope: .remixable,
      createdAt: timeOffset(0), expiresAt: timeOffset(3600))
    XCTAssertEqual(ShareTokenPolicy.status(token, at: timeOffset(3600)), .expired)
    XCTAssertFalse(ShareTokenPolicy.accepts(token, at: timeOffset(3600)))
  }

  func testTokenRevocationIsFinal() {
    let token = ShareTokenMetadata(
      id: "tok-1", programID: "prog-1", scope: .readOnly,
      createdAt: timeOffset(0), expiresAt: timeOffset(3600))
    let revoked = token.revoking(at: timeOffset(10))
    XCTAssertTrue(revoked.isRevoked)
    XCTAssertEqual(revoked.revokedAt, timeOffset(10))
    XCTAssertEqual(revoked.status(at: timeOffset(20)), .revoked)
    XCTAssertEqual(revoked.status(at: timeOffset(9999)), .revoked)
    XCTAssertEqual(ShareTokenPolicy.status(revoked, at: timeOffset(20)), .revoked)
  }

  func testTokenRoundTripsThroughCodable() throws {
    let token = ShareTokenMetadata(
      id: "tok-1", programID: "prog-1", scope: .remixable,
      createdAt: timeOffset(0), expiresAt: timeOffset(3600), revokedAt: timeOffset(10))
    let data = try JSONEncoder().encode(token)
    let decoded = try JSONDecoder().decode(ShareTokenMetadata.self, from: data)
    XCTAssertEqual(decoded, token)
    XCTAssertEqual(decoded.status(at: timeOffset(20)), .revoked)
  }

  func testShareableProgramRoundTrips() throws {
    let shareable = ShareableProgram(
      formatVersion: 1, title: "Block", note: "hi", createdAt: timeOffset(1),
      days: [makeDay("Day A", [makeEntry("back_squat")])])
    let data = try JSONEncoder().encode(shareable)
    XCTAssertEqual(try JSONDecoder().decode(ShareableProgram.self, from: data), shareable)
  }
}
