import XCTest
@testable import ForgeCore

final class CoachIntentTests: XCTestCase {
  func testBirthdayIsProfileFactMissingNotMedical() {
    let intent = CoachIntentClassifier.classify("when is my birthday", known: [])
    XCTAssertEqual(intent, .profileFactMissing(field: "birthday"))
    if case .unsafeOrMedical = intent { XCTFail("must not be medical") }
  }

  func testAgeIsProfileFactMissing() {
    XCTAssertEqual(CoachIntentClassifier.classify("how old am i", known: []), .profileFactMissing(field: "age"))
  }

  func testKnownFactIsTrainingQuestion() {
    XCTAssertEqual(CoachIntentClassifier.classify("when is my birthday", known: ["birthday"]), .trainingQuestion)
  }

  func testHowMuchDoIWeighIsAmbiguous() {
    let intent = CoachIntentClassifier.classify("how much do i weigh", known: [])
    if case .ambiguous(let options) = intent {
      XCTAssertEqual(options.count, 2)
    } else {
      XCTFail("expected ambiguous, got \(intent)")
    }
  }

  func testKneeHurtsIsMedical() {
    XCTAssertEqual(CoachIntentClassifier.classify("my knee hurts when i squat", known: []), .unsafeOrMedical)
  }

  func testOutOfScope() {
    XCTAssertEqual(CoachIntentClassifier.classify("what is the weather today", known: []), .outOfScope)
  }

  func testBodyWeightStatementIsNotAmbiguous() {
    XCTAssertEqual(
      CoachIntentClassifier.classify("my body weight is down 0.8 kg over four weeks. why, and should i change anything?", known: []),
      .trainingQuestion)
  }

  func testBodyweightOneWordIsNotAmbiguous() {
    XCTAssertEqual(CoachIntentClassifier.classify("has my bodyweight moved this block", known: []), .trainingQuestion)
  }

  func testNamedLiftWeightIsNotAmbiguous() {
    XCTAssertEqual(CoachIntentClassifier.classify("what weight should i squat today", known: []), .trainingQuestion)
  }

  func testBareWeightQuestionStaysAmbiguous() {
    guard case .ambiguous = CoachIntentClassifier.classify("has my weight changed", known: []) else {
      return XCTFail("bare weight must stay ambiguous")
    }
  }

  func testClarificationReplyMatchesLooseWording() {
    let pending = CoachClarification(question: "q", options: ["Body weight", "The load for an exercise"])
    XCTAssertEqual(
      CoachClarificationResolver.resolve(reply: "The load for an exercise, please.", pending: pending),
      .resolved(question: "q", choice: "The load for an exercise"))
  }

  func testVietnameseBareAffirmationDoesNotResolve() {
    let pending = CoachClarification(question: "q", options: ["Body weight", "The load for an exercise"])
    guard case .repeatOptions = CoachClarificationResolver.resolve(reply: "Vâng", pending: pending) else {
      return XCTFail("a bare affirmation picks nothing")
    }
  }
}
