import Foundation
import ForgeCore
import Observation

/// Weekly volume increases wait for the lifter's OK; decreases apply on their own.
/// Answers are kept per block week, so next week's increase asks again.
@Observable
final class VolumeApprovalStore {
  @MainActor static let shared = VolumeApprovalStore()

  enum Answer: String { case approved, kept }

  private static let key = "forge.volumeApprovals"
  private var dict: [String: String]

  init() {
    dict = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
  }

  func answer(_ key: String) -> Answer? {
    dict[key].flatMap(Answer.init(rawValue:))
  }

  func set(_ answer: Answer?, for key: String) {
    if let answer {
      dict[key] = answer.rawValue
    } else {
      dict.removeValue(forKey: key)
    }
    UserDefaults.standard.set(dict, forKey: Self.key)
  }
}

/// One weekly volume increase, resolved to the exercise that gains the set.
struct VolumeIncrease: Identifiable {
  let key: String
  let muscle: Muscle
  let exercise: Exercise
  let dayName: String
  let fromSets: Int
  let toSets: Int
  let weeklyFrom: Int
  let weeklyTo: Int
  let weeklyMax: Int?
  let answer: VolumeApprovalStore.Answer?
  var id: String { key }
}

/// Call-site facade. Reads go through the observable store, so views that read the
/// gated delta during body evaluation redraw as soon as an answer changes.
enum VolumeApprovals {
  private static func key(profile: UserProfile, week: Int, muscle: Muscle) -> String {
    "\(Int(profile.mesoStart.timeIntervalSince1970))|\(week)|\(muscle.rawValue)"
  }

  /// The raw autoregulation delta from the last full microcycle.
  static func rawDelta(profile: UserProfile, sessions: [WorkoutSession], checkIns: [CheckIn]) -> [Muscle: Int] {
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted { $0.date < $1.date }
    let index = done.count / days
    let performances: [ExercisePerformance]
    if index >= 1 {
      let previous = Array(done[((index - 1) * days)..<min(index * days, done.count)])
      let goal = Goal(rawValue: profile.goal) ?? .hypertrophy
      performances = Dictionary(grouping: previous.flatMap(\.sets), by: \.exerciseID)
        .compactMap { id, sets in
          guard let exercise = ExerciseDB.find(id), let first = sets.first else { return nil }
          return ExercisePerformance(
            exercise: exercise,
            repRange: Program.repRange(exercise, goal: goal),
            targetRPE: first.targetRPE,
            sets: sets.map {
              SetLog(
                weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe,
                effortReported: $0.effortReported)
            })
        }
    } else {
      performances = []
    }
    let soreness = checkIns.last(where: { Calendar.current.isDateInToday($0.date) })
    let soreMuscles = Set(soreness?.soreMuscles.compactMap(Muscle.init(rawValue:)) ?? [])
    return Autoregulation.volumeDelta(
      performances, soreness: soreness?.soreness, soreMuscles: soreMuscles)
  }

  /// Decreases always; increases only once approved.
  @MainActor static func gated(_ raw: [Muscle: Int], profile: UserProfile, week: Int) -> [Muscle: Int] {
    raw.filter { muscle, delta in
      delta < 0
        || (delta > 0
          && VolumeApprovalStore.shared.answer(key(profile: profile, week: week, muscle: muscle)) == .approved)
    }
  }

  /// Increases for the current week that still matter: answer nil (needs OK) or approved. Excludes kept ones.
  @MainActor static func increases(profile: UserProfile, sessions: [WorkoutSession], checkIns: [CheckIn]) -> [VolumeIncrease] {
    let week = profile.currentWeek(sessions: sessions)
    let raw = rawDelta(profile: profile, sessions: sessions, checkIns: checkIns)
    let input = profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions))
    var out: [VolumeIncrease] = []
    for (muscle, delta) in raw.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where delta > 0 {
      let k = key(profile: profile, week: week, muscle: muscle)
      let answer = VolumeApprovalStore.shared.answer(k)
      guard answer != .kept else { continue }
      var base = gated(raw, profile: profile, week: week)
      base[muscle] = nil
      var with = base
      with[muscle] = delta
      let beforeDays = Program.week(week, profile: input, volumeDelta: base)
      let afterDays = Program.week(week, profile: input, volumeDelta: with)
      guard let rise = firstRise(before: beforeDays, after: afterDays),
        (afterDays[rise.dayIndex].exercises.reduce(0) { $0 + $1.sets }
          > beforeDays[rise.dayIndex].exercises.reduce(0) { $0 + $1.sets })
      else { continue }
      let day = afterDays[rise.dayIndex]
      // ponytail: Today presents the first day of a repeated name; a rise past it never shows
      guard rise.dayIndex == afterDays.firstIndex(where: { $0.name == day.name }) else { continue }
      // ponytail: name match, repeated day names in one week share the check
      let startedThisWeek = sessions.contains {
        !$0.tombstoned && $0.date >= profile.mesoStart && $0.week == week && $0.dayName == day.name
      }
      guard !startedThisWeek else { continue }
      let ownedByRoutine = profile.appliedRoutines.contains {
        $0.blockStart == profile.mesoStart && $0.sessionName == day.name && $0.programWeek == week
      }
      guard !ownedByRoutine else { continue }
      out.append(
        VolumeIncrease(
          key: k,
          muscle: muscle,
          exercise: afterDays[rise.dayIndex].exercises[rise.exerciseIndex].exercise,
          dayName: day.name,
          fromSets: rise.fromSets,
          toSets: afterDays[rise.dayIndex].exercises[rise.exerciseIndex].sets,
          weeklyFrom: weeklySets(beforeDays, muscle: muscle),
          weeklyTo: weeklySets(afterDays, muscle: muscle),
          weeklyMax: VolumeLandmarks.landmarks(for: muscle, recoveryReduced: profile.recoveryReduced)?.mrv,
          answer: answer))
    }
    return out.filter { $0.answer == nil } + out.filter { $0.answer == .approved }
  }

  @MainActor static func approve(_ increase: VolumeIncrease) {
    VolumeApprovalStore.shared.set(.approved, for: increase.key)
  }

  @MainActor static func keep(_ increase: VolumeIncrease) {
    VolumeApprovalStore.shared.set(.kept, for: increase.key)
  }

  @MainActor static func undo(_ increase: VolumeIncrease) {
    VolumeApprovalStore.shared.set(nil, for: increase.key)
  }

  /// First exercise whose sets rise when the delta applies; nil when the increase never
  /// lands (capped at MRV, deload week, session budget trim).
  private static func firstRise(before: [PlannedDay], after: [PlannedDay]) -> (dayIndex: Int, exerciseIndex: Int, fromSets: Int)? {
    for d in after.indices where d < before.count {
      for e in after[d].exercises.indices {
        let id = after[d].exercises[e].exercise.id
        if let from = before[d].exercises.first(where: { $0.exercise.id == id })?.sets,
          after[d].exercises[e].sets > from
        {
          return (d, e, from)
        }
      }
    }
    return nil
  }

  private static func weeklySets(_ days: [PlannedDay], muscle: Muscle) -> Int {
    days.reduce(0) { total, day in
      total + day.exercises.filter { $0.exercise.primary == muscle }.reduce(0) { $0 + $1.sets }
    }
  }
}
