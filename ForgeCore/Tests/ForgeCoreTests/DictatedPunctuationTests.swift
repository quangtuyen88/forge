import XCTest
@testable import ForgeCore

/// Dictation punctuates what it hears, so every command must survive a trailing full stop.
final class DictatedPunctuationTests: XCTestCase {
  private var candidates: [QuickLogCandidate] {
    ExerciseDB.everything.map { QuickLogCandidate(id: $0.id, name: $0.name) }
  }

  private func parse(_ s: String) -> VoiceCommand {
    VoiceCommandParser.parse(s, candidates: candidates, defaultLb: false)
  }

  func testShortCommandsSurvivePunctuation() {
    XCTAssertEqual(parse("Complete set."), .completeSet)
    XCTAssertEqual(parse("Done."), .completeSet)
    XCTAssertEqual(parse("Skip rest."), .skipRest)
    XCTAssertEqual(parse("Next exercise."), .nextExercise)
  }

  func testRestCommandsSurvivePunctuation() {
    XCTAssertEqual(parse("Start two minute rest."), .startRest(seconds: 120))
    XCTAssertEqual(parse("Rest 90 seconds."), .startRest(seconds: 90))
    XCTAssertEqual(parse("start rest"), .startRest(seconds: nil))
  }

  func testAdjustmentsSurvivePunctuation() {
    XCTAssertEqual(parse("Add 5 kilos."), .changeWeight(deltaKg: 5))
    XCTAssertEqual(parse("Make it 9 reps."), .changeReps(to: 9, delta: nil))
  }

  func testDecimalsStillParse() {
    XCTAssertEqual(parse("Minus 2.5 kg"), .changeWeight(deltaKg: -2.5))
    guard case .logSet(let set) = parse("Deadlift 132.5 for 8 at 8") else {
      return XCTFail("expected a set")
    }
    XCTAssertEqual(set.weightKg, 132.5, accuracy: 0.001)
    XCTAssertEqual(set.reps, 8)
  }

  func testSwapAndCoachSurvivePunctuation() {
    XCTAssertEqual(parse("Swap bench."), .swapExercise(exerciseID: "barbell_bench"))
    XCTAssertEqual(parse("Ask coach why did bench change?"), .askCoach("why did bench change?"))
  }
}
