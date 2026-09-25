import XCTest
@testable import ForgeCore

final class PlausibilityTests: XCTestCase {
  let base = Date(timeIntervalSince1970: 1_700_000_000)

  func testJumpAtExactlyRatioIsNotAJump() {
    XCTAssertFalse(Plausibility.isJump(e1rm: 120, previousBest: 100))
    XCTAssertTrue(Plausibility.isJump(e1rm: 121, previousBest: 100))
  }

  func testJumpNilPreviousIsNotAJump() {
    XCTAssertFalse(Plausibility.isJump(e1rm: 200, previousBest: nil))
  }

  func testJumpZeroPreviousIsNotAJump() {
    XCTAssertFalse(Plausibility.isJump(e1rm: 10, previousBest: 0))
  }

  func testRapidGapBoundary() {
    XCTAssertTrue(Plausibility.isRapid(loggedAt: base.addingTimeInterval(19), previous: base))
    XCTAssertFalse(Plausibility.isRapid(loggedAt: base.addingTimeInterval(20), previous: base))
  }

  func testRapidNilPrevious() {
    XCTAssertFalse(Plausibility.isRapid(loggedAt: base, previous: nil))
  }

  func testShortSessionNeedsFourSets() {
    let last = base.addingTimeInterval(100)
    XCTAssertFalse(Plausibility.isShortSession(setCount: 3, first: base, last: last))
    XCTAssertTrue(Plausibility.isShortSession(setCount: 4, first: base, last: last))
  }

  func testShortSessionNotShortAtBoundary() {
    XCTAssertFalse(Plausibility.isShortSession(setCount: 5, first: base, last: base.addingTimeInterval(300)))
    XCTAssertTrue(Plausibility.isShortSession(setCount: 5, first: base, last: base.addingTimeInterval(299)))
  }
}
