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

private func makeProfile(days: Int, session: SessionLength = .m60) -> ProfileInput {
  ProfileInput(
    goal: .hypertrophy, daysPerWeek: days, sessionLength: session,
    equipment: Set(Equipment.allCases), injuryFlags: [])
}

final class PlanChangeTests: XCTestCase {

  // MARK: rebasedOffset

  func testRebasedOffsetKeepsTheProgramWeek() {
    for (done, offset, from, to) in [
      (6, 0, 4, 3), (6, 0, 3, 4), (2, 0, 4, 3), (7, 0, 4, 2),
      (5, -1, 3, 4), (0, 0, 3, 5), (13, 2, 3, 6),
    ] {
      let weekBefore = min(6, max(0, done + offset) / from + 1)
      let newOffset = Mesocycle.rebasedOffset(
        sessionsDone: done, offset: offset, fromDays: from, toDays: to)
      XCTAssertEqual(
        min(6, max(0, done + newOffset) / to + 1), weekBefore,
        "(\(done), \(offset), \(from), \(to))")
    }
  }

  func testRebasedOffsetDoesNotAdvanceOnEditAndAdvancesWhenTheNewWeekIsFull() {
    let newOffset = Mesocycle.rebasedOffset(sessionsDone: 7, offset: 0, fromDays: 4, toDays: 2)
    XCTAssertEqual(min(6, max(0, 7 + newOffset) / 2 + 1), 2, "the edit itself must not advance the week")
    XCTAssertEqual(min(6, max(0, 8 + newOffset) / 2 + 1), 3, "the next session fills the new week")
  }

  func testRebasedOffsetReturnsSameOffsetWhenDaysUnchanged() {
    XCTAssertEqual(Mesocycle.rebasedOffset(sessionsDone: 5, offset: 3, fromDays: 4, toDays: 4), 3)
  }

  // MARK: revise

  func testReviseKeepsCompletedDaysAndAddsOnlyWhatIsLeft() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    var plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)
    plan.complete(dayID: plan.days[0].id, sessionID: "s-mon")
    plan.complete(dayID: plan.days[1].id, sessionID: "s-tue")
    let originalMonday = plan.days[0]
    let originalTuesday = plan.days[1]

    let now = date(2024, 1, 3, 10)
    let threeDay45 = makeProfile(days: 3, session: .m45)
    let threeDayProgram = Program.week(1, profile: threeDay45)
    let revised = WeekPlanBuilder.revise(
      plan,
      program: threeDayProgram,
      nextDayIndex: 2,
      profile: threeDay45,
      constraints: TrainingConstraints(),
      from: now,
      now: now,
      calendar: utc)

    XCTAssertEqual(revised.days.count, 3)
    XCTAssertEqual(revised.days.first { $0.id == originalMonday.id }, originalMonday)
    XCTAssertEqual(revised.days.first { $0.id == originalTuesday.id }, originalTuesday)
    let added = revised.days.filter { $0.state == .planned }
    XCTAssertEqual(added.count, 1)
    XCTAssertTrue(utc.isDate(added[0].date, inSameDayAs: now))
    XCTAssertEqual(added[0].plannedSessionID, "Full C")
    XCTAssertEqual(added[0].timeBudgetMinutes, 45)
    for day in revised.days where day.state != .completed {
      XCTAssertTrue(threeDayProgram.map(\.id).contains(day.plannedSessionID ?? ""), day.id)
    }
    let counts = revised.evaluation(now: now, calendar: utc).counts
    XCTAssertEqual(counts.completed, 2)
    XCTAssertEqual(counts.remaining, 1)
    XCTAssertEqual(counts.missed, 0)
  }

  func testReviseWithTwoDayProgramAddsNothingWhenTwoDaysAreCompleted() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    var plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)
    plan.complete(dayID: plan.days[0].id, sessionID: "s-mon")
    plan.complete(dayID: plan.days[1].id, sessionID: "s-tue")
    let originalMonday = plan.days[0]
    let originalTuesday = plan.days[1]

    let now = date(2024, 1, 3, 10)
    let twoDay = makeProfile(days: 2)
    let revised = WeekPlanBuilder.revise(
      plan,
      program: Program.week(1, profile: twoDay),
      nextDayIndex: 2,
      profile: twoDay,
      constraints: TrainingConstraints(),
      from: now,
      now: now,
      calendar: utc)

    XCTAssertEqual(revised.days.count, 2)
    XCTAssertEqual(revised.days.first { $0.id == originalMonday.id }, originalMonday)
    XCTAssertEqual(revised.days.first { $0.id == originalTuesday.id }, originalTuesday)
    XCTAssertTrue(revised.days.filter { $0.state == .planned }.isEmpty)
    let counts = revised.evaluation(now: now, calendar: utc).counts
    XCTAssertEqual(counts.completed, 2)
    XCTAssertEqual(counts.remaining, 0)
    XCTAssertEqual(counts.missed, 0)
  }

  func testReviseKeepsPastPlannedAndSkippedDaysAndRefillsDroppedDates() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    var plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)
    plan.skip(dayID: plan.days[1].id)
    let originalMonday = plan.days[0]
    let originalTuesday = plan.days[1]

    let now = date(2024, 1, 3, 10)
    let threeDay = makeProfile(days: 3)
    let revised = WeekPlanBuilder.revise(
      plan,
      program: Program.week(1, profile: threeDay),
      nextDayIndex: 0,
      profile: threeDay,
      constraints: TrainingConstraints(),
      from: now,
      now: now,
      calendar: utc)

    XCTAssertEqual(revised.days.first { $0.id == originalMonday.id }, originalMonday)
    XCTAssertEqual(revised.days.first { $0.id == originalTuesday.id }, originalTuesday)
    XCTAssertEqual(revised.days.count, 5)
    let addedDates = revised.days
      .filter { $0.id != originalMonday.id && $0.id != originalTuesday.id }
      .map { utc.startOfDay(for: $0.date) }
    XCTAssertEqual(addedDates, [date(2024, 1, 3), date(2024, 1, 4), date(2024, 1, 5)])
  }

  func testReviseKeepsOpenWorkoutTodayWhenFromIsTomorrow() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    var plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)
    plan.complete(dayID: plan.days[0].id, sessionID: "s-mon")
    let originals = plan.days

    let revised = WeekPlanBuilder.revise(
      plan,
      program: Program.week(1, profile: fourDay),
      nextDayIndex: 0,
      profile: fourDay,
      constraints: TrainingConstraints(),
      from: date(2024, 1, 4),
      now: date(2024, 1, 3, 10),
      calendar: utc)

    XCTAssertEqual(revised.days.count, 5)
    for original in originals.prefix(3) {
      XCTAssertEqual(revised.days.first { $0.id == original.id }, original)
    }
    let added = revised.days.filter { $0.date >= date(2024, 1, 4) }
    XCTAssertEqual(added.count, 2)
    XCTAssertEqual(
      added.map { utc.startOfDay(for: $0.date) }, [date(2024, 1, 4), date(2024, 1, 5)])
  }

  func testReviseCapsAddedDaysToDaysLeftInTheWeek() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    let plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)

    let now = date(2024, 1, 7, 10)
    let revised = WeekPlanBuilder.revise(
      plan,
      program: Program.week(1, profile: fourDay),
      nextDayIndex: 0,
      profile: fourDay,
      constraints: TrainingConstraints(),
      from: now,
      now: now,
      calendar: utc)

    XCTAssertEqual(revised.days.count, 5)
    let added = revised.days.filter { $0.date >= utc.startOfDay(for: now) }
    XCTAssertEqual(added.count, 1)
    XCTAssertTrue(utc.isDate(added[0].date, inSameDayAs: now))
    for original in plan.days {
      XCTAssertEqual(revised.days.first { $0.id == original.id }, original)
    }
  }

  func testReviseKeepsPlanIdentity() {
    let utc = gregorianUTC()
    let monday = date(2024, 1, 1)
    let fourDay = makeProfile(days: 4)
    var plan = WeekPlanBuilder.plan(
      startingOn: monday,
      plannedDays: Program.week(1, profile: fourDay),
      profile: fourDay,
      constraints: TrainingConstraints(),
      calendar: utc)
    plan.complete(dayID: plan.days[0].id, sessionID: "s-mon")

    let revised = WeekPlanBuilder.revise(
      plan,
      program: Program.week(1, profile: fourDay),
      nextDayIndex: 1,
      profile: fourDay,
      constraints: TrainingConstraints(),
      from: date(2024, 1, 3, 10),
      now: date(2024, 1, 3, 10),
      calendar: utc)

    XCTAssertEqual(revised.id, plan.id)
    XCTAssertEqual(revised.weekStart, plan.weekStart)
    XCTAssertEqual(revised.enrollmentDate, plan.enrollmentDate)
    XCTAssertEqual(revised.timeZoneIdentifier, plan.timeZoneIdentifier)
  }

  // MARK: PlanChangeAdvice

  func testPlanChangeAdvice() {
    XCTAssertEqual(PlanChangeAdvice.windowDays, 14)
    XCTAssertNil(PlanChangeAdvice.advice(blockSessions: 0, changesInWindow: 1))
    XCTAssertEqual(PlanChangeAdvice.advice(blockSessions: 2, changesInWindow: 1), .early(sessions: 2))
    XCTAssertEqual(PlanChangeAdvice.advice(blockSessions: 3, changesInWindow: 2), .early(sessions: 3))
    XCTAssertNil(PlanChangeAdvice.advice(blockSessions: 4, changesInWindow: 1))
    XCTAssertEqual(
      PlanChangeAdvice.advice(blockSessions: 2, changesInWindow: 3), .repeated(changes: 3))
    XCTAssertEqual(
      PlanChangeAdvice.advice(blockSessions: 10, changesInWindow: 4), .repeated(changes: 4))
  }

  // MARK: PlanSettings

  func testPlanSettingsChangesListEachChangedFieldInFixedEnglish() {
    let current = PlanSettings(goal: .hypertrophy, split: .auto, daysPerWeek: 4, sessionMinutes: 60)
    XCTAssertEqual(
      PlanSettings.changes(
        from: current,
        to: PlanSettings(goal: .hypertrophy, split: .auto, daysPerWeek: 3, sessionMinutes: 45)),
      ["days a week 4 → 3", "session 60 → 45 min"])
    XCTAssertEqual(PlanSettings.changes(from: current, to: current), [])
    XCTAssertEqual(
      PlanSettings.changes(
        from: PlanSettings(goal: .hypertrophy, split: .auto, daysPerWeek: 4, sessionMinutes: 60),
        to: PlanSettings(goal: .strength, split: .fullBody, daysPerWeek: 4, sessionMinutes: 60)),
      ["goal Hypertrophy → Strength", "split Auto → Full body"])
  }

  // MARK: PlanAdjustment

  func testPlanAdjustmentInitRejectsUnsupportedValues() {
    XCTAssertNotNil(PlanAdjustment(daysPerWeek: 3, sessionMinutes: 45, goal: nil, split: nil))
    XCTAssertNotNil(PlanAdjustment(daysPerWeek: 2, sessionMinutes: nil, goal: nil, split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: 1, sessionMinutes: nil, goal: nil, split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: nil, sessionMinutes: 35, goal: nil, split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: nil, sessionMinutes: nil, goal: "power", split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: nil, sessionMinutes: nil, goal: nil, split: "broSplit"))
    XCTAssertNil(PlanAdjustment(daysPerWeek: nil, sessionMinutes: nil, goal: nil, split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: 7, sessionMinutes: nil, goal: nil, split: nil))
    XCTAssertNil(PlanAdjustment(daysPerWeek: 3, sessionMinutes: 35, goal: nil, split: nil))
  }

  func testPlanAdjustmentChangingKeepsOnlyDifferingFields() {
    let current = PlanSettings(goal: .hypertrophy, split: .auto, daysPerWeek: 4, sessionMinutes: 60)
    XCTAssertEqual(
      PlanAdjustment(daysPerWeek: 4, sessionMinutes: 45, goal: nil, split: nil)?.changing(current),
      PlanAdjustment(daysPerWeek: nil, sessionMinutes: 45, goal: nil, split: nil))
    XCTAssertNil(
      PlanAdjustment(daysPerWeek: 4, sessionMinutes: 60, goal: nil, split: nil)?.changing(current))
  }

  func testPlanAdjustmentAppliedToProfileInput() throws {
    let base = makeProfile(days: 4)
    let adjusted = try XCTUnwrap(
      PlanAdjustment(daysPerWeek: 3, sessionMinutes: 45, goal: "strength", split: "fullBody"))
      .applied(to: base)
    XCTAssertEqual(adjusted.daysPerWeek, 3)
    XCTAssertEqual(adjusted.sessionLength, .m45)
    XCTAssertEqual(adjusted.goal, .strength)
    XCTAssertEqual(adjusted.split, .fullBody)
    XCTAssertEqual(adjusted.equipment, base.equipment)

    let threeDayAuto = try XCTUnwrap(
      PlanAdjustment(daysPerWeek: 3, sessionMinutes: 45, goal: nil, split: nil))
      .applied(to: base)
    XCTAssertEqual(Program.week(1, profile: threeDayAuto).map(\.name), ["Full A", "Full B", "Full C"])
  }

  func testPlanAdjustmentDigestComponents() throws {
    let adjustment = try XCTUnwrap(PlanAdjustment(daysPerWeek: 3, sessionMinutes: 45, goal: nil, split: nil))
    XCTAssertEqual(
      adjustment.digestComponents,
      ["adjustPlan", "days:3", "minutes:45", "goal:-", "split:-"])
  }
}
