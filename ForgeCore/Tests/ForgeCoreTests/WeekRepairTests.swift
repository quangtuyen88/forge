import XCTest
@testable import ForgeCore

final class WeekRepairTests: XCTestCase {
  func testNoOptionsWhenNothingMissed() {
    XCTAssertEqual(WeekRepair.options(missed: 0, daysLeftInWeek: 3), [])
    XCTAssertEqual(WeekRepair.options(missed: -1, daysLeftInWeek: 3), [])
  }

  func testCanFitOffersShiftFirst() {
    XCTAssertEqual(WeekRepair.options(missed: 2, daysLeftInWeek: 3), [.shift, .light, .skip])
  }

  func testCannotFitOffersCompressFirst() {
    XCTAssertEqual(WeekRepair.options(missed: 3, daysLeftInWeek: 1), [.compress, .light, .skip, .restart])
  }

  func testRestartOnlyWhenMissedAtLeastTwo() {
    XCTAssertEqual(WeekRepair.options(missed: 1, daysLeftInWeek: 0), [.compress, .light, .skip])
  }
}
