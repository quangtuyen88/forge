import Foundation

public struct PlannedSetCoordinate: Hashable, Sendable {
  public let exerciseID: String
  public let setIndex: Int

  public init(exerciseID: String, setIndex: Int) {
    self.exerciseID = exerciseID
    self.setIndex = setIndex
  }
}

public enum WorkoutProgressPolicy {
  public static func remainingPlannedSets(
    planned: Set<PlannedSetCoordinate>,
    logged: Set<PlannedSetCoordinate>
  ) -> Int {
    max(0, planned.count - planned.intersection(logged).count)
  }
}

public enum RecoveryPresentation: Equatable, Sendable {
  case empty
  case collecting(sampleCount: Int, windowDays: Int)
  case assessed(summary: String, sampleCount: Int, windowDays: Int)
}

public enum RecoveryPresentationPolicy {
  public static let minimumAssessmentSamples = 3

  public static func presentation(
    sampleCount: Int,
    windowDays: Int = 7,
    assessedSummary: String
  ) -> RecoveryPresentation {
    guard sampleCount > 0 else { return .empty }
    guard sampleCount >= minimumAssessmentSamples else {
      return .collecting(sampleCount: sampleCount, windowDays: windowDays)
    }
    return .assessed(summary: assessedSummary, sampleCount: sampleCount, windowDays: windowDays)
  }
}

public enum BalancePresentation: Equatable, Sendable {
  case collecting(sessionCount: Int, setCount: Int)
  case assessed(pushPull: Double?, upperLower: Double?, sessionCount: Int, setCount: Int)
}

public enum BalancePresentationPolicy {
  public static let minimumSessions = 3
  public static let minimumSets = 12

  public static func presentation(
    push: Double,
    pull: Double,
    upper: Double,
    lower: Double,
    sessionCount: Int,
    setCount: Int
  ) -> BalancePresentation {
    guard sessionCount >= minimumSessions, setCount >= minimumSets else {
      return .collecting(sessionCount: sessionCount, setCount: setCount)
    }
    return .assessed(
      pushPull: pull > 0 ? push / pull : nil,
      upperLower: lower > 0 ? upper / lower : nil,
      sessionCount: sessionCount,
      setCount: setCount)
  }
}

public enum ExperimentPresentation: Equatable, Sendable {
  case collecting(day: Int, totalDays: Int, comparableCount: Int)
  case result(delta: Double, comparableCount: Int)
  case inconclusive(reason: String, comparableCount: Int)
}

public enum ExperimentPresentationPolicy {
  public static func presentation(
    startedAt: Date,
    endsAt: Date,
    comparableCount: Int,
    baseline: Double,
    current: Double,
    isActive: Bool,
    now: Date = .now,
    calendar: Calendar = .current
  ) -> ExperimentPresentation {
    let totalDays = max(1, calendar.dateComponents([.day], from: startedAt, to: endsAt).day ?? 28)
    let elapsed = max(0, calendar.dateComponents([.day], from: startedAt, to: now).day ?? 0)
    if isActive && now < endsAt {
      return .collecting(
        day: min(totalDays, elapsed + 1), totalDays: totalDays, comparableCount: comparableCount)
    }
    guard comparableCount >= 2 else {
      return .inconclusive(
        reason: "Not enough comparable follow-up sets", comparableCount: comparableCount)
    }
    return .result(delta: current - baseline, comparableCount: comparableCount)
  }
}

public struct WeekStatusPresentation: Equatable, Sendable {
  public let recorded: Int
  public let planned: Int
  public let remaining: Int
  public let atRisk: Int

  public init(recorded: Int, planned: Int, remaining: Int, atRisk: Int) {
    self.recorded = recorded
    self.planned = planned
    self.remaining = remaining
    self.atRisk = atRisk
  }
}

public enum WeekStatusPolicy {
  public static func presentation(
    planned: Int,
    recorded: Int,
    daysLeft: Int,
    enrollmentDate: Date,
    now: Date = .now,
    calendar: Calendar = .current
  ) -> WeekStatusPresentation {
    let remaining = max(0, planned - recorded)
    let enrolledThisWeek = calendar.isDate(enrollmentDate, equalTo: now, toGranularity: .weekOfYear)
    let atRisk = enrolledThisWeek ? 0 : max(0, remaining - max(0, daysLeft))
    return WeekStatusPresentation(
      recorded: recorded, planned: planned, remaining: remaining, atRisk: atRisk)
  }
}

// MARK: metric scope

/// Which recorded sets a headline metric is allowed to count.
///
/// Today reports *all recorded* work so the lifter sees every set they did.
/// Progress reports *analysis eligible* work so trends, records and reports are never
/// built from sets the plausibility guard could not verify. The difference is
/// intentional — the label has to name the scope it used.
public enum MetricScope: String, Equatable, Sendable, CaseIterable {
  case allRecorded
  case analysisEligible
}

public struct MetricScopeDescriptor: Equatable, Sendable {
  public let scope: MetricScope
  public let label: String
  public let caption: String
  /// True when unverified or suspect sets are dropped from the number.
  public let excludesUnverifiedSets: Bool
  /// True when the number may drive trends, records and reports.
  public let drivesAnalysis: Bool

  public init(
    scope: MetricScope,
    label: String,
    caption: String,
    excludesUnverifiedSets: Bool,
    drivesAnalysis: Bool
  ) {
    self.scope = scope
    self.label = label
    self.caption = caption
    self.excludesUnverifiedSets = excludesUnverifiedSets
    self.drivesAnalysis = drivesAnalysis
  }
}

public enum MetricScopePolicy {
  public static func descriptor(for scope: MetricScope) -> MetricScopeDescriptor {
    switch scope {
    case .allRecorded:
      return MetricScopeDescriptor(
        scope: .allRecorded,
        label: String(localized: "All recorded", bundle: ForgeCoreResources.bundle),
        caption: String(
          localized: "Everything you logged, including sets the plausibility check did not verify",
          bundle: ForgeCoreResources.bundle),
        excludesUnverifiedSets: false,
        drivesAnalysis: false)
    case .analysisEligible:
      return MetricScopeDescriptor(
        scope: .analysisEligible,
        label: String(localized: "Analysis eligible", bundle: ForgeCoreResources.bundle),
        caption: String(
          localized: "Only sets the plausibility check verified — what trends and records use",
          bundle: ForgeCoreResources.bundle),
        excludesUnverifiedSets: true,
        drivesAnalysis: true)
    }
  }

  public static func descriptors() -> [MetricScopeDescriptor] {
    MetricScope.allCases.map(descriptor(for:))
  }

  /// A one-line qualifier naming how much of the recorded work the analysis-eligible
  /// scope could keep. `nil` when nothing was excluded, so an honest number stays quiet.
  public static func qualifier(
    scope: MetricScope,
    recordedSetCount: Int,
    analysisEligibleSetCount: Int
  ) -> String? {
    guard scope == .analysisEligible else { return nil }
    let kept = max(0, min(analysisEligibleSetCount, recordedSetCount))
    guard recordedSetCount > kept else { return nil }
    return String(
      localized: "\(kept) of \(recordedSetCount) sets passed the plausibility check",
      bundle: ForgeCoreResources.bundle)
  }
}
