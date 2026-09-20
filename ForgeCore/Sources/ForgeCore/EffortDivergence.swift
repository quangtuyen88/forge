import Foundation

// MARK: - What unreported effort is worth
//
// `SetLog.rpe` always holds a number: the plan target sits in the field until the lifter
// rates the set. The display layer now refuses to read that as an observation. The engine
// still reads it — `Autoregulation.signals` compares `set.rpe` against the target — so a
// set nobody rated agrees with the plan by construction, and the loop closes with no
// feedback in it.
//
// This type changes no rule. It runs the SAME rule twice — once over the field as stored,
// once with unreported sets dropped — and reports where the two disagree, so the decision
// about what progression should do with no effort signal is made against a measured delta
// instead of an argument.

/// One muscle whose volume signal depends on effort the lifter never reported.
public struct EffortDivergenceEntry: Sendable, Equatable {
  public let muscle: Muscle
  /// What the engine concludes today, reading the field as stored.
  public let current: VolumeSignal
  /// What the same rule concludes when only rated sets are read. Nil when dropping the
  /// unrated sets leaves nothing to judge — an honest "no signal", not a third verdict.
  public let honest: VolumeSignal?
  /// How many of the muscle's counting sets carried a real report.
  public let ratedSets: Int
  public let totalSets: Int

  public init(
    muscle: Muscle, current: VolumeSignal, honest: VolumeSignal?, ratedSets: Int,
    totalSets: Int
  ) {
    self.muscle = muscle
    self.current = current
    self.honest = honest
    self.ratedSets = ratedSets
    self.totalSets = totalSets
  }

  /// True when reading only rated effort would have produced a different conclusion.
  public var diverges: Bool { honest != current }
}

public struct EffortDivergenceReport: Sendable, Equatable {
  public let entries: [EffortDivergenceEntry]

  public init(entries: [EffortDivergenceEntry]) {
    self.entries = entries
  }

  public var diverging: [EffortDivergenceEntry] { entries.filter(\.diverges) }
  public var isClean: Bool { diverging.isEmpty }
  /// Sets across the whole report that the engine read as effort without a report behind it.
  public var unratedSetsRead: Int {
    entries.reduce(0) { $0 + ($1.totalSets - $1.ratedSets) }
  }
}

public enum EffortDivergence {
  /// Runs `Autoregulation.signals` over the performances as stored and again over the same
  /// performances with unreported sets removed. Pure: no clock, no storage, nothing applied.
  public static func report(_ performances: [ExercisePerformance]) -> EffortDivergenceReport {
    let current = Autoregulation.signals(performances)
    let rated = performances.map { performance in
      ExercisePerformance(
        exercise: performance.exercise,
        repRange: performance.repRange,
        targetRPE: performance.targetRPE,
        sets: performance.sets.filter(\.effortReported))
    }
    let honest = Autoregulation.signals(rated)

    var counts: [Muscle: (rated: Int, total: Int)] = [:]
    for performance in performances {
      let muscle = performance.exercise.primary
      let counting = performance.sets.filter(\.countsTowardVolume)
      var entry = counts[muscle] ?? (0, 0)
      entry.rated += counting.filter(\.effortReported).count
      entry.total += counting.count
      counts[muscle] = entry
    }

    let entries = current.keys.sorted { $0.rawValue < $1.rawValue }.compactMap {
      muscle -> EffortDivergenceEntry? in
      guard let currentSignal = current[muscle] else { return nil }
      let count = counts[muscle] ?? (0, 0)
      return EffortDivergenceEntry(
        muscle: muscle, current: currentSignal, honest: honest[muscle],
        ratedSets: count.rated, totalSets: count.total)
    }
    return EffortDivergenceReport(entries: entries)
  }
}
