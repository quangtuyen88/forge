import XCTest
@testable import ForgeCore

final class ExerciseDBTests: XCTestCase {
  let requiredIDs = [
    "barbell_bench", "db_bench_neutral", "overhead_press", "landmine_press", "dips",
    "cable_fly", "back_squat", "leg_press", "hack_squat", "lunge",
    "leg_extension", "deadlift", "hip_thrust", "cable_pull_through", "bent_row",
    "chest_supported_row", "romanian_deadlift", "pull_up", "lat_pulldown", "incline_db_press",
    "lateral_raise", "face_pull", "tricep_pushdown", "barbell_curl", "standing_calf_raise",
    "cable_crunch", "leg_curl", "front_squat", "seated_db_press", "hammer_curl",
  ]

  func testCountAtLeast80() {
    XCTAssertGreaterThanOrEqual(ExerciseDB.all.count, 80)
  }

  func testAllIDsUnique() {
    XCTAssertEqual(Set(ExerciseDB.all.map(\.id)).count, ExerciseDB.all.count)
  }

  func testRequiredIDsPresent() {
    for id in requiredIDs {
      XCTAssertNotNil(ExerciseDB.find(id), id)
    }
  }

  func testEveryMusclePrimaryAtLeast3() {
    for muscle in Muscle.allCases {
      let n = ExerciseDB.all.filter { $0.primary == muscle }.count
      XCTAssertGreaterThanOrEqual(n, 3, "\(muscle) has \(n)")
    }
  }

  func testEveryEquipmentAtLeast5() {
    for equipment in Equipment.allCases {
      let n = ExerciseDB.all.filter { $0.equipment == equipment }.count
      XCTAssertGreaterThanOrEqual(n, 5, "\(equipment) has \(n)")
    }
  }

  func testIsolationHasEmptySynergists() {
    for exercise in ExerciseDB.all where !exercise.isCompound {
      XCTAssertTrue(exercise.synergists.isEmpty, exercise.id)
    }
  }

  func testRestSecondsFollowsCompoundFlag() {
    for exercise in ExerciseDB.all {
      XCTAssertEqual(exercise.restSeconds, exercise.isCompound ? 180 : 90, exercise.id)
    }
  }

  func testSmallestIncrementFollowsEquipment() {
    let expected: [Equipment: Double] = [
      .barbell: 2.5, .dumbbell: 1.0, .machine: 2.5, .cable: 2.5, .bodyweight: 1.0, .bands: 1.0,
    ]
    for exercise in ExerciseDB.all {
      XCTAssertEqual(exercise.smallestIncrementKg, expected[exercise.equipment]!, exercise.id)
    }
  }

  func testMatchingFiltersEquipment() {
    let barbells = ExerciseDB.matching(equipment: [.barbell])
    XCTAssertGreaterThanOrEqual(barbells.count, 5)
    XCTAssertTrue(barbells.allSatisfy { $0.equipment == .barbell })
    XCTAssertTrue(ExerciseDB.matching(equipment: []).isEmpty)
  }

  func testFindUnknownReturnsNil() {
    XCTAssertNil(ExerciseDB.find("nope"))
  }
}
