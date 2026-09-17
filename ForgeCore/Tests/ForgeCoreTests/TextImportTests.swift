import XCTest
@testable import ForgeCore

final class TextImportTests: XCTestCase {
  private func c(_ id: String, _ name: String) -> QuickLogCandidate {
    QuickLogCandidate(id: id, name: name)
  }

  func testThreeLinePaste() {
    let lines = TextImport.parse(
      "Bench 80x8 @8\nSquat 120x5\nDeadlift 180x3",
      candidates: [c("barbell_bench", "Barbell Bench Press"), c("back_squat", "Back Squat"), c("deadlift", "Deadlift")],
      defaultLb: false)
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0].parsed?.exerciseID, "barbell_bench")
    XCTAssertEqual(lines[0].parsed?.reps, 8)
    XCTAssertEqual(lines[0].parsed?.rpe, 8)
    XCTAssertEqual(lines[1].parsed?.exerciseID, "back_squat")
    XCTAssertEqual(lines[2].parsed?.exerciseID, "deadlift")
    XCTAssertEqual(TextImport.sets(from: lines).count, 3)
  }

  func testHeaderIgnored() {
    let lines = TextImport.parse(
      "Push Day\nBench 80x8",
      candidates: [c("barbell_bench", "Barbell Bench Press")],
      defaultLb: false)
    XCTAssertEqual(lines.count, 1)
    XCTAssertEqual(lines[0].parsed?.exerciseID, "barbell_bench")
  }

  func testRepSchemePrefixExpands() {
    let lines = TextImport.parse(
      "3x10 bench 60kg",
      candidates: [c("barbell_bench", "Barbell Bench Press")],
      defaultLb: false)
    XCTAssertEqual(lines.count, 3)
    for line in lines {
      XCTAssertEqual(line.parsed?.exerciseID, "barbell_bench")
      XCTAssertEqual(line.parsed?.weightKg ?? 0, 60, accuracy: 0.001)
      XCTAssertEqual(line.parsed?.reps, 10)
    }
    XCTAssertEqual(TextImport.sets(from: lines).count, 3)
  }

  func testUnreadableLineSurvives() {
    let lines = TextImport.parse(
      "wobble 100x5",
      candidates: [c("deadlift", "Deadlift")],
      defaultLb: false)
    XCTAssertEqual(lines.count, 1)
    XCTAssertNil(lines[0].parsed)
    XCTAssertEqual(lines[0].raw, "wobble 100x5")
    XCTAssertTrue(TextImport.sets(from: lines).isEmpty)
  }
}
