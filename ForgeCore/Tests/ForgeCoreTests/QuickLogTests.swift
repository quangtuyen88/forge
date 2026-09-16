import XCTest
@testable import ForgeCore

final class QuickLogTests: XCTestCase {
  private func c(_ id: String, _ name: String) -> QuickLogCandidate {
    QuickLogCandidate(id: id, name: name)
  }

  func testDeadliftWithRpe() {
    let result = QuickLog.parse(
      "deadlift 132.5x8 @8",
      candidates: [c("deadlift", "Deadlift"), c("back_squat", "Back Squat")],
      defaultLb: false)
    XCTAssertEqual(result, QuickLogParse(exerciseID: "deadlift", weightKg: 132.5, reps: 8, rpe: 8))
  }

  func testAliasCommaAndHalfRpe() {
    let result = QuickLog.parse(
      "dl 132,5 x 8 rpe 8.5",
      candidates: [c("deadlift", "Deadlift"), c("back_squat", "Back Squat")],
      defaultLb: false)
    XCTAssertEqual(result, QuickLogParse(exerciseID: "deadlift", weightKg: 132.5, reps: 8, rpe: 8.5))
  }

  func testBenchForReps() {
    let result = QuickLog.parse(
      "bench 100 for 8",
      candidates: [c("barbell_bench", "Barbell Bench Press"), c("db_bench_neutral", "Neutral-Grip Dumbbell Bench Press")],
      defaultLb: false)
    XCTAssertEqual(result?.exerciseID, "barbell_bench")
    XCTAssertEqual(result?.weightKg, 100)
    XCTAssertEqual(result?.reps, 8)
    XCTAssertNil(result?.rpe)
  }

  func testDbCurlAliasAndKg() {
    let result = QuickLog.parse(
      "db curl 12.5kg x 12",
      candidates: [c("dumbbell_curl", "Dumbbell Curl")],
      defaultLb: false)
    XCTAssertEqual(result, QuickLogParse(exerciseID: "dumbbell_curl", weightKg: 12.5, reps: 12, rpe: nil))
  }

  func testLbConversion() {
    let result = QuickLog.parse(
      "ohp 45 lb x 5",
      candidates: [c("overhead_press", "Overhead Press")],
      defaultLb: false)
    XCTAssertEqual(result?.exerciseID, "overhead_press")
    XCTAssertEqual(result?.weightKg ?? 0, 20.41, accuracy: 0.01)
    XCTAssertEqual(result?.reps, 5)
    XCTAssertNil(result?.rpe)
  }

  func testSquatPicksFirstCandidate() {
    let result = QuickLog.parse(
      "squat 140x5@9",
      candidates: [c("back_squat", "Back Squat"), c("front_squat", "Front Squat")],
      defaultLb: false)
    XCTAssertEqual(result?.exerciseID, "back_squat")
    XCTAssertEqual(result?.weightKg, 140)
    XCTAssertEqual(result?.reps, 5)
    XCTAssertEqual(result?.rpe, 9)
  }

  func testNoNumberReturnsNil() {
    XCTAssertNil(QuickLog.parse("nothing here", candidates: [c("deadlift", "Deadlift")], defaultLb: false))
  }

  func testMissingWeightReturnsNil() {
    XCTAssertNil(QuickLog.parse("deadlift x 8", candidates: [c("deadlift", "Deadlift")], defaultLb: false))
  }

  func testUnicodeCrossNoRpe() {
    let result = QuickLog.parse(
      "Deadlift 132.5 × 8",
      candidates: [c("deadlift", "Deadlift")],
      defaultLb: false)
    XCTAssertEqual(result, QuickLogParse(exerciseID: "deadlift", weightKg: 132.5, reps: 8, rpe: nil))
  }
}
