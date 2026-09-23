import Foundation
import SwiftData
import ForgeCore

/// Inserts a logged set into today's open session, creating the session when needed.
@MainActor
enum SetInserter {
  enum Failure: LocalizedError, Equatable {
    case routineNeedsReview, savedWorkoutUnreadable, weekPlanUnreadable
    var errorDescription: String? {
      switch self {
      case .routineNeedsReview: "Review the changed routine in Regulift before logging this planned workout."
      case .savedWorkoutUnreadable: "Regulift cannot read the saved workout. Open the app to review it before logging."
      case .weekPlanUnreadable: "Regulift cannot read the accepted week plan. Open the app before logging."
      }
    }
  }
  static func insert(exerciseID: String, weightKg: Double, reps: Int, rpe: Double?) throws -> LoggedSet {
    try insert(exerciseID: exerciseID, weightKg: weightKg, reps: reps, rpe: rpe,
      in: ForgeApp.sharedContainer.mainContext)
  }

  static func insert(exerciseID: String, weightKg: Double, reps: Int, rpe: Double?,
    in context: ModelContext) throws -> LoggedSet {
    let now = Date.now
    let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
    let all = try context.fetch(FetchDescriptor<WorkoutSession>())
    let open = all.filter { !$0.completed && !$0.tombstoned
      && (Calendar.current.isDateInToday($0.date) || $0.routinePrescription != nil)
    }.max(by: { $0.date < $1.date })
    if RoutineAdaptationService.hasUnreadableOpenSnapshot(all) { throw Failure.savedWorkoutUnreadable }
    if let profile, RoutineAdaptationService.weekPlanUnreadable(profile),
      open?.routinePrescription.flatMap(RoutineAdaptation.plannedDay) == nil {
      throw Failure.weekPlanUnreadable
    }
    if let profile, let plan = profile.weekPlan,
      let owed = WeekPlanTodayStatus(plan: plan, now: now).owed,
      RoutineAdaptationService.needsReview(owed, profile: profile, sessions: all),
      !all.contains(where: { !$0.completed && !$0.tombstoned && $0.routinePrescription != nil }) {
      throw Failure.routineNeedsReview
    }
    let planned = profile.flatMap { RoutineAdaptationService.currentDay(profile: $0, sessions: all) }

    let session: WorkoutSession
    if let existing = open {
      session = existing
    } else {
      let week = profile?.currentWeek(sessions: all) ?? 1
      let new = WorkoutSession(date: now, dayName: planned?.name ?? "Today", week: week, completed: false)
      if let planned {
        new.rememberPrescription(planned,
          planDayID: profile?.weekPlan.flatMap { WeekPlanTodayStatus(plan: $0, now: now).owed?.id })
        if !new.plannedDayID.isEmpty {
          new.plannedPlanID = profile?.weekPlan?.id
          new.plannedAcceptanceID = profile?.weekPlan?.acceptanceID
        }
      }
      context.insert(new)
      session = new
    }

    let existingIndexes = session.sets.filter { $0.exerciseID == exerciseID }.map(\.setIndex)
    let nextIndex = existingIndexes.isEmpty ? 0 : (existingIndexes.max() ?? -1) + 1
    let targetRPE = session.routinePrescription?.exercises.first { $0.exerciseID == exerciseID }?.targetRPE
      ?? planned?.exercises.first { $0.exercise.id == exerciseID }?.targetRPE ?? 8

    // The same equipment context the logger would resolve: seed on first need, then build a
    // descriptor from the profile. Typed/voice input arrives already normalized to kg, so the
    // original value is that kg number and no display unit is fabricated.
    profile?.seedEquipmentPassportIfEmpty()
    let kind = ExerciseDB.find(exerciseID).map { EquipmentKind(equipment: $0.equipment) } ?? .unknown
    let loadDescriptor = profile?.equipmentLoadDescriptor(
      exerciseID: exerciseID,
      variant: "straight",
      displayValue: "",
      displayUnit: "kg",
      weightKg: weightKg,
      side: UserProfile.defaultSide(for: kind))
      ?? LoggedSet.inferredDescriptor(exerciseID: exerciseID, weightKg: weightKg)

    let set = LoggedSet(
      exerciseID: exerciseID,
      setIndex: nextIndex,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe ?? 8,
      targetRPE: targetRPE,
      loggedAt: now,
      loadDescriptor: loadDescriptor,
      effortReported: rpe != nil)
    context.insert(set)
    session.sets.append(set)
    try context.save()
    return set
  }

}
