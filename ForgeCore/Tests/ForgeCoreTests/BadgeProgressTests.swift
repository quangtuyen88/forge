import XCTest
@testable import ForgeCore

final class BadgeProgressTests: XCTestCase {
  func testProgressAndEarned() {
    let progress = Badges.progress(sessions: 7, streakWeeks: 2, tonnageKg: 48_000, prCount: 1)
    func entry(_ badge: Badge) -> BadgeProgress {
      progress.first { $0.badge == badge }!
    }
    XCTAssertEqual(entry(.tenSessions).progress, 7)
    XCTAssertEqual(entry(.tenSessions).target, 10)
    XCTAssertEqual(entry(.tonnage100k).progress, 48)
    XCTAssertEqual(entry(.tonnage100k).target, 100)
    XCTAssertEqual(entry(.firstPR).progress, 1)
    XCTAssertEqual(entry(.firstPR).target, 1)
    XCTAssertEqual(entry(.fourWeekStreak).progress, 2)
    XCTAssertEqual(entry(.fourWeekStreak).target, 4)
    let earned = Badges.earned(sessions: 7, streakWeeks: 2, tonnageKg: 48_000, prCount: 1)
    XCTAssertEqual(earned, [.firstSession, .firstPR])
  }
}
