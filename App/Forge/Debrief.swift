import ForgeCore

func debriefLines(session: WorkoutSession, sessions: [WorkoutSession], prs: [PRRecord], profile: UserProfile?, usesLb: Bool) -> [DebriefLine] {
  let sets = session.sets
    .sorted { $0.setIndex < $1.setIndex }
    .map { set in
      DebriefSet(
        exercise: ExerciseDB.find(set.exerciseID)?.localizedName ?? set.exerciseID,
        weightKg: set.weightKg,
        reps: set.reps,
        rpe: set.rpe,
        targetRPE: set.targetRPE,
        effortReported: set.effortReported)
    }

  let earlier = sessions.filter { $0.completed && $0 !== session && $0.date < session.date }
  let debriefPRs = prs.map { pr in
    DebriefPR(
      exercise: pr.exercise.localizedName,
      e1RM: pr.e1rm,
      priorE1RM: earlier.trustedSets
        .filter { $0.exerciseID == pr.exercise.id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max())
  }

  let tonnage = session.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
  let priorTonnage = earlier
    .filter { $0.dayName == session.dayName }
    .sorted { $0.date > $1.date }
    .first
    .map { $0.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) } }

  let next = sessionNextLoads(session: session, sessions: sessions, profile: profile).map {
    DebriefNext(
      exercise: ExerciseDB.find($0.exerciseID)?.localizedName ?? $0.exerciseID,
      kg: $0.kg,
      deltaKg: $0.deltaKg)
  }

  return Debrief.lines(
    sets: sets,
    prs: debriefPRs,
    tonnageKg: tonnage,
    priorTonnageKg: priorTonnage,
    dayName: localizedDayName(session.dayName),
    next: next,
    usesLb: usesLb)
}

/// Next-session starting loads for a finished session, in planned order. Empty when there is
/// no profile — there is no plan to project from.
func sessionNextLoads(session: WorkoutSession, sessions: [WorkoutSession], profile: UserProfile?)
  -> [WorkoutNextLoad]
{
  guard let profile else { return [] }
  let day = session.routinePrescription.flatMap(RoutineAdaptation.plannedDay)
    ?? Program.week(session.week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
      .first { $0.name == session.dayName }
  var loads: [WorkoutNextLoad] = []
  for planned in day?.exercises ?? [] {
    let last = session.sets
      .filter { $0.exerciseID == planned.exercise.id }
      .sorted { $0.setIndex < $1.setIndex }
    guard let lastSet = last.last else { continue }
    let suggested = suggestedStartKg(for: planned, last: last, profile: profile)
    loads.append(
      WorkoutNextLoad(
        exerciseID: planned.exercise.id, kg: suggested, deltaKg: suggested - lastSet.weightKg))
  }
  return loads
}

func sessionPRs(session: WorkoutSession, sessions: [WorkoutSession]) -> [PRRecord] {
  guard session.verified else { return [] }
  let earlier = sessions.filter { $0.completed && $0 !== session && $0.date < session.date }
  return Set(session.trustedSets.map(\.exerciseID)).compactMap { id -> PRRecord? in
    guard let exercise = ExerciseDB.find(id) else { return nil }
    let best = session.trustedSets.filter { $0.exerciseID == id }
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
    let previous = earlier.trustedSets.filter { $0.exerciseID == id }
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
    guard let previous, best > previous else { return nil }
    return PRRecord(exercise: exercise, e1rm: best, previous: previous)
  }
  .sorted { $0.exercise.localizedName < $1.exercise.localizedName }
}
