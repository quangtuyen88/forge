import XCTest
@testable import ForgeCore

final class CoachOutputValidatorTests: XCTestCase {
  func testMedicalDisclaimerForProfileFactIsFlagged() {
    let issues = CoachOutputValidator.validate(
      answer: "You should consult a healthcare professional about that.",
      intent: .profileFactMissing(field: "birthday"), context: "", language: "en", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .medicalDisclaimerMisuse })
    XCTAssertTrue(CoachOutputValidator.mustReplace(issues))
  }

  func testMedicalLanguageNotFlaggedForMedicalIntent() {
    let issues = CoachOutputValidator.validate(
      answer: "This sounds like it needs a doctor. Consult a healthcare professional.",
      intent: .unsafeOrMedical, context: "", language: "en", usesLb: false)
    XCTAssertFalse(issues.contains { $0.kind == .medicalDisclaimerMisuse })
  }

  func testInventedNumberAbsentFromContext() {
    let issues = CoachOutputValidator.validate(
      answer: "Your bench is 92.5 kg next session.",
      intent: .trainingQuestion, context: "", language: "en", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .inventedNumber })
    XCTAssertTrue(CoachOutputValidator.mustReplace(issues))
  }

  func testNumberPresentInContextPasses() {
    let issues = CoachOutputValidator.validate(
      answer: "Your bench is 92.5 kg next session.",
      intent: .trainingQuestion, context: "bench last session 92.5 kg", language: "en", usesLb: false)
    XCTAssertFalse(issues.contains { $0.kind == .inventedNumber })
  }

  func testRoundedNumberInContextPasses() {
    let issues = CoachOutputValidator.validate(
      answer: "Use 92.5 kg.",
      intent: .trainingQuestion, context: "e1rm 92.46 kg", language: "en", usesLb: false)
    XCTAssertFalse(issues.contains { $0.kind == .inventedNumber })
  }

  func testQuotedNumberIgnored() {
    let issues = CoachOutputValidator.validate(
      answer: "You asked \"is 92.5 kg good?\" — here's my answer.",
      intent: .trainingQuestion, context: "", language: "en", usesLb: false)
    XCTAssertFalse(issues.contains { $0.kind == .inventedNumber })
  }

  func testPromptLeakFlagged() {
    let issues = CoachOutputValidator.validate(
      answer: "As an AI assistant following my system prompt, I cannot answer.",
      intent: .trainingQuestion, context: "", language: "en", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .promptLeak })
  }

  func testInternalTagFlagged() {
    let issues = CoachOutputValidator.validate(
      answer: "Scope: load_change\nFatigue: high",
      intent: .trainingQuestion, context: "", language: "en", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .internalTag })
  }

  func testUnitMismatchLbInKgSystem() {
    let issues = CoachOutputValidator.validate(
      answer: "Add 10 lb to your bench.",
      intent: .trainingQuestion, context: "", language: "en", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .unitMismatch })
  }

  func testWrongLanguageJapanese() {
    let issues = CoachOutputValidator.validate(
      answer: "Add 5 kg to your bench.",
      intent: .trainingQuestion, context: "", language: "ja", usesLb: false)
    XCTAssertTrue(issues.contains { $0.kind == .wrongLanguage })
  }
}
