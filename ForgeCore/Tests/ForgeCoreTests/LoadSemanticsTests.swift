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
}
