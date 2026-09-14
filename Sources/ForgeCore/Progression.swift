public enum LoadDecision: Equatable, Sendable {
  case increase(toKg: Double)
  case addReps(atKg: Double)
  case repeatLoad(kg: Double)
  case decrease(toKg: Double, flagFatigue: Bool)
}

public enum Progression {
  public static func nextLoad(currentKg: Double, targetRPE: Double, actualRPE: Double) -> LoadDecision {
    let d = ((actualRPE - targetRPE) * 2).rounded() / 2
    switch d {
    case ..<(-0.5): return .increase(toKg: currentKg * 1.05)
    case -0.5: return .increase(toKg: currentKg * 1.025)
    case 0: return .addReps(atKg: currentKg)
    case 0.5: return .repeatLoad(kg: currentKg)
    default: return .decrease(toKg: currentKg * 0.95, flagFatigue: true)
    }
  }

  public static func shouldIncreaseLoad(sets: [SetLog], repRange: ClosedRange<Int>, targetRPE: Double) -> Bool {
    !sets.isEmpty && sets.allSatisfy { $0.reps >= repRange.upperBound && $0.rpe <= targetRPE }
  }

  public static func round(_ kg: Double, toIncrement increment: Double) -> Double {
    precondition(increment > 0)
    return (kg / increment).rounded() * increment
  }
}
