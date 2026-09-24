import ForgeCore
import XCTest

@testable import Forge

/// Today's goal card: which session counts as done, and what share of the plan it logged.
@MainActor
final class TodayGoalTests: XCTestCase {
  func testPercentIsTheRoundedShareOfPlannedSets() {
    XCTAssertEqual(TodayGoal.percent(logged: 14, planned: 16), 88)
    XCTAssertEqual(TodayGoal.percent(logged: 17, planned: 16), 106)
  }

  func testAnUnknownPlanHasNoPercent() {
    XCTAssertNil(TodayGoal.percent(logged: 5, planned: 0))
  }

  func testOnlyAFinishedUndeletedSessionFromTodayCounts() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func session(_ date: Date, completed: Bool, deleted: Bool = false) -> WorkoutSession {
      let s = WorkoutSession(date: date, dayName: "Full A", week: 1, completed: completed)
      s.tombstoned = deleted
      context.insert(s)
      return s
    }
    let yesterday = session(now.addingTimeInterval(-86_400), completed: true)
    let open = session(now, completed: false)
    let deleted = session(now, completed: true, deleted: true)
    XCTAssertNil(TodayGoal.finishedToday([yesterday, open, deleted], now: now))

    let done = session(now.addingTimeInterval(-60), completed: true)
    XCTAssertTrue(TodayGoal.finishedToday([yesterday, done, open, deleted], now: now) === done)
  }

  func testPrimaryMusclesKeepTrainingOrderAndDropRepeats() throws {
    let bench = try XCTUnwrap(ExerciseDB.find("barbell_bench")).primary
    let squat = try XCTUnwrap(ExerciseDB.find("back_squat")).primary
    XCTAssertEqual(
      TodayGoal.primaryMuscles(["barbell_bench", "back_squat", "barbell_bench", "unknown"]),
      [bench, squat])
  }
}
