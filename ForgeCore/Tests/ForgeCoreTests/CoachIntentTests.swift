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

  func testTrainingQuestion() {
    XCTAssertEqual(CoachIntentClassifier.classify("should i add weight to my bench", known: []), .trainingQuestion)
  }

  func testOutOfScope() {
    XCTAssertEqual(CoachIntentClassifier.classify("what is the weather today", known: []), .outOfScope)
  }
}
