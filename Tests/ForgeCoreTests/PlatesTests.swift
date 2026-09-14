import XCTest
@testable import ForgeCore

final class PlatesTests: XCTestCase {
  func testPerSide100kg() {
    XCTAssertEqual(Plates.perSide(target: 100, bar: 20, available: Plates.defaultKg)!, [25, 15])
  }

  func testPerSideBelowBarIsNil() {
    XCTAssertNil(Plates.perSide(target: 15, bar: 20, available: Plates.defaultKg))
  }

  func testPerSideUnrepresentableIsNil() {
    XCTAssertNil(Plates.perSide(target: 21, bar: 20, available: Plates.defaultKg))
    XCTAssertNil(Plates.perSide(target: 20.4, bar: 20, available: Plates.defaultKg))
  }

  func testPerSideBarOnly() {
    XCTAssertEqual(Plates.perSide(target: 20, bar: 20, available: Plates.defaultKg)!, [])
  }

  func testPerSideLb() {
    let lb = Plates.perSide(target: 225, bar: 45, available: Plates.defaultLb)!
    XCTAssertEqual(lb.reduce(0, +) * 2 + 45, 225, accuracy: 0.0001)
  }

  func testKgLbRoundtrip() {
    XCTAssertEqual(Plates.kgToLb(100), 220.462, accuracy: 0.001)
    XCTAssertEqual(Plates.lbToKg(Plates.kgToLb(100)), 100, accuracy: 0.0001)
    XCTAssertEqual(Plates.kgToLb(Plates.lbToKg(220.462)), 220.462, accuracy: 0.0001)
  }
}
