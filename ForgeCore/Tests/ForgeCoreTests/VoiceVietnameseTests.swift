import XCTest
@testable import ForgeCore

final class VoiceVietnameseTests: XCTestCase {
  private let candidates = [
    QuickLogCandidate(id: "barbell_bench", name: "Barbell Bench Press"),
    QuickLogCandidate(id: "back_squat", name: "Back Squat"),
    QuickLogCandidate(id: "deadlift", name: "Deadlift"),
    QuickLogCandidate(id: "lat_pulldown", name: "Lat Pulldown"),
  ]

  private func parse(_ t: String) -> VoiceCommand {
    VoiceCommandParser.parse(t, candidates: candidates, defaultLb: false, language: .vi)
  }

  // MARK: - Short commands (two phrasings each)

  func testCompleteSet() {
    XCTAssertEqual(parse("xong"), .completeSet)
    XCTAssertEqual(parse("xong rồi"), .completeSet)
    XCTAssertEqual(parse("ghi lại"), .completeSet)
    XCTAssertEqual(parse("hoàn thành"), .completeSet)
  }

  func testNextExercise() {
    XCTAssertEqual(parse("bài tiếp"), .nextExercise)
    XCTAssertEqual(parse("bài tiếp theo"), .nextExercise)
    XCTAssertEqual(parse("tiếp theo"), .nextExercise)
  }

  func testSkipRest() {
    XCTAssertEqual(parse("bỏ nghỉ"), .skipRest)
    XCTAssertEqual(parse("bỏ qua nghỉ"), .skipRest)
    XCTAssertEqual(parse("hết nghỉ"), .skipRest)
  }

  func testStartRestBare() {
    XCTAssertEqual(parse("nghỉ"), .startRest(seconds: nil))
    XCTAssertEqual(parse("bắt đầu nghỉ"), .startRest(seconds: nil))
  }

  func testStartRestNumbered() {
    XCTAssertEqual(parse("nghỉ 2 phút"), .startRest(seconds: 120))
    XCTAssertEqual(parse("nghỉ 90 giây"), .startRest(seconds: 90))
  }

  func testChangeWeightAdd() {
    XCTAssertEqual(parse("thêm 5 ký"), .changeWeight(deltaKg: 5))
    XCTAssertEqual(parse("thêm 5 kg"), .changeWeight(deltaKg: 5))
  }

  func testChangeWeightRemove() {
    XCTAssertEqual(parse("bớt 2 kg"), .changeWeight(deltaKg: -2))
    XCTAssertEqual(parse("giảm 5 ký"), .changeWeight(deltaKg: -5))
  }

  func testChangeRepsAbsolute() {
    XCTAssertEqual(parse("9 lần"), .changeReps(to: 9, delta: nil))
    XCTAssertEqual(parse("9 cái"), .changeReps(to: 9, delta: nil))
  }

  func testChangeRepsRelative() {
    XCTAssertEqual(parse("thêm 2 lần"), .changeReps(to: nil, delta: 2))
  }

  func testChangeRPE() {
    XCTAssertEqual(parse("rpe 8"), .changeRPE(8))
    XCTAssertEqual(parse("đổi thành rpe 8"), .changeRPE(8))
  }

  func testConfirm() {
    XCTAssertEqual(parse("xác nhận"), .confirm)
    XCTAssertEqual(parse("đồng ý"), .confirm)
    XCTAssertEqual(parse("được"), .confirm)
  }

  func testCancel() {
    XCTAssertEqual(parse("hủy"), .cancel)
    XCTAssertEqual(parse("không"), .cancel)
    XCTAssertEqual(parse("thôi"), .cancel)
  }

  func testUndo() {
    XCTAssertEqual(parse("hoàn tác"), .undo)
    XCTAssertEqual(parse("bỏ"), .undo)
  }

  func testAskCoach() {
    XCTAssertEqual(parse("hỏi coach tại sao"), .askCoach("tại sao"))
    XCTAssertEqual(parse("hỏi huấn luyện viên vì sao đổi"), .askCoach("vì sao đổi"))
  }

  func testSwap() {
    XCTAssertEqual(parse("đổi bench"), .swapExercise(exerciseID: "barbell_bench"))
    XCTAssertEqual(parse("thay squat"), .swapExercise(exerciseID: "back_squat"))
  }

  // MARK: - Set grammar

  func testSetWithoutExercise() {
    XCTAssertEqual(
      parse("80 ký 8 lần"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil))
    )
  }

  func testSetRepsBeforeWeight() {
    XCTAssertEqual(
      parse("8 lần 80 ký"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil))
    )
  }

  func testSetWithExerciseAndRPE() {
    XCTAssertEqual(
      parse("bench 80 ký 8 lần @ 8"),
      .logSet(QuickLogParse(exerciseID: "barbell_bench", weightKg: 80, reps: 8, rpe: 8))
    )
  }

  func testSetWithExerciseLast() {
    XCTAssertEqual(
      parse("80 ký 8 lần bench"),
      .logSet(QuickLogParse(exerciseID: "barbell_bench", weightKg: 80, reps: 8, rpe: nil))
    )
  }

  // MARK: - Vietnamese numbers

  func testSpokenNumbersInSet() {
    XCTAssertEqual(
      parse("tám mươi ký tám lần"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 80, reps: 8, rpe: nil))
    )
  }

  func testTeenNumber() {
    XCTAssertEqual(parse("thêm mười lăm ký"), .changeWeight(deltaKg: 15))
  }

  func testCompoundNumber() {
    XCTAssertEqual(parse("thêm tám mươi lăm ký"), .changeWeight(deltaKg: 85))
  }

  func testCompoundNumberWithMot() {
    XCTAssertEqual(parse("hai mươi mốt lần"), .changeReps(to: 21, delta: nil))
  }

  func testHundred() {
    XCTAssertEqual(parse("một trăm ký tám lần"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 100, reps: 8, rpe: nil)))
  }

  // MARK: - Half (rưỡi)

  func testHalfWeightChange() {
    XCTAssertEqual(parse("bớt 2 kg rưỡi"), .changeWeight(deltaKg: -2.5))
    XCTAssertEqual(parse("thêm 2 kg rưỡi"), .changeWeight(deltaKg: 2.5))
  }

  func testHalfInSet() {
    XCTAssertEqual(
      parse("hai kg rưỡi tám lần"),
      .logSet(QuickLogParse(exerciseID: "", weightKg: 2.5, reps: 8, rpe: nil))
    )
  }

  // MARK: - Diacritic-normalised input

  func testToneMarksStrippedStillMatch() {
    XCTAssertEqual(parse("xong roi"), .completeSet)
    XCTAssertEqual(parse("them 5 ky"), .changeWeight(deltaKg: 5))
    XCTAssertEqual(parse("bat đau nghi"), .startRest(seconds: nil))
    XCTAssertEqual(parse("huy"), .cancel)
  }

  func testGibberishReturnsOriginal() {
    XCTAssertEqual(parse("lộn xộn vô nghĩa"), .unrecognised("lộn xộn vô nghĩa"))
  }
}

extension VoiceVietnameseTests {
  /// Vietnamese đ carries no combining mark, so a transcript written "doi" must still match "đổi".
  func testDStrokeFoldsToPlainD() {
    let cands = ExerciseDB.everything.map { QuickLogCandidate(id: $0.id, name: $0.name) }
    XCTAssertEqual(
      VoiceCommandParser.parse("doi bench", candidates: cands, defaultLb: false, language: .vi),
      .swapExercise(exerciseID: "barbell_bench"))
    XCTAssertEqual(
      VoiceCommandParser.parse("dong y", candidates: cands, defaultLb: false, language: .vi),
      .confirm)
  }
}
