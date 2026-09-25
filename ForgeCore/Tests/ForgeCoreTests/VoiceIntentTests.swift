import XCTest
@testable import ForgeCore

final class VoiceIntentTests: XCTestCase {
  private func command(
    _ intent: VoiceIntent,
    _ transcript: String,
    defaultLb: Bool = false,
    language: VoiceLanguage = .en
  ) -> VoiceCommand {
    VoiceCommandParser.command(
      for: intent, transcript: transcript, candidates: [], defaultLb: defaultLb, language: language)
  }

  func testLocalParseWins() {
    XCTAssertEqual(command(.none, "complete set"), .completeSet)
  }

  func testStartRestFreeFormEnglish() {
    XCTAssertEqual(command(.startRest, "can we take two minutes here"), .startRest(seconds: 120))
  }

  func testStartRestFreeFormVietnamese() {
    XCTAssertEqual(command(.startRest, "nghỉ hai phút đi", language: .vi), .startRest(seconds: 120))
  }

  func testStartRestWithoutDuration() {
    XCTAssertEqual(command(.startRest, "let's have a break"), .startRest(seconds: nil))
  }

  func testChangeWeightFreeFormEnglish() {
    XCTAssertEqual(command(.changeWeight, "put another five kilos on there"), .changeWeight(deltaKg: 5))
  }

  func testChangeWeightPoundsNegative() {
    XCTAssertEqual(command(.changeWeight, "take off ten pounds please"),
      .changeWeight(deltaKg: -Plates.lbToKg(10)))
  }

  func testChangeWeightNeedsSignAndNumber() {
    if case .unrecognised = command(.changeWeight, "make it heavier") {} else {
      XCTFail("expected unrecognised without a number")
    }
    if case .unrecognised = command(.changeWeight, "a bit less on there") {} else {
      XCTFail("expected unrecognised without a number")
    }
  }

  func testChangeRepsTarget() {
    XCTAssertEqual(command(.changeReps, "let's call it nine"), .changeReps(to: 9, delta: nil))
  }

  func testChangeRepsDelta() {
    XCTAssertEqual(command(.changeReps, "can we do two more reps"), .changeReps(to: nil, delta: 2))
    XCTAssertEqual(command(.changeReps, "one less rep please"), .changeReps(to: nil, delta: -1))
  }

  func testChangeRepsNeedsInteger() {
    if case .unrecognised = command(.changeReps, "how about more") {} else {
      XCTFail("expected unrecognised without a number")
    }
  }

  func testChangeRPE() {
    XCTAssertEqual(command(.changeRPE, "that felt like an eight"), .changeRPE(8))
    XCTAssertEqual(command(.changeRPE, "felt like a 9.5 out there"), .changeRPE(9.5))
  }

  func testChangeRPEOutsideRange() {
    if case .unrecognised = command(.changeRPE, "felt like a four") {} else {
      XCTFail("expected unrecognised below 5")
    }
  }

  func testSwapExerciseWithoutName() {
    if case .unrecognised = command(.swapExercise, "chuyển sang bài khác", language: .vi) {} else {
      XCTFail("expected unrecognised without a matchable name")
    }
  }

  func testLogSetNeedsWeightAndReps() {
    if case .unrecognised = command(.logSet, "eighty kilos there") {} else {
      XCTFail("expected unrecognised with only a weight")
    }
    if case .unrecognised = command(.logSet, "eight reps there") {} else {
      XCTFail("expected unrecognised with only reps")
    }
  }

  func testLogSetFreeForm() {
    XCTAssertEqual(
      command(.logSet, "eighty kilos for eight reps"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil)))
    XCTAssertEqual(
      command(.logSet, "eight reps at eighty kilos"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil)))
  }

  func testLogSetUnmatchedNameIsUnrecognised() {
    // A spoken name that fails to match must not silently log onto the active exercise.
    if case .unrecognised = command(.logSet, "flurb machine eighty kilos for eight reps") {} else {
      XCTFail("expected unrecognised for an unmatched exercise name")
    }
  }

  func testLogSetMatchedName() {
    XCTAssertEqual(
      command(.logSet, "deadlift eighty kilos for eight reps"),
      .logSet(QuickLogParse(exerciseID: "deadlift", weightKg: 80, reps: 8, rpe: nil)))
  }
}
