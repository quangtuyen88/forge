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
        targetRPE: set.targetRPE)
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

  var next: [DebriefNext] = []
  if let profile {
    let day = Program.week(session.week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
      .first { $0.name == session.dayName }
    for planned in day?.exercises ?? [] {
      let last = session.sets
        .filter { $0.exerciseID == planned.exercise.id }
        .sorted { $0.setIndex < $1.setIndex }
      guard let lastSet = last.last else { continue }
      let suggested = suggestedStartKg(for: planned, last: last, profile: profile)
      next.append(DebriefNext(exercise: planned.exercise.localizedName, kg: suggested, deltaKg: suggested - lastSet.weightKg))
    }
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
