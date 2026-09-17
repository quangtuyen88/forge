import Foundation

public struct PlateauFinding: Sendable, Identifiable {
  public let exerciseID: String
  public let exposures: Int
  public let decision: Decision
  public var id: String { exerciseID }
}

public enum PlateauRescue {
  public static let minExposures = 4

  private static func heavier(_ r: ClosedRange<Int>) -> ClosedRange<Int> {
    switch "\(r.lowerBound)-\(r.upperBound)" {
    case "12-15", "10-15": return 8...12
    case "8-12": return 5...8
    case "6-10": return 4...6
    case "5-8": return 3...6
    case "4-6": return 3...5
    case "3-6", "3-5": return 1...3
    default: return max(1, r.lowerBound - 2) ... max(1, r.upperBound - 4)
    }
  }

  /// Nil when the lift is not stalled. Picks ONE intervention, never a menu.
  public static func rescue(exerciseID: String, history: [AuditSet], repRange: ClosedRange<Int>,
                            weeklySets: Double, landmarks: VolumeLandmarks?, sorenessHigh: Bool,
                            recentRPEOverTarget: Bool, equipment: Set<Equipment>,
                            injuries: Set<InjuryFlag>) -> PlateauFinding? {
    let cal = Calendar.current
    let relevant = history.filter { $0.exerciseID == exerciseID }
    let byDay = Dictionary(grouping: relevant, by: { cal.startOfDay(for: $0.date) })
    let days = byDay.keys.sorted()
    let bests = days.map { day in byDay[day]!.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()! }
    let exposures = bests.count
    guard exposures >= minExposures else { return nil }

    let window = Array(bests.suffix(minExposures))
    let first = window.first!
    let stalled = !window.dropFirst().contains { $0 > first * 1.01 }
    guard stalled else { return nil }

    // 1. Fatigue first.
    if sorenessHigh || recentRPEOverTarget {
      var causes: [DecisionCause] = []
      if sorenessHigh { causes.append(DecisionCause(signal: .sorenessHigh, evidence: "")) }
      if recentRPEOverTarget { causes.append(DecisionCause(signal: .rpeAboveTarget, evidence: "")) }
      return PlateauFinding(exerciseID: exerciseID, exposures: exposures,
        decision: Decision(subject: .exercise(id: exerciseID), action: .deload, causes: causes, overridable: true))
    }

    // 2. Under-trained volume.
    if let l = landmarks, weeklySets < Double(l.mev) {
      return PlateauFinding(exerciseID: exerciseID, exposures: exposures,
        decision: Decision(subject: .exercise(id: exerciseID), action: .addSets(1),
                           causes: [DecisionCause(signal: .volumeBelowMEV, evidence: "")], overridable: true))
    }

    // 3. Over-trained volume.
    if let l = landmarks, weeklySets > Double(l.mrv) {
      return PlateauFinding(exerciseID: exerciseID, exposures: exposures,
        decision: Decision(subject: .exercise(id: exerciseID), action: .removeSets(1),
                           causes: [DecisionCause(signal: .volumeAboveMRV, evidence: "")], overridable: true))
    }

    // 4. Swap exercise for a fresh same-pattern stimulus.
    if exposures >= 6, let exercise = ExerciseDB.find(exerciseID),
       let replacement = ExerciseDB.replacements(for: exercise, equipment: equipment, injuries: injuries, limit: 1).first {
      return PlateauFinding(exerciseID: exerciseID, exposures: exposures,
        decision: Decision(subject: .exercise(id: exerciseID), action: .swapExercise(fromID: exerciseID, toID: replacement.id),
                           causes: [DecisionCause(signal: .plateau, evidence: "")], overridable: true))
    }

    // 5. Heavier rep range.
    let to = heavier(repRange)
    return PlateauFinding(exerciseID: exerciseID, exposures: exposures,
      decision: Decision(subject: .exercise(id: exerciseID), action: .changeRepRange(from: repRange, to: to),
                         causes: [DecisionCause(signal: .plateau, evidence: "")], overridable: true))
  }
}
