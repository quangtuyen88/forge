import Foundation
import SwiftData
import ForgeCore

/// Inserts a logged set into today's open session, creating the session when needed.
@MainActor
enum SetInserter {
  static func insert(exerciseID: String, weightKg: Double, reps: Int, rpe: Double?) throws -> LoggedSet {
    let context = ForgeApp.sharedContainer.mainContext
    let now = Date.now
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: now)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { $0.completed == false && $0.date >= dayStart && $0.date < dayEnd })
    let sessions = (try? context.fetch(descriptor)) ?? []
    let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
    let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []

    let session: WorkoutSession
    if let existing = sessions.first {
      session = existing
    } else {
      let week = profile?.currentWeek(sessions: all) ?? 1
      let new = WorkoutSession(date: now, dayName: nextDayName(profile: profile, sessions: all), week: week, completed: false)
      context.insert(new)
      session = new
    }

    let existingIndexes = session.sets.filter { $0.exerciseID == exerciseID }.map(\.setIndex)
    let nextIndex = existingIndexes.isEmpty ? 0 : (existingIndexes.max() ?? -1) + 1
    let targetRPE = plannedTargetRPE(for: exerciseID, profile: profile, sessions: all) ?? 8

    let set = LoggedSet(
      exerciseID: exerciseID,
      setIndex: nextIndex,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe ?? 8,
      targetRPE: targetRPE,
      loggedAt: now)
    context.insert(set)
    session.sets.append(set)
    try? context.save()
    return set
  }

  private static func nextDayName(profile: UserProfile?, sessions: [WorkoutSession]) -> String {
    guard let profile else { return "Today" }
    let week = profile.currentWeek(sessions: sessions)
    let days = Program.week(week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    guard !days.isEmpty else { return "Today" }
    return days[profile.nextDayIndex % days.count].name
  }

  private static func plannedTargetRPE(for exerciseID: String, profile: UserProfile?, sessions: [WorkoutSession]) -> Double? {
    guard let profile else { return nil }
    let week = profile.currentWeek(sessions: sessions)
    let days = Program.week(week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    for day in days {
      if let planned = day.exercises.first(where: { $0.exercise.id == exerciseID }) {
        return planned.targetRPE
      }
    }
    return nil
  }
}
