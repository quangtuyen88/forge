import XCTest
@testable import ForgeCore

final class WeeklyReviewTests: XCTestCase {
  func testHeadline() {
    let r = WeeklyReview(week: 3, sessionsDone: 3, sessionsPlanned: 4, tonnageKg: 900, priorTonnageKg: 1000, prs: [], nextWeekNote: "note")
    XCTAssertEqual(WeeklyReviewBuilder.headline(r, usesLb: false), "Week 3 done: 3/4 sessions.")
  }

  func testPercentLineWithPrior() {
    let r = WeeklyReview(week: 3, sessionsDone: 3, sessionsPlanned: 4, tonnageKg: 900, priorTonnageKg: 1000, prs: [], nextWeekNote: "note")
    let lines = WeeklyReviewBuilder.lines(r, usesLb: false)
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0], "Tonnage 900 kg, -10 % vs week 2.")
    XCTAssertEqual(lines[1], "No PRs this week — normal in an accumulation week.")
    XCTAssertEqual(lines[2], "note")
  }

  func testNoPriorLine() {
    let r = WeeklyReview(week: 1, sessionsDone: 3, sessionsPlanned: 3, tonnageKg: 800, priorTonnageKg: nil, prs: [], nextWeekNote: "note")
    let lines = WeeklyReviewBuilder.lines(r, usesLb: false)
    XCTAssertEqual(lines[0], "Tonnage 800 kg.")
  }

  func testPRsLine() {
    let r = WeeklyReview(week: 2, sessionsDone: 3, sessionsPlanned: 3, tonnageKg: 800, priorTonnageKg: nil, prs: ["Bench Press", "Squat"], nextWeekNote: "note")
    let lines = WeeklyReviewBuilder.lines(r, usesLb: false)
    XCTAssertEqual(lines[1], "PRs: Bench Press, Squat.")
  }
}
