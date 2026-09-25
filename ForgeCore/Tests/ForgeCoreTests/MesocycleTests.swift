import XCTest
@testable import ForgeCore

final class MesocycleTests: XCTestCase {
  func weeks(_ muscle: Muscle, recoveryReduced: Bool = false) -> [Int?] {
    (1...6).map { Mesocycle.targetSets(muscle: muscle, week: $0, recoveryReduced: recoveryReduced) }
  }

  func testChest() {
    XCTAssertEqual(weeks(.chest), [8, 9, 10, 11, 12, 6])
  }

  func testSideDeltsDoubleStep() {
    XCTAssertEqual(weeks(.sideDelts), [8, 10, 12, 14, 16, 8])
  }

  func testRecoveryReducedLowersWeeklyTargets() {
    for muscle in Muscle.allCases {
      guard let reducedLandmarks = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: true)
      else { continue }
      for week in 1...5 {
        let normal = Mesocycle.targetSets(muscle: muscle, week: week, recoveryReduced: false)!
        let reduced = Mesocycle.targetSets(muscle: muscle, week: week, recoveryReduced: true)!
        XCTAssertLessThan(reduced, normal, "\(muscle) week \(week)")
        XCTAssertGreaterThanOrEqual(reduced, reducedLandmarks.mv, "\(muscle) week \(week)")
      }
      XCTAssertEqual(
        Mesocycle.targetSets(muscle: muscle, week: 6, recoveryReduced: true),
        Mesocycle.targetSets(muscle: muscle, week: 6, recoveryReduced: false), "\(muscle)")
    }
    XCTAssertEqual(Mesocycle.targetSets(muscle: .chest, week: 1, recoveryReduced: true), 7)
    XCTAssertEqual(Mesocycle.targetSets(muscle: .chest, week: 1, recoveryReduced: false), 8)
  }

  func testNilMusclesAndWeeks() {
    XCTAssertNil(Mesocycle.targetSets(muscle: .frontDelts, week: 1, recoveryReduced: false))
    XCTAssertNil(Mesocycle.targetSets(muscle: .forearms, week: 3, recoveryReduced: false))
    XCTAssertNil(Mesocycle.targetSets(muscle: .chest, week: 0, recoveryReduced: false))
    XCTAssertNil(Mesocycle.targetSets(muscle: .chest, week: 7, recoveryReduced: false))
  }
}
