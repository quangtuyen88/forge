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

  private func candidate(_ t: String, defaultLb: Bool = false) -> VoiceCandidate? {
    VoiceCommandParser.candidate(t, candidates: candidates, defaultLb: defaultLb)
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

  func testWordNumberRest() {
    XCTAssertEqual(parse("two minute rest"), .startRest(seconds: 120))
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

  func testExerciseNameOnlyIsUnrecognised() {
    XCTAssertEqual(parse("bench"), .unrecognised("bench"))
  }

  // MARK: - Control words

  func testConfirmPhrasings() {
    XCTAssertEqual(parse("confirm"), .confirm)
    XCTAssertEqual(parse("yes"), .confirm)
    XCTAssertEqual(parse("do it"), .confirm)
    XCTAssertEqual(parse("go ahead"), .confirm)
  }

  func testCancelPhrasings() {
    XCTAssertEqual(parse("cancel"), .cancel)
    XCTAssertEqual(parse("no"), .cancel)
    XCTAssertEqual(parse("stop"), .cancel)
    XCTAssertEqual(parse("never mind"), .cancel)
  }

  func testUndoPhrasings() {
    XCTAssertEqual(parse("undo"), .undo)
    XCTAssertEqual(parse("undo that"), .undo)
    XCTAssertEqual(parse("scratch that"), .undo)
  }

  // MARK: - Partial parsing

  func testCandidateIncompleteTrailingConnector() {
    XCTAssertNil(candidate("eight reps at"))
    XCTAssertNil(candidate("bench 80 for"))
  }

  func testCandidateCompleteSetShape() {
    XCTAssertEqual(
      candidate("eight reps at eighty kilos"),
      VoiceCandidate(command: .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil)), isComplete: true)
    )
  }

  // MARK: - Activation phrase

  func testStripActivationWithPhraseRequired() {
    XCTAssertEqual(VoiceCommandParser.stripActivation("coach eight at eighty", required: true), "eight at eighty")
    XCTAssertEqual(VoiceCommandParser.stripActivation("hey coach skip rest", required: true), "skip rest")
    XCTAssertEqual(VoiceCommandParser.stripActivation("regulift start rest", required: true), "start rest")
  }

  func testStripActivationWithoutPhraseRequired() {
    XCTAssertNil(VoiceCommandParser.stripActivation("skip rest", required: true))
  }

  func testStripActivationWithoutPhraseNotRequired() {
    XCTAssertEqual(VoiceCommandParser.stripActivation("skip rest", required: false), "skip rest")
  }

  func testStripActivationWithPhraseNotRequired() {
    XCTAssertEqual(VoiceCommandParser.stripActivation("coach skip rest", required: false), "skip rest")
  }

  func testCoachActivationParsesAsSetNotAskCoach() {
    guard let stripped = VoiceCommandParser.stripActivation("coach eight at eighty", required: true) else {
      return XCTFail("expected activation to be stripped")
    }
    XCTAssertEqual(stripped, "eight at eighty")
    XCTAssertEqual(parse(stripped), .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil)))
  }
}
