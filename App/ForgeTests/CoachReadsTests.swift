import XCTest
import ForgeCore
@testable import Forge

/// The read side of the coach contract, checked where it matters: what it refuses.
@MainActor
final class CoachReadsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func reads(
    decisions: [DecisionRecord] = [],
    sets: [(exerciseID: String, at: Date, weightKg: Double, reps: Int, rpe: Double, effortReported: Bool)] = [],
    usesLb: Bool = false
  ) -> CoachLocalReads {
    CoachLocalReads(
      planRevision: "r1",
      asOf: now,
      dayName: "Full A",
      prescriptions: [],
      sessionID: "v1#Full A",
      decisions: decisions,
      sets: sets,
      equipmentIDs: ["barbell"],
      excludedExerciseIDs: [],
      minutesPerSession: 60,
      daysPerWeek: 3,
      usesLb: usesLb)
  }

  private func record(id: String, codes: [String], evidence: [String]) -> DecisionRecord {
    DecisionRecord(
      id: id, date: now, type: "load", exerciseID: "bench", muscle: nil,
      fromValue: 80, toValue: 82.5, reasonCodes: codes, evidence: evidence,
      humanSummary: "changed the load")
  }

  func testHealthDerivedDecisionIsWithheldFromAToolRead() {
    let source = reads(decisions: [
      record(id: "d1", codes: [DecisionSignal.readinessLow.code], evidence: ["readiness 61", "HRV 38 ms"])
    ])
    let envelope = source.decision(id: "d1")
    XCTAssertEqual(envelope.status, .notShared)
    XCTAssertNil(envelope.data, "a withheld decision must carry no payload at all")
  }

  func testWorkoutDecisionIsReadableWithoutItsEvidenceProse() {
    let source = reads(decisions: [
      record(id: "d2", codes: [DecisionSignal.repsAtTopOfRange.code], evidence: ["8, 8, 8 reps"])
    ])
    let envelope = source.decision(id: "d2")
    XCTAssertEqual(envelope.status, .ok)
    XCTAssertEqual(envelope.data?.reasonCode, DecisionSignal.repsAtTopOfRange.code)
    // The projection has no evidence field: free text is exactly where a private number leaks.
    XCTAssertNil(envelope.data?.before)
  }

  func testUnreportedEffortIsAbsentNotTheTarget() {
    let source = reads(sets: [
      (exerciseID: "bench", at: now, weightKg: 80, reps: 8, rpe: 8, effortReported: false)
    ])
    let envelope = source.recentSets(exerciseID: "bench", limit: 5)
    XCTAssertEqual(envelope.status, .ok)
    XCTAssertNil(envelope.data?.first?.rpeTenths)
  }

  func testReportedEffortSurvivesAsTenths() {
    let source = reads(sets: [
      (exerciseID: "bench", at: now, weightKg: 80, reps: 8, rpe: 8.5, effortReported: true)
    ])
    XCTAssertEqual(source.recentSets(exerciseID: "bench", limit: 5).data?.first?.rpeTenths, 85)
  }

  func testNoSetsIsNotFoundRatherThanAnEmptySuccess() {
    XCTAssertEqual(reads().recentSets(exerciseID: "bench", limit: 5).status, .notFound)
  }

  func testLoadIsConvertedOnceIntoTheLiftersUnit() {
    let source = reads(sets: [
      (exerciseID: "bench", at: now, weightKg: 100, reps: 5, rpe: 8, effortReported: true)
    ], usesLb: true)
    let load = source.recentSets(exerciseID: "bench", limit: 1).data?.first?.load
    XCTAssertEqual(load?.unit, .lb)
    XCTAssertEqual(Int(load?.value ?? 0), 220)
  }

  func testEveryReadCarriesThePlanItWasTrueFor() {
    let source = reads()
    XCTAssertTrue(source.currentWorkout().isFresh(against: "r1"))
    XCTAssertFalse(source.currentWorkout().isFresh(against: "r2"))
    XCTAssertTrue(source.constraints().isFresh(against: "r1"))
  }
}
