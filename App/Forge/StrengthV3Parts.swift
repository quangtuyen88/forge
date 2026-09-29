import ForgeCore
import Foundation

/// Shared helpers for the Strength v3 screens (Trends, lift page, collection, record sheet).
/// Data helpers only; every view stays in the file that owns its screen.
enum StrengthV3 {
  /// Dates of completed sessions logged during the deload week. LiftWorkout does not carry
  /// the flag, so the lift screens match workout dates against this set.
  static func deloadDates(sessions: [WorkoutSession]) -> Set<Date> {
    Set(
      sessions
        .filter { $0.completed && $0.week == Mesocycle.deloadWeek }
        .map(\.date))
  }

  /// Lifts that set a record in the last 7 days (ProgressData.freshRecord uses 30).
  static func freshRecordIDs(_ data: ProgressData, now: Date = .now) -> Set<String> {
    let cutoff = now.addingTimeInterval(-7 * 86400)
    return Set(data.records.filter { $0.date >= cutoff }.map(\.exercise.id))
  }

  /// The day Today is offering next (no accepted week plan: the program day at
  /// nextDayIndex). nil when an accepted week plan owns the schedule or the lift is not
  /// in that day; Today's owed-day resolution stays private to TodayView.
  @MainActor static func todayPlanned(
    exercise: Exercise, sessions: [WorkoutSession], profile: UserProfile?
  ) -> (day: PlannedDay, planned: PlannedExercise)? {
    guard let profile,
      profile.weekPlan == nil, !RoutineAdaptationService.weekPlanUnreadable(profile)
    else { return nil }
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    guard !days.isEmpty else { return nil }
    let day = days[profile.nextDayIndex % days.count]
    guard let planned = day.exercises.first(where: { $0.exercise.id == exercise.id }) else {
      return nil
    }
    return (day, planned)
  }

  /// Suggested load for a planned exercise, the same source ProgressData.nextTarget uses.
  static func suggestedKg(
    _ planned: PlannedExercise, sessions: [WorkoutSession], profile: UserProfile?
  ) -> Double {
    suggestedStartKg(
      for: planned, last: lastSets(planned.exercise.id, in: sessions, profile: profile),
      profile: profile)
  }

  /// "3rd" in the user's language.
  static func ordinal(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    formatter.locale = L10n.locale
    return formatter.string(from: n as NSNumber) ?? "\(n)"
  }

  /// The heaviest analysis-eligible set ever logged on a lift, with its reps and session date.
  /// LiftWorkout keeps only each session's best-e1RM set, so the lift page asks the sets.
  static func heaviestSet(
    exerciseID: String, sessions: [WorkoutSession]
  ) -> (weightKg: Double, reps: Int, date: Date)? {
    var heaviest: (weightKg: Double, reps: Int, date: Date)?
    let completed = sessions
      .filter { $0.verified && $0.completed }
      .sorted { $0.date < $1.date }
    for session in completed {
      let pool = session.analysisSets(.trends).filter { $0.exerciseID == exerciseID }
      guard let set = comparableSets(pool).max(by: { $0.weightKg < $1.weightKg }) else {
        continue
      }
      if set.weightKg > (heaviest?.weightKg ?? 0) {
        heaviest = (set.weightKg, set.reps, session.date)
      }
    }
    return heaviest
  }

  struct HistoryEntry {
    let date: Date
    let weightKg: Double
    let reps: Int
    let e1rm: Double
    let isRecord: Bool
  }

  /// One entry per session that trained the lift: its best comparable achievement set,
  /// with record events flagged. The same walk ProgressData uses for its record events,
  /// kept here because ProgressData keeps its sessions private.
  static func history(exerciseID: String, sessions: [WorkoutSession]) -> [HistoryEntry] {
    var entries: [HistoryEntry] = []
    var best: Double?
    let completed = sessions
      .filter { $0.verified && $0.completed }
      .sorted { $0.date < $1.date }
    for session in completed {
      let pool = session.analysisSets(.achievements).filter { $0.exerciseID == exerciseID }
      guard let set = comparableSets(pool).max(by: {
        Strength.epley(weightKg: $0.weightKg, reps: $0.reps)
          < Strength.epley(weightKg: $1.weightKg, reps: $1.reps)
      }) else { continue }
      let e1rm = Strength.epley(weightKg: set.weightKg, reps: set.reps)
      let isRecord = e1rm > (best ?? 0) && best != nil
      entries.append(
        HistoryEntry(
          date: session.date, weightKg: set.weightKg, reps: set.reps, e1rm: e1rm,
          isRecord: isRecord))
      best = max(best ?? 0, e1rm)
    }
    return entries
  }

  /// Copy of ProgressData.comparableSets: the newest verified equipment context decides
  /// which sets of one exercise are comparable.
  private static func comparableSets(_ sets: [LoggedSet]) -> [LoggedSet] {
    let reference =
      sets
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return sets }
    return sets.filter { $0.isComparableForBaseline(to: reference) }
  }
}

extension BodyArea {
  /// Group illustration for v6 headers.
  var art: String { "art-group-\(rawValue)" }
  /// Short filter-pill name ("Legs"), against `title` ("Legs and glutes").
  var shortTitle: String {
    switch self {
    case .legs: return String(localized: "Legs", bundle: L10n.bundle)
    case .push: return String(localized: "Push", bundle: L10n.bundle)
    case .pull: return String(localized: "Pull", bundle: L10n.bundle)
    case .core: return String(localized: "Core", bundle: L10n.bundle)
    }
  }
}
