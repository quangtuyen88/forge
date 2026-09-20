import ForgeCore
import XCTest

@testable import Forge

/// What the screens are allowed to claim about a session. Each case here is a sentence the
/// app used to say that the log could not support.
@MainActor
final class SessionClaimsTests: XCTestCase {

  // MARK: - F05: one duration, one way of writing it

  func testASessionShorterThanAMinuteSaysSoInsteadOfRoundingToZero() {
    XCTAssertEqual(SessionSummaryView.durationText(28), "Under 1 min")
  }

  func testNoElapsedTimeIsAbsentRatherThanZeroMinutes() {
    XCTAssertEqual(SessionSummaryView.durationText(0), "—")
  }

  func testAWholeMinuteReadsAsMinutes() {
    XCTAssertEqual(SessionSummaryView.durationText(600), "10 min")
  }

  /// The summary and History used to round the same short session to 0 and 1. One rule now.
  func testTheSummaryAndHistoryAgreeOnTheSameShortSession() {
    let container = try? JourneyTestStore.inMemory()
    guard let context = container?.mainContext else { return XCTFail("no store") }
    let session = WorkoutSession(
      date: Date(timeIntervalSince1970: 1_700_000_000), dayName: "Full A", week: 1,
      completed: true)
    context.insert(session)
    let first = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let second = LoggedSet(
      exerciseID: "bench_press", setIndex: 1, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_028))
    first.session = session
    second.session = session
    context.insert(first)
    context.insert(second)

    XCTAssertEqual(SessionMath.durationText([session]), "Under 1 min")
    XCTAssertEqual(SessionSummaryView.durationText(28), SessionMath.durationText([session]))
  }

  // MARK: - F01: effort is an observation

  func testASetLoggedWithoutTouchingRPEReportsNoEffort() {
    let set = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertFalse(set.effortReported)
    XCTAssertNil(set.reportedRPE, "the plan target must not read back as a report")
  }

  func testAnExplicitlyTypedEffortIsARealReport() {
    let set = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8.5, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000), effortReported: true)
    XCTAssertEqual(set.reportedRPE, 8.5)
  }
}
