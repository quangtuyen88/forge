import XCTest
@testable import ForgeCore

final class TimeBudgetTests: XCTestCase {
  private func ex(_ id: String, sets: Int) -> PlannedExercise {
    PlannedExercise(exercise: ExerciseDB.find(id)!, sets: sets, repRange: 8...12, targetRPE: 8)
  }

  private func day(_ exercises: [PlannedExercise]) -> PlannedDay {
    PlannedDay(name: "Test", exercises: exercises)
  }

  func testEstimatedMinutes() {
    // 3 compound sets × (180 + 45) = 675s → 11.25 → 10 min
    XCTAssertEqual(TimeBudget.estimatedMinutes(day([ex("back_squat", sets: 3)])), 10)
  }

  func testTwentyMinutesKeepsFirstCompoundCutsIsolation() {
    let d = day([ex("back_squat", sets: 3), ex("barbell_bench", sets: 3), ex("leg_extension", sets: 3), ex("leg_curl", sets: 3)])
    let result = TimeBudget.fit(d, minutes: 20)
    XCTAssertTrue(result.exercises.contains { $0.exercise.id == "back_squat" })
    XCTAssertFalse(result.exercises.contains { $0.exercise.id == "leg_extension" })
    XCTAssertFalse(result.exercises.contains { $0.exercise.id == "leg_curl" })
    XCTAssertLessThanOrEqual(TimeBudget.estimatedMinutes(result), 20)
  }

  func testSixtyMinutesShortDayUnchanged() {
    let d = day([ex("back_squat", sets: 3)])
    let result = TimeBudget.fit(d, minutes: 60)
    XCTAssertEqual(result.exercises, d.exercises)
    XCTAssertEqual(result.trimmedSets, 0)
  }

  func testFloorNeverEmpty() {
    let d = day([ex("back_squat", sets: 5), ex("barbell_bench", sets: 4)])
    let result = TimeBudget.fit(d, minutes: 5)
    XCTAssertFalse(result.exercises.isEmpty)
    XCTAssertTrue(result.exercises.contains { $0.exercise.id == "back_squat" })
    for e in result.exercises { XCTAssertGreaterThanOrEqual(e.sets, 2) }
  }

  func testTrimmedSetsCounts() {
    let d = day([ex("back_squat", sets: 4), ex("leg_extension", sets: 3), ex("leg_curl", sets: 3)])
    let result = TimeBudget.fit(d, minutes: 20)
    XCTAssertEqual(result.trimmedSets, 3)
  }
}
