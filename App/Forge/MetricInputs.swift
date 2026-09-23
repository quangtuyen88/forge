import Foundation
import ForgeCore

extension Array where Element == WorkoutSession {
  /// Completed sessions' sets as metric inputs; `eligible` follows `analysisSets(in: scopes)`.
  func metricSets(scopes: Set<SetAnalysisScope> = Set(SetAnalysisScope.allCases)) -> [MetricSet] {
    flatMap { session -> [MetricSet] in
      guard session.completed else { return [] }
      let eligible = session.analysisSets(in: scopes)
      return session.sets.map { set in
        MetricSet(
          exerciseID: set.exerciseID,
          date: session.date,
          weightKg: set.weightKg,
          reps: set.reps,
          storedRPE: set.rpe,
          effortReported: set.effortReported,
          eligible: eligible.contains { $0 === set })
      }
    }
  }

  /// The first completed session's date: where recorded history starts.
  var coverageStart: Date? {
    filter(\.completed).map(\.date).min()
  }
}
