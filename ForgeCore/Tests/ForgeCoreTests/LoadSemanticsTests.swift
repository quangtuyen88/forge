import XCTest

@testable import ForgeCore

final class LoadSemanticsTests: XCTestCase {
  func testLegacyLoadStaysAmbiguous() {
    let descriptor = LoadDescriptor.legacy(weightKg: 80)
    XCTAssertEqual(descriptor.convention, .unknown)
    XCTAssertEqual(descriptor.normalizationStatus, .ambiguous)
  }

  func testComparableContextRequiresSameMeaning() {
    let a = ComparisonContext(
      exerciseID: "bench", equipmentInstanceID: "rack-a", loadModelRevision: 1,
      convention: .totalIncludingBar, normalizationStatus: .verified)
    XCTAssertTrue(a.isComparable(to: a))
    var other = a
    other.equipmentInstanceID = "rack-b"
    XCTAssertFalse(a.isComparable(to: other))
    XCTAssertEqual(a.incompatibility(with: other), "Different equipment instances")
  }

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
