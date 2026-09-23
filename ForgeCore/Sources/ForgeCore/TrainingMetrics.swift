import Foundation

/// One logged set as the metrics read it; `eligible` is the app's analysis-eligible decision.
public struct MetricSet: Sendable, Equatable {
  public var exerciseID: String
  public var date: Date
  public var weightKg: Double
  public var reps: Int
  public var storedRPE: Double
  public var effortReported: Bool
  public var eligible: Bool

  public init(
    exerciseID: String,
    date: Date,
    weightKg: Double,
    reps: Int,
    storedRPE: Double,
    effortReported: Bool,
    eligible: Bool
  ) {
    self.exerciseID = exerciseID
    self.date = date
    self.weightKg = weightKg
    self.reps = reps
    self.storedRPE = storedRPE
    self.effortReported = effortReported
    self.eligible = eligible
  }
}

public enum TrainingMetrics {
  /// Reporting weeks are ISO weeks (Monday first) in `timeZone`.
  public static func reportingCalendar(timeZone: TimeZone = .current) -> Calendar {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = timeZone
    return calendar
  }

  /// The half-open reporting week [start, end) that contains `date`.
  public static func reportingWeek(containing date: Date, calendar: Calendar) -> DateInterval {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    let start = calendar.date(from: components)!
    let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
    return DateInterval(start: start, end: end)
  }

  /// Half-open membership: start <= date < end.
  public static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
    interval.start <= date && date < interval.end
  }

  public static func sets(_ sets: [MetricSet], in interval: DateInterval?, scope: MetricScope) -> [MetricSet] {
    sets.filter { set in
      (scope == .analysisEligible ? set.eligible : true)
        && (interval.map { contains($0, set.date) } ?? true)
    }
  }

  /// Σ weightKg × reps.
  public static func volume(_ sets: [MetricSet]) -> Double {
    sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  public struct EffortCoverage: Equatable, Sendable {
    public let reported: Int
    public let total: Int
    public let mean: Double?
  }

  /// Reported RPE only; an unreported set counts toward `total`, never toward the mean.
  public static func effortCoverage(_ sets: [MetricSet]) -> EffortCoverage {
    let reported = sets.filter(\.effortReported)
    let mean = reported.isEmpty
      ? nil
      : reported.map(\.storedRPE).reduce(0, +) / Double(reported.count)
    return EffortCoverage(reported: reported.count, total: sets.count, mean: mean)
  }

  public struct WeekBin: Equatable, Sendable {
    public let start: Date
    public let count: Int
    public let volume: Double
    public let covered: Bool
  }

  /// Weeks ending by coverageStart are covered == false: known-empty, not missing history.
  public static func weeklyBins(
    _ sets: [MetricSet],
    weeks: Int,
    now: Date,
    calendar: Calendar,
    scope: MetricScope,
    hardSetsOnly: Bool,
    coverageStart: Date?
  ) -> [WeekBin] {
    let currentStart = reportingWeek(containing: now, calendar: calendar).start
    return (0..<weeks).reversed().map { offset in
      let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart)!
      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
      var members = Self.sets(sets, in: DateInterval(start: start, end: end), scope: scope)
      if hardSetsOnly {
        members = members.filter { $0.storedRPE >= 6 }
      }
      let covered = coverageStart.map { end > $0 } ?? false
      return WeekBin(start: start, count: members.count, volume: volume(members), covered: covered)
    }
  }

  /// Mean of `count` over covered bins, with its denominator; nil when no bin is covered.
  public static func averageCount(_ bins: [WeekBin]) -> (mean: Double, weeks: Int)? {
    let covered = bins.filter(\.covered)
    guard !covered.isEmpty else { return nil }
    let total = covered.map(\.count).reduce(0, +)
    return (Double(total) / Double(covered.count), covered.count)
  }

  public struct LiftEstimate: Equatable, Sendable {
    public let exerciseID: String
    public let e1RM: Double
  }

  /// Best Epley estimate among `scope` sets inside `interval` (nil = all time), optionally for one exercise.
  public static func bestEstimate(
    _ sets: [MetricSet],
    scope: MetricScope,
    in interval: DateInterval?,
    exerciseID: String?
  ) -> LiftEstimate? {
    var candidates = Self.sets(sets, in: interval, scope: scope)
    if let exerciseID {
      candidates = candidates.filter { $0.exerciseID == exerciseID }
    }
    let best = candidates.max { lhs, rhs in
      Strength.epley(weightKg: lhs.weightKg, reps: lhs.reps)
        < Strength.epley(weightKg: rhs.weightKg, reps: rhs.reps)
    }
    guard let best else { return nil }
    return LiftEstimate(
      exerciseID: best.exerciseID,
      e1RM: Strength.epley(weightKg: best.weightKg, reps: best.reps))
  }
}
