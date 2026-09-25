import XCTest

@testable import ForgeCore

// MARK: - deterministic fixtures

private func gregorianUTC() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0)
  -> Date
{
  gregorianUTC().date(
    from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func date(zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: zone)!
  return calendar.date(
    from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func planDay(
  _ id: String,
  _ day: Date,
  session: String = "Full A",
  state: WeekPlanDayState = .planned,
  gym: String? = "commercial"
) -> WeekPlanDay {
  WeekPlanDay(
    id: id,
    date: day,
    plannedSessionID: session,
    sessionName: session,
    exerciseIDs: ["back_squat", "bench_press"],
    plannedSetCount: 12,
    gymProfileID: gym,
    gymProfileName: "Commercial gym",
    timeBudgetMinutes: 60,
    state: state)
}

/// Monday 1 Jan 2024 … Sunday 7 Jan 2024, five planned sessions.
private func weekPlan(
  enrollmentDate: Date,
  graceWindow: TimeInterval = WeekPlan.defaultGraceWindow,
  timeZoneIdentifier: String = "UTC",
  days: [WeekPlanDay]? = nil
) -> WeekPlan {
  let monday = date(2024, 1, 1)
  let resolved =
    days
    ?? (0..<5).map { index in
      planDay(
        "d\(index + 1)",
        gregorianUTC().date(byAdding: .day, value: index, to: monday)!)
    }
  return WeekPlan(
    id: "week-1",
    weekStart: monday,
    timeZoneIdentifier: timeZoneIdentifier,
    enrollmentDate: enrollmentDate,
    graceWindow: graceWindow,
    days: resolved)
}

final class PlanningFeaturesTests: XCTestCase {

  // MARK: late-week enrollment

  func testLateWeekEnrollmentNeverMarksEarlierDaysMissed() {
    let plan = weekPlan(enrollmentDate: date(2024, 1, 3, 9))
    let evaluation = plan.evaluation(now: date(2024, 1, 3, 12), calendar: gregorianUTC())

    XCTAssertEqual(evaluation.counts.beforeEnrollment, 2)
    XCTAssertEqual(evaluation.counts.missed, 0, "Monday and Tuesday predate enrollment")

    for index in 0..<2 {
      let day = evaluation.days[index]
      XCTAssertEqual(day.state, .skipped)
      XCTAssertEqual(day.reason, .beforeEnrollment)
      XCTAssertFalse(day.isCountedInPlan)
    }

    XCTAssertEqual(evaluation.days[2].state, .remaining)
    XCTAssertEqual(evaluation.days[2].reason, .dueToday)
    XCTAssertEqual(evaluation.days[3].state, .remaining)
    XCTAssertEqual(evaluation.days[3].reason, .upcoming)
    XCTAssertEqual(evaluation.counts.remaining, 3)
    XCTAssertEqual(evaluation.counts.scheduled, 3, "pre-enrollment days leave the denominator")
    XCTAssertEqual(evaluation.atRisk, 1)
    XCTAssertNil(evaluation.adherence, "nothing has come due yet")

    let validation = plan.validation(now: date(2024, 1, 3, 12), calendar: gregorianUTC())
    XCTAssertTrue(validation.isValid, "\(validation.issues)")
    XCTAssertFalse(validation.contains(.missedBeforeEnrollment))
  }

  func testEnrollmentOnWednesdayStillLeavesTheRestOfTheWeekRemaining() {
    let plan = weekPlan(enrollmentDate: date(2024, 1, 3, 9))
    let evaluation = plan.evaluation(now: date(2024, 1, 5, 6), calendar: gregorianUTC())
    // Wednesday is only missed once its grace window closes on Thursday 12:00.
    XCTAssertEqual(evaluation.counts.missed, 1)
    XCTAssertEqual(evaluation.days[2].state, .missed)
    XCTAssertEqual(evaluation.days[2].reason, .graceExpired)
    XCTAssertEqual(evaluation.days[3].state, .remaining)
    XCTAssertEqual(evaluation.days[4].state, .remaining)
    XCTAssertEqual(evaluation.adherence, 0)
  }

  // MARK: grace windows

  func testExplicitGraceWindowIsHonouredExactly() {
    let monday = date(2024, 1, 1)
    let plan = weekPlan(
      enrollmentDate: monday,
      graceWindow: 6 * 60 * 60,
      days: [planDay("d1", monday)])

    let inside = plan.evaluation(now: date(2024, 1, 2, 3), calendar: gregorianUTC()).days[0]
    XCTAssertEqual(inside.state, .remaining)
    XCTAssertEqual(inside.reason, .withinGraceWindow)
    XCTAssertEqual(inside.deadline, date(2024, 1, 2, 6))

    let outside = plan.evaluation(now: date(2024, 1, 2, 6), calendar: gregorianUTC()).days[0]
    XCTAssertEqual(outside.state, .missed)
    XCTAssertEqual(outside.reason, .graceExpired)
  }

  func testCompletedAndSkippedDaysIgnoreTheGraceWindow() {
    let monday = date(2024, 1, 1)
    var plan = weekPlan(
      enrollmentDate: monday,
      graceWindow: 0,
      days: [planDay("d1", monday), planDay("d2", date(2024, 1, 2))])
    XCTAssertTrue(plan.complete(dayID: "d1", sessionID: "session-1"))
    XCTAssertTrue(plan.skip(dayID: "d2"))

    let evaluation = plan.evaluation(now: date(2024, 1, 10), calendar: gregorianUTC())
    XCTAssertEqual(evaluation.days[0].state, .completed)
    XCTAssertEqual(evaluation.days[0].reason, .completed)
    XCTAssertEqual(evaluation.days[1].state, .skipped)
    XCTAssertEqual(evaluation.days[1].reason, .skippedByUser)
    XCTAssertEqual(evaluation.counts.missed, 0)
    XCTAssertEqual(evaluation.counts.completed, 1)
    XCTAssertEqual(evaluation.counts.skipped, 1)
    XCTAssertEqual(evaluation.adherence, 1)
  }

  // MARK: validation distinguishes remaining from missed

  func testStoredMissedBeforeTheDeadlineIsAValidationError() {
    let monday = date(2024, 1, 1)
    let plan = weekPlan(
      enrollmentDate: monday,
      days: [planDay("d1", monday, state: .missed)])

    let early = plan.validation(now: date(2024, 1, 1, 12), calendar: gregorianUTC())
    XCTAssertFalse(early.isValid)
    XCTAssertTrue(early.contains(.missedWhileStillRemaining))
    XCTAssertEqual(early.errors.first?.dayID, "d1")

    let resolved = plan.evaluation(now: date(2024, 1, 1, 12), calendar: gregorianUTC())
    XCTAssertEqual(resolved.days[0].state, .remaining, "evaluation disagrees with the stored state")

    let late = plan.validation(now: date(2024, 1, 5), calendar: gregorianUTC())
    XCTAssertFalse(late.contains(.missedWhileStillRemaining))
    XCTAssertTrue(late.isValid, "\(late.issues)")
  }

  func testMissedDayBeforeEnrollmentIsAlwaysAValidationError() {
    let monday = date(2024, 1, 1)
    let plan = weekPlan(
      enrollmentDate: date(2024, 1, 4),
      days: [planDay("d1", monday, state: .missed)])
    let validation = plan.validation(now: date(2024, 1, 10), calendar: gregorianUTC())
    XCTAssertTrue(validation.contains(.missedBeforeEnrollment))
    XCTAssertFalse(validation.isValid)
  }

  func testStaleRecordedStateAndMissingIdentityAreReported() {
    let monday = date(2024, 1, 1)
    let plan = WeekPlan(
      id: "week-1",
      weekStart: monday,
      timeZoneIdentifier: "UTC",
      enrollmentDate: monday,
      graceWindow: 0,
      days: [
        WeekPlanDay(
          id: "d1", date: monday, plannedSessionID: nil, sessionName: "Full A",
          gymProfileID: nil, timeBudgetMinutes: 0),
        planDay("d2", date(2024, 1, 2), state: .completed),
        planDay("d3", date(2024, 1, 3), state: .moved),
      ])

    let validation = plan.validation(now: date(2024, 1, 10), calendar: gregorianUTC())
    XCTAssertTrue(validation.contains(.missingPlannedSession))
    XCTAssertTrue(validation.contains(.missingGymProfile))
    XCTAssertTrue(validation.contains(.nonPositiveTimeBudget))
    XCTAssertTrue(validation.contains(.completedWithoutSession))
    XCTAssertTrue(validation.contains(.movedWithoutDestination))
    XCTAssertFalse(validation.isValid)
  }

  func testDuplicateDatesAndEmptyPlansAreErrors() {
    let monday = date(2024, 1, 1)
    let plan = weekPlan(
      enrollmentDate: monday,
      days: [planDay("d1", monday), planDay("d2", monday, session: "Full B")])
    XCTAssertTrue(
      plan.validation(now: monday, calendar: gregorianUTC()).contains(.duplicateDayDate))

    let empty = weekPlan(enrollmentDate: monday, days: [])
    XCTAssertTrue(empty.validation(now: monday, calendar: gregorianUTC()).contains(.emptyPlan))
  }

  // MARK: moves

  func testMoveMarksTheSourceAndCarriesTheSessionIdentityForward() {
    let monday = date(2024, 1, 1)
    var plan = weekPlan(
      enrollmentDate: monday,
      days: [planDay("d1", monday, session: "Full A"), planDay("d2", date(2024, 1, 4), session: "Full B")])

    XCTAssertFalse(plan.move(dayID: "missing", to: date(2024, 1, 5)))
    XCTAssertFalse(
      plan.move(dayID: "d1", to: monday), "moving a session onto its own day is a no-op")
    XCTAssertTrue(plan.move(dayID: "d1", to: date(2024, 1, 5)))

    XCTAssertEqual(plan.days.count, 3)
    XCTAssertEqual(plan.days.map(\.id), ["d1", "d2", "d1@1704412800"])
    XCTAssertEqual(plan.days[0].state, .moved)
    XCTAssertEqual(plan.days[0].movedToDate, date(2024, 1, 5))

    let carried = plan.days[2]
    XCTAssertEqual(carried.date, date(2024, 1, 5))
    XCTAssertEqual(carried.plannedSessionID, "Full A")
    XCTAssertEqual(carried.exerciseIDs, ["back_squat", "bench_press"])
    XCTAssertEqual(carried.movedFromDate, monday)
    XCTAssertEqual(carried.state, .planned)

    let evaluation = plan.evaluation(now: date(2024, 1, 5, 6), calendar: gregorianUTC())
    XCTAssertEqual(evaluation.day("d1")?.state, .moved)
    XCTAssertEqual(evaluation.day("d1")?.reason, .movedAway)
    XCTAssertEqual(evaluation.day("d1@1704412800")?.state, .remaining)
    XCTAssertEqual(evaluation.day("d2")?.state, .remaining, "the host day is untouched")
    XCTAssertEqual(evaluation.counts.missed, 0)
    XCTAssertTrue(plan.validation(now: date(2024, 1, 5, 6), calendar: gregorianUTC()).isValid)
  }

  func testMoveOntoAnExistingDayAppendsTheReceivedSession() {
    let monday = date(2024, 1, 1)
    let thursday = date(2024, 1, 4)
    var plan = weekPlan(
      enrollmentDate: monday,
      days: [planDay("d1", monday, session: "Full A"), planDay("d2", thursday, session: "Full B")])

    XCTAssertTrue(plan.move(dayID: "d1", to: thursday))
    XCTAssertEqual(plan.days.count, 2)
    XCTAssertEqual(plan.days[1].receivedSessionIDs, ["Full A"])
    XCTAssertEqual(plan.days[1].plannedSessionID, "Full B", "the host keeps its own session")
  }

  // MARK: time zones

  func testDayEvaluationIsAnchoredToThePlanTimeZoneNotTheCallersCalendar() {
    // 2 Jan 00:00 JST is 1 Jan 15:00 UTC. Evaluating with a UTC calendar must
    // still treat the day as the Tokyo day the plan was authored in.
    let mondayTokyo = date(2024, 1, 1)
    let plan = WeekPlan(
      id: "week-tokyo",
      weekStart: mondayTokyo,
      timeZoneIdentifier: "Asia/Tokyo",
      enrollmentDate: mondayTokyo,
      graceWindow: 12 * 60 * 60,
      days: [planDay("d1", date(zone: "Asia/Tokyo", 2024, 1, 2))])

    XCTAssertEqual(plan.resolvedCalendar(gregorianUTC()).timeZone.identifier, "Asia/Tokyo")

    // 2 Jan 14:00 UTC == 2 Jan 23:00 JST: the session is still owed today. A UTC
    // reading of the same instant would already have closed the window.
    let tokyoView = plan.evaluation(now: date(2024, 1, 2, 14), calendar: gregorianUTC())
    XCTAssertEqual(tokyoView.days[0].state, .remaining)
    XCTAssertEqual(tokyoView.days[0].reason, .dueToday)
    XCTAssertEqual(tokyoView.days[0].deadline, date(2024, 1, 3, 3))

    // 2 Jan 20:00 UTC == 3 Jan 05:00 JST: still inside the Tokyo grace window,
    // while a UTC-anchored evaluation would call it missed.
    let late = plan.evaluation(now: date(2024, 1, 2, 20), calendar: gregorianUTC())
    XCTAssertEqual(late.days[0].state, .remaining)
    XCTAssertEqual(late.days[0].reason, .withinGraceWindow)

    let utcAnchored = WeekPlanStatusPolicy.resolve(
      day: planDay("d1", date(zone: "Asia/Tokyo", 2024, 1, 2)),
      start: date(2024, 1, 1),
      deadline: date(2024, 1, 2, 12),
      beforeEnrollment: false,
      now: date(2024, 1, 2, 20),
      calendar: gregorianUTC()).0
    XCTAssertEqual(utcAnchored, .missed, "the naive UTC anchor disagrees — hence the test")
  }

  func testEvaluationIsIdenticalAcrossCallerCalendars() {
    let monday = date(2024, 1, 1)
    let plan = weekPlan(enrollmentDate: monday)
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

    let now = date(2024, 1, 3, 12)
    XCTAssertEqual(
      plan.evaluation(now: now, calendar: gregorianUTC()),
      plan.evaluation(now: now, calendar: tokyo))
  }

  // MARK: builder reuse

  func testBuilderReusesProfileAndTrainingConstraints() {
    let profile = ProfileInput(
      goal: .strength,
      daysPerWeek: 3,
      sessionLength: .m60,
      equipment: [.barbell, .dumbbell])
    let travel = TrainingConstraints(
      activeGymProfileID: "hotel", travelMode: true, sessionBudgetMinutes: 35)

    let plan = WeekPlanBuilder.plan(
      startingOn: date(2024, 1, 1),
      plannedDays: Program.week(1, profile: profile),
      profile: profile,
      constraints: travel,
      calendar: gregorianUTC())

    XCTAssertEqual(plan.mode, .travel)
    XCTAssertEqual(plan.gymProfileID, "hotel")
    XCTAssertEqual(plan.id, "week-1704067200")
    XCTAssertEqual(plan.days.count, Program.split(daysPerWeek: 3, style: .auto).count)
    XCTAssertEqual(plan.days[0].timeBudgetMinutes, 35)
    XCTAssertEqual(plan.days[0].gymProfileID, "hotel")
    XCTAssertEqual(plan.days[0].gymProfileName, "Hotel")
    XCTAssertEqual(plan.days.map(\.date), (0..<3).map { date(2024, 1, 1 + $0) })
    XCTAssertTrue(plan.validation(now: date(2024, 1, 1), calendar: gregorianUTC()).isValid)
  }

  func testBuilderKeepsPlannedDayIdentityAndFallsBackToDefaultGymAndBudget() {
    let profile = ProfileInput(
      goal: .hypertrophy, daysPerWeek: 4, sessionLength: .m90, equipment: [.barbell])
    let planned = Program.week(2, profile: profile)
    let plan = WeekPlanBuilder.plan(
      startingOn: date(2024, 1, 1),
      plannedDays: planned,
      profile: profile,
      constraints: TrainingConstraints(),
      calendar: gregorianUTC())

    XCTAssertEqual(plan.mode, .standard)
    XCTAssertEqual(plan.days.map(\.plannedSessionID), planned.map(\.id))
    XCTAssertEqual(plan.days[0].exerciseIDs, planned[0].exercises.map(\.exercise.id))
    XCTAssertEqual(plan.days[0].plannedSetCount, planned[0].exercises.reduce(0) { $0 + $1.sets })
    XCTAssertEqual(plan.days[0].timeBudgetMinutes, 90)
    XCTAssertEqual(plan.days[0].gymProfileName, "Commercial gym")
  }

  func testBuilderModesFollowConstraintsAndProfile() {
    let profile = ProfileInput(
      goal: .both, daysPerWeek: 3, sessionLength: .m45, equipment: [.barbell])
    XCTAssertEqual(
      WeekPlanBuilder.mode(profile: profile, constraints: TrainingConstraints()),
      .standard)
    XCTAssertEqual(
      WeekPlanBuilder.mode(
        profile: profile, constraints: TrainingConstraints(minimumEffectiveWorkout: true)),
      .minimumEffective)
    XCTAssertEqual(
      WeekPlanBuilder.mode(profile: profile, constraints: TrainingConstraints(travelMode: true)),
      .travel)

    var reduced = profile
    reduced.recoveryReduced = true
    XCTAssertEqual(
      WeekPlanBuilder.mode(profile: reduced, constraints: TrainingConstraints()), .reduced)
    XCTAssertTrue(WeekPlanMode.travel.relaxesMissedSessions)
    XCTAssertFalse(WeekPlanMode.standard.relaxesMissedSessions)
  }

  // MARK: week status hand-off & codable

  func testWeekStatusPresentationDefersToWeekStatusPolicy() {
    let now = date(2024, 1, 3, 12)
    let plan = weekPlan(enrollmentDate: date(2024, 1, 1))
    let presentation = plan.weekStatusPresentation(now: now, calendar: gregorianUTC())
    XCTAssertEqual(presentation.planned, 5)
    XCTAssertEqual(presentation.recorded, 0)
    XCTAssertEqual(presentation.remaining, 5)
    XCTAssertEqual(presentation.atRisk, 0, "enrolling this week never creates retrospective debt")
  }
}

// MARK: - goals

private func benchmarkGoal(
  id: String = "g1",
  baseline: Double = 100,
  target: Double = 120,
  exerciseID: String = "back_squat",
  createdAt: Date,
  deadline: Date?,
  status: GoalStatus = .notStarted,
  evidenceCount: Int = 0
) -> GoalRecord {
  GoalRecord(
    id: id,
    goal: .strength,
    title: "Squat \(Int(target))kg e1RM",
    target: .benchmark(
      BenchmarkTarget(
        exerciseID: exerciseID,
        metric: .estimatedOneRepMax,
        baseline: baseline,
        target: target,
        unit: .kilograms)),
    deadline: deadline,
    createdAt: createdAt,
    status: status,
    evidenceCount: evidenceCount)
}

private func evidence(
  _ values: [Double],
  goalID: String = "g1",
  exerciseID: String? = "back_squat",
  kind: GoalEvidenceKind = .measured,
  verified: Bool = true,
  from start: Date,
  stepDays: Int = 1
) -> [GoalEvidence] {
  values.enumerated().map { index, value in
    GoalEvidence(
      id: "\(goalID)-e\(index)",
      goalID: goalID,
      kind: kind,
      exerciseID: exerciseID,
      verified: verified,
      value: value,
      occurredAt: gregorianUTC().date(byAdding: .day, value: index * stepDays, to: start)!)
  }
}

final class GoalPlanningFeaturesTests: XCTestCase {

  // MARK: benchmark progress

  func testBenchmarkProgressTracksBaselineTargetAndMilestones() {
    let created = date(2024, 1, 1)
    let goal = benchmarkGoal(createdAt: created, deadline: date(2024, 3, 1), evidenceCount: 3)
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence([105, 110, 115], from: date(2024, 1, 5)),
      now: date(2024, 1, 29))

    XCTAssertTrue(progress.isConclusive)
    XCTAssertEqual(progress.current, 115)
    XCTAssertEqual(progress.baseline, 100)
    XCTAssertEqual(progress.target, 120)
    XCTAssertEqual(progress.unit, .kilograms)
    XCTAssertEqual(progress.fraction ?? -1, 0.75, accuracy: 0.0001)
    XCTAssertEqual(progress.status, .onTrack)
    XCTAssertEqual(progress.milestones.map(\.value), [105, 110, 115, 120])
    XCTAssertEqual(progress.milestones.map(\.label), ["25%", "50%", "75%", "100%"])
    XCTAssertEqual(progress.milestones.map(\.id), ["g1#0.25", "g1#0.5", "g1#0.75", "g1#1.0"])
    XCTAssertEqual(progress.reachedMilestoneIDs, ["g1#0.25", "g1#0.5", "g1#0.75"])
    XCTAssertEqual(progress.nextMilestone?.value, 120)
    XCTAssertTrue(progress.hasReached(progress.milestones[2]))
    XCTAssertFalse(progress.hasReached(progress.milestones[3]))
  }

  func testBehindPaceIsAtRiskNotAchieved() {
    let created = date(2024, 1, 1)
    let goal = benchmarkGoal(
      baseline: 100, target: 200, createdAt: created, deadline: date(2024, 3, 1))
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence([105], from: date(2024, 1, 31)),
      now: date(2024, 1, 31))
    XCTAssertEqual(progress.status, .atRisk)
    XCTAssertEqual(progress.fraction ?? -1, 0.05, accuracy: 0.0001)
    XCTAssertEqual(progress.reachedMilestoneIDs, [])
  }

  func testReachingTheTargetIsAchievedAndClampsTheFraction() {
    let created = date(2024, 1, 1)
    let goal = benchmarkGoal(createdAt: created, deadline: date(2024, 3, 1), evidenceCount: 4)
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence([105, 110, 115, 124], from: date(2024, 1, 5)),
      now: date(2024, 1, 29))

    XCTAssertEqual(progress.status, .achieved)
    XCTAssertEqual(progress.current, 124)
    XCTAssertEqual(progress.fraction ?? -1, 1)
    XCTAssertEqual(progress.reachedMilestoneIDs.count, 4)
    XCTAssertNil(progress.nextMilestone)
    XCTAssertEqual(progress.reason, "Target reached on 4 verified records")
  }

  func testAtMostComparatorUsesTheMinimumVerifiedValue() {
    let goal = GoalRecord(
      id: "bw",
      goal: .hypertrophy,
      title: "Bodyweight",
      target: .benchmark(
        BenchmarkTarget(
          exerciseID: "bodyweight",
          metric: .topSetLoad,
          baseline: 95,
          target: 85,
          unit: .kilograms,
          comparator: .atMost)),
      createdAt: date(2024, 1, 1),
      status: .onTrack)
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence(
        [93, 88, 87], goalID: "bw", exerciseID: "bodyweight", from: date(2024, 1, 2)),
      now: date(2024, 1, 10))

    XCTAssertEqual(progress.current, 87)
    XCTAssertEqual(progress.status, .onTrack)
    XCTAssertEqual(progress.fraction ?? -1, 0.8, accuracy: 0.0001)
    XCTAssertEqual(
      progress.reachedMilestoneIDs, ["bw#0.25", "bw#0.5", "bw#0.75"],
      "87kg is already below the 87.5kg rung")
    XCTAssertEqual(progress.nextMilestone?.value, 85)
  }

  // MARK: insufficient evidence

  func testNoEvidenceNeverClaimsSuccess() {
    let goal = benchmarkGoal(createdAt: date(2024, 1, 1), deadline: date(2024, 3, 1))
    let progress = GoalProgressPolicy.progress(goal: goal, evidence: [], now: date(2024, 1, 10))

    XCTAssertFalse(progress.isConclusive)
    XCTAssertEqual(progress.status, .notStarted)
    XCTAssertNotEqual(progress.status, .achieved)
    XCTAssertNil(progress.current, "no stand-in number")
    XCTAssertNil(progress.fraction, "no invented percentage")
    XCTAssertEqual(progress.reachedMilestoneIDs, [])
    XCTAssertEqual(progress.nextMilestone?.value, 105, "the ladder is still described")
    XCTAssertEqual(progress.milestones.count, 4)
    XCTAssertEqual(progress.reason, "Needs 1 verified evidence record, has 0")
  }

  func testUnverifiedManualEvidenceIsNotEnough() {
    let goal = benchmarkGoal(createdAt: date(2024, 1, 1), deadline: nil)
    let manual = evidence(
      [130, 132, 135], kind: .manual, verified: false, from: date(2024, 1, 2))
    let progress = GoalProgressPolicy.progress(goal: goal, evidence: manual, now: date(2024, 1, 10))

    XCTAssertEqual(progress.evidenceCount, 0, "unverified records are not even counted")
    XCTAssertEqual(progress.verifiedEvidenceCount, 0)
    XCTAssertFalse(progress.isConclusive)
    XCTAssertNotEqual(progress.status, .achieved)
    XCTAssertNil(progress.fraction)
  }

  func testEvidenceForAnotherExerciseOrInTheFutureIsIgnored() {
    let goal = benchmarkGoal(createdAt: date(2024, 1, 1), deadline: nil)
    let other = evidence([999], exerciseID: "bench_press", from: date(2024, 1, 2))
    let future = evidence([888], from: date(2024, 2, 1))
    let progress = GoalProgressPolicy.progress(
      goal: goal, evidence: other + future, now: date(2024, 1, 10))

    XCTAssertEqual(progress.evidenceCount, 0)
    XCTAssertFalse(progress.isConclusive)
    XCTAssertNil(progress.current)
  }

  func testSkillTargetNeedsRepeatedAttributableEvidence() {
    let created = date(2024, 1, 1)
    let skill = GoalRecord(
      id: "skill",
      goal: .both,
      title: "Handstand hold",
      target: .skill(
        SkillTarget(
          skillID: "handstand",
          skillName: "Handstand hold",
          target: 5,
          unit: .repetitions,
          requiredEvidenceKind: .coachSignOff)),
      createdAt: created,
      status: .onTrack)

    let once = GoalProgressPolicy.progress(
      goal: skill,
      evidence: evidence(
        [1], goalID: "skill", exerciseID: nil, kind: .coachSignOff, from: date(2024, 1, 2)),
      now: date(2024, 1, 10))
    XCTAssertFalse(once.isConclusive)
    XCTAssertEqual(once.status, .notStarted)
    XCTAssertEqual(once.reason, "Needs 2 verified evidence records, has 1")
    XCTAssertNil(once.current)

    // Measured evidence does not substitute for the coach sign-off the target demands.
    let wrongKind = GoalProgressPolicy.progress(
      goal: skill,
      evidence: evidence(
        [1, 2], goalID: "skill", exerciseID: nil, kind: .measured, from: date(2024, 1, 2)),
      now: date(2024, 1, 10))
    XCTAssertFalse(wrongKind.isConclusive)
    XCTAssertEqual(wrongKind.evidenceCount, 0)

    let enough = GoalProgressPolicy.progress(
      goal: skill,
      evidence: evidence(
        [1, 2], goalID: "skill", exerciseID: nil, kind: .coachSignOff, from: date(2024, 1, 2)),
      now: date(2024, 1, 10))
    XCTAssertTrue(enough.isConclusive)
    XCTAssertEqual(enough.current, 2)
    XCTAssertEqual(enough.fraction ?? -1, 0.4, accuracy: 0.0001)
    XCTAssertEqual(enough.status, .onTrack)
    XCTAssertEqual(enough.milestones.map(\.value), [1.25, 2.5, 3.75, 5.0])
  }

  func testAdherenceTargetCountsVerifiedSessions() {
    let adherence = GoalRecord(
      id: "adh",
      goal: .hypertrophy,
      title: "Train 12 times",
      target: .adherence(
        AdherenceTarget(metric: .completedSessions, target: 12, windowWeeks: 4)),
      createdAt: date(2024, 1, 1),
      status: .onTrack)

    let partial = GoalProgressPolicy.progress(
      goal: adherence,
      evidence: evidence(
        Array(repeating: 1, count: 5), goalID: "adh", exerciseID: nil, from: date(2024, 1, 1)),
      now: date(2024, 1, 20))
    XCTAssertTrue(partial.isConclusive)
    XCTAssertEqual(partial.current, 5)
    XCTAssertEqual(partial.fraction ?? -1, 5.0 / 12.0, accuracy: 0.0001)
    XCTAssertEqual(partial.status, .onTrack)

    let done = GoalProgressPolicy.progress(
      goal: adherence,
      evidence: evidence(
        Array(repeating: 1, count: 12), goalID: "adh", exerciseID: nil, from: date(2024, 1, 1)),
      now: date(2024, 1, 20))
    XCTAssertEqual(done.status, .achieved)
    XCTAssertEqual(done.fraction ?? -1, 1)
  }

  // MARK: achieved and expired states

  func testDeadlineWithoutEnoughEvidenceIsExpired() {
    let created = date(2024, 1, 1)
    let goal = benchmarkGoal(createdAt: created, deadline: date(2024, 1, 30))
    let progress = GoalProgressPolicy.progress(goal: goal, evidence: [], now: date(2024, 3, 1))

    XCTAssertEqual(progress.status, .expired)
    XCTAssertFalse(progress.isConclusive)
    XCTAssertNil(progress.current)
    XCTAssertEqual(progress.reason, "Deadline passed without enough verified evidence")
  }

  func testAchievedOutranksAnExpiredDeadline() {
    let created = date(2024, 1, 1)
    let goal = benchmarkGoal(
      createdAt: created, deadline: date(2024, 1, 30), status: .onTrack, evidenceCount: 1)
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence([121], from: date(2024, 1, 5)),
      now: date(2024, 6, 1))

    XCTAssertEqual(progress.status, .achieved)
    XCTAssertEqual(progress.current, 121)
  }

  func testExpiredWithProgressReportsHowFarItGot() {
    let goal = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: date(2024, 1, 30), evidenceCount: 2)
    let progress = GoalProgressPolicy.progress(
      goal: goal,
      evidence: evidence([105, 112], from: date(2024, 1, 5)),
      now: date(2024, 3, 1))

    XCTAssertEqual(progress.status, .expired)
    XCTAssertEqual(progress.current, 112)
    XCTAssertEqual(progress.fraction ?? -1, 0.6, accuracy: 0.0001)
    XCTAssertEqual(progress.reason, "Deadline passed at 112 kg of 120 kg")
    XCTAssertEqual(progress.reachedMilestoneIDs, ["g1#0.25", "g1#0.5"])
  }

  func testAbandonedGoalStopsReportingProgress() {
    let goal = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: nil, status: .abandoned, evidenceCount: 1)
    let progress = GoalProgressPolicy.progress(
      goal: goal, evidence: evidence([121], from: date(2024, 1, 5)), now: date(2024, 1, 10))
    XCTAssertEqual(progress.status, .abandoned)
    XCTAssertNil(progress.current)
    XCTAssertNil(progress.fraction)
    XCTAssertEqual(progress.reason, "Goal was abandoned")
  }

  // MARK: validation

  func testClaimingAchievedWithoutEvidenceIsAValidationError() {
    let goal = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: date(2024, 3, 1), status: .achieved)
    let validation = GoalValidationPolicy.validate(goal: goal, evidence: [], now: date(2024, 2, 1))

    XCTAssertFalse(validation.isValid)
    XCTAssertTrue(validation.contains(.achievedWithoutSufficientEvidence))
    XCTAssertEqual(validation.errors.first?.severity, .error)
  }

  func testClaimingAchievedBelowTargetIsAValidationError() {
    let goal = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: date(2024, 3, 1), status: .achieved, evidenceCount: 3)
    let validation = GoalValidationPolicy.validate(
      goal: goal,
      evidence: evidence([105, 110, 115], from: date(2024, 1, 5)),
      now: date(2024, 2, 1))

    XCTAssertFalse(validation.isValid)
    XCTAssertTrue(validation.contains(.achievedBelowTarget))
    XCTAssertFalse(validation.contains(.achievedWithoutSufficientEvidence))
  }

  func testValidAchievedGoalPassesAndEvidenceCountDriftIsAWarning() {
    let goal = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: date(2024, 3, 1), status: .achieved, evidenceCount: 3)
    let validation = GoalValidationPolicy.validate(
      goal: goal,
      evidence: evidence([105, 110, 121], from: date(2024, 1, 5)),
      now: date(2024, 2, 1))
    XCTAssertTrue(validation.isValid, "\(validation.issues)")

    let drifted = benchmarkGoal(
      createdAt: date(2024, 1, 1), deadline: date(2024, 3, 1), status: .achieved, evidenceCount: 9)
    let driftedValidation = GoalValidationPolicy.validate(
      goal: drifted,
      evidence: evidence([105, 110, 121], from: date(2024, 1, 5)),
      now: date(2024, 2, 1))
    XCTAssertTrue(driftedValidation.isValid)
    XCTAssertTrue(driftedValidation.contains(.evidenceCountMismatch))
  }

  func testStructuralGoalValidationCatchesBadRecords() {
    let created = date(2024, 1, 1)
    var goal = benchmarkGoal(baseline: 100, target: 100, createdAt: created, deadline: created)
    goal.id = ""
    goal.title = ""

    let validation = GoalValidationPolicy.validate(goal: goal, evidence: [], now: created)
    XCTAssertTrue(validation.contains(.emptyIdentifier))
    XCTAssertTrue(validation.contains(.emptyTitle))
    XCTAssertTrue(validation.contains(.deadlineBeforeCreation))
    XCTAssertTrue(validation.contains(.targetEqualsBaseline))
    XCTAssertFalse(validation.isValid)
  }

  // MARK: versioning & codable

  func testGoalRecordCodableRoundTripPreservesTypedTarget() throws {
    let goal = GoalRecord(
      id: "g1",
      goal: .strength,
      title: "Squat 120",
      target: .benchmark(
        BenchmarkTarget(
          exerciseID: "back_squat", metric: .estimatedOneRepMax, baseline: 100, target: 120,
          unit: .kilograms)),
      deadline: date(2024, 3, 1),
      createdAt: date(2024, 1, 1),
      status: .onTrack,
      evidenceCount: 3)

    let data = try JSONEncoder().encode(goal)
    let decoded = try JSONDecoder().decode(GoalRecord.self, from: data)
    XCTAssertEqual(decoded, goal)
    XCTAssertEqual(decoded.version, GoalRecord.currentSchemaVersion)
    XCTAssertEqual(decoded.unit, .kilograms)
    XCTAssertEqual(decoded.baseline, 100)
    XCTAssertEqual(decoded.targetValue, 120)
    XCTAssertEqual(decoded.kind, .benchmark)

    let skill = GoalRecord(
      id: "s1", goal: .both, title: "Handstand",
      target: .skill(SkillTarget(skillID: "handstand", skillName: "Handstand", target: 5)),
      createdAt: date(2024, 1, 1))
    XCTAssertEqual(
      try JSONDecoder().decode(GoalRecord.self, from: JSONEncoder().encode(skill)), skill)

    let adherence = GoalRecord(
      id: "a1", goal: .hypertrophy, title: "Train",
      target: .adherence(AdherenceTarget(metric: .completedSessions, target: 12)),
      createdAt: date(2024, 1, 1))
    XCTAssertEqual(
      try JSONDecoder().decode(GoalRecord.self, from: JSONEncoder().encode(adherence)), adherence)
    XCTAssertEqual(adherence.minimumVerifiedEvidence, 1)
    XCTAssertEqual(skill.minimumVerifiedEvidence, 2)
  }

  private struct LegacyGoal: Codable {
    var goal: Goal
    var title: String
    var targetValue: Double
    var exerciseID: String
    var unit: GoalUnit
    var createdAt: Date
  }

  func testUnversionedLegacyGoalMigratesToTheCurrentSchema() throws {
    let legacy = LegacyGoal(
      goal: .strength,
      title: "Squat 140",
      targetValue: 140,
      exerciseID: "back_squat",
      unit: .kilograms,
      createdAt: date(2024, 1, 1))
    let data = try JSONEncoder().encode(legacy)
    let migrated = try JSONDecoder().decode(GoalRecord.self, from: data)

    XCTAssertEqual(migrated.version, GoalRecord.currentSchemaVersion)
    XCTAssertEqual(migrated.id, "legacy-strength-Squat 140", "deterministic fallback id")
    XCTAssertEqual(migrated.kind, .benchmark)
    XCTAssertEqual(migrated.targetValue, 140)
    XCTAssertEqual(migrated.baseline, 0, "the legacy shape carried no baseline; none is invented")
    XCTAssertEqual(migrated.unit, .kilograms)
    XCTAssertEqual(migrated.status, .notStarted)
    XCTAssertEqual(migrated.evidenceCount, 0)
    XCTAssertNil(migrated.deadline)

    // And it must not claim success without evidence.
    XCTAssertNotEqual(
      GoalProgressPolicy.progress(goal: migrated, evidence: [], now: date(2024, 2, 1)).status,
      .achieved)
  }

  func testLegacyGoalWithoutATargetValueIsRejected() {
    let json = Data(#"{"goal":"strength","title":"Squat","createdAt":0}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(GoalRecord.self, from: json)) { error in
      guard case DecodingError.dataCorrupted = error else {
        return XCTFail("expected a dataCorrupted error, got \(error)")
      }
    }
  }
}
