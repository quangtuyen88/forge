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

  func testVideoURLNilUntilBaseSet() {
    XCTAssertNil(ExerciseDB.find("barbell_bench")!.videoURL)
    ExerciseDB.videoBaseURL = URL(string: "https://cdn.example.com/videos")
    defer { ExerciseDB.videoBaseURL = nil }
    XCTAssertEqual(ExerciseDB.find("barbell_bench")!.videoURL?.absoluteString, "https://cdn.example.com/videos/barbell_bench.mp4")
    XCTAssertTrue(ExerciseDB.find("barbell_bench")!.videoURL!.absoluteString.hasSuffix("barbell_bench.mp4"))
  }
}
