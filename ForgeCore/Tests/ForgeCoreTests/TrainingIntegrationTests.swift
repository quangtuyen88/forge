import XCTest

@testable import ForgeCore

/// The integration boundary's job is provenance, not training rules: these tests pin the
/// lineage gate that keeps Health-derived reasoning off the network, and the identity rules
/// that stop a retry from committing a change twice.
final class TrainingIntegrationTests: XCTestCase {

  // MARK: Load values

  func testLoadValueRoundTripsWithoutFloatingPointDrift() {
    let load = LoadValue(kg: 82.5)
    XCTAssertEqual(load.milliUnits, 82_500)
    XCTAssertEqual(load.unit, .kg)
    XCTAssertEqual(load.value, 82.5, accuracy: 0.000_001)

    let encoded = try! JSONEncoder().encode(load)
    let decoded = try! JSONDecoder().decode(LoadValue.self, from: encoded)
    XCTAssertEqual(decoded, load)
  }

  func testPoundsAreCarriedAsPoundsNotSilentlyConverted() {
    let lb = LoadValue(milliUnits: 185_000, unit: .lb)
    XCTAssertEqual(lb.unit, .lb)
    XCTAssertEqual(lb.value, 185)
    XCTAssertNotEqual(lb, LoadValue(kg: 185))
  }

  func testNilLoadMeansUncalibratedNotZero() {
    let prescription = SetPrescription(
      exerciseID: "pull_up", load: nil, workingSets: 3, minimumReps: 6, maximumReps: 10,
      targetRPETenths: 80)
    XCTAssertNil(prescription.load)
    let json = String(data: try! JSONEncoder().encode(prescription), encoding: .utf8)!
    XCTAssertFalse(json.contains("\"milliUnits\":0"))
  }

  // MARK: Signal provenance

  func testEverySignalHasAnOriginAndRecoverySignalsAreHealthDerived() {
    for signal in DecisionSignal.allCases {
      XCTAssertNotEqual(signal.origin, .unknown, "\(signal) must declare a real origin")
    }
    XCTAssertEqual(DecisionSignal.readinessLow.origin, .derivedHealth)
    XCTAssertEqual(DecisionSignal.readinessNormal.origin, .derivedHealth)
    XCTAssertEqual(DecisionSignal.readinessHigh.origin, .derivedHealth)
    XCTAssertEqual(DecisionSignal.sleepShort.origin, .derivedHealth)
    XCTAssertEqual(DecisionSignal.sorenessHigh.origin, .manualCheckIn)
    XCTAssertEqual(DecisionSignal.repsAtTopOfRange.origin, .workoutLog)
    XCTAssertEqual(DecisionSignal.deloadWeek.origin, .programConfiguration)
    XCTAssertEqual(DecisionSignal.userOverride.origin, .userPreference)
  }

  // MARK: Export policy

  private func decision(
    reasonCode: String, origins: Set<EvidenceOrigin>, evidence: [EvidenceFact] = []
  ) -> ProgramDecision {
    ProgramDecision(
      id: "decision-1",
      requestID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
      planID: "plan-1",
      planRevisionBefore: 41,
      planRevisionAfter: 42,
      sessionID: "session-1",
      scope: .futureSession,
      engineVersion: "engine-test",
      rulesVersion: "rules-test",
      reasonCode: reasonCode,
      before: SetPrescription(
        exerciseID: "bench_press", load: LoadValue(kg: 82.5), workingSets: 3, minimumReps: 6,
        maximumReps: 8, targetRPETenths: 80),
      after: SetPrescription(
        exerciseID: "bench_press", load: LoadValue(kg: 85), workingSets: 3, minimumReps: 6,
        maximumReps: 8, targetRPETenths: 80),
      evidence: evidence,
      dependencyOrigins: origins,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000))
  }

  func testWorkoutOnlyDecisionWithReviewedCodeIsExportable() {
    let projection = CloudExportPolicy().project(
      decision(reasonCode: TrainingReasonCode.progressionRepRangePassed, origins: [.workoutLog]))
    XCTAssertEqual(projection?.id, "decision-1")
    XCTAssertEqual(projection?.planRevisionAfter, 42)
    XCTAssertEqual(projection?.after.load, LoadValue(kg: 85))
  }

  func testHealthDerivedDependencyBlocksExportEvenWhenEvidenceLooksLikeAWorkout() {
    // The visible evidence is a logged set; the decision still passed through a readiness
    // branch, so the lineage — not the display text — decides.
    let hidden = decision(
      reasonCode: TrainingReasonCode.progressionRepRangePassed,
      origins: [.workoutLog, .derivedHealth],
      evidence: [EvidenceFact(key: "last_set", displayValue: "82.5 kg × 8", origin: .workoutLog)])
    XCTAssertNil(CloudExportPolicy().project(hidden))
  }

  func testEvidenceOriginAloneCanBlockExport() {
    let hidden = decision(
      reasonCode: TrainingReasonCode.holdTargetMet,
      origins: [.workoutLog],
      evidence: [EvidenceFact(key: "readiness", displayValue: "82", origin: .derivedHealth)])
    XCTAssertNil(CloudExportPolicy().project(hidden))
  }

  func testUnreviewedOrUnknownReasonCodeIsNeverExported() {
    XCTAssertNil(
      CloudExportPolicy().project(
        decision(reasonCode: "load.some.future_rule", origins: [.workoutLog])))
    XCTAssertNil(
      CloudExportPolicy().project(
        decision(reasonCode: TrainingReasonCode.deloadScheduled, origins: [.programConfiguration])),
      "a code outside the reviewed set stays local until it is reviewed")
  }

  func testDecisionWithNoOriginsIsNotExported() {
    XCTAssertNil(
      CloudExportPolicy().project(
        decision(reasonCode: TrainingReasonCode.holdTargetMet, origins: [])))
  }

  func testProjectionCarriesNoEvidenceOrHealthFields() {
    let projection = CloudExportPolicy().project(
      decision(
        reasonCode: TrainingReasonCode.holdTargetMet,
        origins: [.workoutLog],
        evidence: [EvidenceFact(key: "last_set", displayValue: "82.5 kg × 8", origin: .workoutLog)]))
    let json = String(data: try! JSONEncoder().encode(projection!), encoding: .utf8)!
    XCTAssertFalse(json.contains("evidence"))
    XCTAssertFalse(json.contains("82.5 kg"))
    XCTAssertTrue(json.contains("\"schemaVersion\":1"))
  }

  // MARK: Legacy ledger lineage

  private func record(_ codes: [String], evidence: [String]) -> DecisionRecord {
    DecisionRecord(
      id: "r-\(codes.joined(separator: "-"))",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      type: "load_change",
      exerciseID: "bench_press",
      muscle: nil,
      fromValue: 82.5,
      toValue: 85,
      reasonCodes: codes,
      evidence: evidence,
      humanSummary: "Increase Bench Press to 85 kg")
  }

  func testLedgerRecordWithReadinessEvidenceIsWithheldFromCloud() {
    let readiness = record(
      [DecisionSignal.completedAllSets.code, DecisionSignal.readinessNormal.code],
      evidence: ["82.5 kg × 8", "readiness 82"])
    XCTAssertFalse(DecisionProvenance.isCloudExportable(readiness))
    XCTAssertTrue(
      DecisionProvenance.origins(readiness).contains(.derivedHealth))
  }

  func testWorkoutOnlyLedgerRecordIsExportable() {
    let workout = record(
      [DecisionSignal.completedAllSets.code, DecisionSignal.repsAtTopOfRange.code],
      evidence: ["82.5 kg × 8", "8/8 reps"])
    XCTAssertTrue(DecisionProvenance.isCloudExportable(workout))
  }

  func testUnknownReasonCodeIsTreatedAsUnknownProvenanceAndWithheld() {
    let mystery = record(["some_future_signal"], evidence: ["?"])
    XCTAssertEqual(DecisionProvenance.origins(mystery), [.unknown])
    XCTAssertFalse(DecisionProvenance.isCloudExportable(mystery))
  }

  func testEmptyReasonCodesAreWithheld() {
    XCTAssertFalse(DecisionProvenance.isCloudExportable(record([], evidence: [])))
  }

  func testCloudExportableFiltersAndReportsWhatWasWithheld() {
    let workout = record(
      [DecisionSignal.completedAllSets.code], evidence: ["82.5 kg × 8"])
    let private1 = record(
      [DecisionSignal.readinessLow.code], evidence: ["readiness 41"])
    let private2 = record([DecisionSignal.sleepShort.code], evidence: ["5.1 h"])

    let exportable = DecisionProvenance.cloudExportable([workout, private1, private2])
    XCTAssertEqual(exportable.map(\.id), [workout.id])

    let withheld = DecisionProvenance.withheldCodes([workout, private1, private2])
    XCTAssertEqual(withheld, [DecisionSignal.readinessLow.code, DecisionSignal.sleepShort.code])
  }

  func testPayloadBuiltFromFilteredRecordsCarriesNoRecoveryText() {
    let records = [
      record([DecisionSignal.completedAllSets.code], evidence: ["82.5 kg × 8"]),
      record([DecisionSignal.readinessLow.code], evidence: ["readiness 41"]),
    ]
    let payload = DecisionLedger.payload(DecisionProvenance.cloudExportable(records))
    XCTAssertFalse(payload.contains("readiness"))
    XCTAssertTrue(payload.contains("82.5 kg"))
  }

  // MARK: Coach packet lineage

  func testCoachPacketWithholdsHealthFieldsAndHealthDerivedDecisions() {
    let fields = [
      ContextField(key: "goal", value: "Hypertrophy", source: .app),
      ContextField(key: "hrv_ms", value: "68", source: .healthKit),
      ContextField(key: "coach_notes", value: "left shoulder", source: .user),
    ]
    let decisions = [
      record([DecisionSignal.completedAllSets.code], evidence: ["82.5 kg × 8"]),
      record([DecisionSignal.readinessLow.code], evidence: ["readiness 41"]),
    ]
    let packet = CoachContextBuilder.packet(fields: fields, decisions: decisions)

    XCTAssertEqual(packet.withheld, ["hrv_ms"])
    XCTAssertEqual(packet.withheldDecisionCodes, [DecisionSignal.readinessLow.code])
    XCTAssertEqual(packet.decisions.count, 1)

    let body = packet.rendered()
    XCTAssertTrue(body.contains("goal: Hypertrophy"))
    XCTAssertFalse(body.contains("hrv_ms"))
    XCTAssertFalse(body.contains("readiness"))
    XCTAssertFalse(body.contains("41"))
  }

  func testCoachPacketKeepsWorkoutDecisionsIntact() {
    let workout = record(
      [DecisionSignal.completedAllSets.code, DecisionSignal.repsAtTopOfRange.code],
      evidence: ["82.5 kg × 8", "8/8 reps"])
    let packet = CoachContextBuilder.packet(fields: [], decisions: [workout])
    XCTAssertEqual(packet.decisions.map(\.id), [workout.id])
    XCTAssertTrue(packet.withheldDecisionCodes.isEmpty)
    XCTAssertTrue(packet.rendered().contains("82.5 kg"))
  }

  // MARK: Request identity

  func testFingerprintIsStableAcrossRetriesAndIgnoresTimestamps() {
    let first = TrainingRequest(
      id: UUID(), kind: .applyDecisionLedger, resourceID: "session-1",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["b", "a"]),
      requestedAt: Date(timeIntervalSince1970: 10))
    let retry = TrainingRequest(
      id: UUID(), kind: .applyDecisionLedger, resourceID: "session-1",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["a", "b"]),
      requestedAt: Date(timeIntervalSince1970: 9_999))
    XCTAssertEqual(first.fingerprint, retry.fingerprint)
  }

  func testDifferentContentProducesADifferentFingerprint() {
    let base = TrainingRequest(
      id: UUID(), kind: .applyDecisionLedger, resourceID: "session-1",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["a"]),
      requestedAt: Date(timeIntervalSince1970: 10))
    let changed = TrainingRequest(
      id: UUID(), kind: .applyDecisionLedger, resourceID: "session-1",
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: ["a", "c"]),
      requestedAt: Date(timeIntervalSince1970: 10))
    XCTAssertNotEqual(base.fingerprint, changed.fingerprint)
  }

  func testFingerprintSeparatesIntentsOnTheSameResource() {
    XCTAssertNotEqual(
      TrainingFingerprint.make(kind: .shortenSession, resourceID: "s1", contentKey: "30"),
      TrainingFingerprint.make(kind: .swapExercise, resourceID: "s1", contentKey: "30"))
  }
}
