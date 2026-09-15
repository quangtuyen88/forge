import XCTest
@testable import ForgeCore

final class BadgesTests: XCTestCase {
  func testZeroStatsEarnNothing() {
    XCTAssertEqual(Badges.earned(sessions: 0, streakWeeks: 0, tonnageKg: 0, prCount: 0), [])
  }

  func testExactBoundaries() {
    let all = Badges.earned(sessions: 100, streakWeeks: 12, tonnageKg: 1_000_000, prCount: 10)
    XCTAssertEqual(all, Badge.allCases)
    XCTAssertTrue(Badges.earned(sessions: 1, streakWeeks: 0, tonnageKg: 0, prCount: 0).contains(.firstSession))
    XCTAssertTrue(Badges.earned(sessions: 10, streakWeeks: 4, tonnageKg: 100_000, prCount: 1).contains(.tenSessions))
    XCTAssertFalse(Badges.earned(sessions: 9, streakWeeks: 3, tonnageKg: 99_999, prCount: 0).contains(.tenSessions))
  }
}
