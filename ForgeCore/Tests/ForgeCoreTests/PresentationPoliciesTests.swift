import XCTest

@testable import ForgeCore

final class PresentationPoliciesTests: XCTestCase {
  func testRemainingPlannedSetsIgnoresExtraLogsAndNeverGoesNegative() {
    let planned: Set<PlannedSetCoordinate> = [
      .init(exerciseID: "squat", setIndex: 0),
      .init(exerciseID: "squat", setIndex: 1),
    ]
    let logged: Set<PlannedSetCoordinate> = [
      .init(exerciseID: "squat", setIndex: 0),
      .init(exerciseID: "deadlift", setIndex: 0),
      .init(exerciseID: "deadlift", setIndex: 1),
    ]
    XCTAssertEqual(WorkoutProgressPolicy.remainingPlannedSets(planned: planned, logged: logged), 1)
    XCTAssertEqual(WorkoutProgressPolicy.remainingPlannedSets(planned: planned, logged: planned), 0)
  }

  func testRecoveryCollectsBeforeAssessment() {
    XCTAssertEqual(
      RecoveryPresentationPolicy.presentation(sampleCount: 0, assessedSummary: "x"), .empty)
    XCTAssertEqual(
      RecoveryPresentationPolicy.presentation(sampleCount: 1, assessedSummary: "x"),
      .collecting(sampleCount: 1, windowDays: 7))
    XCTAssertEqual(
      RecoveryPresentationPolicy.presentation(sampleCount: 3, assessedSummary: "Ready"),
      .assessed(summary: "Ready", sampleCount: 3, windowDays: 7))
  }

  func testBalanceDoesNotInventRatiosOrAdviceFromSparseData() {
    XCTAssertEqual(
      BalancePresentationPolicy.presentation(
        push: 0, pull: 0, upper: 0, lower: 0, sessionCount: 1, setCount: 2),
      .collecting(sessionCount: 1, setCount: 2))
    let assessed = BalancePresentationPolicy.presentation(
      push: 10, pull: 0, upper: 10, lower: 5, sessionCount: 4, setCount: 20)
    XCTAssertEqual(assessed, .assessed(pushPull: nil, upperLower: 2, sessionCount: 4, setCount: 20))
  }

  func testNewExperimentCollectsInsteadOfShowingZeroEffect() {
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(28 * 86400)
    XCTAssertEqual(
      ExperimentPresentationPolicy.presentation(
        startedAt: start, endsAt: end, comparableCount: 0,
        baseline: 100, current: 100, isActive: true,
        now: start),
      .collecting(day: 1, totalDays: 28, comparableCount: 0))
    XCTAssertEqual(
      ExperimentPresentationPolicy.presentation(
        startedAt: start, endsAt: end, comparableCount: 1,
        baseline: 100, current: 100, isActive: false,
        now: end),
      .inconclusive(reason: "Not enough comparable follow-up sets", comparableCount: 1))
  }

  func testEnrollmentWeekNeverCreatesRetrospectiveMissedSessions() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    XCTAssertEqual(
      WeekStatusPolicy.presentation(
        planned: 3, recorded: 0, daysLeft: 0,
        enrollmentDate: now, now: now),
      WeekStatusPresentation(recorded: 0, planned: 3, remaining: 3, atRisk: 0))
  }

  func testAllRecordedAndAnalysisEligibleScopesStayDistinctAndSelfDescribing() {
    let all = MetricScopePolicy.descriptor(for: .allRecorded)
    let eligible = MetricScopePolicy.descriptor(for: .analysisEligible)

    XCTAssertEqual(all.scope, .allRecorded)
    XCTAssertEqual(all.label, "All recorded")
    XCTAssertFalse(all.excludesUnverifiedSets)
    XCTAssertFalse(all.drivesAnalysis)

    XCTAssertEqual(eligible.scope, .analysisEligible)
    XCTAssertEqual(eligible.label, "Analysis eligible")
    XCTAssertTrue(eligible.excludesUnverifiedSets)
    XCTAssertTrue(eligible.drivesAnalysis)

    XCTAssertNotEqual(all.label, eligible.label)
    XCTAssertNotEqual(all.caption, eligible.caption)
    XCTAssertEqual(MetricScopePolicy.descriptors().count, MetricScope.allCases.count)
    XCTAssertEqual(MetricScopePolicy.descriptors().map(\.scope), [.allRecorded, .analysisEligible])
  }

  func testMetricQualifierOnlyAppearsWhenTheAnalysisScopeDroppedSets() {
    XCTAssertNil(
      MetricScopePolicy.qualifier(
        scope: .allRecorded, recordedSetCount: 120, analysisEligibleSetCount: 118))
    XCTAssertNil(
      MetricScopePolicy.qualifier(
        scope: .analysisEligible, recordedSetCount: 120, analysisEligibleSetCount: 120))
    XCTAssertEqual(
      MetricScopePolicy.qualifier(
        scope: .analysisEligible, recordedSetCount: 120, analysisEligibleSetCount: 118),
      "118 of 120 sets passed the plausibility check")
    // Inconsistent counts (more eligible than recorded) drop nothing, so the qualifier stays
    // quiet rather than claiming a coverage number it cannot support.
    XCTAssertNil(
      MetricScopePolicy.qualifier(
        scope: .analysisEligible, recordedSetCount: 4, analysisEligibleSetCount: 9))
    XCTAssertNil(
      MetricScopePolicy.qualifier(
        scope: .analysisEligible, recordedSetCount: 0, analysisEligibleSetCount: 0))
  }
}
