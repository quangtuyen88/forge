import XCTest
@testable import ForgeCore

/// The engine reads `SetLog.rpe` whether or not anyone rated the set. These tests measure
/// what that is worth. Nothing here changes a training rule — they are the evidence the
/// decision needs.
final class EffortDivergenceTests: XCTestCase {
  private let bench = ExerciseDB.find("bench_press") ?? ExerciseDB.everything[0]

  private func performance(
    _ sets: [SetLog], repRange: ClosedRange<Int> = 8...12, targetRPE: Double = 8
  ) -> ExercisePerformance {
    ExercisePerformance(exercise: bench, repRange: repRange, targetRPE: targetRPE, sets: sets)
  }

  private func set(
    reps: Int = 10, rpe: Double = 8, reported: Bool = true
  ) -> SetLog {
    SetLog(weightKg: 80, reps: reps, rpe: rpe, effortReported: reported)
  }

  // MARK: - The measurement

  /// The exact shape the audit describes: every set carries the plan target because nobody
  /// rated one. The engine concludes "on target" from its own prescription.
  func testUnratedSetsAtTargetMakeTheEngineAgreeWithItself() {
    let report = EffortDivergence.report([
      performance([set(reported: false), set(reported: false)])
    ])
    let entry = report.entries.first
    XCTAssertEqual(entry?.current, .onTarget)
    XCTAssertNil(entry?.honest, "with no rated set there is no effort signal to read")
    XCTAssertTrue(report.diverging.count == 1, "this is the closed loop the audit found")
    XCTAssertEqual(report.unratedSetsRead, 2)
  }

  /// A set rated well above target is real evidence, and the honest path still sees it.
  func testARealReportStillDrivesTheSignal() {
    let report = EffortDivergence.report([
      performance([set(rpe: 9.5), set(rpe: 9.5)])
    ])
    XCTAssertEqual(report.entries.first?.current, .overreached)
    XCTAssertEqual(report.entries.first?.honest, .overreached)
    XCTAssertTrue(report.isClean, "nothing was inferred, so nothing diverges")
  }

  /// The case that actually costs the lifter: unrated sets at the plan target dilute a
  /// genuine hard report into "on target", so the load keeps climbing.
  func testUnratedSetsCanMaskAHardReport() {
    let report = EffortDivergence.report([
      performance([set(rpe: 9.5), set(reported: false), set(reported: false)])
    ])
    let entry = report.entries.first
    XCTAssertEqual(entry?.ratedSets, 1)
    XCTAssertEqual(entry?.totalSets, 3)
    // Both paths call it overreached here — the rule fires on ANY set over target — so the
    // padding is visible in the coverage counts rather than in the verdict.
    XCTAssertEqual(entry?.current, .overreached)
    XCTAssertEqual(entry?.honest, .overreached)
  }

  /// The "easy" branch needs two sets at the top of the range AND at or under target.
  /// Unrated sets at the target satisfy the effort half for free.
  func testUnratedSetsCanManufactureAnEasyVerdict() {
    let report = EffortDivergence.report([
      performance([set(reps: 12, reported: false), set(reps: 12, reported: false)])
    ])
    let entry = report.entries.first
    XCTAssertEqual(entry?.current, .easy, "top-of-range reps plus a borrowed RPE adds volume")
    XCTAssertNil(entry?.honest)
    XCTAssertTrue(entry?.diverges ?? false)
  }

  func testAFullyRatedHistoryNeverDiverges() {
    let report = EffortDivergence.report([
      performance([set(reps: 12, rpe: 7.5), set(reps: 12, rpe: 7.5)])
    ])
    XCTAssertTrue(report.isClean)
    XCTAssertEqual(report.unratedSetsRead, 0)
  }

  func testSetsBelowTheVolumeThresholdAreNotCountedAsCoverage() {
    let report = EffortDivergence.report([
      performance([set(rpe: 5, reported: false), set(rpe: 9.5)])
    ])
    let entry = report.entries.first
    XCTAssertEqual(entry?.totalSets, 1, "an RPE 5 set does not count toward volume at all")
    XCTAssertEqual(entry?.ratedSets, 1)
  }

  func testNoPerformancesIsAnEmptyCleanReport() {
    let report = EffortDivergence.report([])
    XCTAssertTrue(report.entries.isEmpty)
    XCTAssertTrue(report.isClean)
  }

  // MARK: - The flag itself

  func testAnUnreportedSetHasNoReportedEffort() {
    XCTAssertNil(set(reported: false).reportedRPE)
    XCTAssertEqual(set(rpe: 8.5).reportedRPE, 8.5)
  }

  /// Rows written before the flag existed meant "this is the effort", so they decode as
  /// reported. Guessing otherwise would rewrite history to fit a newer opinion.
  func testLegacyRowsDecodeAsReported() throws {
    let legacy = Data(#"{"weightKg":80,"reps":8,"rpe":8}"#.utf8)
    let decoded = try JSONDecoder().decode(SetLog.self, from: legacy)
    XCTAssertTrue(decoded.effortReported)
  }

  func testTheFlagRoundTrips() throws {
    let encoded = try JSONEncoder().encode(set(reported: false))
    let decoded = try JSONDecoder().decode(SetLog.self, from: encoded)
    XCTAssertFalse(decoded.effortReported)
  }
}
