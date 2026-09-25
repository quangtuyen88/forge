import XCTest
@testable import ForgeCore

final class VolumeTests: XCTestCase {
  let bench = ExerciseDB.find("barbell_bench")!
  let curl = ExerciseDB.find("barbell_curl")!

  func testRIRAndCounting() {
    let s = SetLog(weightKg: 100, reps: 8, rpe: 7.5)
    XCTAssertEqual(s.rir, 2.5, accuracy: 0.0001)
    XCTAssertTrue(SetLog(weightKg: 100, reps: 8, rpe: 6).countsTowardVolume)
    XCTAssertFalse(SetLog(weightKg: 100, reps: 8, rpe: 5.9).countsTowardVolume)
    XCTAssertFalse(SetLog(weightKg: 100, reps: 8, rpe: 5.5).countsTowardVolume)
  }

  func testWeeklySetsSums() {
    let hard = SetLog(weightKg: 100, reps: 8, rpe: 8)
    let w = Volume.weeklySets([
      (exercise: bench, set: hard),
      (exercise: bench, set: hard),
      (exercise: curl, set: SetLog(weightKg: 30, reps: 12, rpe: 9)),
      (exercise: bench, set: SetLog(weightKg: 100, reps: 10, rpe: 5)),
    ])
    XCTAssertEqual(w[.chest]!, 2.0, accuracy: 0.0001)
    XCTAssertEqual(w[.triceps]!, 1.0, accuracy: 0.0001)
    XCTAssertEqual(w[.frontDelts]!, 1.0, accuracy: 0.0001)
    XCTAssertEqual(w[.biceps]!, 1.0, accuracy: 0.0001)
    XCTAssertEqual(w.count, 4)
  }
}
