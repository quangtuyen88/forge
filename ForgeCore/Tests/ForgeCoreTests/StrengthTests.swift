import XCTest
@testable import ForgeCore

final class StrengthTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let wk: TimeInterval = 7 * 24 * 3600

  func testEpley() {
    XCTAssertEqual(Strength.epley(weightKg: 100, reps: 10), 133.33, accuracy: 0.01)
    XCTAssertEqual(Strength.epley(weightKg: 100, reps: 1), 103.33, accuracy: 0.01)
  }

  func testPlateauTrueWhenFlatVsEarlierBest() {
    let h = [
      E1RMPoint(date: now - 10 * wk, e1rm: 140),
      E1RMPoint(date: now - 6 * wk, e1rm: 140),
      E1RMPoint(date: now - 2 * wk, e1rm: 140),
      E1RMPoint(date: now - 1 * wk, e1rm: 138),
    ]
    XCTAssertTrue(Strength.isPlateaued(h, asOf: now))
  }

  func testPlateauFalseWhenImproving() {
    let h = [
      E1RMPoint(date: now - 10 * wk, e1rm: 130),
      E1RMPoint(date: now - 8 * wk, e1rm: 132),
      E1RMPoint(date: now - 2 * wk, e1rm: 140),
    ]
    XCTAssertFalse(Strength.isPlateaued(h, asOf: now))
  }

  func testPlateauFalseWithNoPriorData() {
    let h = [
      E1RMPoint(date: now - 2 * wk, e1rm: 150),
      E1RMPoint(date: now - 1 * wk, e1rm: 148),
    ]
    XCTAssertFalse(Strength.isPlateaued(h, asOf: now))
  }

  func testPlateauIgnoresPointsOutsideWindow() {
    let h = [
      E1RMPoint(date: now - 20 * wk, e1rm: 999),
      E1RMPoint(date: now - 8 * wk, e1rm: 140),
      E1RMPoint(date: now - 1 * wk, e1rm: 140),
    ]
    XCTAssertTrue(Strength.isPlateaued(h, asOf: now))
  }

  func testEstimatedStartingLoads() {
    let cases: [(String, Double, Double?)] = [
      ("barbell_bench", 100, 60),
      ("back_squat", 100, 80),
      ("deadlift", 100, 100),
      ("overhead_press", 100, 40),
      ("bent_row", 100, 55),
      ("lateral_raise", 100, nil),
    ]
    for (id, bw, expected) in cases {
      let actual = Strength.estimatedStartingLoad(exerciseID: id, bodyweightKg: bw)
      if let e = expected {
        XCTAssertEqual(actual!, e, accuracy: 0.001, id)
      } else {
        XCTAssertNil(actual, id)
      }
    }
  }

  func testEstimatedStartingLoadByExercise() {
    XCTAssertEqual(Strength.estimatedStartingLoad(exercise: ExerciseDB.find("back_squat")!, bodyweightKg: 80), 64, accuracy: 0.001)
    XCTAssertEqual(Strength.estimatedStartingLoad(exercise: ExerciseDB.find("leg_extension")!, bodyweightKg: 80), 27.5, accuracy: 0.001)
    XCTAssertEqual(Strength.estimatedStartingLoad(exercise: ExerciseDB.find("pull_up")!, bodyweightKg: 80), 0, accuracy: 0.001)
    XCTAssertEqual(Strength.estimatedStartingLoad(exercise: ExerciseDB.find("lateral_raise")!, bodyweightKg: 80), 10, accuracy: 0.001)
  }
}
