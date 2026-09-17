import Foundation

public enum TimeBudget {
  public static let options = [20, 30, 45, 60]

  /// Minutes per set, the same rate `Program.setBudget` uses to size a session.
  /// Keeping one rate means a 60-minute session length and a 60-minute time box agree.
  public static let minutesPerSet = 2.5

  public static func estimatedMinutes(_ day: PlannedDay) -> Int {
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    return Int((Double(sets) * minutesPerSet / 5.0).rounded()) * 5
  }

  public static func fit(_ day: PlannedDay, minutes: Int) -> PlannedDay {
    var exercises = day.exercises.map { PlannedExercise(exercise: $0.exercise, sets: $0.sets, repRange: $0.repRange, targetRPE: $0.targetRPE) }
    var removed = 0

    func current() -> Int {
      estimatedMinutes(PlannedDay(name: day.name, exercises: exercises, trimmedSets: 0))
    }

    func reduce(_ i: Int) {
      exercises[i] = PlannedExercise(exercise: exercises[i].exercise, sets: exercises[i].sets - 1,
                                    repRange: exercises[i].repRange, targetRPE: exercises[i].targetRPE)
      removed += 1
    }

    while current() > minutes {
      let firstCompound = exercises.firstIndex { $0.exercise.isCompound }

      // 2. Drop trailing isolation exercises (lowest priority last).
      if let last = exercises.last, !last.exercise.isCompound {
        removed += last.sets
        exercises.removeLast()
        continue
      }
      // 3a. Remove one set from the largest remaining isolation slot.
      var idx: Int? = nil
      for (i, e) in exercises.enumerated() where e.sets > 2 && !e.exercise.isCompound {
        if idx == nil || e.sets > exercises[idx!].sets { idx = i }
      }
      if let i = idx { reduce(i); continue }
      // 3b. Then from compounds other than the first.
      idx = nil
      for (i, e) in exercises.enumerated() where e.sets > 2 && e.exercise.isCompound && i != firstCompound {
        if idx == nil || e.sets > exercises[idx!].sets { idx = i }
      }
      if let i = idx { reduce(i); continue }
      // 4. First compound down to its 2-set floor.
      if let f = firstCompound, exercises[f].sets > 2 { reduce(f); continue }
      break
    }

    return PlannedDay(name: day.name, exercises: exercises, trimmedSets: removed)
  }
}
