import XCTest

@testable import ForgeCore

final class LoadSemanticsTests: XCTestCase {
  func testAmbiguousHistoryNeverCompares() {
    let legacy = ComparisonContext(
      exerciseID: "curl", convention: .unknown, normalizationStatus: .ambiguous)
    XCTAssertFalse(legacy.isComparable(to: legacy))
  }

  func testLoadEntryAcceptsTypedLoads() {
    XCTAssertEqual(LoadEntry.parse("60", allowsZero: false), 60)
    XCTAssertEqual(LoadEntry.parse("62,5", allowsZero: false), 62.5)
    XCTAssertEqual(LoadEntry.parse("62.56", allowsZero: false), 62.56)
    XCTAssertEqual(LoadEntry.parse(" 80 ", allowsZero: false), 80)
  }

  func testLoadEntryRejectsUnusableText() {
    XCTAssertNil(LoadEntry.parse("", allowsZero: false))
    XCTAssertNil(LoadEntry.parse("62.555", allowsZero: false))
    XCTAssertNil(LoadEntry.parse("-5", allowsZero: false))
    XCTAssertNil(LoadEntry.parse("inf", allowsZero: true))
    XCTAssertNil(LoadEntry.parse("nan", allowsZero: true))
    XCTAssertNil(LoadEntry.parse("2000.5", allowsZero: false))
  }

  func testLoadEntryZeroFollowsTheMovement() {
    XCTAssertNil(LoadEntry.parse("0", allowsZero: false))
    XCTAssertEqual(LoadEntry.parse("0", allowsZero: true), 0)
  }
}
