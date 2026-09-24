import XCTest
@testable import ForgeCore

final class PlanAuditTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let day: TimeInterval = 86_400

  private func set(_ id: String, daysAgo: Int, weight: Double, reps: Int, rpe: Double? = 8) -> AuditSet {
    AuditSet(exerciseID: id, date: now.addingTimeInterval(-Double(daysAgo) * day), weightKg: weight, reps: reps, rpe: rpe)
  }

  func testProgressingLift() {
    let sets = [
      set("barbell_bench", daysAgo: 14, weight: 80, reps: 10),
      set("barbell_bench", daysAgo: 7, weight: 90, reps: 10),
      set("barbell_bench", daysAgo: 0, weight: 100, reps: 10),
    ]
    let audit = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    guard let trend = audit.trends.first else { return XCTFail("expected a trend") }
    XCTAssertEqual(trend.exercise.id, "barbell_bench")
    XCTAssertEqual(trend.direction, .progressing)
    XCTAssertEqual(trend.sessions, 3)
    XCTAssertEqual(trend.firstE1RM, Strength.epley(weightKg: 80, reps: 10), accuracy: 0.001)
    XCTAssertEqual(trend.latestE1RM, Strength.epley(weightKg: 100, reps: 10), accuracy: 0.001)
    XCTAssertGreaterThan(trend.changePercent, 3)
  }

  func testFlatLift() {
    let sets = [
      set("barbell_bench", daysAgo: 7, weight: 80, reps: 8),
      set("barbell_bench", daysAgo: 0, weight: 82, reps: 8),
    ]
    let audit = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    XCTAssertEqual(audit.trends.first?.direction, .flat)
  }

  func testSingleSessionLift() {
    let sets = [set("barbell_bench", daysAgo: 0, weight: 80, reps: 8)]
    let audit = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    XCTAssertEqual(audit.trends.first?.direction, .tooFewSessions)
    XCTAssertEqual(audit.trends.first?.sessions, 1)
    XCTAssertEqual(audit.trends.first?.changePercent, 0)
  }

  func testUndertrainedMuscle() {
    let sets = [set("barbell_curl", daysAgo: 0, weight: 30, reps: 10)]
    let audit = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    let biceps = audit.muscles.first { $0.muscle == .biceps }
    XCTAssertEqual(biceps?.verdict, .under)
    XCTAssertEqual(biceps?.setsPerWeek ?? 0, 1.0, accuracy: 0.001)
  }

  func testOvertrainedMuscle() {
    let sets = (0..<20).map { _ in set("barbell_curl", daysAgo: 0, weight: 30, reps: 10) }
    let audit = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    let biceps = audit.muscles.first { $0.muscle == .biceps }
    XCTAssertEqual(biceps?.verdict, .over)
    XCTAssertEqual(biceps?.setsPerWeek ?? 0, 20.0, accuracy: 0.001)
  }

  func testRecoveryReducedFloorBetweenMVAndMEV() {
    let sets = (0..<7).map { _ in set("barbell_bench", daysAgo: 0, weight: 80, reps: 10) }
    let reduced = PlanAuditEngine.audit(sets: sets, recoveryReduced: true, now: now)
    let chest = reduced.muscles.first { $0.muscle == .chest }
    XCTAssertEqual(chest?.verdict, .inRange)
    XCTAssertEqual(chest?.mev, 6)
    XCTAssertEqual(chest?.mrv, 17)

    let full = PlanAuditEngine.audit(sets: sets, recoveryReduced: false, now: now)
    XCTAssertEqual(full.muscles.first { $0.muscle == .chest }?.verdict, .under)
  }

  func testEmptyInput() {
    let audit = PlanAuditEngine.audit(sets: [], recoveryReduced: false, now: now)
    XCTAssertEqual(audit.weeks, 0)
    XCTAssertEqual(audit.sessionCount, 0)
    XCTAssertEqual(audit.sessionsPerWeek, 0)
    XCTAssertTrue(audit.trends.isEmpty)
    XCTAssertTrue(audit.muscles.isEmpty)
    XCTAssertFalse(audit.headline.isEmpty)
  }
}
