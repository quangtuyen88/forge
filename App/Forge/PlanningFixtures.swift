#if DEBUG
import Foundation
import SwiftData
import ForgeCore

/// QA fixtures from the planning goal doc: `--planning-fixture=<ID>` wipes and seeds a known state.
enum PlanningFixtures {
  private static let cal: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }()

  private static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .now
  }

  // MARK: entry

  static func run(in context: ModelContext) {
    guard let id = fixtureID(from: ProcessInfo.processInfo.arguments) else { return }
    resetStore(in: context)
    switch id {
    case "F00": break // reset only, no profile — onboarding shows
    case "F01": seedBaselineBlock(in: context, mesoStart: at(2026, 9, 21))
    case "F01C": seedF01C(in: context)
    case "F02": seedBaselineBlock(in: context, mesoStart: at(2026, 9, 7))
    case "F04": seedF04(in: context)
    case "F08": seedF08(in: context)
    case "F09": seedF09(in: context)
    case "F10": seedF10(in: context)
    case "F12": seedF12(in: context)
    case "FREST": seedFRest(in: context)
    case "FEMPTY": seedFEmpty(in: context)
    case "FROUTINE": seedRoutineCopy(in: context)
    case "FROUTINE_DB": seedRoutineCopy(in: context, dumbbellOnly: true)
    case "FROUTINE_BAD":
      seedRoutineCopy(in: context)
      if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
        profile.appliedRoutinesJSON = "unreadable-future-format"
        try? context.save()
      }
    case "FROUTINE_BAD_SNAPSHOT":
      seedRoutineCopy(in: context)
      let open = WorkoutSession(date: .now, dayName: "Full A", week: 1, completed: false)
      open.routinePrescriptionJSON = "unreadable-future-format"
      context.insert(open)
      try? context.save()
    case "FROUTINE_REMOTE":
      seedRoutineCopy(in: context)
      if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first,
        var plan = profile.weekPlan, !plan.days.isEmpty {
        plan.days[0].exerciseIDs = ["barbell_bench", "bent_row"]
        plan.days[0].plannedSetCount = 4
        plan.days[0].routineApplicationID = "remote-routine-application"
        profile.weekPlan = plan
        try? context.save()
      }
    case "FROUTINE_REMOTE_SAME":
      seedRoutineCopy(in: context)
      if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first,
        var plan = profile.weekPlan, !plan.days.isEmpty {
        plan.days[0].routineApplicationID = "remote-routine-same-exercises-and-sets"
        profile.weekPlan = plan
        try? context.save()
      }
    case "FROUTINE_BAD_PLAN":
      seedRoutineCopy(in: context)
      if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
        profile.weekPlanJSON = "unreadable-future-week"
        try? context.save()
      }
    default:
      print("PlanningFixtures: unknown fixture ID \"\(id)\" — store reset, nothing seeded")
    }
  }

  /// `--planning-fixture=<ID>` as one argument, or `--planning-fixture <ID>` as two.
  private static func fixtureID(from arguments: [String]) -> String? {
    let flag = "--planning-fixture"
    for argument in arguments where argument.hasPrefix("\(flag)=") {
      return String(argument.dropFirst(flag.count + 1))
    }
    if let index = arguments.firstIndex(of: flag), index + 1 < arguments.count {
      return arguments[index + 1]
    }
    return nil
  }

  // MARK: reset

  /// Deletes every row of every registered model type — DEBUG launch-argument only.
  private static func resetStore(in context: ModelContext) {
    let models: [any PersistentModel.Type] = [
      UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self,
      BodyMeasurement.self, ProgressPhoto.self, CoachMessage.self, CoachNote.self,
      NutritionProfile.self, FoodItem.self, FoodEntry.self, CustomExercise.self,
      DecisionLogEntry.self, JourneyReflection.self, JourneyVisibilityOverride.self,
      JourneyPrivateProfile.self,
    ]
    for model in models { wipe(model, in: context) }
    try? context.save()
  }

  private static func wipe<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
    for row in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(row) }
  }

  // MARK: common shape (every fixture except F00)

  /// `DemoSeed`'s profile; non-nil `trialStartedAt` makes it subscribed, skipping onboarding.
  @discardableResult
  private static func insertProfile(in context: ModelContext, mesoStart: Date) -> UserProfile {
    let profile = UserProfile(
      goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3, sessionMinutes: 60,
      equipment: [.barbell, .dumbbell], injuryFlags: [], recoveryReduced: false,
      bodyweightKg: 80, usesLb: false,
      startingLoads: ["barbell_bench": 60, "bent_row": 40, "deadlift": 80])
    profile.mesoStart = mesoStart
    profile.trialStartedAt = at(2026, 8, 3, 12)
    profile.nextDayIndex = 1 // Full A done, Full B next
    profile.mesoSessionOffset = 0
    profile.theme = "system"
    context.insert(profile)
    UserDefaults.standard.set("kai", forKey: Coach.storageKey)
    UserDefaults.standard.set(true, forKey: "coachConsent")
    return profile
  }

  /// Five completed "Imported" August sessions: bench 55×8 + row 35×10; Aug 10 is deadlift 80×8.
  @discardableResult
  private static func insertHistory(in context: ModelContext) -> [WorkoutSession] {
    let history: [(day: Int, exercises: [(id: String, kg: Double, reps: Int, rpe: Double)])] = [
      (3, [("barbell_bench", 55, 8, 8), ("bent_row", 35, 10, 7)]),
      (6, [("barbell_bench", 55, 8, 8), ("bent_row", 35, 10, 7)]),
      (10, [("deadlift", 80, 8, 8)]),
      (13, [("barbell_bench", 55, 8, 8), ("bent_row", 35, 10, 7)]),
      (17, [("barbell_bench", 55, 8, 8), ("bent_row", 35, 10, 7)]),
    ]
    var sessions: [WorkoutSession] = []
    for entry in history {
      let start = at(2026, 8, entry.day, 18)
      let session = WorkoutSession(date: start, dayName: "Imported", week: 1, completed: true)
      context.insert(session)
      insertSets(
        in: context, session: session, start: start,
        sets: entry.exercises.flatMap { spec in (0..<3).map { _ in
          SetSpec(exerciseID: spec.id, weightKg: spec.kg, reps: spec.reps, rpe: spec.rpe,
                  effortReported: true)
        } })
      sessions.append(session)
    }
    return sessions
  }

  /// F01's Monday "Full A": five sets in exact order; the third bench set's effort is unreported.
  private static func mondaySets(full: Bool) -> [SetSpec] {
    let five: [SetSpec] = [
      SetSpec(exerciseID: "barbell_bench", weightKg: 60, reps: 8, rpe: 8, effortReported: true),
      SetSpec(exerciseID: "barbell_bench", weightKg: 60, reps: 8, rpe: 8, effortReported: true),
      SetSpec(exerciseID: "barbell_bench", weightKg: 60, reps: 8, rpe: 8, effortReported: false),
      SetSpec(exerciseID: "bent_row", weightKg: 40, reps: 10, rpe: 7, effortReported: true),
      SetSpec(exerciseID: "bent_row", weightKg: 40, reps: 10, rpe: 8, effortReported: true),
    ]
    // F09 ended partial: only the two reported bench sets were logged, session still completed.
    return full ? five : Array(five.prefix(2))
  }

  @discardableResult
  private static func insertMondayFullA(in context: ModelContext, full: Bool) -> WorkoutSession {
    let start = at(2026, 9, 21, 18)
    let session = WorkoutSession(date: start, dayName: "Full A", week: 1, completed: true)
    context.insert(session)
    insertSets(in: context, session: session, start: start, sets: mondaySets(full: full))
    return session
  }

  /// Accepted week plan for 2026-09-21: Full A Mon, Full B Wed, Full C Fri; days stay .planned.
  private static func insertWeekPlan(
    in context: ModelContext, profile: UserProfile, sessions: [WorkoutSession],
    layout: [Date]? = nil
  ) {
    let monday = at(2026, 9, 21)
    var plan = WeekPlanBuilder.plan(
      programWeek: profile.currentWeek(sessions: sessions),
      profile: profile.profileInput,
      constraints: profile.trainingConstraints,
      startingOn: monday,
      enrollmentDate: monday,
      calendar: cal)
    let layout = layout ?? [at(2026, 9, 21), at(2026, 9, 23), at(2026, 9, 25)]
    plan.days = zip(plan.days, layout).map { built, date in
      var day = built
      let startOfDay = cal.startOfDay(for: date)
      day.date = startOfDay
      day.id = "\(day.plannedSessionID ?? day.id)@\(Int(startOfDay.timeIntervalSince1970))"
      return day
    }
    profile.weekPlan = plan
  }

  /// One seeded set: stored RPE plus whether the lifter actually reported the effort.
  private struct SetSpec {
    let exerciseID: String
    let weightKg: Double
    let reps: Int
    let rpe: Double
    let effortReported: Bool
    var suspect = false
  }

  /// Inserts sets in order, 90 s apart, numbering setIndex per exercise like a real session.
  private static func insertSets(
    in context: ModelContext, session: WorkoutSession, start: Date, sets: [SetSpec]
  ) {
    var nextIndex: [String: Int] = [:]
    for (offset, spec) in sets.enumerated() {
      let set = LoggedSet(
        exerciseID: spec.exerciseID,
        setIndex: nextIndex[spec.exerciseID, default: 0],
        weightKg: spec.weightKg, reps: spec.reps, rpe: spec.rpe, targetRPE: 8,
        loggedAt: start.addingTimeInterval(Double(offset) * 90),
        effortReported: spec.effortReported)
      set.suspect = spec.suspect
      set.session = session
      context.insert(set)
      nextIndex[spec.exerciseID, default: 0] += 1
    }
  }

  /// The F01 block unsaved, so fixture variations can add rows before saving.
  @discardableResult
  private static func insertBaseline(
    in context: ModelContext, mesoStart: Date, fullMonday: Bool = true, layout: [Date]? = nil
  ) -> UserProfile {
    let profile = insertProfile(in: context, mesoStart: mesoStart)
    let history = insertHistory(in: context)
    let monday = insertMondayFullA(in: context, full: fullMonday)
    insertWeekPlan(in: context, profile: profile, sessions: history + [monday], layout: layout)
    return profile
  }

  /// Today's check-in, shared by F01C and FREST.
  private static func insertTodaysCheckIn(in context: ModelContext) {
    let checkIn = CheckIn(date: .now, sleep: 4, soreness: 2, energy: 4, sleepHours: 7.5)
    checkIn.motivation = 4
    context.insert(checkIn)
  }

  // MARK: fixtures

  /// Relative dates keep the copy/adapt journey usable whenever QA runs it.
  private static func seedRoutineCopy(in context: ModelContext, dumbbellOnly: Bool = false) {
    let today = cal.startOfDay(for: .now)
    let profile = insertProfile(in: context, mesoStart: today)
    profile.nextDayIndex = 0
    if dumbbellOnly {
      profile.equipment = [Equipment.dumbbell.rawValue]
      profile.startingLoads = [:]
      profile.bodyweightKg = 0 // No verified or estimateable starting load for this QA path.
    }
    let sourceDate = cal.date(byAdding: .day, value: -7, to: today) ?? today
    let source = WorkoutSession(
      date: sourceDate, dayName: "Routine copy source", week: 1, completed: true)
    source.notes = "Private history note — must not appear in shared routine"
    context.insert(source)
    insertSets(
      in: context, session: source, start: sourceDate,
      sets: [
        SetSpec(exerciseID: "barbell_bench", weightKg: 90, reps: 8, rpe: 8,
                effortReported: true),
        SetSpec(exerciseID: "barbell_bench", weightKg: 90, reps: 9, rpe: 8,
                effortReported: false),
        SetSpec(exerciseID: "bent_row", weightKg: 55, reps: 10, rpe: 7,
                effortReported: true),
        SetSpec(exerciseID: "bent_row", weightKg: 55, reps: 10, rpe: 8,
                effortReported: true),
      ])
    var plan = WeekPlanBuilder.plan(
      programWeek: 1, profile: profile.profileInput,
      constraints: profile.trainingConstraints, startingOn: today,
      enrollmentDate: today, calendar: cal)
    plan.days = plan.days.enumerated().map { index, built in
      var day = built
      day.date = cal.date(byAdding: .day, value: index * 2, to: today) ?? today
      day.id = "\(day.plannedSessionID ?? day.id)@\(Int(day.date.timeIntervalSince1970))"
      return day
    }
    profile.weekPlan = plan
    insertTodaysCheckIn(in: context)
    do {
      try context.save()
    } catch {
      assertionFailure("Routine fixture could not be saved: \(error)")
    }
  }

  /// F01 — active block started Mon 2026-09-21, Monday "Full A" completed.
  private static func seedBaselineBlock(in context: ModelContext, mesoStart: Date) {
    insertBaseline(in: context, mesoStart: mesoStart)
    try? context.save()
  }

  /// F01C — F01 plus today's check-in, so Today offers Start.
  private static func seedF01C(in context: ModelContext) {
    insertBaseline(in: context, mesoStart: at(2026, 9, 21))
    insertTodaysCheckIn(in: context)
    try? context.save()
  }

  /// F04 — F01 plus an unplanned "Extra" session with two suspect 100×10 bench jumps.
  private static func seedF04(in context: ModelContext) {
    insertBaseline(in: context, mesoStart: at(2026, 9, 21))
    let start = at(2026, 9, 22, 12)
    let extra = WorkoutSession(date: start, dayName: "Extra", week: 1, completed: true)
    context.insert(extra)
    insertSets(
      in: context, session: extra, start: start,
      sets: [
        SetSpec(exerciseID: "barbell_bench", weightKg: 100, reps: 10, rpe: 8, effortReported: true,
                suspect: true),
        SetSpec(exerciseID: "barbell_bench", weightKg: 100, reps: 10, rpe: 8, effortReported: true,
                suspect: true),
      ])
    try? context.save()
  }

  /// F08 — F01 plus two Sep bench sessions and a bench e1RM goal 90 → 100 dated before them.
  private static func seedF08(in context: ModelContext) {
    let profile = insertBaseline(in: context, mesoStart: at(2026, 9, 21))
    for (day, reps) in [(10, 6), (17, 8)] {
      let start = at(2026, 9, day, 18)
      let session = WorkoutSession(date: start, dayName: "Imported", week: 1, completed: true)
      context.insert(session)
      insertSets(
        in: context, session: session, start: start,
        sets: [SetSpec(exerciseID: "barbell_bench", weightKg: 75, reps: reps, rpe: 8,
                       effortReported: true)])
    }
    profile.goalRecords = [
      GoalRecord(
        goal: .hypertrophy,
        title: "Bench estimated 1RM 100 kg",
        target: .benchmark(
          BenchmarkTarget(
            exerciseID: "barbell_bench", metric: .estimatedOneRepMax,
            baseline: 90, target: 100, unit: .kilograms, comparator: .atLeast)),
        createdAt: at(2026, 9, 7, 8))
    ]
    try? context.save()
  }

  /// F09 — F01 with only the Monday session's first two sets, still completed: an ended partial.
  private static func seedF09(in context: ModelContext) {
    insertBaseline(in: context, mesoStart: at(2026, 9, 21), fullMonday: false)
    try? context.save()
  }

  /// F10 — F01 plus an open "Full B" dated now with one 60×8 set, so Today offers Resume.
  private static func seedF10(in context: ModelContext) {
    insertBaseline(in: context, mesoStart: at(2026, 9, 21))
    let now = Date.now
    let open = WorkoutSession(date: now, dayName: "Full B", week: 1, completed: false)
    context.insert(open)
    insertSets(
      in: context, session: open, start: now,
      sets: [SetSpec(exerciseID: "barbell_bench", weightKg: 60, reps: 8, rpe: 8,
                     effortReported: true)])
    try? context.save()
  }

  /// F12 — profile and history only: no accepted week plan and no Monday session.
  private static func seedF12(in context: ModelContext) {
    insertProfile(in: context, mesoStart: at(2026, 9, 21))
    insertHistory(in: context)
    try? context.save()
  }

  /// FREST — plan on Mon/Thu/Sat: Wednesday is a scheduled rest day, Thursday is next.
  private static func seedFRest(in context: ModelContext) {
    insertBaseline(
      in: context, mesoStart: at(2026, 9, 21),
      layout: [at(2026, 9, 21), at(2026, 9, 24), at(2026, 9, 26)])
    insertTodaysCheckIn(in: context)
    try? context.save()
  }

  /// FEMPTY — an accepted week with no sessions: the unconfigured-week state.
  private static func seedFEmpty(in context: ModelContext) {
    insertBaseline(in: context, mesoStart: at(2026, 9, 21), layout: [])
    try? context.save()
  }
}
#endif
