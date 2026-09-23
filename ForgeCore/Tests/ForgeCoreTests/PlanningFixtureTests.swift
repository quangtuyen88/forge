import XCTest

@testable import ForgeCore

// Pins the planning engine's actual behaviour against the goal doc's §5 fixtures (Tokyo dates).

private func tokyo() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
  return calendar
}

private func tokyoDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
  tokyo().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func fixtureDay(_ id: String, _ day: Date, session: String) -> WeekPlanDay {
  WeekPlanDay(
    id: id,
    date: day,
    plannedSessionID: session,
    sessionName: session,
    exerciseIDs: ["bench_press", "barbell_row"],
    plannedSetCount: 5,
    gymProfileID: "commercial",
    gymProfileName: "Commercial gym",
    timeBudgetMinutes: 60)
}

/// F01: Mon/Wed/Fri week of 2026-09-21, Full A completed; August workouts are not in the plan.
private func f01Plan() -> WeekPlan {
  var plan = WeekPlan(
    id: "week-f01",
    weekStart: tokyoDate(2026, 9, 21),
    timeZoneIdentifier: "Asia/Tokyo",
    enrollmentDate: tokyoDate(2026, 9, 21),
    graceWindow: WeekPlan.defaultGraceWindow,
    days: [
      fixtureDay("full-a", tokyoDate(2026, 9, 21), session: "Full A"),
      fixtureDay("full-b", tokyoDate(2026, 9, 23), session: "Full B"),
      fixtureDay("full-c", tokyoDate(2026, 9, 25), session: "Full C"),
    ])
  plan.complete(dayID: "full-a", sessionID: "s1-f01")
  return plan
}

final class PlanningFixtureTests: XCTestCase {

  /// Frozen F01 now: Tuesday 2026-09-22 22:00 Asia/Tokyo.
  private static let now = tokyoDate(2026, 9, 22, 22)

  // MARK: F01

  func testF01WeekPlanAtFrozenNowReportsOneOfThreeAndPointsAtFullB() {
    // F01: scheduled 3, completed 1; the next owed session is Full B on 2026-09-23.
    let plan = f01Plan()

    // The same evaluation call WeekPlanTodayStatus uses, on the plan's own calendar.
    let evaluation = plan.evaluation(now: Self.now, calendar: tokyo())

    XCTAssertEqual(evaluation.counts.scheduled, 3)
    XCTAssertEqual(evaluation.counts.completed, 1)
    XCTAssertEqual(evaluation.counts.remaining, 2)
    XCTAssertEqual(evaluation.counts.missed, 0)

    // Rest day: the plan has no row for Tuesday at all.
    XCTAssertNil(plan.day(on: Self.now, calendar: tokyo()))
    XCTAssertEqual(evaluation.atRisk, 0, "nothing is due today")

    // The owed session: the earliest remaining planned day — Full B on Wednesday, not today.
    let owed = evaluation.days
      .filter { $0.state == .remaining && $0.plannedSessionID != nil }
      .sorted { $0.date < $1.date }
    XCTAssertEqual(owed.first?.dayID, "full-b")
    XCTAssertEqual(owed.first?.date, tokyoDate(2026, 9, 23))
    XCTAssertEqual(owed.first?.reason, .upcoming)
    XCTAssertFalse(tokyo().isDate(owed.first!.date, inSameDayAs: Self.now))
  }

  // MARK: F13

  func testF13ClockAtSep28KeepsCompletedCountAndNeverRewritesAttendance() {
    // F13 at Sep 28: still 1 of 3; Full B/C are .missed — grace is only the window before it.
    let plan = f01Plan()
    let evaluation = plan.evaluation(now: tokyoDate(2026, 9, 28), calendar: tokyo())

    XCTAssertEqual(evaluation.counts.scheduled, 3)
    XCTAssertEqual(evaluation.counts.completed, 1)
    XCTAssertEqual(evaluation.counts.missed, 2)
    XCTAssertEqual(evaluation.counts.remaining, 0)

    XCTAssertEqual(evaluation.day("full-b")?.state, .missed)
    XCTAssertEqual(evaluation.day("full-b")?.reason, .graceExpired)
    XCTAssertEqual(evaluation.day("full-c")?.state, .missed)
    XCTAssertEqual(evaluation.day("full-c")?.reason, .graceExpired)
    XCTAssertEqual(evaluation.adherence ?? -1, 1.0 / 3.0, accuracy: 0.0001)

    // Evaluation is pure: advancing the clock never rewrites recorded attendance.
    XCTAssertEqual(plan.days.map(\.state), [.completed, .planned, .planned])
    XCTAssertEqual(plan.days.first?.completedSessionID, "s1-f01")
  }

  // MARK: F09

  func testF09PartialSessionCountsAsCompleted() {
    // F09 expects partial; the only API is complete(dayID:sessionID:), so it reads completed.
    let plan = f01Plan()

    XCTAssertEqual(plan.days[0].plannedSetCount, 5, "the plan knows five working sets were planned")
    XCTAssertEqual(plan.days[0].completedSessionID, "s1-f01")

    let evaluation = plan.evaluation(now: Self.now, calendar: tokyo())
    XCTAssertEqual(evaluation.day("full-a")?.state, .completed)
    XCTAssertEqual(evaluation.counts.completed, 1)
  }

  // MARK: F08

  func testF08BenchmarkGoalClosesHalfTheGapWithoutAchieving() {
    // F08: best verified estimate 95 vs baseline 90, target 100 — fraction 0.5, not achieved.
    let first = Strength.epley(weightKg: 75, reps: 6)
    let second = Strength.epley(weightKg: 75, reps: 8)
    XCTAssertEqual(first, 90, accuracy: 0.0001)
    XCTAssertEqual(second, 95, accuracy: 0.0001)

    let goal = GoalRecord(
      id: "f08",
      goal: .strength,
      title: "Bench e1RM 100 kg",
      target: .benchmark(
        BenchmarkTarget(
          exerciseID: "bench_press",
          metric: .estimatedOneRepMax,
          baseline: 90,
          target: 100,
          unit: .kilograms)),
      deadline: nil,
      createdAt: tokyoDate(2026, 9, 21),
      status: .onTrack,
      evidenceCount: 2)
    let evidence = [
      GoalEvidence(
        goalID: "f08", kind: .measured, exerciseID: "bench_press", verified: true,
        value: first, occurredAt: tokyoDate(2026, 9, 21, 18)),
      GoalEvidence(
        goalID: "f08", kind: .measured, exerciseID: "bench_press", verified: true,
        value: second, occurredAt: tokyoDate(2026, 9, 22, 20)),
    ]

    let progress = GoalProgressPolicy.progress(goal: goal, evidence: evidence, now: Self.now)

    XCTAssertTrue(progress.isConclusive)
    XCTAssertEqual(progress.verifiedEvidenceCount, 2)
    XCTAssertEqual(progress.current ?? -1, 95, accuracy: 0.0001)
    XCTAssertEqual(progress.fraction ?? -1, 0.5, accuracy: 0.0001)
    XCTAssertNotEqual(progress.status, .achieved)
    XCTAssertEqual(progress.status, .onTrack, "no deadline set, so pace never flags atRisk")
  }

  // MARK: F11

  func testF11CanaryHealthValuesNeverReachTheRenderedPayload() {
    // F11: canaries must not reach `rendered()`; the withheld list names both Health keys.
    let fields = [
      ContextField(key: "trainingGoal", value: "hypertrophy", source: .app),
      ContextField(key: "hrv", value: "CANARY-HRV-38", source: .healthKit),
      ContextField(key: "sleepHours", value: "CANARY-SLEEP-5.5", source: .healthKit),
    ]

    let packet = CoachContextBuilder.packet(fields: fields, decisions: [])
    let rendered = packet.rendered()

    XCTAssertFalse(rendered.contains("CANARY-HRV-38"))
    XCTAssertFalse(rendered.contains("CANARY-SLEEP-5.5"))
    XCTAssertEqual(packet.withheld, ["hrv", "sleepHours"])
    XCTAssertTrue(rendered.contains("trainingGoal: hypertrophy"))
  }
}
