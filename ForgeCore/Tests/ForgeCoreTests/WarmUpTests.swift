import XCTest
@testable import ForgeCore

final class WarmUpTests: XCTestCase {
  func testStandardRamp() {
    let ramp = WarmUp.ramp(workingKg: 100, barKg: 20, incrementKg: 2.5)
    XCTAssertEqual(ramp.map(\.kg), [40.0, 60.0, 80.0])
    XCTAssertEqual(ramp.map(\.reps), [8, 5, 3])
  }

  func testLightLoadIsEmpty() {
    XCTAssertTrue(WarmUp.ramp(workingKg: 25, barKg: 20, incrementKg: 2.5).isEmpty)
  }

  func testNoEntryAtOrBeyondBounds() {
    let ramp = WarmUp.ramp(workingKg: 45, barKg: 20, incrementKg: 2.5)
    XCTAssertFalse(ramp.isEmpty)
    for set in ramp {
      XCTAssertGreaterThan(set.kg, 20)
      XCTAssertLessThan(set.kg, 45)
    }
  }
}
