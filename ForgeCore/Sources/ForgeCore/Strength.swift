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
}
