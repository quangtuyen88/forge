import XCTest
@testable import ForgeCore

final class ProgressionTests: XCTestCase {
  private func assertDecision(_ actual: LoadDecision, _ expected: LoadDecision,
                              file: StaticString = #filePath, line: UInt = #line) {
    switch (actual, expected) {
    case let (.increase(a), .increase(b)):
      XCTAssertEqual(a, b, accuracy: 0.001, file: file, line: line)
    case let (.addReps(a), .addReps(b)):
      XCTAssertEqual(a, b, accuracy: 0.001, file: file, line: line)
    case let (.repeatLoad(a), .repeatLoad(b)):
      XCTAssertEqual(a, b, accuracy: 0.001, file: file, line: line)
    case let (.decrease(a, fa), .decrease(b, fb)):
      XCTAssertEqual(a, b, accuracy: 0.001, file: file, line: line)
      XCTAssertEqual(fa, fb, file: file, line: line)
    default:
      XCTFail("\(actual) != \(expected)", file: file, line: line)
    }
  }

  func testNextLoadTable() {
    let cases: [(Double, LoadDecision)] = [
      (7.0, .increase(toKg: 105)),
      (6.5, .increase(toKg: 105)),
      (7.5, .increase(toKg: 102.5)),
      (8.0, .addReps(atKg: 100)),
      (8.5, .repeatLoad(kg: 100)),
      (9.0, .decrease(toKg: 95, flagFatigue: true)),
      (9.7, .decrease(toKg: 95, flagFatigue: true)),
    ]
    for (actualRPE, expected) in cases {
      assertDecision(Progression.nextLoad(currentKg: 100, targetRPE: 8, actualRPE: actualRPE), expected)
    }
  }

  func testShouldIncreaseLoad() {
    let good = [SetLog(weightKg: 60, reps: 12, rpe: 8), SetLog(weightKg: 60, reps: 12, rpe: 7.5)]
    XCTAssertTrue(Progression.shouldIncreaseLoad(sets: good, repRange: 8...12, targetRPE: 8))
    let lowReps = [SetLog(weightKg: 60, reps: 11, rpe: 8)]
    XCTAssertFalse(Progression.shouldIncreaseLoad(sets: lowReps, repRange: 8...12, targetRPE: 8))
    let highRPE = [SetLog(weightKg: 60, reps: 12, rpe: 9)]
    XCTAssertFalse(Progression.shouldIncreaseLoad(sets: highRPE, repRange: 8...12, targetRPE: 8))
    XCTAssertFalse(Progression.shouldIncreaseLoad(sets: [], repRange: 8...12, targetRPE: 8))
  }

  func testRound() {
    XCTAssertEqual(Progression.round(102.5, toIncrement: 2.5), 102.5, accuracy: 0.0001)
    XCTAssertEqual(Progression.round(101, toIncrement: 2.5), 100, accuracy: 0.0001)
    XCTAssertEqual(Progression.round(101.3, toIncrement: 2.5), 102.5, accuracy: 0.0001)
    XCTAssertEqual(Progression.round(60.5, toIncrement: 1), 61, accuracy: 0.0001)
    XCTAssertEqual(Progression.round(60.2, toIncrement: 1), 60, accuracy: 0.0001)
  }
}
