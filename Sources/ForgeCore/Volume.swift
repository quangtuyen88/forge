public struct SetLog: Hashable, Codable, Sendable {
  public let weightKg: Double
  public let reps: Int
  public let rpe: Double

  public var rir: Double { 10 - rpe }
  public var countsTowardVolume: Bool { rpe >= 6 }

  public init(weightKg: Double, reps: Int, rpe: Double) {
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
  }
}

public enum Volume {
  public static func credit(for set: SetLog, exercise: Exercise) -> [Muscle: Double] {
    guard set.countsTowardVolume else { return [:] }
    var c: [Muscle: Double] = [exercise.primary: 1.0]
    if exercise.isCompound {
      for m in exercise.synergists { c[m, default: 0] += 0.5 }
    }
    return c
  }

  public static func weeklySets(_ entries: [(exercise: Exercise, set: SetLog)]) -> [Muscle: Double] {
    var totals: [Muscle: Double] = [:]
    for entry in entries {
      for (m, v) in credit(for: entry.set, exercise: entry.exercise) {
        totals[m, default: 0] += v
      }
    }
    return totals
  }
}
