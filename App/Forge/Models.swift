import Foundation
import SwiftData
import ForgeCore

@Model
final class UserProfile {
  var goal: String
  var experience: String
  var daysPerWeek: Int
  var sessionMinutes: Int
  var equipment: [String]
  var injuryFlags: [String]
  var recoveryReduced: Bool
  var bodyweightKg: Double
  var usesLb: Bool
  var startingLoads: [String: Double]
  var mesoStart: Date
  var trialStartedAt: Date?
  var nextDayIndex: Int
  var restCompoundSeconds: Int = 180
  var restIsolationSeconds: Int = 90
  var restOverrides: [String: Int] = [:]
  var deloadStartedAt: Date? = nil
  var unitOverrides: [String: Bool] = [:]
  var barKg: Double = 20
  var barLb: Double = 45
  var platesKg: [Double] = Plates.defaultKg
  var platesLb: [Double] = Plates.defaultLb
  var exerciseNotes: [String: String] = [:]
  var exerciseOverrides: [String: String] = [:]
  var split: String = "auto"
  var gymPreset: String = "commercial"
  /// Plateau rescue: sets added or removed per exercise, and a forced rep range like "5-8".
  var setDeltas: [String: Int] = [:]
  var repRangeOverrides: [String: String] = [:]
  /// Week repair: compress adds sessions, restart-microcycle subtracts the partial week.
  var mesoSessionOffset: Int = 0
  var theme: String = "dark"
  var reminderHour: Int? = nil
  var reminderMinute: Int = 0
  var remoteID: String = ""
  var updatedAt: Date = Date.now

  init(goal: Goal, experience: Experience, daysPerWeek: Int, sessionMinutes: Int, equipment: Set<Equipment>, injuryFlags: Set<InjuryFlag>, recoveryReduced: Bool, bodyweightKg: Double, usesLb: Bool, startingLoads: [String: Double], restCompoundSeconds: Int = 180, restIsolationSeconds: Int = 90, restOverrides: [String: Int] = [:]) {
    self.goal = goal.rawValue
    self.experience = experience.rawValue
    self.daysPerWeek = daysPerWeek
    self.sessionMinutes = sessionMinutes
    self.equipment = equipment.map(\.rawValue).sorted()
    self.injuryFlags = injuryFlags.map(\.rawValue).sorted()
    self.recoveryReduced = recoveryReduced
    self.bodyweightKg = bodyweightKg
    self.usesLb = usesLb
    self.startingLoads = startingLoads
    self.mesoStart = .now
    self.trialStartedAt = nil
    self.nextDayIndex = 0
    self.restCompoundSeconds = restCompoundSeconds
    self.restIsolationSeconds = restIsolationSeconds
    self.restOverrides = restOverrides
  }

  var profileInput: ProfileInput {
    profileInput(plateaued: [])
  }

  func profileInput(plateaued: Set<String>) -> ProfileInput {
    ProfileInput(
      goal: Goal(rawValue: goal) ?? .hypertrophy,
      daysPerWeek: daysPerWeek,
      sessionLength: SessionLength(rawValue: sessionMinutes) ?? .m60,
      equipment: Set(equipment.compactMap { Equipment(rawValue: $0) }),
      injuryFlags: Set(injuryFlags.compactMap { InjuryFlag(rawValue: $0) }),
      recoveryReduced: recoveryReduced,
      plateauedExerciseIDs: plateaued,
      split: SplitStyle(rawValue: split) ?? .auto,
      exerciseOverrides: exerciseOverrides,
      setDeltas: setDeltas,
      repRangeOverrides: repRangeOverrides.compactMapValues(ProfileInput.repRange))
  }

  /// Start a fresh mesocycle: week 1, no deload, and plateau interventions cleared.
  func startNewBlock() {
    mesoStart = .now
    nextDayIndex = 0
    deloadStartedAt = nil
    mesoSessionOffset = 0
    setDeltas = [:]
    repRangeOverrides = [:]
    updatedAt = .now
  }

  func mesoSessions(_ sessions: [WorkoutSession]) -> Int {
    sessions.filter { $0.completed && $0.date >= mesoStart }.count
  }

  func currentWeek(sessions: [WorkoutSession]) -> Int {
    if deloadStartedAt != nil { return Mesocycle.deloadWeek }
    let counted = max(0, mesoSessions(sessions) + mesoSessionOffset)
    return min(Mesocycle.weeks, counted / max(daysPerWeek, 1) + 1)
  }

  var isSubscribed: Bool { trialStartedAt != nil }
}

@Model
final class CheckIn {
  var date: Date
  var sleep: Int
  var soreness: Int
  var energy: Int
  var sleepHours: Double
  var motivation: Int = 3
  var soreMuscles: [String] = []
  var remoteID: String = ""
  var updatedAt: Date = Date.now
  var deleted: Bool = false

  init(date: Date, sleep: Int, soreness: Int, energy: Int, sleepHours: Double) {
    self.date = date
    self.sleep = sleep
    self.soreness = soreness
    self.energy = energy
    self.sleepHours = sleepHours
  }
}

@Model
final class WorkoutSession {
  var date: Date
  var dayName: String
  var week: Int
  var completed: Bool
  var notes: String = ""
  var order: [String] = []
  var supersets: [String] = []
  var extraExerciseIDs: [String] = []
  var removedExerciseIDs: [String] = []
  var setCounts: [String: Int] = [:]
  @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session) var sets: [LoggedSet]
  var remoteID: String = ""
  var updatedAt: Date = Date.now
  var deleted: Bool = false
  var heartRateSeen: Bool = false

  init(date: Date, dayName: String, week: Int, completed: Bool) {
    self.date = date
    self.dayName = dayName
    self.week = week
    self.completed = completed
    self.sets = []
  }

  /// False when the session looks fabricated; such sessions stay in history but do not feed PRs, badges or Crew.
  var verified: Bool {
    if heartRateSeen { return true }
    if sets.contains(where: \.suspect) { return false }
    let times = sets.map(\.loggedAt).sorted()
    return !Plausibility.isShortSession(setCount: sets.count, first: times.first, last: times.last)
  }

  /// Sets that may drive charts, PRs and trends: everything the plausibility guard did not flag.
  var trustedSets: [LoggedSet] {
    verified ? sets.filter { !$0.suspect } : []
  }
}

extension Array where Element == WorkoutSession {
  /// Every set from completed sessions that the plausibility guard trusts.
  var trustedSets: [LoggedSet] {
    filter(\.completed).flatMap(\.trustedSets)
  }
}

func plateauedExerciseIDs(sessions: [WorkoutSession], now: Date = .now) -> Set<String> {
  var history: [String: [E1RMPoint]] = [:]
  for session in sessions where session.completed {
    let bestPerExercise = Dictionary(grouping: session.sets, by: \.exerciseID)
      .mapValues { sets in sets.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0 }
    for (id, best) in bestPerExercise where best > 0 {
      history[id, default: []].append(E1RMPoint(date: session.date, e1rm: best))
    }
  }
  return Set(history.filter { Strength.isPlateaued($0.value, asOf: now) }.keys)
}

@Model
final class LoggedSet {
  var exerciseID: String
  var setIndex: Int
  var weightKg: Double
  var reps: Int
  var rpe: Double
  var targetRPE: Double
  var variant: String = "straight"
  var loggedAt: Date
  var suspect: Bool = false
  var session: WorkoutSession?

  init(exerciseID: String, setIndex: Int, weightKg: Double, reps: Int, rpe: Double, targetRPE: Double, variant: String = "straight", loggedAt: Date) {
    self.exerciseID = exerciseID
    self.setIndex = setIndex
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.targetRPE = targetRPE
    self.variant = variant
    self.loggedAt = loggedAt
  }
}

extension UserProfile {
  func isLb(for exerciseID: String) -> Bool {
    unitOverrides[exerciseID] ?? usesLb
  }

  func unit(for exerciseID: String) -> String {
    isLb(for: exerciseID) ? "lb" : "kg"
  }

  func display(kg: Double, for exerciseID: String) -> Double {
    isLb(for: exerciseID) ? Plates.kgToLb(kg) : kg
  }
}
