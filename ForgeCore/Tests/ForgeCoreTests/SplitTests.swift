import XCTest
@testable import ForgeCore

final class SplitTests: XCTestCase {
  func makeProfile(days: Int, style: SplitStyle, session: SessionLength = .m90) -> ProfileInput {
    ProfileInput(goal: .hypertrophy, daysPerWeek: days, sessionLength: session, equipment: Set(Equipment.allCases), split: style)
  }

  func testEveryStyleAndDayCountBuildsFullWeek() {
    for style in SplitStyle.allCases {
      for days in 3...6 {
        let names = Program.split(daysPerWeek: days, style: style)
        XCTAssertEqual(names.count, days, "\(style) \(days)")
        let week = Program.week(1, profile: makeProfile(days: days, style: style))
        XCTAssertEqual(week.map(\.name), names, "\(style) \(days)")
        for day in week {
          XCTAssertGreaterThanOrEqual(day.exercises.count, 1, day.name)
          XCTAssertLessThanOrEqual(day.exercises.count, 8, day.name)
        }
      }
    }
  }

  func testArnoldSixDaysRepeatsChestBack() {
    let names = Program.split(daysPerWeek: 6, style: .arnold)
    XCTAssertEqual(names.filter { $0 == "Chest+Back" }.count, 2)
  }

  func testPushPullPutsQuadsOnPushDays() {
    let week = Program.week(1, profile: makeProfile(days: 4, style: .pushPull))
    XCTAssertEqual(week.map(\.name), ["Push+", "Pull+", "Push+", "Pull+"])
    for day in week where day.name == "Push+" {
      XCTAssertTrue(day.exercises.contains { $0.exercise.primary == .quads }, day.name)
    }
  }

  func testAutoSplitUnchanged() {
    for days in 3...6 {
      XCTAssertEqual(Program.split(daysPerWeek: days, style: .auto), Program.split(daysPerWeek: days), "\(days)")
    }
  }
}
