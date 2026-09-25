import XCTest
@testable import ForgeCore

final class ExerciseTests: XCTestCase {
  func testDefaultDifficulty() {
    XCTAssertEqual(ExerciseDB.find("barbell_bench")!.difficulty, .intermediate)
    XCTAssertEqual(ExerciseDB.find("cable_fly")!.difficulty, .beginner)
  }

  func testAdvancedByTechnicalID() {
    let powerClean = Exercise(id: "power_clean", name: "Power Clean", pattern: .hinge, primary: .hamstrings, synergists: [], isCompound: true, equipment: .barbell)
    XCTAssertEqual(powerClean.difficulty, .advanced)
    for id in ["nordic_curl", "handstand_push_up", "snatch_grip_deadlift"] {
      XCTAssertEqual(ExerciseDB.find(id)!.difficulty, .advanced, id)
    }
  }
}
