import ForgeCore
import Foundation
import SwiftUI

enum BodyArea: String, CaseIterable, Identifiable {
  case legs, push, pull, core
  var id: String { rawValue }

  init(_ muscle: Muscle) {
    switch muscle {
    case .quads, .hamstrings, .glutes, .calves: self = .legs
    case .chest, .frontDelts, .sideDelts, .triceps: self = .push
    case .back, .rearDelts, .biceps, .forearms: self = .pull
    case .abs: self = .core
    }
  }

  var title: String {
    switch self {
    case .legs: return String(localized: "Legs and glutes", bundle: L10n.bundle)
    case .push: return String(localized: "Push", bundle: L10n.bundle)
    case .pull: return String(localized: "Pull", bundle: L10n.bundle)
    case .core: return String(localized: "Core", bundle: L10n.bundle)
    }
  }
}

struct ProgressData {
  struct LiftDelta: Identifiable {
    let exercise: Exercise
    let firstE1RM: Double
    let latestE1RM: Double
    var deltaKg: Double { latestE1RM - firstE1RM }
    var id: String { exercise.id }
  }

  struct Record: Identifiable {
    let exercise: Exercise
    let weightKg: Double
    let reps: Int
    let e1rm: Double
    let previousE1RM: Double
    let date: Date
    var id: String { "\(exercise.id)-\(date.timeIntervalSince1970)" }
  }

  struct Lift: Identifiable {
    let exercise: Exercise
    let area: BodyArea
    let bestE1RM: Double
    let freshRecord: Bool
    var id: String { exercise.id }
  }

  struct NextTarget {
    let dayName: String
    let weightKg: Double
    let sets: Int
    let repRange: ClosedRange<Int>
  }

  let blockLine: String?
  let strengthSince: Date?
  let strongerLifts: [LiftDelta]
  let comparedLiftCount: Int
  let records: [Record]
  let lifts: [Lift]
  /// Every lift with at least one completed, verified workout, sorted by localized name.
  let liftTrends: [LiftTrend]
  /// Training block of the newest completed session; 1 when there is none.
  let currentBlock: Int
  /// Date of the first completed session of each block; index 0 is block 1.
  let blockStarts: [Date]
  let plannedNotLogged: [Exercise]
  let plannedCount: Int
  let streakWeeks: Int
  let sessionCount: Int
  let sessionsPerWeek: Double
  let weekSets: [Muscle: Double]
  let topMuscles: [(muscle: Muscle, sets: Double)]
  let earnedBadges: [Badge]
  let badgeProgress: [BadgeProgress]
  let nextBadge: BadgeProgress?

  private let profile: UserProfile?
  private let sessions: [WorkoutSession]
  private let series: [String: [E1RMPoint]]
  private let planDays: [PlannedDay]

  let prCount: Int

  @MainActor init(sessions: [WorkoutSession], profile: UserProfile?, now: Date = .now) {
    self.profile = profile
    self.sessions = sessions

    let verified = sessions.filter(\.verified)
    let completedVerified = verified.filter(\.completed).sorted { $0.date < $1.date }
    strengthSince = completedVerified.first?.date

    var built: [String: [E1RMPoint]] = [:]
    for session in completedVerified {
      let trendSets = session.analysisSets(.trends)
      for id in Set(trendSets.map(\.exerciseID)) {
        let best = Self.comparableSets(trendSets, exerciseID: id)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
        if let best { built[id, default: []].append(E1RMPoint(date: session.date, e1rm: best)) }
      }
    }
    series = built

    var stronger: [LiftDelta] = []
    var compared = 0
    for (id, points) in built where points.count >= 2 {
      compared += 1
      let first = points.first!.e1rm
      let latest = points.last!.e1rm
      if latest - first >= 0.5, let exercise = ExerciseDB.find(id) {
        stronger.append(LiftDelta(exercise: exercise, firstE1RM: first, latestE1RM: latest))
      }
    }
    strongerLifts = stronger.sorted {
      $0.deltaKg == $1.deltaKg ? $0.exercise.localizedName < $1.exercise.localizedName : $0.deltaKg > $1.deltaKg
    }
    comparedLiftCount = compared

    // Same walk as prCount, keeping every record event instead of only the count.
    var bests: [String: Double] = [:]
    var events: [Record] = []
    var improvedIDs: Set<String> = []
    for session in completedVerified {
      let achievementSets = session.analysisSets(.achievements)
      var sessionBests: [String: (set: LoggedSet, e1rm: Double)] = [:]
      for id in Set(achievementSets.map(\.exerciseID)) {
        let sets = Self.comparableSets(achievementSets, exerciseID: id)
        guard
          let set = sets.max(by: {
            Strength.epley(weightKg: $0.weightKg, reps: $0.reps)
              < Strength.epley(weightKg: $1.weightKg, reps: $1.reps)
          })
        else { continue }
        sessionBests[id] = (set, Strength.epley(weightKg: set.weightKg, reps: set.reps))
      }
      for (id, entry) in sessionBests {
        if entry.e1rm > (bests[id] ?? 0), let previous = bests[id] {
          improvedIDs.insert(id)
          if let exercise = ExerciseDB.find(id) {
            events.append(
              Record(
                exercise: exercise, weightKg: entry.set.weightKg, reps: entry.set.reps,
                e1rm: entry.e1rm, previousE1RM: previous, date: session.date))
          }
        }
        bests[id] = max(bests[id] ?? 0, entry.e1rm)
      }
    }
    prCount = improvedIDs.count
    let recordEvents = Array(events.reversed())
    records = recordEvents

    let recordKeys = Set(events.map { "\($0.exercise.id)|\($0.date.timeIntervalSince1970)" })
    let blocks = Self.blockNumbers(sessions)
    let newestCompleted = sessions.filter(\.completed).max { $0.date < $1.date }
    currentBlock = newestCompleted.map { blocks.numbers[ObjectIdentifier($0)] ?? 1 } ?? 1
    blockStarts = blocks.starts

    var builtWorkouts: [String: [LiftWorkout]] = [:]
    for session in completedVerified {
      let trendSets = session.analysisSets(.trends)
      for id in Set(trendSets.map(\.exerciseID)) {
        guard
          let set = Self.comparableSets(trendSets, exerciseID: id).max(by: {
            Strength.epley(weightKg: $0.weightKg, reps: $0.reps)
              < Strength.epley(weightKg: $1.weightKg, reps: $1.reps)
          })
        else { continue }
        builtWorkouts[id, default: []].append(
          LiftWorkout(
            date: session.date,
            e1rmKg: Strength.epley(weightKg: set.weightKg, reps: set.reps),
            weightKg: set.weightKg,
            reps: set.reps,
            block: blocks.numbers[ObjectIdentifier(session)] ?? currentBlock,
            isRecord: recordKeys.contains("\(id)|\(session.date.timeIntervalSince1970)")))
      }
    }
    liftTrends = builtWorkouts
      .compactMap { id, workouts in
        guard let exercise = ExerciseDB.find(id) else { return nil }
        return LiftTrend(exercise: exercise, area: BodyArea(exercise.primary), workouts: workouts)
      }
      .sorted { $0.exercise.localizedName < $1.exercise.localizedName }

    let loggedIDs = Set(verified.flatMap { $0.analysisSets(.trends).map(\.exerciseID) })
    let freshCutoff = now.addingTimeInterval(-30 * 86400)
    lifts = loggedIDs
      .compactMap { id in
        guard let exercise = ExerciseDB.find(id) else { return nil }
        let best = (built[id]?.max { $0.e1rm < $1.e1rm })?.e1rm ?? 0
        return Lift(
          exercise: exercise, area: BodyArea(exercise.primary), bestE1RM: best,
          freshRecord: recordEvents.contains { $0.exercise.id == id && $0.date >= freshCutoff })
      }
      .sorted { $0.exercise.localizedName < $1.exercise.localizedName }

    if let profile {
      let week = profile.currentWeek(sessions: sessions)
      // Today follows an accepted week plan (and refuses to guess when it is unreadable), so a generated week here could contradict it.
      planDays =
        profile.weekPlan == nil && !RoutineAdaptationService.weekPlanUnreadable(profile)
        ? Program.week(
          week,
          profile: profile.profileInput(
            plateaued: plateauedExerciseIDs(sessions: sessions, now: now)))
        : []
      let plannedIDs = Set(planDays.flatMap { $0.exercises.map(\.exercise.id) })
      plannedCount = plannedIDs.count
      plannedNotLogged = plannedIDs
        .filter { !loggedIDs.contains($0) }
        .compactMap { ExerciseDB.find($0) }
        .sorted { $0.localizedName < $1.localizedName }
      let goalName = Goal(rawValue: profile.goal)?.name ?? Goal.hypertrophy.name
      blockLine = String(
        localized:
          "\(goalName) · Block \(Self.mesoBlockCount(sessions)) · Week \(week) of \(Mesocycle.weeks)",
        bundle: L10n.bundle)
    } else {
      planDays = []
      plannedCount = 0
      plannedNotLogged = []
      blockLine = nil
    }

    streakWeeks = Self.streakWeeks(verified, now: now)
    let eligible = sessions.analysisEligibleSessions
    sessionCount = eligible.count
    let cal = TrainingMetrics.reportingCalendar()
    if let firstDate = eligible.map(\.date).min() {
      let firstWeek = TrainingMetrics.reportingWeek(containing: firstDate, calendar: cal).start
      let thisWeek = TrainingMetrics.reportingWeek(containing: now, calendar: cal).start
      let weeks = (cal.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0)
        + 1
      sessionsPerWeek = Double(sessionCount) / Double(max(1, weeks))
    } else {
      sessionsPerWeek = 0
    }

    let reportingWeek = TrainingMetrics.reportingWeek(
      containing: now, calendar: TrainingMetrics.reportingCalendar())
    let entries: [(exercise: Exercise, set: SetLog)] =
      sessions
      .filter { TrainingMetrics.contains(reportingWeek, $0.date) }
      .flatMap { session in
        session.analysisSets(.trends).compactMap { set in
          ExerciseDB.find(set.exerciseID).map { exercise in
            (
              exercise: exercise,
              set: SetLog(
                weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
                effortReported: set.effortReported)
            )
          }
        }
      }
    weekSets = Volume.weeklySets(entries)

    let muscleOrder = Dictionary(
      uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    topMuscles = weekSets
      .filter { $0.value > 0 }
      .sorted {
        $0.value == $1.value ? muscleOrder[$0.key]! < muscleOrder[$1.key]! : $0.value > $1.value
      }
      .prefix(3)
      .map { (muscle: $0.key, sets: $0.value) }

    let tonnageKg = completedVerified
      .flatMap { $0.analysisSets(.achievements) }
      .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    let streak = Self.streakWeeks(verified, now: now)
    let earned = Badges.earned(
      sessions: eligible.count, streakWeeks: streak, tonnageKg: tonnageKg, prCount: prCount)
    let progress = Badges.progress(
      sessions: eligible.count, streakWeeks: streak, tonnageKg: tonnageKg, prCount: prCount)
    earnedBadges = earned
    badgeProgress = progress
    nextBadge = progress.filter { !earned.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
      .first
  }

  func e1rmSeries(for exerciseID: String) -> [E1RMPoint] { series[exerciseID] ?? [] }

  func bestSet(for exerciseID: String) -> Record? { records.first { $0.exercise.id == exerciseID } }

  func trend(for exerciseID: String) -> LiftTrend? {
    liftTrends.first { $0.exercise.id == exerciseID }
  }

  /// Record events of one lift, oldest first.
  func recordEvents(for exerciseID: String) -> [Record] {
    Array(records.filter { $0.exercise.id == exerciseID }.reversed())
  }

  func nextTarget(for exercise: Exercise) -> NextTarget? {
    guard let profile, !planDays.isEmpty else { return nil }
    let start = profile.nextDayIndex % planDays.count
    for offset in 0..<planDays.count {
      let day = planDays[(start + offset) % planDays.count]
      guard let planned = day.exercises.first(where: { $0.exercise.id == exercise.id }) else {
        continue
      }
      let kg = suggestedStartKg(for: planned, last: lastSets(exercise.id, in: sessions), profile: profile)
      return NextTarget(
        dayName: localizedDayName(day.name), weightKg: kg, sets: planned.sets,
        repRange: planned.repRange)
    }
    return nil
  }

  func lifts(in area: BodyArea) -> [Lift] { lifts.filter { $0.area == area } }

  /// Sets of `exerciseID` comparable with the most recent verified equipment context
  /// (copy of ProgressView.comparableSets).
  private static func comparableSets(_ sets: [LoggedSet], exerciseID: String) -> [LoggedSet] {
    let pool = sets.filter { $0.exerciseID == exerciseID }
    let reference =
      pool
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return pool }
    return pool.filter { $0.isComparableForBaseline(to: reference) }
  }

  private static func streakWeeks(_ sessions: [WorkoutSession], now: Date) -> Int {
    let cal = TrainingMetrics.reportingCalendar()
    let thisWeek = TrainingMetrics.reportingWeek(containing: now, calendar: cal).start
    let weeks = Set(
      sessions.filter(\.completed).map {
        TrainingMetrics.reportingWeek(containing: $0.date, calendar: cal).start
      })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }

  /// Block number of each completed session and the first session date of each block.
  private static func blockNumbers(_ sessions: [WorkoutSession]) -> (
    numbers: [ObjectIdentifier: Int], starts: [Date]
  ) {
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    var numbers: [ObjectIdentifier: Int] = [:]
    var starts: [Date] = []
    var block = 0
    var previousWeek = Int.max
    for session in completed {
      if session.week < previousWeek {
        block += 1
        starts.append(session.date)
      }
      numbers[ObjectIdentifier(session)] = block
      previousWeek = session.week
    }
    return (numbers, starts)
  }

  private static func mesoBlockCount(_ sessions: [WorkoutSession]) -> Int {
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    guard !completed.isEmpty else { return 1 }
    return 1 + zip(completed, completed.dropFirst()).filter { $0.1.week < $0.0.week }.count
  }
}
