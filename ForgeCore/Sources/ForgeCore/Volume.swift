public struct SetLog: Hashable, Codable, Sendable {
  public let weightKg: Double
  public let reps: Int
  /// The effort value in the field. When `effortReported` is false this is the plan's own
  /// target standing in for an answer the lifter never gave.
  public let rpe: Double
  /// Whether the lifter actually rated this set.
  ///
  /// Defaults to `true` so existing callers and fixtures keep their current meaning — a
  /// caller that knows the effort is unreported says so explicitly. Nothing in the engine
  /// branches on this yet; `EffortDivergence` uses it to measure what would change if it did.
  public let effortReported: Bool

  public var rir: Double { 10 - rpe }
  public var countsTowardVolume: Bool { rpe >= 6 }
  /// The effort the lifter reported, or nothing.
  public var reportedRPE: Double? { effortReported ? rpe : nil }

  public init(weightKg: Double, reps: Int, rpe: Double, effortReported: Bool = true) {
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.effortReported = effortReported
  }

  private enum CodingKeys: String, CodingKey { case weightKg, reps, rpe, effortReported }

  /// Rows written before the flag existed decode as reported, which is what they meant when
  /// they were written — a migration that guessed otherwise would rewrite history.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    weightKg = try container.decode(Double.self, forKey: .weightKg)
    reps = try container.decode(Int.self, forKey: .reps)
    rpe = try container.decode(Double.self, forKey: .rpe)
    effortReported = try container.decodeIfPresent(Bool.self, forKey: .effortReported) ?? true
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
