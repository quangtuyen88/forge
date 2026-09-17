import XCTest
@testable import ForgeCore

final class VoiceCommandTests: XCTestCase {
  private let candidates = [
    QuickLogCandidate(id: "barbell_bench", name: "Barbell Bench Press"),
    QuickLogCandidate(id: "back_squat", name: "Back Squat"),
    QuickLogCandidate(id: "deadlift", name: "Deadlift"),
    QuickLogCandidate(id: "lat_pulldown", name: "Lat Pulldown"),
  ]

  private func parse(_ t: String, defaultLb: Bool = false) -> VoiceCommand {
    VoiceCommandParser.parse(t, candidates: candidates, defaultLb: defaultLb)
  }

  func testLogSetForPhrasing() {
    XCTAssertEqual(parse("bench 80 for 8 at rpe 8"),
      .logSet(QuickLogParse(exerciseID: "barbell_bench", weightKg: 80, reps: 8, rpe: 8)))
  }

  func testLogSetAtPhrasing() {
    XCTAssertEqual(parse("deadlift 132.5 for 8 at 8"),
      .logSet(QuickLogParse(exerciseID: "deadlift", weightKg: 132.5, reps: 8, rpe: 8)))
  }

  func testCompleteSetPhrasings() {
    XCTAssertEqual(parse("complete set"), .completeSet)
    XCTAssertEqual(parse("done"), .completeSet)
    XCTAssertEqual(parse("log it"), .completeSet)
    XCTAssertEqual(parse("that's it"), .completeSet)
  }

  func testStartRestMinutes() {
    XCTAssertEqual(parse("start 2 minute rest"), .startRest(seconds: 120))
  }

  func testStartRestSeconds() {
    XCTAssertEqual(parse("rest 90 seconds"), .startRest(seconds: 90))
  }

  func testStartRestBare() {
    XCTAssertEqual(parse("start rest"), .startRest(seconds: nil))
  }

  func testWordNumberRest() {
    XCTAssertEqual(parse("two minute rest"), .startRest(seconds: 120))
  }

  func testSkipRestPhrasings() {
    XCTAssertEqual(parse("skip rest"), .skipRest)
    XCTAssertEqual(parse("skip the timer"), .skipRest)
  }

  func testChangeWeightAdd() {
    XCTAssertEqual(parse("add 5 kilos"), .changeWeight(deltaKg: 5))
  }

  func testChangeWeightNegative() {
    XCTAssertEqual(parse("minus 2.5 kg"), .changeWeight(deltaKg: -2.5))
  }

  func testChangeWeightPoundsToKg() {
    if case .changeWeight(let deltaKg) = parse("add 10 pounds") {
      XCTAssertEqual(deltaKg, 10 * 0.45359237, accuracy: 0.001)
    } else {
      XCTFail("expected changeWeight")
    }
  }

  func testChangeWeightMissingUnitUsesDefaultLb() {
    if case .changeWeight(let deltaKg) = parse("add 10", defaultLb: true) {
      XCTAssertEqual(deltaKg, 10 * 0.45359237, accuracy: 0.001)
    } else {
      XCTFail("expected changeWeight")
    }
  }

  func testChangeRepsAbsolute() {
    XCTAssertEqual(parse("make it 9 reps"), .changeReps(to: 9, delta: nil))
  }

  func testChangeRepsAddRelative() {
    XCTAssertEqual(parse("add 2 reps"), .changeReps(to: nil, delta: 2))
  }

  func testChangeRepsOneMore() {
    XCTAssertEqual(parse("one more rep"), .changeReps(to: nil, delta: 1))
  }

  func testChangeRepsOneLess() {
    XCTAssertEqual(parse("one less rep"), .changeReps(to: nil, delta: -1))
  }

  func testChangeRepsWordNumber() {
    XCTAssertEqual(parse("eight reps"), .changeReps(to: 8, delta: nil))
  }

  func testChangeRPEPrefix() {
    XCTAssertEqual(parse("rpe 8"), .changeRPE(8))
  }

  func testChangeRPEMakeIt() {
    XCTAssertEqual(parse("make it rpe 9.5"), .changeRPE(9.5))
  }

  func testNextExercisePhrasings() {
    XCTAssertEqual(parse("next exercise"), .nextExercise)
    XCTAssertEqual(parse("move on"), .nextExercise)
  }

  func testAskCoachKeepsQuestion() {
    XCTAssertEqual(parse("ask coach why did bench change"), .askCoach("why did bench change"))
  }

  func testCoachPrefixKeepsQuestion() {
    XCTAssertEqual(parse("coach what should i do"), .askCoach("what should i do"))
  }

  func testSwapBenchResolvesID() {
    XCTAssertEqual(parse("swap bench"), .swapExercise(exerciseID: "barbell_bench"))
  }

  func testChangeSquatResolvesID() {
    XCTAssertEqual(parse("change squat"), .swapExercise(exerciseID: "back_squat"))
  }

  func testGibberishReturnsOriginal() {
    XCTAssertEqual(parse("gibberish blah blah"), .unrecognised("gibberish blah blah"))
  }

  func testExerciseNameOnlyIsUnrecognised() {
    XCTAssertEqual(parse("bench"), .unrecognised("bench"))
  }
}
