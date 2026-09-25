import XCTest

@testable import ForgeCore

final class TrainingFeaturesTests: XCTestCase {
  func testTravelAndCrowdModesNarrowEquipment() {
    var constraints = TrainingConstraints(activeGymProfileID: "commercial")
    constraints.travelMode = true
    XCTAssertEqual(
      TrainingConstraintEngine.effectiveEquipment(
        base: Set(Equipment.allCases), constraints: constraints),
      [.dumbbell, .bodyweight, .bands])
    constraints.travelMode = false
    constraints.crowdMode = true
    XCTAssertFalse(
      TrainingConstraintEngine.effectiveEquipment(
        base: Set(Equipment.allCases), constraints: constraints
      ).contains(.machine))
  }

  func testProgramHonorsMinimumEffectiveWorkout() {
    var profile = ProfileInput(
      goal: .hypertrophy,
      daysPerWeek: 3,
      sessionLength: .m60,
      equipment: Set(Equipment.allCases))
    profile.minimumEffectiveWorkout = true
    for day in Program.week(1, profile: profile) {
      XCTAssertLessThanOrEqual(day.exercises.count, 3)
      XCTAssertLessThanOrEqual(day.exercises.reduce(0) { $0 + $1.sets }, 8)
    }
  }

  func testProgramHonorsExerciseExclusionAndLock() {
    var profile = ProfileInput(
      goal: .hypertrophy,
      daysPerWeek: 3,
      sessionLength: .m60,
      equipment: Set(Equipment.allCases))
    let first = Program.week(1, profile: profile).first!.exercises.first!.exercise.id
    profile.excludedExerciseIDs = [first]
    XCTAssertFalse(
      Program.week(1, profile: profile).flatMap(\.exercises).contains { $0.exercise.id == first })

    profile.excludedExerciseIDs = []
    profile.lockedExerciseIDs = ["barbell_bench"]
    XCTAssertTrue(
      Program.week(1, profile: profile).flatMap(\.exercises).contains {
        $0.exercise.id == "barbell_bench"
      })
  }

  func testExperimentReadinessUsesFourWeekWindow() {
    let start = Date(timeIntervalSince1970: 0)
    let experiment = TrainingExperiment(
      exerciseID: "bench", intervention: .addSet, startedAt: start, baselineE1RM: 100)
    XCTAssertFalse(experiment.isReady(asOf: start.addingTimeInterval(27 * 86400)))
    XCTAssertTrue(experiment.isReady(asOf: start.addingTimeInterval(28 * 86400)))
  }
}

extension TrainingFeaturesTests {
  func testCoachMemoryInfersTypedFacts() {
    XCTAssertEqual(CoachMemoryKind.infer(from: "No cable station at my gym"), .equipment)
    XCTAssertEqual(CoachMemoryKind.infer(from: "I avoid dips"), .preference)
    XCTAssertEqual(CoachMemoryKind.infer(from: "My knee is sore"), .injury)
  }
}
