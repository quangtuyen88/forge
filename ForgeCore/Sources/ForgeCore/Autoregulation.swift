public struct ExercisePerformance: Sendable {
  public let exercise: Exercise
  public let repRange: ClosedRange<Int>
  public let targetRPE: Double
  public let sets: [SetLog]

  public init(exercise: Exercise, repRange: ClosedRange<Int>, targetRPE: Double, sets: [SetLog]) {
    self.exercise = exercise
    self.repRange = repRange
    self.targetRPE = targetRPE
    self.sets = sets
  }
}

public enum VolumeSignal: Equatable, Sendable { case easy, onTarget, overreached }

public enum Autoregulation {
  public static func signals(_ performances: [ExercisePerformance]) -> [Muscle: VolumeSignal] {
    var out: [Muscle: VolumeSignal] = [:]
    for (muscle, group) in Dictionary(grouping: performances, by: { $0.exercise.primary }) {
      let counting = group.flatMap { perf in
        perf.sets.filter { $0.countsTowardVolume }
          .map { (set: $0, range: perf.repRange, target: perf.targetRPE) }
      }
      guard !counting.isEmpty else { continue }
      if counting.contains(where: { $0.set.rpe >= $0.target + 1 || $0.set.reps < $0.range.lowerBound }) {
        out[muscle] = .overreached
      } else if counting.count >= 2 && counting.allSatisfy({ $0.set.reps >= $0.range.upperBound && $0.set.rpe <= $0.target }) {
        out[muscle] = .easy
      } else {
        out[muscle] = .onTarget
      }
    }
    return out
  }

  public static func volumeDelta(_ performances: [ExercisePerformance], soreness: Int? = nil, soreMuscles: Set<Muscle> = []) -> [Muscle: Int] {
    var out: [Muscle: Int] = [:]
    for (muscle, signal) in signals(performances) {
      switch signal {
      case .easy: if (soreness == nil || soreness! < 4) && !soreMuscles.contains(muscle) { out[muscle] = 1 }
      case .overreached: out[muscle] = -1
      case .onTarget: break
      }
    }
    return out
  }
}
