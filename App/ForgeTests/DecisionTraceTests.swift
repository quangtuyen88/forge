import Foundation
import ForgeCore
import SwiftData
import XCTest

@testable import Forge

/// The trace must add explanations without changing what the engine decided, and a retried
/// start must not be able to log the same committed decision twice.
@MainActor
final class DecisionTraceTests: XCTestCase {

  /// The app's own schema, through the shared fixture, so this suite cannot drift from
  /// `ForgeApp.sharedContainer`.
  ///
  /// The container is a stored property on purpose. A `ModelContainer` created inside a
  /// helper and dropped on return takes its persistent store with it, and the `mainContext`
  /// the test kept on calling then traps inside SwiftData mid-insert — an `EXC_BREAKPOINT`
  /// with no error to catch. Holding it for the test's lifetime is the fix.
  private var store: ModelContainer!
  private var context: ModelContext!

  override func setUpWithError() throws {
    try super.setUpWithError()
    store = try JourneyTestStore.inMemory()
    context = store.mainContext
  }

  override func tearDown() {
    context = nil
    store = nil
    super.tearDown()
  }

  private func record(
    id: String, codes: [String], evidence: [String], from: Double = 82.5, to: Double = 85
  ) -> DecisionRecord {
    DecisionRecord(
      id: id,
      date: Date(timeIntervalSince1970: 1_700_000_000),
      type: "load_change",
      exerciseID: "bench_press",
      muscle: nil,
      fromValue: from,
      toValue: to,
      reasonCodes: codes,
      evidence: evidence,
      humanSummary: "Increase Bench Press to 85 kg")
  }

  func testRetriedStartWritesTheLedgerOnce() throws {
    let records = [
      record(id: "exercise:bench_press#increaseLoad", codes: ["completed_all_sets"], evidence: ["82.5 kg × 8"]),
      record(id: "exercise:row#holdLoad", codes: ["rpe_above_target"], evidence: ["RPE 9"]),
    ]

    let first = DecisionTrace.commit(records: records, sessionKey: "session-1", context: context)
    let replay = DecisionTrace.commit(records: records, sessionKey: "session-1", context: context)

    XCTAssertEqual(first.fingerprint, replay.fingerprint)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 2)
  }

  func testRecordOrderDoesNotChangeTheOperationIdentity() throws {
    let a = record(id: "a", codes: ["completed_all_sets"], evidence: ["x"])
    let b = record(id: "b", codes: ["completed_all_sets"], evidence: ["y"])

    DecisionTrace.commit(records: [a, b], sessionKey: "session-1", context: context)
    DecisionTrace.commit(records: [b, a], sessionKey: "session-1", context: context)

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 2)
  }

  func testADifferentSessionOrChangedPlanIsNewWork() throws {
    let a = record(id: "a", codes: ["completed_all_sets"], evidence: ["x"])
    let changed = record(id: "c", codes: ["rpe_above_target"], evidence: ["RPE 9"])

    DecisionTrace.commit(records: [a], sessionKey: "session-1", context: context)
    DecisionTrace.commit(records: [a], sessionKey: "session-2", context: context)
    DecisionTrace.commit(records: [a, changed], sessionKey: "session-1", context: context)

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 4)
  }

  func testStoredEntryKeepsTheRecordedValuesAndReportsItsExportLineage() throws {
    let workout = record(id: "w", codes: ["completed_all_sets"], evidence: ["82.5 kg × 8"])
    let recovery = record(id: "r", codes: ["readiness_low"], evidence: ["readiness 41"])
    DecisionTrace.commit(records: [workout, recovery], sessionKey: "session-1", context: context)

    let stored = try context.fetch(FetchDescriptor<DecisionLogEntry>())
    XCTAssertEqual(stored.count, 2)

    let workoutRow = try XCTUnwrap(stored.first { $0.reasonCodes == ["completed_all_sets"] })
    XCTAssertEqual(workoutRow.fromValue, 82.5)
    XCTAssertEqual(workoutRow.toValue, 85)
    XCTAssertTrue(workoutRow.isCloudExportable)

    let recoveryRow = try XCTUnwrap(stored.first { $0.reasonCodes == ["readiness_low"] })
    XCTAssertFalse(
      recoveryRow.isCloudExportable,
      "a decision that read readiness keeps its explanation on device")
    XCTAssertEqual(
      recoveryRow.evidence, ["readiness 41"],
      "the local Why? card still shows the full reason")
  }

  func testCoachPacketBuiltFromStoredEntriesOmitsRecoveryReasoning() throws {
    DecisionTrace.commit(
      records: [
        record(id: "w", codes: ["completed_all_sets"], evidence: ["82.5 kg × 8"]),
        record(id: "r", codes: ["readiness_low", "sleep_short"], evidence: ["readiness 41", "5.1 h"]),
      ],
      sessionKey: "session-1",
      context: context)

    let stored = try context.fetch(FetchDescriptor<DecisionLogEntry>()).map(\.record)
    let packet = CoachAPI.contextPacket(
      profile: nil, sessions: [], checkIns: [], decisions: stored, bodyweightKg: nil,
      usesLb: false, notes: [], hrv: 68, restingHR: 52)

    let body = packet.rendered()
    XCTAssertFalse(body.contains("readiness"))
    XCTAssertFalse(body.contains("5.1"))
    XCTAssertFalse(body.contains("hrv_ms"))
    XCTAssertTrue(body.contains("82.5 kg"))
    XCTAssertEqual(packet.withheldDecisionCodes, ["readiness_low", "sleep_short"])
  }
}
