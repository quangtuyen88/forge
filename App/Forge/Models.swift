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

  init(goal: Goal, experience: Experience, daysPerWeek: Int, sessionMinutes: Int, equipment: Set<Equipment>, injuryFlags: Set<InjuryFlag>, recoveryReduced: Bool, bodyweightKg: Double, usesLb: Bool, startingLoads: [String: Double], restCompoundSeconds: Int = 180, restIsolationSeconds: Int = 90) {
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
  }

  var profileInput: ProfileInput {
    ProfileInput(
      goal: Goal(rawValue: goal) ?? .hypertrophy,
      daysPerWeek: daysPerWeek,
      sessionLength: SessionLength(rawValue: sessionMinutes) ?? .m60,
      equipment: Set(equipment.compactMap { Equipment(rawValue: $0) }),
      injuryFlags: Set(injuryFlags.compactMap { InjuryFlag(rawValue: $0) }),
      recoveryReduced: recoveryReduced)
  }

  var currentWeek: Int {
    let days = Calendar.current.dateComponents([.day], from: mesoStart, to: .now).day ?? 0
    return days / 7 % 6 + 1
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
  @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session) var sets: [LoggedSet]

  init(date: Date, dayName: String, week: Int, completed: Bool) {
    self.date = date
    self.dayName = dayName
    self.week = week
    self.completed = completed
    self.sets = []
  }
}

@Model
final class LoggedSet {
  var exerciseID: String
  var setIndex: Int
  var weightKg: Double
  var reps: Int
  var rpe: Double
  var targetRPE: Double
  var loggedAt: Date
  var session: WorkoutSession?

  init(exerciseID: String, setIndex: Int, weightKg: Double, reps: Int, rpe: Double, targetRPE: Double, loggedAt: Date) {
    self.exerciseID = exerciseID
    self.setIndex = setIndex
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.targetRPE = targetRPE
    self.loggedAt = loggedAt
  }
}
