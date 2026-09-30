import ForgeCore
import XCTest

@testable import Forge

/// Failure modes pinned by this suite:
/// 1. Day options give the wrong weekly sets (ids "2"–"6" with the sets Program.week builds).
/// 2. The "Now" tag lands on the wrong day option (only the current one is current).
/// 3. The lifts-a-day note is missing or spurious (only when the count differs from today's plan).
/// 4. Minute options give the wrong sets or lift counts ("4"/"6 lifts a session", "Up to …").
/// 5. Goal options miss a case, the current tag or a detail.
/// 6. A split that repeats reads as a list twice over instead of the ", twice" form.
/// 7. Delta text formats +16, −8 and 0 wrongly.
/// 8. planDetailsValue does not resolve .auto to the split it builds.
/// 9. goalPhrase does not return three distinct non-empty phrases.
/// 10. smallestJump is not twice the lightest owned plate (or misses nil).
/// 11. missingFinerPlate names the wrong finer plate.
/// 12. barChoices drop the current bar or break descending order.
/// 13. sizeRank ranks plates outside the catalogue wrongly.
/// 14. Reminder slots exist with no plan, or a plan with no days.
/// 15. Slots miss plan days, weekday repeats, ordering, details or the 14-day horizon.
/// 16. A slot fires today after its reminder time already passed.
/// 17. A completed day keeps a slot, or loses its weekday repeat.
/// 18. A skipped day still defines a training weekday.
/// 19. A moved day reminds on its old date instead of the moved-to date.
/// 20. A stale plan yields slots in the past instead of the future weekday pattern.
/// 21. limit does not cap the slot list.
/// 22. Reminder titles/bodies drop the session name, counts or fallback text.
/// 23. exerciseSwapDetails disagrees with the legacy exerciseSwaps strings.
/// 24. mmss formats minutes:seconds wrongly.
/// 25. languageName falls back wrongly.
/// 26. gymName misses the matching preset or "Custom".
@MainActor
final class SettingsModelTests: XCTestCase {
  private let previewWeek = 4

  private var previewInput: ProfileInput {
    ProfileInput(
      goal: .hypertrophy,
      experience: .intermediate,
      daysPerWeek: 3,
      sessionLength: .m60,
      equipment: GymPreset.commercial.equipment,
      injuryFlags: [.shoulder],
      recoveryReduced: false,
      split: .auto)
  }

  // MARK: Plan previews

  func testDayOptionsWeeklySetsMatchProgramWeek() {
    let options = PlanPreview.dayOptions(input: previewInput, week: previewWeek)
    XCTAssertEqual(options.map(\.id), ["2", "3", "4", "5", "6"])
    XCTAssertEqual(options.map(\.weeklySets), [48, 72, 88, 116, 121])
  }

  func testOnlyTheCurrentDayOptionIsMarkedNow() {
    let options = PlanPreview.dayOptions(input: previewInput, week: previewWeek)
    XCTAssertEqual(options.filter(\.isCurrent).map(\.id), ["3"])
  }

  func testLiftsADayNoteAppearsOnlyWhenTheCountChanges() {
    let options = PlanPreview.dayOptions(input: previewInput, week: previewWeek)
    let details = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.detail) })
    XCTAssertTrue(details["6"]?.contains(" · ") ?? false)
    for id in ["2", "4", "5"] {
      XCTAssertFalse(details[id]?.contains(" · ") ?? true, "spurious note on \(id)")
    }
  }

  func testMinuteOptionsSetsAndLiftCounts() {
    let options = PlanPreview.minuteOptions(input: previewInput, week: previewWeek)
    XCTAssertEqual(options.map(\.id), ["45", "60", "90"])
    XCTAssertEqual(options.map(\.weeklySets), [54, 72, 107])
    XCTAssertTrue(options[0].detail.contains("4"))
    XCTAssertTrue(options[1].detail.contains("6"))
    XCTAssertEqual(
      options[2].detail, String(localized: "Up to \(8) lifts a session", bundle: L10n.bundle))
  }

  func testGoalOptionsCoverEveryGoalWithDetail() {
    let options = PlanPreview.goalOptions(input: previewInput, week: previewWeek)
    XCTAssertEqual(options.map(\.id), Goal.allCases.map(\.rawValue))
    XCTAssertEqual(options.filter(\.isCurrent).map(\.id), ["hypertrophy"])
    XCTAssertTrue(options.allSatisfy { !$0.detail.isEmpty })
  }

  func testSplitDescriptionCollapsesARepeatingSplit() {
    let twice = PlanPreview.splitDescription(days: 4, style: .auto)
    XCTAssertTrue(twice.hasSuffix(String(localized: ", twice", bundle: L10n.bundle)))
    XCTAssertEqual(twice.components(separatedBy: localizedDayName("Upper")).count - 1, 1)
    XCTAssertEqual(twice.components(separatedBy: localizedDayName("Lower")).count - 1, 1)

    let full = PlanPreview.splitDescription(days: 4, style: .fullBody)
    XCTAssertEqual(full.components(separatedBy: localizedDayName("Full A")).count - 1, 1)
    XCTAssertFalse(full.hasSuffix(String(localized: ", twice", bundle: L10n.bundle)))
  }

  func testDeltaText() {
    XCTAssertEqual(PlanPreview.deltaText(16), "+16")
    XCTAssertEqual(PlanPreview.deltaText(-8), "\u{2212}8")
    XCTAssertEqual(PlanPreview.deltaText(0), "")
  }

  func testPlanDetailsValueResolvesAutoSplit() {
    XCTAssertEqual(
      PlanPreview.planDetailsValue(experience: .intermediate, split: .auto, days: 3),
      "\(Experience.intermediate.name) · \(SplitStyle.fullBody.name)")
    XCTAssertEqual(
      PlanPreview.planDetailsValue(experience: .intermediate, split: .upperLower, days: 3),
      "\(Experience.intermediate.name) · \(SplitStyle.upperLower.name)")
  }

  func testGoalPhraseGivesThreeDistinctPhrases() {
    let phrases = Goal.allCases.map(PlanPreview.goalPhrase)
    XCTAssertEqual(Set(phrases).count, 3)
    XCTAssertTrue(phrases.allSatisfy { !$0.isEmpty })
  }

  // MARK: Plates

  func testSmallestJumpIsTwiceTheLightestOwnedPlate() {
    XCTAssertEqual(PlateMath.smallestJump(owned: [25, 20, 15, 10, 5, 2.5, 1.25]), 2.5)
    XCTAssertNil(PlateMath.smallestJump(owned: []))
  }

  func testMissingFinerPlate() {
    XCTAssertEqual(
      PlateMath.missingFinerPlate(owned: [25, 20, 15, 10, 5, 2.5, 1.25], usesLb: false), 0.5)
    XCTAssertNil(
      PlateMath.missingFinerPlate(owned: [25, 20, 15, 10, 5, 2.5, 1.25, 0.5], usesLb: false))
    XCTAssertNil(PlateMath.missingFinerPlate(owned: [45, 35, 25, 10, 5, 2.5, 1.25], usesLb: true))
    XCTAssertNil(PlateMath.missingFinerPlate(owned: [], usesLb: false))
  }

  func testBarChoices() {
    XCTAssertEqual(PlateMath.barChoices(usesLb: false, current: 20), [20, 15, 10])
    XCTAssertEqual(PlateMath.barChoices(usesLb: false, current: 17.5), [20, 17.5, 15, 10])
    XCTAssertEqual(PlateMath.barChoices(usesLb: true, current: 45), [45, 35, 25])
  }

  func testSizeRank() {
    XCTAssertEqual(PlateMath.sizeRank(25, usesLb: false), 0)
    XCTAssertEqual(PlateMath.sizeRank(0.5, usesLb: false), 7)
    XCTAssertEqual(PlateMath.sizeRank(45, usesLb: true), 0)
    XCTAssertEqual(PlateMath.sizeRank(1.25, usesLb: true), 6)
  }

  // MARK: Reminders

  private var zone: TimeZone { TimeZone(identifier: "Asia/Ho_Chi_Minh")! }

  private var cal: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private let deadlifts = [
    "deadlift", "romanian_deadlift", "sumo_deadlift", "trap_bar_deadlift", "deficit_deadlift",
    "paused_deadlift",
  ]

  /// Mon 2026-09-28 (completed Full A), Wed 30 (Full B, six deadlifts, 60 min), Fri Oct 2 (Full C).
  private func plan(
    wednesdayState: WeekPlanDayState = .planned,
    wednesdayMovedTo: Date? = nil,
    fridayState: WeekPlanDayState = .planned,
    weeksAgo: Int = 0
  ) -> WeekPlan {
    let monday = cal.date(byAdding: .day, value: -7 * weeksAgo, to: at(2026, 9, 28))!
    let days = [
      WeekPlanDay(id: "mon", date: monday, sessionName: "Full A", state: .completed),
      WeekPlanDay(
        id: "wed", date: cal.date(byAdding: .day, value: 2, to: monday)!, sessionName: "Full B",
        exerciseIDs: deadlifts, plannedSetCount: 6, timeBudgetMinutes: 60,
        state: wednesdayState, movedToDate: wednesdayMovedTo),
      WeekPlanDay(
        id: "fri", date: cal.date(byAdding: .day, value: 4, to: monday)!, sessionName: "Full C",
        state: fridayState),
    ]
    return WeekPlan(
      id: "test", weekStart: monday, timeZoneIdentifier: zone.identifier, enrollmentDate: monday,
      days: days)
  }

  func testSlotsNeedAPlanWithDays() {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    XCTAssertNil(ReminderSchedule.slots(plan: nil, hour: 18, minute: 30, now: now, calendar: cal))
    let empty = WeekPlan(
      id: "empty", weekStart: at(2026, 9, 28), timeZoneIdentifier: zone.identifier,
      enrollmentDate: at(2026, 9, 28), days: [])
    XCTAssertNil(
      ReminderSchedule.slots(plan: empty, hour: 18, minute: 30, now: now, calendar: cal))
  }

  func testSlotsListPlanDaysThenWeekdayPattern() throws {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(plan: plan(), hour: 18, minute: 30, now: now, calendar: cal))
    XCTAssertEqual(
      slots.map(\.date),
      [
        at(2026, 9, 30, hour: 18, minute: 30),
        at(2026, 10, 2, hour: 18, minute: 30),
        at(2026, 10, 5, hour: 18, minute: 30),
        at(2026, 10, 7, hour: 18, minute: 30),
        at(2026, 10, 9, hour: 18, minute: 30),
        at(2026, 10, 12, hour: 18, minute: 30),
      ])
    XCTAssertEqual(slots.first?.sessionName, localizedDayName("Full B"))
    XCTAssertEqual(slots.first?.lifts, 6)
    XCTAssertEqual(slots.first?.minutes, 60)
    XCTAssertEqual(slots.first?.firstLiftName, ExerciseDB.find("deadlift")?.localizedName)
    XCTAssertEqual(slots[1].sessionName, localizedDayName("Full C"))
    XCTAssertTrue(slots[2...].allSatisfy { $0.sessionName == nil })
  }

  func testSlotsDropTodayOnceTheTimePassed() throws {
    let now = at(2026, 9, 30, hour: 19)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(plan: plan(), hour: 18, minute: 30, now: now, calendar: cal))
    XCTAssertEqual(slots.first?.date, at(2026, 10, 2, hour: 18, minute: 30))
    XCTAssertFalse(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 9, 30)) })
  }

  func testCompletedDayHasNoSlotButKeepsTheWeekday() throws {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(
        plan: plan(wednesdayState: .completed), hour: 18, minute: 30, now: now, calendar: cal))
    XCTAssertFalse(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 9, 30)) })
    XCTAssertTrue(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 10, 7)) })
  }

  func testSkippedDayDefinesNoWeekday() throws {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(
        plan: plan(fridayState: .skipped), hour: 18, minute: 30, now: now, calendar: cal))
    XCTAssertFalse(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 10, 2)) })
    XCTAssertFalse(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 10, 9)) })
  }

  func testMovedDayShiftsToItsNewDate() throws {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(
        plan: plan(wednesdayState: .moved, wednesdayMovedTo: at(2026, 10, 1)), hour: 18,
        minute: 30, now: now,
        calendar: cal))
    XCTAssertTrue(slots.contains { $0.date == at(2026, 10, 1, hour: 18, minute: 30) })
    XCTAssertFalse(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 9, 30)) })
    XCTAssertTrue(slots.contains { cal.isDate($0.date, inSameDayAs: at(2026, 10, 8)) })
  }

  func testStalePlanOnlyProducesFuturePatternSlots() throws {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    let slots = try XCTUnwrap(
      ReminderSchedule.slots(
        plan: plan(weeksAgo: 3), hour: 18, minute: 30, now: now, calendar: cal))
    XCTAssertTrue(slots.allSatisfy { $0.date > now })
    XCTAssertTrue(slots.allSatisfy { [2, 4, 6].contains(cal.component(.weekday, from: $0.date)) })
    XCTAssertEqual(slots.first?.date, at(2026, 9, 30, hour: 18, minute: 30))
    XCTAssertNil(slots.first?.sessionName)
  }

  func testLimitCapsSlots() {
    let now = at(2026, 9, 30, hour: 9, minute: 41)
    XCTAssertEqual(
      ReminderSchedule.slots(plan: plan(), hour: 18, minute: 30, now: now, calendar: cal, limit: 3)?
        .count,
      3)
  }

  func testReminderTitleAndBody() {
    let withSession = ReminderSlot(
      date: at(2026, 9, 30, hour: 18, minute: 30), sessionName: "Full B", lifts: 6, minutes: 60,
      firstLiftName: "Deadlift")
    XCTAssertTrue(ReminderSchedule.title(for: withSession).contains("Full B"))
    let body = ReminderSchedule.body(for: withSession)
    XCTAssertTrue(body.contains("6"))
    XCTAssertTrue(body.contains("60"))
    XCTAssertTrue(body.contains("Deadlift"))

    let plain = ReminderSlot(
      date: at(2026, 10, 5, hour: 18, minute: 30), sessionName: nil, lifts: 0, minutes: 0,
      firstLiftName: nil)
    XCTAssertEqual(
      ReminderSchedule.title(for: plain), String(localized: "Time to train", bundle: L10n.bundle))
    XCTAssertEqual(
      ReminderSchedule.body(for: plain),
      String(localized: "Open Regulift for today's session.", bundle: L10n.bundle))
  }

  // MARK: Swaps

  func testExerciseSwapDetailsMapToTheLegacyStrings() {
    var home = previewInput
    home.equipment = GymPreset.home.equipment
    let details = Personalization.exerciseSwapDetails(before: previewInput, after: home)
    XCTAssertFalse(details.isEmpty)
    XCTAssertTrue(details.allSatisfy { !$0.dayName.isEmpty })
    func legacy(_ swap: ExerciseSwap) -> String? {
      switch (swap.fromName, swap.toName) {
      case let (from?, to?): return "\(from) → \(to)"
      case let (from?, nil): return "\u{2212} \(from)"
      case let (nil, to?): return "+ \(to)"
      default: return nil
      }
    }
    XCTAssertEqual(
      details.compactMap(legacy),
      Personalization.exerciseSwaps(before: previewInput, after: home))
  }

  // MARK: Formatting

  func testMmss() {
    XCTAssertEqual(SettingsFormat.mmss(180), "3:00")
    XCTAssertEqual(SettingsFormat.mmss(90), "1:30")
    XCTAssertEqual(SettingsFormat.mmss(65), "1:05")
  }

  func testLanguageName() {
    XCTAssertEqual(SettingsFormat.languageName("ja"), "日本語")
    XCTAssertEqual(SettingsFormat.languageName("xx"), "English")
  }

  func testGymName() {
    XCTAssertEqual(
      SettingsFormat.gymName(equipment: GymPreset.home.equipment.map(\.rawValue)),
      GymPreset.home.name)
    XCTAssertEqual(
      SettingsFormat.gymName(equipment: ["cable"]),
      String(localized: "Custom", bundle: L10n.bundle))
  }
}
