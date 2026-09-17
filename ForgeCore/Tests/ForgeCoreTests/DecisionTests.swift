import XCTest
@testable import ForgeCore

final class DecisionTests: XCTestCase {
  func testEasierOnIncreaseLandsFivePercentLighter() {
    let d = Decision(subject: .exercise(id: "barbell_bench"),
                     action: .increaseLoad(fromKg: 100, toKg: 110),
                     causes: [], overridable: true)
    let applied = d.applying(.easier)
    XCTAssertEqual(applied.action, .increaseLoad(fromKg: 100, toKg: 104.5))
    XCTAssertTrue(applied.causes.contains { $0.signal == .userOverride })
  }

  func testEasierOnFivePercentIncreaseBecomesHold() {
    let d = Decision(subject: .exercise(id: "barbell_bench"),
                     action: .increaseLoad(fromKg: 100, toKg: 105),
                     causes: [], overridable: true)
    XCTAssertEqual(d.applying(.easier).action, .holdLoad(kg: 100))
  }

  func testHarderOnHoldBecomesIncrease() {
    let d = Decision(subject: .exercise(id: "barbell_bench"),
                     action: .holdLoad(kg: 100),
                     causes: [], overridable: true)
    XCTAssertEqual(d.applying(.harder).action, .increaseLoad(fromKg: 100, toKg: 102.5))
  }

  func testKeepOriginalRecordsOverrideCause() {
    let d = Decision(subject: .exercise(id: "barbell_bench"),
                     action: .increaseLoad(fromKg: 100, toKg: 110),
                     causes: [DecisionCause(signal: .rpeBelowTarget, evidence: "80 kg × 8 @ 7")], overridable: true)
    let applied = d.applying(.keepOriginal)
    XCTAssertEqual(applied.action, .increaseLoad(fromKg: 100, toKg: 110))
    XCTAssertTrue(applied.causes.contains { $0.signal == .userOverride })
    XCTAssertEqual(applied.causes.filter { $0.signal == .rpeBelowTarget }.count, 1)
  }

  func testLoadDecisionCarriesRPECause() {
    let sets = [SetLog(weightKg: 80, reps: 8, rpe: 7)]
    let d = DecisionBuilder.load(exerciseID: "barbell_bench", lastSets: sets, repRange: 8...12,
                                 targetRPE: 8, proposedKg: 80, e1rmChangePercent: nil, readiness: nil, sore: false)
    XCTAssertTrue(d.causes.contains { $0.signal == .rpeBelowTarget })
  }

  func testLoadDecisionCarriesReadinessCause() {
    let sets = [SetLog(weightKg: 80, reps: 8, rpe: 8)]
    let d = DecisionBuilder.load(exerciseID: "barbell_bench", lastSets: sets, repRange: 8...12,
                                 targetRPE: 8, proposedKg: 80, e1rmChangePercent: nil, readiness: 2, sore: false)
    XCTAssertTrue(d.causes.contains { $0.signal == .readinessLow })
  }
}
