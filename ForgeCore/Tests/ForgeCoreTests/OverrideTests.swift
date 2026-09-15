import XCTest
@testable import ForgeCore

final class OverrideTests: XCTestCase {
  func profile(overrides: [String: String]) -> ProfileInput {
    ProfileInput(goal: .hypertrophy, daysPerWeek: 4, sessionLength: .m60, equipment: Set(Equipment.allCases), exerciseOverrides: overrides)
  }

  func testSamePrimaryOverrideApplies() {
    let week = Program.week(1, profile: profile(overrides: ["barbell_bench": "incline_barbell_press"]))
    XCTAssertTrue(week.flatMap(\.exercises).contains { $0.exercise.id == "incline_barbell_press" })
    XCTAssertFalse(week.flatMap(\.exercises).contains { $0.exercise.id == "barbell_bench" })
  }

  func testDifferentPrimaryOverrideIgnored() {
    let week = Program.week(1, profile: profile(overrides: ["barbell_bench": "back_squat"]))
    XCTAssertTrue(week.flatMap(\.exercises).contains { $0.exercise.id == "barbell_bench" })
  }
}
