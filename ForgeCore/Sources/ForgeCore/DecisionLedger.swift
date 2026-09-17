import Foundation

public extension DecisionSignal {
  /// snake_case reason code for payloads and logs: "rpe_below_target".
  var code: String {
    switch self {
    case .rpeBelowTarget: return "rpe_below_target"
    case .rpeAboveTarget: return "rpe_above_target"
    case .repsAtTopOfRange: return "reps_at_top_of_range"
    case .repsBelowRange: return "reps_below_range"
    case .completedAllSets: return "completed_all_sets"
    case .e1rmUp: return "e1rm_up"
    case .e1rmFlat: return "e1rm_flat"
    case .e1rmDown: return "e1rm_down"
    case .sorenessHigh: return "soreness_high"
    case .readinessLow: return "readiness_low"
    case .readinessNormal: return "readiness_normal"
    case .readinessHigh: return "readiness_high"
    case .sleepShort: return "sleep_short"
    case .volumeBelowMEV: return "volume_below_mev"
    case .volumeAboveMRV: return "volume_above_mrv"
    case .missedSessions: return "missed_sessions"
    case .plateau: return "plateau"
    case .firstExposure: return "first_exposure"
    case .timeBudget: return "time_budget"
    case .equipmentMissing: return "equipment_missing"
    case .deloadWeek: return "deload_week"
    case .userOverride: return "user_override"
    }
  }
}

public struct DecisionRecord: Codable, Sendable, Identifiable, Equatable {
  public let id: String
  public let date: Date
  public let type: String            // "load_change", "volume_change", "swap", "session", "plateau"
  public let exerciseID: String?
  public let muscle: String?
  public let fromValue: Double?      // 64
  public let toValue: Double?        // 65
  public let reasonCodes: [String]   // ["completed_all_sets", "rpe_below_target", "readiness_normal"]
  public let evidence: [String]      // ["80 kg × 8 @ 7.5", "+2.1%", "readiness 82"]
  public let humanSummary: String    // one plain sentence, localized

  public init(id: String, date: Date, type: String, exerciseID: String?, muscle: String?,
              fromValue: Double?, toValue: Double?, reasonCodes: [String], evidence: [String], humanSummary: String) {
    self.id = id
    self.date = date
    self.type = type
    self.exerciseID = exerciseID
    self.muscle = muscle
    self.fromValue = fromValue
    self.toValue = toValue
    self.reasonCodes = reasonCodes
    self.evidence = evidence
    self.humanSummary = humanSummary
  }

  /// Built from a Decision plus the display helpers the app owns.
  public static func from(_ decision: Decision, date: Date, name: String, weight: (Double) -> String) -> DecisionRecord {
    let type: String
    if decision.causes.contains(where: { $0.signal == .plateau }) {
      type = "plateau"
    } else {
      switch decision.action {
      case .increaseLoad, .decreaseLoad, .holdLoad, .addReps, .firstTime, .changeRepRange: type = "load_change"
      case .addSets, .removeSets: type = "volume_change"
      case .swapExercise: type = "swap"
      case .lightSession, .deload: type = "session"
      }
    }

    let exerciseID: String?
    let muscle: String?
    switch decision.subject {
    case .exercise(let id): exerciseID = id; muscle = nil
    case .muscle(let m): muscle = m.rawValue; exerciseID = nil
    case .session, .week: exerciseID = nil; muscle = nil
    }

    let fromValue: Double?
    let toValue: Double?
    switch decision.action {
    case .increaseLoad(let f, let t): fromValue = f; toValue = t
    case .decreaseLoad(let f, let t): fromValue = f; toValue = t
    case .holdLoad(let kg): fromValue = kg; toValue = kg
    case .addReps(let atKg): fromValue = atKg; toValue = nil
    case .firstTime(let startKg): fromValue = nil; toValue = startKg
    default: fromValue = nil; toValue = nil
    }

    return DecisionRecord(
      id: decision.id,
      date: date,
      type: type,
      exerciseID: exerciseID,
      muscle: muscle,
      fromValue: fromValue,
      toValue: toValue,
      reasonCodes: decision.causes.map { $0.signal.code },
      evidence: decision.causes.map { $0.evidence },
      humanSummary: decision.headline(name: name, weight: weight))
  }
}

public enum DecisionLedger {
  /// Compact JSON for the coach payload: newest first, at most `limit`.
  public static func payload(_ records: [DecisionRecord], limit: Int = 12) -> String {
    let sorted = records.sorted { $0.date > $1.date }
    let limited = Array(sorted.prefix(max(0, limit)))
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(limited), let json = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return json
  }

  /// The record that explains a given exercise's current prescription, if any.
  public static func latest(for exerciseID: String, in records: [DecisionRecord]) -> DecisionRecord? {
    records.filter { $0.exerciseID == exerciseID }.max { $0.date < $1.date }
  }
}
