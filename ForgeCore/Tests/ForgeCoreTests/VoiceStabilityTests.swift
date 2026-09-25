import XCTest
@testable import ForgeCore

final class VoiceStabilityTests: XCTestCase {
  private let set = QuickLogParse(exerciseID: "deadlift", weightKg: 80, reps: 8, rpe: nil)

  private func everyCase() -> [VoiceCommand] {
    [
      .logSet(set),
      .completeSet,
      .changeWeight(deltaKg: 5),
      .changeReps(to: 9, delta: nil),
      .changeRPE(8),
      .startRest(seconds: 90),
      .skipRest,
      .nextExercise,
      .confirm,
      .cancel,
      .undo,
      .askCoach("why"),
      .unrecognised("blah"),
      .swapExercise(exerciseID: "deadlift"),
    ]
  }

  // MARK: - Confirmation tiers

  func testConsequenceEveryCaseFastLoggingOff() {
    let expected: [VoiceConsequence] = [
      .confirm,   // logSet
      .confirm,   // completeSet
      .undoable,  // changeWeight
      .undoable,  // changeReps
      .undoable,  // changeRPE
      .immediate, // startRest
      .immediate, // skipRest
      .immediate, // nextExercise
      .immediate, // confirm
      .immediate, // cancel
      .immediate, // undo
      .immediate, // askCoach
      .immediate, // unrecognised
      .confirm,   // swapExercise
    ]
    let cases = everyCase()
    XCTAssertEqual(cases.count, expected.count)
    for (command, want) in zip(cases, expected) {
      XCTAssertEqual(command.consequence(fastLogging: false), want, "\(command)")
    }
  }

  func testConsequenceEveryCaseFastLoggingOn() {
    let expected: [VoiceConsequence] = [
      .undoable,  // logSet
      .undoable,  // completeSet
      .undoable,  // changeWeight
      .undoable,  // changeReps
      .undoable,  // changeRPE
      .immediate, // startRest
      .immediate, // skipRest
      .immediate, // nextExercise
      .immediate, // confirm
      .immediate, // cancel
      .immediate, // undo
      .immediate, // askCoach
      .immediate, // unrecognised
      .confirm,   // swapExercise
    ]
    let cases = everyCase()
    XCTAssertEqual(cases.count, expected.count)
    for (command, want) in zip(cases, expected) {
      XCTAssertEqual(command.consequence(fastLogging: true), want, "\(command)")
    }
  }

  // MARK: - Idempotency

  func testCommitLogSameUtteranceCommitsOnce() {
    var log = VoiceCommitLog()
    let u = UUID()
    XCTAssertTrue(log.shouldCommit(.skipRest, utteranceID: u))
    XCTAssertFalse(log.shouldCommit(.skipRest, utteranceID: u))
  }

  func testCommitLogDifferentUtteranceCommitsTwice() {
    var log = VoiceCommitLog()
    XCTAssertTrue(log.shouldCommit(.skipRest, utteranceID: UUID()))
    XCTAssertTrue(log.shouldCommit(.skipRest, utteranceID: UUID()))
  }

  func testCommitLogWindowEvictsOldEntries() {
    var log = VoiceCommitLog(window: 2)
    let u = UUID()
    XCTAssertTrue(log.shouldCommit(.completeSet, utteranceID: u))
    XCTAssertTrue(log.shouldCommit(.skipRest, utteranceID: u))
    XCTAssertTrue(log.shouldCommit(.nextExercise, utteranceID: u))  // evicts completeSet
    XCTAssertTrue(log.shouldCommit(.completeSet, utteranceID: u))   // re-commits after eviction
  }

  // MARK: - Fingerprint

  func testFingerprintDiffersByWeight() {
    let a = VoiceCommand.logSet(QuickLogParse(exerciseID: "deadlift", weightKg: 80, reps: 8, rpe: nil))
    let b = VoiceCommand.logSet(QuickLogParse(exerciseID: "deadlift", weightKg: 81, reps: 8, rpe: nil))
    XCTAssertNotEqual(a.fingerprint, b.fingerprint)
  }

  // MARK: - Partial-command stability

  private let stableCandidate = VoiceCandidate(command: .skipRest, isComplete: true)

  func testStabilizerReleasesOnSecondIdenticalOffer() {
    var s = VoiceStabilizer()
    let t = Date()
    XCTAssertNil(s.offer(stableCandidate, at: t))
    XCTAssertEqual(s.offer(stableCandidate, at: t), .skipRest)
  }

  func testStabilizerReleasesAfterHoldForWithOneSighting() {
    var s = VoiceStabilizer(repeatsRequired: 100, holdFor: 0.35)
    let t = Date()
    XCTAssertNil(s.offer(stableCandidate, at: t))
    XCTAssertNil(s.offer(stableCandidate, at: t.addingTimeInterval(0.2)))
    XCTAssertEqual(s.offer(stableCandidate, at: t.addingTimeInterval(0.4)), .skipRest)
  }

  func testStabilizerIncompleteDoesNotRelease() {
    var s = VoiceStabilizer()
    let t = Date()
    XCTAssertNil(s.offer(stableCandidate, at: t))  // streak 1
    XCTAssertNil(s.offer(VoiceCandidate(command: .skipRest, isComplete: false), at: t))
    XCTAssertNil(s.offer(stableCandidate, at: t))  // streak was reset, must not release
  }

  func testStabilizerReset() {
    var s = VoiceStabilizer()
    let t = Date()
    _ = s.offer(stableCandidate, at: t)
    s.reset()
    XCTAssertNil(s.offer(stableCandidate, at: t))
  }
}
