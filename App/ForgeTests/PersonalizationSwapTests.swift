import XCTest
import ForgeCore
@testable import Forge

/// The Settings "gym change" line: what removing gym equipment or adding an injury flag
/// does to this week's exercises.
final class PersonalizationSwapTests: XCTestCase {
  private func input(equipment: Set<Equipment>) -> ProfileInput {
    ProfileInput(
      goal: .hypertrophy,
      experience: .intermediate,
      daysPerWeek: 3,
      sessionLength: .m60,
      equipment: equipment,
      split: .auto)
  }

  func testRemovingCableAndMachineSwapsExercises() {
    let before = input(equipment: Set(Equipment.allCases))
    var afterEquipment = before.equipment
    afterEquipment.remove(.cable)
    afterEquipment.remove(.machine)
    let after = input(equipment: afterEquipment)

    let swaps = Personalization.exerciseSwaps(before: before, after: after)
    XCTAssertFalse(swaps.isEmpty)

    for swap in swaps where swap.contains(" → ") {
      let to = String(swap.split(separator: " → ", maxSplits: 1).last ?? "")
      let equipment = ExerciseDB.all.first { $0.localizedName == to }?.equipment
      XCTAssertNotEqual(equipment, .cable, "right-hand side \(to) still uses cable")
      XCTAssertNotEqual(equipment, .machine, "right-hand side \(to) still uses machine")
    }
  }

  func testSameSetupHasNoSwaps() {
    let setup = input(equipment: Set(Equipment.allCases))
    XCTAssertEqual(Personalization.exerciseSwaps(before: setup, after: setup), [])
  }
}
