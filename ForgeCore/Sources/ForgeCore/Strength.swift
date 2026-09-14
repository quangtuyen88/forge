import Foundation

public struct E1RMPoint: Hashable, Sendable {
  public let date: Date
  public let e1rm: Double
  public init(date: Date, e1rm: Double) {
    self.date = date
    self.e1rm = e1rm
  }
}

public enum Strength {
  public static func epley(weightKg: Double, reps: Int) -> Double {
    weightKg * (1 + Double(reps) / 30)
  }

  public static func isPlateaued(_ history: [E1RMPoint], asOf now: Date, windowWeeks: Int = 12, plateauWeeks: Int = 3) -> Bool {
    let week: TimeInterval = 7 * 24 * 3600
    let recentStart = now.addingTimeInterval(-Double(plateauWeeks) * week)
    let windowStart = now.addingTimeInterval(-Double(windowWeeks) * week)
    let prior = history.filter { $0.date > windowStart && $0.date <= recentStart }
    let recent = history.filter { $0.date > recentStart && $0.date <= now }
    guard let priorBest = prior.map(\.e1rm).max(), let recentBest = recent.map(\.e1rm).max() else { return false }
    return recentBest <= priorBest
  }

  public static func estimatedStartingLoad(exerciseID: String, bodyweightKg: Double) -> Double? {
    let factors: [String: Double] = [
      "barbell_bench": 0.6,
      "back_squat": 0.8,
      "deadlift": 1.0,
      "overhead_press": 0.4,
      "bent_row": 0.55,
    ]
    return factors[exerciseID].map { $0 * bodyweightKg }
  }

  /// Known-id table first; otherwise a movement-pattern ratio of bodyweight for compounds and a small fixed fraction for isolation. Rounded to the exercise's smallestIncrementKg. Bodyweight-equipment exercises return 0.
  public static func estimatedStartingLoad(exercise: Exercise, bodyweightKg: Double) -> Double {
    if let known = estimatedStartingLoad(exerciseID: exercise.id, bodyweightKg: bodyweightKg) { return known }
    guard exercise.equipment != .bodyweight else { return 0 }
    let ratio: Double
    if exercise.isCompound {
      switch exercise.pattern {
      case .horizontalPush: ratio = 0.5
      case .verticalPush: ratio = 0.35
      case .horizontalPull: ratio = 0.5
      case .verticalPull: ratio = (exercise.equipment == .machine || exercise.equipment == .cable) ? 0.6 : 0
      case .squat: ratio = 0.7
      case .hinge: ratio = 0.9
      case .lunge: ratio = 0.3
      case .carry: ratio = 0.5
      case .core: ratio = 0.2
      case .isolation: ratio = 0
      }
    } else {
      switch exercise.equipment {
      case .dumbbell: ratio = 0.12
      case .barbell: ratio = 0.3
      case .machine: ratio = 0.35
      case .cable: ratio = 0.25
      case .bands, .bodyweight: ratio = 0
      }
    }
    return Progression.round(ratio * bodyweightKg, toIncrement: exercise.smallestIncrementKg)
  }
}
