import XCTest
@testable import ForgeCore

final class FatigueTests: XCTestCase {
  func testACVRScoreBoundaries() {
    XCTAssertEqual(Fatigue.acvrScore(1.3), 0)
    XCTAssertEqual(Fatigue.acvrScore(1.31), 50)
    XCTAssertEqual(Fatigue.acvrScore(1.5), 50)
    XCTAssertEqual(Fatigue.acvrScore(1.51), 100)
    XCTAssertEqual(Fatigue.acvrScore(0.8), 0)
  }

  func testACVR() {
    let i = FatigueInputs(acuteVolume7d: 16, avgWeeklyVolume28d: 10, soreness: 1, sleepHoursLastNight: 8, sleepBaseline7d: 8, sessionsLast7d: 3, missedRPESessionsLast7d: 0)
    XCTAssertEqual(Fatigue.acvr(i), 1.6, accuracy: 0.0001)
    let zero = FatigueInputs(acuteVolume7d: 10, avgWeeklyVolume28d: 0, soreness: 1, sleepHoursLastNight: 8, sleepBaseline7d: 8, sessionsLast7d: 0, missedRPESessionsLast7d: 0)
    XCTAssertEqual(Fatigue.acvr(zero), 1.0)
  }

  func testComponentScores() {
    XCTAssertEqual(Fatigue.sorenessScore(1), 0)
    XCTAssertEqual(Fatigue.sorenessScore(3), 50)
    XCTAssertEqual(Fatigue.sorenessScore(5), 100)
    XCTAssertEqual(Fatigue.sorenessScore(0), 0)
    XCTAssertEqual(Fatigue.sorenessScore(9), 100)
    XCTAssertEqual(Fatigue.sleepDeficitScore(lastNight: 8, baseline: 8), 0)
    XCTAssertEqual(Fatigue.sleepDeficitScore(lastNight: 7, baseline: 8), 50)
    XCTAssertEqual(Fatigue.sleepDeficitScore(lastNight: 4, baseline: 8), 100)
    XCTAssertEqual(Fatigue.missedRPEPenalty(missed: 0, sessions: 0), 0)
    XCTAssertEqual(Fatigue.missedRPEPenalty(missed: 1, sessions: 4), 25)
    XCTAssertEqual(Fatigue.missedRPEPenalty(missed: 5, sessions: 4), 100)
  }

  func testFreshInputProceeds() {
    let i = FatigueInputs(acuteVolume7d: 12, avgWeeklyVolume28d: 12, soreness: 1, sleepHoursLastNight: 8, sleepBaseline7d: 8, sessionsLast7d: 4, missedRPESessionsLast7d: 0)
    let s = Fatigue.score(i)
    XCTAssertLessThan(s, 40)
    XCTAssertEqual(Fatigue.action(forScore: s), .proceed)
  }

  func testWreckedInputForcesRest() {
    let i = FatigueInputs(acuteVolume7d: 16, avgWeeklyVolume28d: 10, soreness: 5, sleepHoursLastNight: 4, sleepBaseline7d: 8, sessionsLast7d: 3, missedRPESessionsLast7d: 3)
    XCTAssertEqual(Fatigue.acvr(i), 1.6, accuracy: 0.0001)
    XCTAssertEqual(Fatigue.score(i), 100)
    XCTAssertEqual(Fatigue.action(forScore: Fatigue.score(i)), .forceRest)
  }

  func testHRVScore() {
    XCTAssertEqual(Fatigue.hrvScore(lastNight: 60, baseline: 60), 0)
    XCTAssertEqual(Fatigue.hrvScore(lastNight: 55, baseline: 60), 50)
    XCTAssertEqual(Fatigue.hrvScore(lastNight: 50, baseline: 60), 100)
    XCTAssertEqual(Fatigue.hrvScore(lastNight: nil, baseline: 60), nil)
    XCTAssertEqual(Fatigue.hrvScore(lastNight: 60, baseline: nil), nil)
  }

  func testRestingHRScore() {
    XCTAssertEqual(Fatigue.restingHRScore(lastNight: 52, baseline: 50), 0)
    XCTAssertEqual(Fatigue.restingHRScore(lastNight: 55, baseline: 50), 50)
    XCTAssertEqual(Fatigue.restingHRScore(lastNight: 58, baseline: 50), 100)
    XCTAssertEqual(Fatigue.restingHRScore(lastNight: nil, baseline: 50), nil)
    XCTAssertEqual(Fatigue.restingHRScore(lastNight: 50, baseline: nil), nil)
  }

  func testFreshWithCardioStaysUnder40() {
    let base = FatigueInputs(acuteVolume7d: 12, avgWeeklyVolume28d: 12, soreness: 1, sleepHoursLastNight: 8, sleepBaseline7d: 8, sessionsLast7d: 4, missedRPESessionsLast7d: 0)
    XCTAssertLessThan(Fatigue.score(base), 40)
    let fresh = FatigueInputs(acuteVolume7d: 12, avgWeeklyVolume28d: 12, soreness: 1, sleepHoursLastNight: 8, sleepBaseline7d: 8, sessionsLast7d: 4, missedRPESessionsLast7d: 0, hrvLastNight: 60, hrvBaseline7d: 60, restingHRLastNight: 50, restingHRBaseline7d: 50)
    XCTAssertEqual(Fatigue.cardioScore(fresh), 0)
    XCTAssertLessThan(Fatigue.score(fresh), 40)
  }

  func testWreckedWithHRVStillForcesRest() {
    let i = FatigueInputs(acuteVolume7d: 16, avgWeeklyVolume28d: 10, soreness: 5, sleepHoursLastNight: 4, sleepBaseline7d: 8, sessionsLast7d: 3, missedRPESessionsLast7d: 3, hrvLastNight: 40, hrvBaseline7d: 60)
    XCTAssertEqual(Fatigue.score(i), 100)
    XCTAssertEqual(Fatigue.action(forScore: Fatigue.score(i)), .forceRest)
  }

  func testNoCardioInputKeepsOldWeights() {
    let i = FatigueInputs(acuteVolume7d: 14, avgWeeklyVolume28d: 10, soreness: 3, sleepHoursLastNight: 6.5, sleepBaseline7d: 8, sessionsLast7d: 4, missedRPESessionsLast7d: 1)
    XCTAssertEqual(Fatigue.cardioScore(i), nil)
    let acvr = 14.0 / 10.0
    let old = 0.35 * (acvr <= 1.5 && acvr > 1.3 ? 50 : 100)
      + 0.25 * Double(3 - 1) / 4 * 100
      + 0.20 * min(100, (8 - 6.5) / 2 * 100)
      + 0.20 * min(100, 1.0 / 4 * 100)
    XCTAssertEqual(Fatigue.score(i), Int(old.rounded()))
  }

  func testActionBoundaries() {
    XCTAssertEqual(Fatigue.action(forScore: 0), .proceed)
    XCTAssertEqual(Fatigue.action(forScore: 39), .proceed)
    XCTAssertEqual(Fatigue.action(forScore: 40), .reduceOptionalSets(by: 1))
    XCTAssertEqual(Fatigue.action(forScore: 59), .reduceOptionalSets(by: 1))
    XCTAssertEqual(Fatigue.action(forScore: 60), .lightSession(volumeMultiplier: 0.7, rpeCap: 7))
    XCTAssertEqual(Fatigue.action(forScore: 79), .lightSession(volumeMultiplier: 0.7, rpeCap: 7))
    XCTAssertEqual(Fatigue.action(forScore: 80), .forceRest)
    XCTAssertEqual(Fatigue.action(forScore: 100), .forceRest)
  }
}
