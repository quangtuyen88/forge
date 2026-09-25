import ForgeCore
import Foundation
import SwiftData
import XCTest

@testable import Forge

/// `currentWeek(sessions:)` = completed ÷ daysPerWeek + 1, pinned against the goal doc's fixtures.
@MainActor
final class PlanningStageTests: XCTestCase {

  // Common setup: a Gregorian calendar in Asia/Tokyo; every fixture date is built in Tokyo.
  private static let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()

  private static func tokyoDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 18) -> Date {
    tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  /// F01 attendance: Full A completed Mon 2026-09-21, plus five August workouts (3–17).
  private func insertF01Sessions(into context: ModelContext) -> [WorkoutSession] {
    let dates = [
      Self.tokyoDate(2026, 8, 3), Self.tokyoDate(2026, 8, 6), Self.tokyoDate(2026, 8, 10),
      Self.tokyoDate(2026, 8, 13), Self.tokyoDate(2026, 8, 17), Self.tokyoDate(2026, 9, 21),
    ]
    let sessions = dates.enumerated().map { index, date in
      WorkoutSession(
        date: date, dayName: index == dates.count - 1 ? "Full A" : "Import", week: 1,
        completed: true)
    }
    sessions.forEach(context.insert)
    return sessions
  }

  @discardableResult
  private func insertProfile(
    into context: ModelContext, daysPerWeek: Int, mesoStart: Date
  ) -> UserProfile {
    let profile = UserProfile(
      goal: .hypertrophy,
      experience: .intermediate,
      daysPerWeek: daysPerWeek,
      sessionMinutes: 60,
      equipment: [.barbell, .dumbbell],
      injuryFlags: [],
      recoveryReduced: false,
      bodyweightKg: 80,
      usesLb: false,
      startingLoads: [:])
    profile.mesoStart = mesoStart
    context.insert(profile)
    return profile
  }

  // MARK: F01

  func testF01CurrentWeekIsOneImportsBeforeMesoStartDoNotCount() throws {
    // F01: August imports predate mesoStart; 1 ÷ 3 + 1 = week 1, as the goal doc expects.
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = insertProfile(
      into: context, daysPerWeek: 3, mesoStart: Self.tokyoDate(2026, 9, 21, hour: 0))
    let sessions = insertF01Sessions(into: context)
    try context.save()

    XCTAssertEqual(profile.currentWeek(sessions: sessions), 1)
  }

  // MARK: doubling up

  func testDoublingUpSixSessionsInTwoDaysReadsWeekThree() throws {
    // Six completed sessions in two days: 6 ÷ 3 + 1 = week 3.
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = insertProfile(
      into: context, daysPerWeek: 3, mesoStart: Self.tokyoDate(2026, 9, 21, hour: 0))
    let dates = [
      Self.tokyoDate(2026, 9, 21, hour: 10), Self.tokyoDate(2026, 9, 21, hour: 14),
      Self.tokyoDate(2026, 9, 21), Self.tokyoDate(2026, 9, 22, hour: 10),
      Self.tokyoDate(2026, 9, 22, hour: 14), Self.tokyoDate(2026, 9, 22),
    ]
    let sessions = dates.map { date in
      WorkoutSession(date: date, dayName: "Doubled", week: 1, completed: true)
    }
    sessions.forEach(context.insert)
    try context.save()

    XCTAssertEqual(profile.currentWeek(sessions: sessions), 3)
  }

  func testRestOfWeekNamesTomorrowAsARestDay() {
    let calendar = TrainingMetrics.reportingCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    let week = TrainingMetrics.reportingWeek(
      containing: Self.tokyoDate(2026, 9, 23, hour: 10), calendar: calendar)
    let sessions: [(date: Date, name: String, state: WeekPlanDayState)] = [
      (Self.tokyoDate(2026, 9, 21), "Full A", .missed),
      (Self.tokyoDate(2026, 9, 23, hour: 10), "Full B", .remaining),
      (Self.tokyoDate(2026, 9, 25), "Full C", .remaining),
    ]
    XCTAssertEqual(
      CoachAPI.restOfWeek(
        today: Self.tokyoDate(2026, 9, 23, hour: 10), week: week, calendar: calendar,
        planCalendar: calendar, sessions: sessions),
      "Wednesday 2026-09-23 (today): Full B; Thursday 2026-09-24 (tomorrow): rest day, nothing planned; Friday 2026-09-25: Full C; Saturday 2026-09-26: rest day, nothing planned; Sunday 2026-09-27: rest day, nothing planned")
  }

  func testRestOfWeekOnSundayPointsTomorrowToNextWeek() {
    let calendar = TrainingMetrics.reportingCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    let week = TrainingMetrics.reportingWeek(
      containing: Self.tokyoDate(2026, 9, 23, hour: 10), calendar: calendar)
    let sessions: [(date: Date, name: String, state: WeekPlanDayState)] = [
      (Self.tokyoDate(2026, 9, 21), "Full A", .missed),
      (Self.tokyoDate(2026, 9, 23, hour: 10), "Full B", .remaining),
      (Self.tokyoDate(2026, 9, 25), "Full C", .completed),
    ]
    XCTAssertEqual(
      CoachAPI.restOfWeek(
        today: Self.tokyoDate(2026, 9, 27, hour: 20), week: week, calendar: calendar,
        planCalendar: calendar, sessions: sessions),
      "Sunday 2026-09-27 (today): rest day, nothing planned; Monday 2026-09-28 (tomorrow): next week, not in this week's plan")
  }

  func testRestOfWeekKeepsPlanDaysWhenTheDeviceZoneDiffersFromThePlanZone() {
    // Plan days are Tokyo midnights read from Taipei: the plan's calendar keeps their days.
    let planCalendar = TrainingMetrics.reportingCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    let calendar = TrainingMetrics.reportingCalendar(timeZone: TimeZone(identifier: "Asia/Taipei")!)
    let sessions: [(date: Date, name: String, state: WeekPlanDayState)] = [
      (Self.tokyoDate(2026, 9, 21, hour: 0), "Full A", .missed),
      (Self.tokyoDate(2026, 9, 23, hour: 0), "Full B", .remaining),
      (Self.tokyoDate(2026, 9, 25, hour: 0), "Full C", .remaining),
    ]
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10))!
    let week = TrainingMetrics.reportingWeek(containing: today, calendar: calendar)
    XCTAssertEqual(
      CoachAPI.restOfWeek(
        today: today, week: week, calendar: calendar, planCalendar: planCalendar,
        sessions: sessions),
      "Wednesday 2026-09-23 (today): Full B; Thursday 2026-09-24 (tomorrow): rest day, nothing planned; Friday 2026-09-25: Full C; Saturday 2026-09-26: rest day, nothing planned; Sunday 2026-09-27: rest day, nothing planned")
  }

  // MARK: plan changes

  func testChangingDaysPerWeekKeepsTheProgramWeek() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let mesoStart = Self.tokyoDate(2026, 9, 7, hour: 0)
    let sessions = (0..<6).map { offset in
      WorkoutSession(
        date: Self.tokyoDate(2026, 9, 7 + offset), dayName: "Full", week: 1, completed: true)
    }
    sessions.forEach(context.insert)
    try context.save()

    let four = insertProfile(into: context, daysPerWeek: 4, mesoStart: mesoStart)
    XCTAssertEqual(four.currentWeek(sessions: sessions), 2)
    four.setDaysPerWeek(3, sessions: sessions)
    XCTAssertEqual(four.currentWeek(sessions: sessions), 2, "an edit must not move the week")
    four.setDaysPerWeek(4, sessions: sessions)
    XCTAssertEqual(four.currentWeek(sessions: sessions), 2, "changing back must not move the week")

    let three = insertProfile(into: context, daysPerWeek: 3, mesoStart: mesoStart)
    XCTAssertEqual(three.currentWeek(sessions: sessions), 3)
    three.setDaysPerWeek(4, sessions: sessions)
    XCTAssertEqual(three.currentWeek(sessions: sessions), 3, "an edit must not move the week")
  }

  func testContextPacketDerivesSessionsThisBlockAndRecentPlanChanges() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = insertProfile(
      into: context, daysPerWeek: 3, mesoStart: .now.addingTimeInterval(-14 * 86400))
    let session = WorkoutSession(date: .now, dayName: "Full A", week: 1, completed: true)
    context.insert(session)
    try context.save()

    let yesterday = DecisionRecord(
      id: "plan-settings-yesterday",
      date: .now.addingTimeInterval(-86400),
      type: "plan_settings",
      exerciseID: nil,
      muscle: nil,
      fromValue: 4,
      toValue: 3,
      reasonCodes: [DecisionSignal.userOverride.code],
      evidence: ["days a week 4 → 3"],
      humanSummary: "Plan settings changed.")
    let twentyDaysAgo = DecisionRecord(
      id: "plan-settings-old",
      date: .now.addingTimeInterval(-20 * 86400),
      type: "plan_settings",
      exerciseID: nil,
      muscle: nil,
      fromValue: nil,
      toValue: nil,
      reasonCodes: [DecisionSignal.userOverride.code],
      evidence: ["goal Hypertrophy → Strength"],
      humanSummary: "Plan settings changed.")

    let packet = CoachAPI.contextPacket(
      profile: profile, sessions: [session], checkIns: [],
      decisions: [yesterday, twentyDaysAgo], bodyweightKg: nil, usesLb: false, notes: [])

    let rendered = packet.rendered()
    XCTAssertTrue(rendered.contains("sessions_this_block: 1 completed since"))
    XCTAssertTrue(rendered.contains("recent_plan_changes: 1 in the last 14 days\n"),
      "only the count of the window's changes, the older one not counted")
    XCTAssertFalse(rendered.contains("days a week 4 → 3"),
      "user_override rows stay on device: their values are never restated in the context")
    XCTAssertFalse(rendered.contains("goal Hypertrophy → Strength"))
    XCTAssertFalse(packet.decisions.contains { $0.type == "plan_settings" },
      "user_override rows never leave the device as decisions")
  }

  func testApplyPlanAdjustmentMatchesSettingsAndKeepsCompletedDays() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let monday = Self.tokyoDate(2026, 9, 21, hour: 0)
    let profile = insertProfile(into: context, daysPerWeek: 4, mesoStart: monday)
    profile.nextDayIndex = 2
    let upper = WorkoutSession(
      date: Self.tokyoDate(2026, 9, 21), dayName: "Upper", week: 1, completed: true)
    let lower = WorkoutSession(
      date: Self.tokyoDate(2026, 9, 22), dayName: "Lower", week: 1, completed: true)
    context.insert(upper)
    context.insert(lower)
    let sessions = [upper, lower]
    try context.save()

    var plan = WeekPlanBuilder.plan(
      programWeek: 1,
      profile: profile.profileInput,
      constraints: profile.trainingConstraints,
      startingOn: monday,
      enrollmentDate: monday,
      calendar: Self.tokyo)
    let layout = [
      monday,
      Self.tokyoDate(2026, 9, 22, hour: 0),
      Self.tokyoDate(2026, 9, 24, hour: 0),
      Self.tokyoDate(2026, 9, 26, hour: 0),
    ]
    plan.days = zip(plan.days, layout).map { built, date in
      var day = built
      let startOfDay = Self.tokyo.startOfDay(for: date)
      day.date = startOfDay
      day.id = "\(day.plannedSessionID ?? day.id)@\(Int(startOfDay.timeIntervalSince1970))"
      return day
    }
    plan.complete(
      dayID: plan.days[0].id, sessionID: WeekPlanCompletionPolicy.sessionReference(upper))
    plan.complete(
      dayID: plan.days[1].id, sessionID: WeekPlanCompletionPolicy.sessionReference(lower))
    profile.weekPlan = plan
    let originalMonday = plan.days[0]
    let originalTuesday = plan.days[1]
    let now = Self.tokyoDate(2026, 9, 23, hour: 10)

    let adjustment = try XCTUnwrap(
      PlanAdjustment(daysPerWeek: 3, sessionMinutes: 45, goal: nil, split: nil))
    let preview = try XCTUnwrap(
      profile.previewWeekPlan(adjustment, sessions: sessions, now: now))
    XCTAssertNotNil(preview)
    XCTAssertEqual(profile.daysPerWeek, 4, "a preview must not change the profile")
    XCTAssertEqual(profile.sessionMinutes, 60)
    XCTAssertEqual(profile.weekPlan, plan, "a preview must not change the week plan")

    profile.applyPlanAdjustment(adjustment, sessions: sessions, now: now)
    XCTAssertEqual(profile.daysPerWeek, 3)
    XCTAssertEqual(profile.sessionMinutes, 45)
    XCTAssertEqual(profile.currentWeek(sessions: sessions), 1, "the rebase keeps the week")
    let revised = try XCTUnwrap(profile.weekPlan)
    XCTAssertEqual(revised.days.first { $0.id == originalMonday.id }, originalMonday)
    XCTAssertEqual(revised.days.first { $0.id == originalTuesday.id }, originalTuesday)
    let program = Program.week(
      profile.currentWeek(sessions: sessions), profile: profile.profileInput)
    let owed = try XCTUnwrap(WeekPlanTodayStatus(plan: revised, now: now, base: Self.tokyo).owed)
    XCTAssertTrue(program.map(\.id).contains(owed.plannedSessionID ?? ""))
    XCTAssertEqual(owed.timeBudgetMinutes, 45)
  }
}
