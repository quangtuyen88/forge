import Foundation
import ForgeCore
import SwiftData
import XCTest

@testable import Forge

/// The pure model the timeline's program-change cards read: scheduled proposals from the
/// engine plus committed ledger entries, and the sheet detail both explain from.
@MainActor
final class ProgramChangesTests: XCTestCase {

  private var store: ModelContainer!
  private var context: ModelContext!

  override func setUpWithError() throws {
    try super.setUpWithError()
    store = try JourneyTestStore.inMemory()
    context = store.mainContext
  }

  override func tearDown() {
    context = nil
    store = nil
    super.tearDown()
  }

  /// One "Full B" session whose first planned exercise hit the top of its rep range — the
  /// canonical "load goes up next time" fixture. Effort reporting, the sets' recorded target
  /// and the logged reps are parameterized so the unreported-effort and part-way paths stay
  /// reachable.
  private func makeProgressedFixture(
    now: Date? = nil, effortReported: Bool = true,
    targetRPEOffset: Double = 0, reps: [Int]? = nil
  ) throws
    -> (profile: UserProfile, session: WorkoutSession, planned: PlannedExercise, lastKg: Double, now: Date)
  {
    let now = now ?? JourneyTestStore.date(2025, 6, 21)
    let profile = try JourneyTestStore.profile(in: context)
    profile.split = SplitStyle.fullBody.rawValue
    let week = profile.currentWeek(sessions: [])
    let day = try XCTUnwrap(
      Program.week(week, profile: profile.profileInput).first { $0.name == "Full B" },
      "the generated program must contain a Full B day")
    let planned = try XCTUnwrap(day.exercises.first)

    let sessionDate = JourneyTestStore.date(2025, 6, 20)
    let session = WorkoutSession(date: sessionDate, dayName: "Full B", week: week, completed: true)
    context.insert(session)
    let lastKg = 40.0
    for index in 0..<3 {
      let set = LoggedSet(
        exerciseID: planned.exercise.id,
        setIndex: index,
        weightKg: lastKg,
        reps: reps?[index] ?? planned.repRange.upperBound,
        rpe: planned.targetRPE - 1,
        targetRPE: planned.targetRPE + targetRPEOffset,
        loggedAt: sessionDate.addingTimeInterval(Double(index) * 180),
        effortReported: effortReported)
      set.session = session
      context.insert(set)
    }
    try context.save()
    return (profile, session, planned, lastKg, now)
  }

  func testTopOfRangeSessionSchedulesAnIncrease() throws {
    let fixture = try makeProgressedFixture()
    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)

    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    XCTAssertEqual(group.state, .scheduled)
    XCTAssertEqual(group.anchorDate, fixture.session.date)
    XCTAssertEqual(group.id, "scheduled|Full B|\(Int(fixture.session.date.timeIntervalSince1970))")

    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    guard case .increase(let fromKg, let toKg) = row.change else {
      return XCTFail("expected an increase, got \(row.change)")
    }
    XCTAssertEqual(fromKg, fixture.lastKg)
    XCTAssertGreaterThan(toKg, fixture.lastKg)
    XCTAssertTrue(row.reason.hasPrefix("All "), "reason was \(row.reason)")
    XCTAssertNil(row.sourceID)
    XCTAssertFalse(row.kept)
  }

  func testLaterSessionOfTheSameDayRemovesTheScheduledGroup() throws {
    let fixture = try makeProgressedFixture()
    let later = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 21, hour: 18), dayName: "Full B", week: 1, completed: false)
    context.insert(later)
    try context.save()

    let groups = ProgramChanges.scheduled(
      sessions: [fixture.session, later], profile: fixture.profile, now: fixture.now)
    XCTAssertFalse(
      groups.contains { $0.dayName == "Full B" },
      "an open later session means the change is already being applied")
  }

  func testKeepOriginalOverrideHoldsTheLoadAndDisablesTheKeepButton() throws {
    let fixture = try makeProgressedFixture()
    DecisionOverrides.set(.keepOriginal, for: fixture.planned.exercise.id)
    defer { DecisionOverrides.set(nil, for: fixture.planned.exercise.id) }

    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    guard case .unchanged(let kg) = row.change else {
      return XCTFail("expected the kept load to hold, got \(row.change)")
    }
    XCTAssertEqual(kg, fixture.lastKg)
    XCTAssertTrue(row.kept)
    XCTAssertTrue(row.reason.hasPrefix("Plan proposed "), "reason was \(row.reason)")

    let detail = ProgramChanges.detail(
      for: row, in: group, sessions: [fixture.session], entries: [], profile: fixture.profile)
    XCTAssertFalse(detail.canKeepOriginal)
    XCTAssertEqual(detail.originalKg, fixture.lastKg)
    // The engine's pre-override target survives the keep, so the undo button can name it.
    let proposedKg = try XCTUnwrap(detail.proposedKg)
    XCTAssertGreaterThan(proposedKg, fixture.lastKg)
    XCTAssertTrue(detail.evidence.contains { $0.hasPrefix("All ") }, "evidence was \(detail.evidence)")
    XCTAssertFalse(detail.evidence.contains { $0.hasPrefix("You chose to keep") })
  }

  /// `.repsAtTopOfRange` comes from the last set only; with 9, 9, 10 in an 8–10 range the
  /// "All N sets reached…" claim must not appear, even though the engine still increases.
  func testNotEverySetAtTheTopNeverClaimsAllSetsReachedIt() throws {
    let fixture = try makeProgressedFixture(reps: [9, 9, 10])
    fixture.profile.repRangeOverrides[fixture.planned.exercise.id] = "8-10"
    defer { fixture.profile.repRangeOverrides[fixture.planned.exercise.id] = nil }

    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    guard case .increase = row.change else {
      return XCTFail("expected an increase, got \(row.change)")
    }
    XCTAssertFalse(row.reason.hasPrefix("All "), "reason was \(row.reason)")

    let detail = ProgramChanges.detail(
      for: row, in: group, sessions: [fixture.session], entries: [], profile: fixture.profile)
    XCTAssertFalse(detail.evidence.first?.hasPrefix("All ") == true, "evidence was \(detail.evidence)")
  }

  func testExerciseWithoutHistoryIsAStartingRow() throws {
    let fixture = try makeProgressedFixture()
    let fresh = try XCTUnwrap(
      Program.week(
        fixture.profile.currentWeek(sessions: [fixture.session]),
        profile: fixture.profile.profileInput
      ).first { $0.name == "Full B" }?.exercises.last)
    XCTAssertNotEqual(fresh.exercise.id, fixture.planned.exercise.id)

    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fresh.exercise.id })
    guard case .starting = row.change else {
      return XCTFail("expected a starting row, got \(row.change)")
    }
    XCTAssertEqual(row.reason, "First session of this exercise")
  }

  func testAppliedEntriesGroupByFingerprint() throws {
    let profile = try JourneyTestStore.profile(in: context)
    func entry(
      _ id: String, exerciseID: String, from: Double?, to: Double?, codes: [String]
    ) -> DecisionLogEntry {
      DecisionLogEntry(
        DecisionRecord(
          id: id, date: JourneyTestStore.date(2025, 6, 20, hour: 9), type: "load_change",
          exerciseID: exerciseID, muscle: nil, fromValue: from, toValue: to,
          reasonCodes: codes, evidence: ["82.5 kg × 8"], humanSummary: "Load changed"),
        operationFingerprint: "fp-1")
    }
    let increase = entry("a", exerciseID: "barbell_bench", from: 80, to: 82.5, codes: ["reps_at_top_of_range"])
    let unchanged = entry("b", exerciseID: "barbell_row", from: 60, to: 60, codes: ["rpe_above_target"])
    let starting = entry("c", exerciseID: "leg_press", from: nil, to: 40, codes: ["first_exposure"])

    // A session that did start nearby still belongs to the fingerprinted group only.
    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 20, hour: 10), dayName: "Full B", week: 1,
      completed: true)
    context.insert(session)
    try context.save()

    let groups = ProgramChanges.applied(entries: [increase, unchanged, starting], sessions: [session], profile: profile)
    XCTAssertEqual(groups.count, 1)
    let group = try XCTUnwrap(groups.first)
    XCTAssertEqual(group.state, .applied)
    XCTAssertEqual(group.rows.count, 3)

    let increaseRow = try XCTUnwrap(group.rows.first { $0.exerciseID == "barbell_bench" })
    XCTAssertEqual(increaseRow.change, .increase(fromKg: 80, toKg: 82.5))
    XCTAssertEqual(increaseRow.sourceID, increase.journeyID)
    XCTAssertEqual(group.dayName, "Full B")
    XCTAssertEqual(group.effectiveDate, session.date)
    let unchangedRow = try XCTUnwrap(group.rows.first { $0.exerciseID == "barbell_row" })
    XCTAssertEqual(unchangedRow.change, .unchanged(kg: 60))
    XCTAssertEqual(unchangedRow.sourceID, unchanged.journeyID)
    let startingRow = try XCTUnwrap(group.rows.first { $0.exerciseID == "leg_press" })
    XCTAssertEqual(startingRow.change, .starting(kg: 40))
    XCTAssertEqual(startingRow.sourceID, starting.journeyID)

    let detail = ProgramChanges.detail(
      for: increaseRow, in: group, sessions: [session], entries: [increase, unchanged, starting],
      profile: profile)
    XCTAssertEqual(
      detail.steps.map(\.title),
      [
        String(localized: "Proposed by your plan", bundle: L10n.bundle),
        String(localized: "Applied when \(localizedDayName("Full B")) started", bundle: L10n.bundle),
      ])
    XCTAssertTrue(detail.steps.allSatisfy(\.done))
    XCTAssertNil(detail.proposedKg)

    let otherFingerprint = DecisionLogEntry(
      DecisionRecord(
        id: "d", date: JourneyTestStore.date(2025, 6, 18, hour: 9), type: "load_change",
        exerciseID: "barbell_bench", muscle: nil, fromValue: 77.5, toValue: 80,
        reasonCodes: ["reps_at_top_of_range"], evidence: [], humanSummary: "Load changed"),
      operationFingerprint: "fp-2")
    let split = ProgramChanges.applied(
      entries: [increase, unchanged, starting, otherFingerprint], sessions: [], profile: profile)
    XCTAssertEqual(split.count, 2)
    XCTAssertEqual(split.map(\.rows.count).sorted(), [1, 3])
  }

  /// Rows without a fingerprint were not written by a session start: no day, no session date,
  /// and a single done "Applied" step — even with a session sitting right next to the entry.
  func testUnfingerprintedAppliedEntriesNeverClaimASessionStart() throws {
    let profile = try JourneyTestStore.profile(in: context)
    let imported = DecisionLogEntry(
      DecisionRecord(
        id: "import", date: JourneyTestStore.date(2025, 6, 20, hour: 9), type: "load_change",
        exerciseID: "barbell_bench", muscle: nil, fromValue: 77.5, toValue: 80,
        reasonCodes: ["reps_at_top_of_range"], evidence: [], humanSummary: "Load changed"))
    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 20, hour: 10), dayName: "Full B", week: 1,
      completed: true)
    context.insert(session)
    try context.save()

    let groups = ProgramChanges.applied(entries: [imported], sessions: [session], profile: profile)
    let group = try XCTUnwrap(groups.first)
    XCTAssertEqual(group.state, .applied)
    XCTAssertEqual(group.dayName, "")
    XCTAssertNil(group.effectiveDate)

    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == "barbell_bench" })
    XCTAssertEqual(row.change, .increase(fromKg: 77.5, toKg: 80))
    let detail = ProgramChanges.detail(for: row, in: group, sessions: [session], entries: [imported], profile: profile)
    XCTAssertEqual(
      detail.steps.map(\.title), [String(localized: "Applied", bundle: L10n.bundle)])
    XCTAssertTrue(detail.steps.allSatisfy(\.done))
    XCTAssertNil(detail.proposedKg)
    XCTAssertNil(detail.planContext)
  }

  /// A keep turns its row into `.unchanged`; when that was the day's only change the group
  /// must stay on the timeline so the keep can still be undone.
  func testKeepingTheOnlyChangedRowKeepsTheScheduledGroup() throws {
    let fixture = try makeProgressedFixture()
    fixture.session.rememberPrescription(PlannedDay(name: "Full B", exercises: [fixture.planned]))
    try context.save()
    DecisionOverrides.set(.keepOriginal, for: fixture.planned.exercise.id)
    defer { DecisionOverrides.set(nil, for: fixture.planned.exercise.id) }

    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    XCTAssertEqual(group.rows.count, 1)
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    XCTAssertTrue(row.kept)
    XCTAssertEqual(row.change, .unchanged(kg: fixture.lastKg))
  }

  func testFinishedWorkoutKeepsOnlyKeptLoadsOfUntrainedLifts() {
    let keepUntrained = "test.keep.untrained"
    let easierUntrained = "test.easier.untrained"
    let keepTrained = "test.keep.trained"
    defer {
      DecisionOverrides.set(nil, for: keepUntrained)
      DecisionOverrides.set(nil, for: easierUntrained)
      DecisionOverrides.set(nil, for: keepTrained)
    }
    DecisionOverrides.set(.keepOriginal, for: keepUntrained)
    DecisionOverrides.set(.easier, for: easierUntrained)
    DecisionOverrides.set(.keepOriginal, for: keepTrained)

    DecisionOverrides.clearAfterWorkout(trained: [keepTrained])

    XCTAssertEqual(DecisionOverrides.get(keepUntrained), .keepOriginal)
    XCTAssertNil(DecisionOverrides.get(easierUntrained))
    XCTAssertNil(DecisionOverrides.get(keepTrained))
  }

  func testNextPlannedDateReadsOnlyFuturePlannedDaysOfTheAcceptedPlan() throws {
    let profile = try JourneyTestStore.profile(in: context)
    let now = JourneyTestStore.date(2025, 6, 20)
    XCTAssertNil(ProgramChanges.nextPlannedDate(dayName: "Full B", profile: profile, now: now))

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let old = calendar.date(byAdding: .day, value: -3, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    func day(_ id: String, _ date: Date, _ name: String, _ state: WeekPlanDayState) -> WeekPlanDay {
      WeekPlanDay(
        id: id, date: date, plannedSessionID: name, sessionName: name, state: state)
    }
    profile.weekPlan = WeekPlan(
      id: "week-test", weekStart: old, enrollmentDate: old, days: [
        day("done", yesterday, "Full B", .completed),
        day("past", old, "Full B", .planned),
        day("today", today, "Full A", .planned),
        day("next", tomorrow, "Full B", .planned),
      ])

    XCTAssertEqual(ProgramChanges.nextPlannedDate(dayName: "Full B", profile: profile, now: now), tomorrow)
  }

  func testUnreportedEffortNeverClaimsTopOfRange() throws {
    let fixture = try makeProgressedFixture(effortReported: false)
    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    XCTAssertFalse(row.reason.hasPrefix("All "), "reason was \(row.reason)")
    if case .unchanged = row.change {
      XCTAssertEqual(row.reason, "Effort not recorded, load held")
    }

    // The same unreported effort on a row the engine holds — the sets' recorded target sits
    // half a point over the plan's, so nextLoad repeats the load — must say exactly that.
    let held = try makeProgressedFixture(effortReported: false, targetRPEOffset: 0.5)
    let heldGroups = ProgramChanges.scheduled(sessions: [held.session], profile: held.profile, now: held.now)
    let heldGroup = try XCTUnwrap(heldGroups.first { $0.dayName == "Full B" })
    let heldRow = try XCTUnwrap(heldGroup.rows.first { $0.exerciseID == held.planned.exercise.id })
    guard case .unchanged(let kg) = heldRow.change else {
      return XCTFail("expected the load to hold, got \(heldRow.change)")
    }
    XCTAssertEqual(kg, held.lastKg)
    XCTAssertEqual(heldRow.reason, "Effort not recorded, load held")
    let detail = ProgramChanges.detail(
      for: heldRow, in: heldGroup, sessions: [held.session], entries: [], profile: held.profile)
    XCTAssertEqual(detail.evidence.first?.hasPrefix("Effort was not recorded"), true)
  }

  func testDetailForTheIncreaseRowShowsStepsEvidenceAndTheReadSets() throws {
    let fixture = try makeProgressedFixture()
    let groups = ProgramChanges.scheduled(sessions: [fixture.session], profile: fixture.profile, now: fixture.now)
    let group = try XCTUnwrap(groups.first { $0.dayName == "Full B" })
    let row = try XCTUnwrap(group.rows.first { $0.exerciseID == fixture.planned.exercise.id })
    guard case .increase(_, let toKg) = row.change else {
      return XCTFail("expected an increase, got \(row.change)")
    }

    let detail = ProgramChanges.detail(
      for: row, in: group, sessions: [fixture.session], entries: [], profile: fixture.profile)
    XCTAssertEqual(detail.steps.count, 3)
    XCTAssertTrue(detail.steps.first!.done)
    XCTAssertFalse(detail.steps.last!.done)
    XCTAssertEqual(detail.state, .scheduled)
    XCTAssertEqual(detail.lastSessionDate, fixture.session.date)
    XCTAssertEqual(detail.lastSessionDayName, "Full B")
    XCTAssertEqual(
      detail.lastSets,
      (0..<3).map { _ in
        ProgramChangeDetail.SetChip(weightKg: fixture.lastKg, reps: fixture.planned.repRange.upperBound)
      })
    XCTAssertEqual(detail.evidence.first?.hasPrefix("All "), true)
    XCTAssertTrue(detail.canKeepOriginal)
    XCTAssertEqual(detail.proposedKg, toKg)
    XCTAssertNotNil(detail.planContext)
    XCTAssertFalse(detail.calculation.isEmpty)
  }
}
