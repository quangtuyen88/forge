import Foundation

public enum DecisionBuilder {
  /// One decision per exercise for the next session.
  public static func load(exerciseID: String, lastSets: [SetLog], repRange: ClosedRange<Int>, targetRPE: Double,
                          proposedKg: Double, e1rmChangePercent: Double?, readiness: Int?, sore: Bool) -> Decision {
    var causes: [DecisionCause] = []

    guard let last = lastSets.last else {
      return Decision(subject: .exercise(id: exerciseID), action: .firstTime(startKg: proposedKg),
                      causes: [DecisionCause(signal: .firstExposure, evidence: "")], overridable: true)
    }
    let current = last.weightKg

    if last.rpe < targetRPE - 0.5 {
      causes.append(DecisionCause(signal: .rpeBelowTarget, evidence: "\(last.weightKg) kg × \(last.reps) @ \(last.rpe)"))
    } else if last.rpe > targetRPE + 0.5 {
      causes.append(DecisionCause(signal: .rpeAboveTarget, evidence: "\(last.weightKg) kg × \(last.reps) @ \(last.rpe)"))
    }

    if last.reps >= repRange.upperBound {
      causes.append(DecisionCause(signal: .repsAtTopOfRange, evidence: "\(last.reps) reps"))
    } else if last.reps < repRange.lowerBound {
      causes.append(DecisionCause(signal: .repsBelowRange, evidence: "\(last.reps) reps"))
    }

    if let c = e1rmChangePercent {
      let signal: DecisionSignal = c >= 1 ? .e1rmUp : (c <= -1 ? .e1rmDown : .e1rmFlat)
      let sign = c > 0 ? "+" : ""
      causes.append(DecisionCause(signal: signal, evidence: "\(sign)\(String(format: "%.1f", c))%"))
    }

    if let r = readiness {
      let signal: DecisionSignal = r <= 2 ? .readinessLow : (r >= 4 ? .readinessHigh : .readinessLow)
      causes.append(DecisionCause(signal: signal, evidence: "\(r)/5"))
    }

    if sore {
      causes.append(DecisionCause(signal: .sorenessHigh, evidence: ""))
    }

    let action: DecisionAction
    if proposedKg > current {
      action = .increaseLoad(fromKg: current, toKg: proposedKg)
    } else if proposedKg < current {
      action = .decreaseLoad(fromKg: current, toKg: proposedKg)
    } else if Progression.shouldIncreaseLoad(sets: lastSets, repRange: repRange, targetRPE: targetRPE) {
      action = .addReps(atKg: current)
    } else {
      switch Progression.nextLoad(currentKg: current, targetRPE: targetRPE, actualRPE: last.rpe) {
      case .addReps(let atKg): action = .addReps(atKg: atKg)
      case .repeatLoad(let kg): action = .holdLoad(kg: kg)
      case .increase(let toKg): action = .increaseLoad(fromKg: current, toKg: toKg)
      case .decrease(let toKg, _): action = .decreaseLoad(fromKg: current, toKg: toKg)
      }
    }

    return Decision(subject: .exercise(id: exerciseID), action: action, causes: causes, overridable: true)
  }

  /// One decision per muscle whose weekly volume moved.
  public static func volume(muscle: Muscle, delta: Int, signal: VolumeSignal, sore: Bool, belowMEV: Bool, aboveMRV: Bool) -> Decision? {
    var causes: [DecisionCause] = []
    let action: DecisionAction?
    if aboveMRV {
      action = .removeSets(1)
      causes.append(DecisionCause(signal: .volumeAboveMRV, evidence: ""))
    } else if belowMEV {
      action = .addSets(1)
      causes.append(DecisionCause(signal: .volumeBelowMEV, evidence: ""))
    } else {
      switch signal {
      case .easy:
        action = .addSets(1)
        causes.append(DecisionCause(signal: .repsAtTopOfRange, evidence: ""))
      case .overreached:
        action = .removeSets(1)
        causes.append(DecisionCause(signal: .rpeAboveTarget, evidence: ""))
      case .onTarget:
        if delta > 0 { action = .addSets(delta) }
        else if delta < 0 { action = .removeSets(-delta) }
        else { action = nil }
      }
    }
    if sore { causes.append(DecisionCause(signal: .sorenessHigh, evidence: "")) }
    guard let action else { return nil }
    return Decision(subject: .muscle(muscle), action: action, causes: causes, overridable: true)
  }

  /// Session-level: light day, deload, rest.
  public static func session(action: FatigueAction, readiness: Int?, redDays: Int) -> Decision? {
    var causes: [DecisionCause] = []
    let decisionAction: DecisionAction
    switch action {
    case .proceed: return nil
    case .reduceOptionalSets(let by): decisionAction = .removeSets(by)
    case .lightSession: decisionAction = .lightSession
    case .forceRest: decisionAction = .deload
    }
    if let r = readiness, r <= 2 { causes.append(DecisionCause(signal: .readinessLow, evidence: "\(r)/5")) }
    if redDays >= 2 { causes.append(DecisionCause(signal: .deloadWeek, evidence: "\(redDays) red days")) }
    return Decision(subject: .session, action: decisionAction, causes: causes, overridable: decisionAction != .deload)
  }
}
