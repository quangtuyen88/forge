import XCTest

@testable import ForgeCore

final class WeekBriefTests: XCTestCase {

  private func fact(
    _ id: String,
    code: String,
    exerciseID: String? = nil,
    scope: WeekBriefScope = .futureSession
  ) -> WeekBriefFact {
    WeekBriefFact(
      id: id, exerciseID: exerciseID, muscleID: nil, reasonCode: code,
      fromValue: nil, toValue: nil, scope: scope)
  }

  private func input(
    week: Int = 2,
    totalWeeks: Int = 6,
    isDeload: Bool = false,
    facts: [WeekBriefFact]
  ) -> WeekBriefInput {
    WeekBriefInput(
      week: week, totalWeeks: totalWeeks, isDeload: isDeload,
      upcomingDayNames: ["Upper", "Lower"], facts: facts)
  }

  // MARK: - truthfulness

  func testEmptyInputYieldsEmptyBrief() {
    let brief = WeekBrief.build(input(facts: []))
    XCTAssertTrue(brief.isEmpty)
    XCTAssertNil(brief.focus)
    XCTAssertNil(brief.change)
    XCTAssertNil(brief.unchanged)
    XCTAssertTrue(brief.statements.isEmpty)
  }

  func testUnknownReasonCodeFallsBackToGenericNonCausalWording() {
    let brief = WeekBrief.build(input(facts: [fact("d1", code: "some.future.reason_code")]))

    XCTAssertNotNil(brief.change)
    XCTAssertEqual(
      brief.change?.text, "Your plan changed for next week. Open the changes to see what moved.")
    XCTAssertEqual(brief.change?.decisionIDs, ["d1"])
    // No invented cause, and no claim that anything is "normal".
    XCTAssertFalse(brief.change?.text.contains("recovery") ?? false)
    XCTAssertFalse(brief.change?.text.contains("normal") ?? false)
    XCTAssertFalse(brief.change?.text.contains("fatigue") ?? false)
    XCTAssertNil(brief.focus)
    XCTAssertNil(brief.unchanged)
  }

  func testDeloadWithoutFlagNeverClaimsReducingLoad() {
    let brief = WeekBrief.build(
      input(isDeload: false, facts: [fact("d1", code: "plan.deload.scheduled")]))
    XCTAssertNotNil(brief.change)
    XCTAssertFalse(brief.change?.text.contains("reducing load") ?? false)
  }

  // MARK: - deload

  func testDeloadFlagAloneProducesReducingLoadStatement() {
    let brief = WeekBrief.build(input(isDeload: true, facts: []))
    XCTAssertEqual(brief.change?.text, "This block is reducing load.")
    XCTAssertFalse(brief.change?.decisionIDs.isEmpty ?? true)
  }

  // MARK: - decision id justification

  func testChangeStatementAlwaysReferencesAtLeastOneDecisionID() {
    let codes = [
      "plateau", "volume_above_mrv", "schedule.change.user_request", "some.unknown.code",
    ]
    for code in codes {
      let brief = WeekBrief.build(input(facts: [fact("d1", code: code)]))
      XCTAssertNotNil(brief.change, "no change statement for \(code)")
      XCTAssertFalse(brief.change?.decisionIDs.isEmpty ?? true, "missing id for \(code)")
    }
  }

  func testFocusAndUnchangedCarryTheirJustifyingDecisionIDs() {
    let focus = WeekBrief.build(input(facts: [fact("f1", code: "completed_all_sets")]))
    XCTAssertEqual(focus.focus?.text, "Keep the current progression.")
    XCTAssertEqual(focus.focus?.decisionIDs, ["f1"])
    XCTAssertNil(focus.change)
    XCTAssertNil(focus.unchanged)

    let hold = WeekBrief.build(input(facts: [fact("u1", code: "load.hold.target_met")]))
    XCTAssertEqual(hold.unchanged?.text, "Your remaining plan stays the same.")
    XCTAssertEqual(hold.unchanged?.decisionIDs, ["u1"])
    XCTAssertNil(hold.focus)
    XCTAssertNil(hold.change)
  }

  // MARK: - The brief names the change

  func testARealBeforeAndAfterIsNamedRatherThanAnnounced() {
    let result = WeekBrief.build(
      WeekBriefInput(
        week: 2, totalWeeks: 6, isDeload: false, upcomingDayNames: ["Full A"],
        facts: [
          WeekBriefFact(
            id: "d1", exerciseID: "bench_press", muscleID: nil,
            reasonCode: "load.reduction.effort_above_target", fromValue: 82.5, toValue: 80,
            scope: .futureSession, exerciseName: "Bench Press")
        ]))
    let text = result.change?.text ?? ""
    XCTAssertTrue(text.hasPrefix("Next Bench Press: "), text)
    XCTAssertTrue(text.contains("→ 80."), text)
    XCTAssertTrue(text.contains("82"), text)
  }

  /// A starting prescription is not an improvement. Without a real before/after the brief
  /// says the lift changes, and never invents a previous value.
  func testAnOpeningPrescriptionIsNotReportedAsABeforeAndAfter() {
    let result = WeekBrief.build(
      WeekBriefInput(
        week: 1, totalWeeks: 6, isDeload: false, upcomingDayNames: ["Full A"],
        facts: [
          WeekBriefFact(
            id: "d1", exerciseID: "bench_press", muscleID: nil, reasonCode: "first_exposure",
            fromValue: nil, toValue: 60, scope: .futureSession, exerciseName: "Bench Press")
        ]))
    XCTAssertEqual(result.change?.text, "Bench Press changes next session.")
  }

  func testWithoutAnExerciseIdentityTheBriefPointsAtTheChangesInsteadOfNamingStorage() {
    let result = WeekBrief.build(
      WeekBriefInput(
        week: 2, totalWeeks: 6, isDeload: false, upcomingDayNames: ["Full A"],
        facts: [
          WeekBriefFact(
            id: "d1", exerciseID: nil, muscleID: nil, reasonCode: "missed_sessions",
            fromValue: nil, toValue: nil, scope: .futureWeek)
        ]))
    XCTAssertEqual(
      result.change?.text, "Your plan changed for next week. Open the changes to see what moved.")
  }
}
