import XCTest
@testable import ForgeCore

final class PlateauRescueTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let day: TimeInterval = 86_400

  private func flatHistory(_ id: String, exposures: Int, weight: Double = 80, reps: Int = 8) -> [AuditSet] {
    (0..<exposures).map { i in
      AuditSet(exerciseID: id, date: now.addingTimeInterval(-Double(i) * 7 * day), weightKg: weight, reps: reps, rpe: 8)
    }
  }

  private func rescue(_ id: String = "barbell_bench", history: [AuditSet], weeklySets: Double,
                      landmarks: VolumeLandmarks?, sorenessHigh: Bool = false,
                      recentRPEOverTarget: Bool = false, equipment: Set<Equipment> = [.barbell],
                      injuries: Set<InjuryFlag> = [], recoveryReduced: Bool = false) -> PlateauFinding? {
    PlateauRescue.rescue(exerciseID: id, history: history, repRange: 8...12, weeklySets: weeklySets,
                         landmarks: landmarks, sorenessHigh: sorenessHigh, recentRPEOverTarget: recentRPEOverTarget,
                         equipment: equipment, injuries: injuries, recoveryReduced: recoveryReduced)
  }

  func testSorenessBranchDeloads() {
    let finding = rescue(history: flatHistory("barbell_bench", exposures: 4), weeklySets: 10,
                         landmarks: VolumeLandmarks.base(for: .chest), sorenessHigh: true)
    XCTAssertEqual(finding?.decision.action, .deload)
    XCTAssertEqual(finding?.decision.subject, .exercise(id: "barbell_bench"))
  }

  func testRecoveryReducedLiftsFloorToMV() {
    let history = flatHistory("barbell_bench", exposures: 4)
    let reduced = rescue(history: history, weeklySets: 7,
                         landmarks: VolumeLandmarks.base(for: .chest), recoveryReduced: true)
    XCTAssertNotEqual(reduced?.decision.action, .addSets(1))

    let full = rescue(history: history, weeklySets: 7,
                      landmarks: VolumeLandmarks.base(for: .chest))
    XCTAssertEqual(full?.decision.action, .addSets(1))
  }

  func testAboveMRVBranchRemovesSet() {
    let finding = rescue(history: flatHistory("barbell_bench", exposures: 4), weeklySets: 24,
                         landmarks: VolumeLandmarks.base(for: .chest))
    XCTAssertEqual(finding?.decision.action, .removeSets(1))
  }

  func testSixExposuresBranchSwapsExercise() {
    let finding = rescue(history: flatHistory("barbell_bench", exposures: 6), weeklySets: 10,
                         landmarks: VolumeLandmarks.base(for: .chest), equipment: [.barbell, .dumbbell])
    guard let decision = finding?.decision else { return XCTFail("expected a finding") }
    if case .swapExercise(let from, let to) = decision.action {
      XCTAssertEqual(from, "barbell_bench")
      XCTAssertNotEqual(to, "barbell_bench")
      XCTAssertNotNil(ExerciseDB.find(to))
    } else {
      XCTFail("expected swapExercise, got \(decision.action)")
    }
  }

  func testOtherwiseBranchShiftsRepRange() {
    let finding = rescue(history: flatHistory("barbell_bench", exposures: 4), weeklySets: 10,
                         landmarks: VolumeLandmarks.base(for: .chest), equipment: [.barbell])
    XCTAssertEqual(finding?.decision.action, .changeRepRange(from: 8...12, to: 5...8))
  }

  func testProgressingLiftReturnsNil() {
    let history = [
      AuditSet(exerciseID: "barbell_bench", date: now.addingTimeInterval(-21 * day), weightKg: 80, reps: 8, rpe: 8),
      AuditSet(exerciseID: "barbell_bench", date: now.addingTimeInterval(-14 * day), weightKg: 80, reps: 8, rpe: 8),
      AuditSet(exerciseID: "barbell_bench", date: now.addingTimeInterval(-7 * day), weightKg: 80, reps: 8, rpe: 8),
      AuditSet(exerciseID: "barbell_bench", date: now, weightKg: 85, reps: 8, rpe: 8),
    ]
    XCTAssertNil(rescue(history: history, weeklySets: 10, landmarks: VolumeLandmarks.base(for: .chest)))
  }
}
