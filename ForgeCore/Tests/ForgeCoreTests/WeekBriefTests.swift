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
    XCTAssertEqual(brief.change?.text, "A program decision was committed.")
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

  func testNoStatementWhenNoMatchingFactExists() {
    // A schedule alone must not fabricate a statement.
    let brief = WeekBrief.build(input(facts: []))
    XCTAssertTrue(brief.isEmpty)
  }

  // MARK: - determinism

  func testSameInputTwiceYieldsIdenticalOutput() {
    let facts = [
      fact("a", code: "completed_all_sets", exerciseID: "bench"),
      fact("b", code: "plateau", exerciseID: "squat"),
      fact("c", code: "load.hold.target_met", exerciseID: "deadlift"),
    ]
    let i = input(facts: facts)
    XCTAssertEqual(WeekBrief.build(i), WeekBrief.build(i))
  }

  func testFactOrderDoesNotAffectOutput() {
    let a = fact("a", code: "completed_all_sets", exerciseID: "bench")
    let b = fact("b", code: "plateau", exerciseID: "squat")
    let forward = WeekBrief.build(input(facts: [a, b]))
    let backward = WeekBrief.build(input(facts: [b, a]))
    XCTAssertEqual(forward, backward)
  }

  // MARK: - deload

  func testDeloadFlagChangesOutput() {
    let facts = [fact("a", code: "completed_all_sets", exerciseID: "bench")]
    let normal = WeekBrief.build(input(isDeload: false, facts: facts))
    let deload = WeekBrief.build(input(isDeload: true, facts: facts))

    XCTAssertNotEqual(normal, deload)
    XCTAssertEqual(deload.change?.text, "This block is reducing load.")
    XCTAssertNil(normal.change, "no change statement without a change fact or deload flag")
  }

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

  func testAtMostThreeStatements() {
    let facts = [
      fact("f", code: "completed_all_sets"),
      fact("c", code: "plateau"),
      fact("u", code: "load.hold.target_met"),
    ]
    let brief = WeekBrief.build(input(facts: facts))
    XCTAssertNotNil(brief.focus)
    XCTAssertNotNil(brief.change)
    XCTAssertNotNil(brief.unchanged)
    XCTAssertLessThanOrEqual(brief.statements.count, 3)
  }
}
