import Foundation

public enum DecisionSignal: String, Sendable, CaseIterable {
  case rpeBelowTarget, rpeAboveTarget, repsAtTopOfRange, repsBelowRange, completedAllSets
  case e1rmUp, e1rmFlat, e1rmDown
  case sorenessHigh, readinessLow, readinessNormal, readinessHigh, sleepShort
  case volumeBelowMEV, volumeAboveMRV
  case missedSessions, plateau, firstExposure, timeBudget, equipmentMissing, deloadWeek
  case userOverride

  public var label: String {
    switch self {
    case .rpeBelowTarget: return String(localized: "RPE under target", bundle: ForgeCoreResources.bundle)
    case .rpeAboveTarget: return String(localized: "RPE over target", bundle: ForgeCoreResources.bundle)
    case .repsAtTopOfRange: return String(localized: "Reps at top of range", bundle: ForgeCoreResources.bundle)
    case .repsBelowRange: return String(localized: "Reps below range", bundle: ForgeCoreResources.bundle)
    case .completedAllSets: return String(localized: "Completed all sets", bundle: ForgeCoreResources.bundle)
    case .e1rmUp: return String(localized: "e1RM up", bundle: ForgeCoreResources.bundle)
    case .e1rmFlat: return String(localized: "e1RM flat", bundle: ForgeCoreResources.bundle)
    case .e1rmDown: return String(localized: "e1RM down", bundle: ForgeCoreResources.bundle)
    case .sorenessHigh: return String(localized: "Sore", bundle: ForgeCoreResources.bundle)
    case .readinessLow: return String(localized: "Readiness low", bundle: ForgeCoreResources.bundle)
    case .readinessNormal: return String(localized: "Readiness normal", bundle: ForgeCoreResources.bundle)
    case .readinessHigh: return String(localized: "Readiness high", bundle: ForgeCoreResources.bundle)
    case .sleepShort: return String(localized: "Short sleep", bundle: ForgeCoreResources.bundle)
    case .volumeBelowMEV: return String(localized: "Below minimum volume", bundle: ForgeCoreResources.bundle)
    case .volumeAboveMRV: return String(localized: "Above maximum volume", bundle: ForgeCoreResources.bundle)
    case .missedSessions: return String(localized: "Missed sessions", bundle: ForgeCoreResources.bundle)
    case .plateau: return String(localized: "Plateau", bundle: ForgeCoreResources.bundle)
    case .firstExposure: return String(localized: "First time", bundle: ForgeCoreResources.bundle)
    case .timeBudget: return String(localized: "Time budget", bundle: ForgeCoreResources.bundle)
    case .equipmentMissing: return String(localized: "Equipment missing", bundle: ForgeCoreResources.bundle)
    case .deloadWeek: return String(localized: "Deload week", bundle: ForgeCoreResources.bundle)
    case .userOverride: return String(localized: "Override", bundle: ForgeCoreResources.bundle)
    }
  }
}

public struct DecisionCause: Sendable, Hashable {
  public let signal: DecisionSignal
  /// Concrete evidence, already formatted: "80 kg × 8 @ 7.5", "+2.1%", "4/5 two sessions".
  public let evidence: String

  public init(signal: DecisionSignal, evidence: String) {
    self.signal = signal
    self.evidence = evidence
  }
}

public enum DecisionAction: Sendable, Hashable {
  case increaseLoad(fromKg: Double, toKg: Double)
  case decreaseLoad(fromKg: Double, toKg: Double)
  case holdLoad(kg: Double)
  case addReps(atKg: Double)
  case firstTime(startKg: Double)
  case addSets(Int)
  case removeSets(Int)
  case swapExercise(fromID: String, toID: String)
  case changeRepRange(from: ClosedRange<Int>, to: ClosedRange<Int>)
  case lightSession
  case deload
}

public enum DecisionSubject: Sendable, Hashable {
  case exercise(id: String)
  case muscle(Muscle)
  case session
  case week
}

public struct Decision: Sendable, Identifiable, Hashable {
  public let subject: DecisionSubject
  public let action: DecisionAction
  public let causes: [DecisionCause]
  public let overridable: Bool

  private var subjectKey: String {
    switch subject {
    case .exercise(let id): return "exercise:\(id)"
    case .muscle(let m): return "muscle:\(m.rawValue)"
    case .session: return "session"
    case .week: return "week"
    }
  }

  private var actionKey: String {
    switch action {
    case .increaseLoad: return "increaseLoad"
    case .decreaseLoad: return "decreaseLoad"
    case .holdLoad: return "holdLoad"
    case .addReps: return "addReps"
    case .firstTime: return "firstTime"
    case .addSets: return "addSets"
    case .removeSets: return "removeSets"
    case .swapExercise: return "swapExercise"
    case .changeRepRange: return "changeRepRange"
    case .lightSession: return "lightSession"
    case .deload: return "deload"
    }
  }

  public var id: String { "\(subjectKey)#\(actionKey)" }

  /// Causes joined with " · ", already localized.
  public var reason: String {
    causes.map { cause in
      cause.evidence.isEmpty ? cause.signal.label : "\(cause.signal.label): \(cause.evidence)"
    }.joined(separator: " · ")
  }

  /// One line, no units guesswork: the caller passes a formatter for weights.
  public func headline(name: String, weight: (Double) -> String) -> String {
    switch action {
    case .increaseLoad(_, let toKg): return "Increase \(name) to \(weight(toKg))"
    case .decreaseLoad(_, let toKg): return "Decrease \(name) to \(weight(toKg))"
    case .holdLoad(let kg): return "Hold \(name) at \(weight(kg))"
    case .addReps(let atKg): return "Add reps to \(name) at \(weight(atKg))"
    case .firstTime(let startKg): return "Start \(name) at \(weight(startKg))"
    case .addSets(let n): return "Add \(n) \(n == 1 ? "set" : "sets") to \(name)"
    case .removeSets(let n): return "Remove \(n) \(n == 1 ? "set" : "sets") from \(name)"
    case .swapExercise: return "Swap \(name) for a substitute"
    case .changeRepRange(_, let to): return "Change \(name) to \(to.lowerBound)–\(to.upperBound) reps"
    case .lightSession: return "Go light this session"
    case .deload: return "Deload this week"
    }
  }

  /// The change alone, for a compact row where the exercise name is already shown.
  /// "24 kg", "+2.5 kg", "−5 kg", "9 reps", "−1 set".
  public func shortValue(weight: (Double) -> String) -> String {
    switch action {
    case .increaseLoad(let from, let to): return "+" + weight(to - from)
    case .decreaseLoad(let from, let to): return "−" + weight(from - to)
    case .holdLoad(let kg): return weight(kg)
    case .addReps(let atKg): return weight(atKg)
    case .firstTime(let startKg): return weight(startKg)
    case .addSets(let n): return "+\(n) \(n == 1 ? "set" : "sets")"
    case .removeSets(let n): return "−\(n) \(n == 1 ? "set" : "sets")"
    case .swapExercise: return String(localized: "swap", bundle: ForgeCoreResources.bundle)
    case .changeRepRange(_, let to): return "\(to.lowerBound)–\(to.upperBound)"
    case .lightSession: return String(localized: "light", bundle: ForgeCoreResources.bundle)
    case .deload: return String(localized: "deload", bundle: ForgeCoreResources.bundle)
    }
  }

  public init(subject: DecisionSubject, action: DecisionAction, causes: [DecisionCause], overridable: Bool) {
    self.subject = subject
    self.action = action
    self.causes = causes
    self.overridable = overridable
  }
}

public enum DecisionOverride: String, Sendable, CaseIterable {
  case keepOriginal, easier, harder

  public var title: String {
    switch self {
    case .keepOriginal: return String(localized: "Keep original", bundle: ForgeCoreResources.bundle)
    case .easier: return String(localized: "Make easier", bundle: ForgeCoreResources.bundle)
    case .harder: return String(localized: "Make harder", bundle: ForgeCoreResources.bundle)
    }
  }
}

public extension Decision {
  /// One step in the asked direction. `keepOriginal` returns the decision unchanged with a `userOverride` cause.
  func applying(_ override: DecisionOverride) -> Decision {
    // Half-kilo steps: an override must still land on a weight you can actually load.
    func round2(_ x: Double) -> Double { (x * 2).rounded() / 2 }
    var action = self.action
    switch override {
    case .keepOriginal:
      break
    case .easier:
      switch action {
      case .increaseLoad(let fromKg, let toKg):
        let easier = round2(toKg * 0.95)
        action = easier <= fromKg ? .holdLoad(kg: fromKg) : .increaseLoad(fromKg: fromKg, toKg: easier)
      case .decreaseLoad(let fromKg, let toKg):
        action = .decreaseLoad(fromKg: fromKg, toKg: round2(toKg * 0.95))
      case .holdLoad(let kg):
        action = .decreaseLoad(fromKg: kg, toKg: round2(kg * 0.95))
      case .addSets:
        action = .addSets(0)  // drop the added sets
      case .addReps(let atKg):
        action = .holdLoad(kg: atKg)
      case .firstTime(let startKg):
        action = .firstTime(startKg: round2(startKg * 0.95))
      default:
        break
      }
    case .harder:
      switch action {
      case .increaseLoad(let fromKg, let toKg):
        action = .increaseLoad(fromKg: fromKg, toKg: round2(toKg * 1.05))
      case .decreaseLoad(let fromKg, let toKg):
        let harder = round2(toKg * 1.05)
        action = harder >= fromKg ? .holdLoad(kg: fromKg) : .decreaseLoad(fromKg: fromKg, toKg: harder)
      case .holdLoad(let kg):
        action = .increaseLoad(fromKg: kg, toKg: round2(kg * 1.025))
      case .removeSets:
        action = .removeSets(0)  // keep the sets
      case .addReps(let atKg):
        action = .increaseLoad(fromKg: atKg, toKg: round2(atKg * 1.025))
      case .firstTime(let startKg):
        action = .firstTime(startKg: round2(startKg * 1.05))
      default:
        break
      }
    }
    var causes = self.causes
    causes.append(DecisionCause(signal: .userOverride, evidence: String(localized: "you asked", bundle: ForgeCoreResources.bundle)))
    return Decision(subject: subject, action: action, causes: causes, overridable: overridable)
  }
}
