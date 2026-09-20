import Foundation

// MARK: - Input

/// Where a committed decision applies. Mirrors the plan's decision scope without
/// importing any persistence layer.
public enum WeekBriefScope: String, Sendable, Equatable, CaseIterable {
  case nextSet, futureSession, futureWeek
}

/// One already-committed change fact. Pure value: it carries the machine reason code,
/// never a human interpretation of that code.
public struct WeekBriefFact: Sendable, Equatable, Identifiable {
  public let id: String
  public let exerciseID: String?
  public let muscleID: String?
  public let reasonCode: String
  public let fromValue: Double?
  public let toValue: Double?
  public let scope: WeekBriefScope
  /// The exercise's display name, when the caller has one. Carried so the brief can say
  /// *what* changed instead of announcing that something was committed.
  public let exerciseName: String?

  public init(
    id: String,
    exerciseID: String?,
    muscleID: String?,
    reasonCode: String,
    fromValue: Double?,
    toValue: Double?,
    scope: WeekBriefScope,
    exerciseName: String? = nil
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.muscleID = muscleID
    self.reasonCode = reasonCode
    self.fromValue = fromValue
    self.toValue = toValue
    self.scope = scope
    self.exerciseName = exerciseName
  }

  /// True when this fact records an actual before/after move, not an opening prescription.
  /// A starting target is not an improvement, and saying "changed" about one is a claim the
  /// record does not support.
  public var isRealChange: Bool {
    guard let from = fromValue, let to = toValue else { return false }
    return abs(from - to) > 0.0001
  }
}

/// Everything the builder may read. The brief does not depend on a clock, so no
/// `now` or `Calendar` is injected; `week` and `totalWeeks` are caller-supplied values.
public struct WeekBriefInput: Sendable, Equatable {
  /// The current week number (caller-computed, e.g. `profile.currentWeek`).
  public let week: Int
  public let totalWeeks: Int
  /// Whether the upcoming week is a deload week. Only when this is true may the brief
  /// say the block is reducing load.
  public let isDeload: Bool
  /// Planned day names for the upcoming week. Carried for the app layer (schedule
  /// display); statements are gated strictly on committed decision facts and the
  /// deload flag, never on the schedule alone, so an empty schedule never invents filler.
  public let upcomingDayNames: [String]
  public let facts: [WeekBriefFact]

  public init(
    week: Int,
    totalWeeks: Int,
    isDeload: Bool,
    upcomingDayNames: [String],
    facts: [WeekBriefFact]
  ) {
    self.week = week
    self.totalWeeks = totalWeeks
    self.isDeload = isDeload
    self.upcomingDayNames = upcomingDayNames
    self.facts = facts
  }
}

// MARK: - Output

public enum WeekBriefStatementKind: String, Sendable, Hashable, CaseIterable {
  case focus, change, unchanged

  public var label: String {
    switch self {
    case .focus: return String(localized: "Focus", bundle: ForgeCoreResources.bundle)
    case .change: return String(localized: "Change", bundle: ForgeCoreResources.bundle)
    case .unchanged: return String(localized: "Unchanged", bundle: ForgeCoreResources.bundle)
    }
  }
}

/// One brief line: a statement plus the committed decision ids that justify it.
public struct WeekBriefStatement: Sendable, Equatable {
  public let kind: WeekBriefStatementKind
  public let text: String
  public let decisionIDs: [String]

  public init(kind: WeekBriefStatementKind, text: String, decisionIDs: [String]) {
    self.kind = kind
    self.text = text
    self.decisionIDs = decisionIDs
  }
}

extension WeekBriefStatement: Identifiable {
  public var id: WeekBriefStatementKind { kind }
}

/// The brief: at most three statements — `focus`, optional `change`, optional
/// `unchanged`. All three are empty when there is nothing truthful to say.
public struct WeekBriefResult: Sendable, Equatable {
  public let focus: WeekBriefStatement?
  public let change: WeekBriefStatement?
  public let unchanged: WeekBriefStatement?

  public init(
    focus: WeekBriefStatement?,
    change: WeekBriefStatement?,
    unchanged: WeekBriefStatement?
  ) {
    self.focus = focus
    self.change = change
    self.unchanged = unchanged
  }

  public var isEmpty: Bool { focus == nil && change == nil && unchanged == nil }

  public var statements: [WeekBriefStatement] {
    [focus, change, unchanged].compactMap { $0 }
  }
}

// MARK: - Builder

/// Builds the forward-looking weekly brief.
///
/// Deterministic and side-effect free: identical input always yields identical output.
/// A statement is emitted only when a matching committed fact (or the deload flag)
/// exists; nothing is ever claimed about recovery being normal, and no cause is
/// invented. Unknown reason codes fall back to a generic, non-causal phrasing.
public enum WeekBrief {

  /// Reason codes reviewed as "the progression continues".
  private static let focusCodes: Set<String> = [
    "completed_all_sets", "reps_at_top_of_range", "rpe_below_target", "e1rm_up",
    "load.progression.rep_range_passed",
  ]

  /// Reason codes reviewed as "this stays the same".
  private static let unchangedCodes: Set<String> = [
    "e1rm_flat", "load.hold.target_met",
  ]

  /// Reason codes reviewed as "a material change was committed".
  private static let changeCodes: Set<String> = [
    "reps_below_range", "e1rm_down", "soreness_high", "readiness_low", "sleep_short",
    "volume_below_mev", "volume_above_mrv", "missed_sessions", "plateau", "time_budget",
    "equipment_missing", "user_override", "first_exposure",
    "load.reduction.effort_above_target", "volume.reduction.recovery_policy",
    "exercise.substitution.equipment", "schedule.change.user_request",
    "schedule.change.missed_session",
  ]

  /// Deload codes only speak the reducing-load line when the flag is actually set.
  private static let deloadCodes: Set<String> = [
    "deload_week", "plan.deload.scheduled", "plan.deload.early_policy",
  ]

  public static func build(_ input: WeekBriefInput) -> WeekBriefResult {
    var facts = input.facts
    if input.isDeload {
      // The deload flag is itself a committed plan fact; give it a stable identity.
      facts.append(
        WeekBriefFact(
          id: "week-\(input.week + 1)-deload",
          exerciseID: nil, muscleID: nil,
          reasonCode: "plan.deload.scheduled",
          fromValue: nil, toValue: nil, scope: .futureWeek))
    }
    // Deterministic regardless of the caller's ordering.
    facts.sort { $0.id < $1.id }

    var focusIDs: [String] = []
    var unchangedIDs: [String] = []
    var changeIDs: [String] = []
    var genericIDs: [String] = []

    for fact in facts {
      let code = fact.reasonCode
      if focusCodes.contains(code) {
        focusIDs.append(fact.id)
      } else if unchangedCodes.contains(code) {
        unchangedIDs.append(fact.id)
      } else if deloadCodes.contains(code) && input.isDeload {
        changeIDs.append(fact.id)
      } else if changeCodes.contains(code) {
        changeIDs.append(fact.id)
      } else {
        // Unknown or unreviewed code: fall back to generic, non-causal phrasing.
        genericIDs.append(fact.id)
      }
    }

    let focus: WeekBriefStatement? =
      focusIDs.isEmpty
      ? nil
      : WeekBriefStatement(
        kind: .focus,
        text: String(localized: "Keep the current progression.", bundle: ForgeCoreResources.bundle),
        decisionIDs: sortedUnique(focusIDs))

    let unchanged: WeekBriefStatement? =
      unchangedIDs.isEmpty
      ? nil
      : WeekBriefStatement(
        kind: .unchanged,
        text: String(
          localized: "Your remaining plan stays the same.", bundle: ForgeCoreResources.bundle),
        decisionIDs: sortedUnique(unchangedIDs))

    let change: WeekBriefStatement?
    if input.isDeload {
      change = WeekBriefStatement(
        kind: .change,
        text: String(localized: "This block is reducing load.", bundle: ForgeCoreResources.bundle),
        decisionIDs: sortedUnique(changeIDs + genericIDs))
    } else if !changeIDs.isEmpty {
      // Name the change. "A change to your plan was committed" describes a storage event,
      // not anything the lifter can act on — so when the facts carry an exercise and a real
      // before/after, the line says which lift moved and where to.
      let named = facts.first {
        changeIDs.contains($0.id) && $0.isRealChange && $0.exerciseName != nil
      }
      if let named, let from = named.fromValue, let to = named.toValue,
        let name = named.exerciseName
      {
        change = WeekBriefStatement(
          kind: .change,
          text: String(
            localized:
              "Next \(name): \(number(from)) → \(number(to)).",
            bundle: ForgeCoreResources.bundle),
          decisionIDs: sortedUnique(changeIDs + genericIDs))
      } else if let onlyNamed = facts.first(where: { changeIDs.contains($0.id) && $0.exerciseName != nil }),
        let name = onlyNamed.exerciseName
      {
        change = WeekBriefStatement(
          kind: .change,
          text: String(
            localized: "\(name) changes next session.", bundle: ForgeCoreResources.bundle),
          decisionIDs: sortedUnique(changeIDs + genericIDs))
      } else {
        // No exercise identity to name: say the scope honestly rather than inventing one.
        change = WeekBriefStatement(
          kind: .change,
          text: String(
            localized: "Your plan changed for next week. Open the changes to see what moved.",
            bundle: ForgeCoreResources.bundle),
          decisionIDs: sortedUnique(changeIDs + genericIDs))
      }
    } else if !genericIDs.isEmpty {
      // Unreviewed reason codes: the app knows something was recorded and nothing more.
      // Saying so is better than paraphrasing a code nobody has read.
      change = WeekBriefStatement(
        kind: .change,
        text: String(
          localized: "Your plan changed for next week. Open the changes to see what moved.",
          bundle: ForgeCoreResources.bundle),
        decisionIDs: sortedUnique(genericIDs))
    } else {
      change = nil
    }

    return WeekBriefResult(focus: focus, change: change, unchanged: unchanged)
  }

  /// Loads as the lifter reads them: no trailing zero on a whole number.
  private static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
  }

  private static func sortedUnique(_ ids: [String]) -> [String] {
    Array(Set(ids)).sorted()
  }
}
