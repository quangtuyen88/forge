import XCTest
@testable import ForgeCore

final class DebriefTests: XCTestCase {
  /// Reported by default: these cases are about what the debrief says once the lifter has
  /// actually rated the work.
  private func set(
    _ exercise: String = "Squat", rpe: Double = 8, targetRPE: Double = 8, reported: Bool = true
  ) -> DebriefSet {
    DebriefSet(
      exercise: exercise, weightKg: 100, reps: 8, rpe: rpe, targetRPE: targetRPE,
      effortReported: reported)
  }

  func testPRLine() {
    let lines = Debrief.lines(
      sets: [], prs: [DebriefPR(exercise: "Bench Press", e1RM: 105, priorE1RM: 100)],
      tonnageKg: 0, priorTonnageKg: nil, dayName: "Push", next: [], usesLb: false)
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0].kind, .result)
    XCTAssertEqual(lines[0].text, "PR: Bench Press e1RM 100 → 105 kg.")
  }

  func testFirstE1RMOnRecord() {
    let lines = Debrief.lines(
      sets: [], prs: [DebriefPR(exercise: "Squat", e1RM: 100, priorE1RM: nil)],
      tonnageKg: 0, priorTonnageKg: nil, dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(lines[0].text, "First e1RM on record for Squat: 100 kg.")
  }

  func testTonnageVsPriorNegativePercent() {
    let lines = Debrief.lines(
      sets: [], prs: [], tonnageKg: 450, priorTonnageKg: 500,
      dayName: "Monday", next: [], usesLb: false)
    XCTAssertEqual(lines[0].text, "Tonnage 450 kg vs 500 kg last Monday (-10 %).")
  }

  func testFirstDayOnRecord() {
    let lines = Debrief.lines(
      sets: [], prs: [], tonnageKg: 900, priorTonnageKg: nil,
      dayName: "Push", next: [], usesLb: false)
    XCTAssertEqual(lines[0].text, "First Push on record: 900 kg.")
  }

  func testEffortOverTarget() {
    let lines = Debrief.lines(
      sets: [set(rpe: 8.5), set(rpe: 8.5)], prs: [], tonnageKg: 0, priorTonnageKg: nil,
      dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(lines[1].kind, .effort)
    XCTAssertEqual(lines[1].text, "RPE ran 0.5 over target on 2 of 2 sets — loads were heavy.")
  }

  func testEffortUnderTarget() {
    let lines = Debrief.lines(
      sets: [set(rpe: 7.5), set(rpe: 7.5)], prs: [], tonnageKg: 0, priorTonnageKg: nil,
      dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(lines[1].text, "RPE 0.5 under target — room to add load.")
  }

  func testEffortOnTarget() {
    let lines = Debrief.lines(
      sets: [set(), set()], prs: [], tonnageKg: 0, priorTonnageKg: nil,
      dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(lines[1].text, "RPE on target across 2 sets.")
  }

  /// The defect this closes: two sets logged without touching RPE were read back as
  /// "RPE on target across 2 sets", turning the plan's own target into the lifter's report.
  func testUnreportedEffortMakesNoClaimAboutEffort() {
    let lines = Debrief.lines(
      sets: [set(reported: false), set(reported: false)], prs: [], tonnageKg: 0,
      priorTonnageKg: nil, dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(lines[1].kind, .effort)
    XCTAssertEqual(lines[1].text, "Effort not recorded for these 2 sets.")
  }

  func testPartialCoverageIsStatedRatherThanAveragedAway() {
    let lines = Debrief.lines(
      sets: [set(rpe: 9), set(reported: false), set(reported: false)], prs: [], tonnageKg: 0,
      priorTonnageKg: nil, dayName: "Legs", next: [], usesLb: false)
    XCTAssertEqual(
      lines[1].text,
      "RPE ran 1.0 over target on 1 of 1 sets — loads were heavy. RPE recorded for 1 of 3 sets.")
  }

  func testAnEmptySessionSaysSoInsteadOfClaimingTargetEffort() {
    let lines = Debrief.lines(
      sets: [], prs: [], tonnageKg: 0, priorTonnageKg: nil, dayName: "Legs", next: [],
      usesLb: false)
    XCTAssertEqual(lines[1].text, "No sets recorded.")
  }

  func testNextThreeEntriesWithHoldMarker() {
    let next = [
      DebriefNext(exercise: "Bench Press", kg: 105, deltaKg: 5),
      DebriefNext(exercise: "Row", kg: 80, deltaKg: 0),
      DebriefNext(exercise: "Curl", kg: 15, deltaKg: -2),
      DebriefNext(exercise: "Ignored", kg: 50, deltaKg: 5),
    ]
    let lines = Debrief.lines(
      sets: [], prs: [], tonnageKg: 0, priorTonnageKg: nil,
      dayName: "Push", next: next, usesLb: false)
    XCTAssertEqual(lines[2].kind, .next)
    XCTAssertEqual(lines[2].text, "Next Push: Bench Press 105 kg (+5), Row 80 kg (=), Curl 15 kg (−2).")
  }

  func testUsesLbConversion() {
    let lines = Debrief.lines(
      sets: [], prs: [DebriefPR(exercise: "Bench Press", e1RM: 100, priorE1RM: 90)],
      tonnageKg: 0, priorTonnageKg: nil, dayName: "Push", next: [], usesLb: true)
    let expected = Plates.kgToLb(100).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    XCTAssertTrue(lines[0].text.contains("\(expected) lb"))
    XCTAssertFalse(lines[0].text.contains("kg"))
  }
}
