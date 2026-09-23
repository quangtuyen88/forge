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

  // MARK: F02

  func testF02ProgramStartedSep7StillReadsWeekOne() throws {
    // F02: app counts completed ÷ daysPerWeek + 1 = 1; the goal's calendar fixture expects 3.
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = insertProfile(
      into: context, daysPerWeek: 3, mesoStart: Self.tokyoDate(2026, 9, 7, hour: 0))
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

  // MARK: F13

  func testF13ClockAdvanceDoesNotChangeTheStageValue() throws {
    // F13: the fixture expects 2 on Sep 28; with no clock and no new sessions it stays 1.
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = insertProfile(
      into: context, daysPerWeek: 3, mesoStart: Self.tokyoDate(2026, 9, 21, hour: 0))
    let sessions = insertF01Sessions(into: context)
    try context.save()

    XCTAssertEqual(profile.currentWeek(sessions: sessions), 1)
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
}
