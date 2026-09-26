import ForgeCore
import Foundation

/// One completed, verified workout of one lift: its best comparable set.
struct LiftWorkout: Identifiable, Hashable {
  let date: Date
  /// Estimated max (Epley) of the best set, in kg.
  let e1rmKg: Double
  let weightKg: Double
  let reps: Int
  /// 1-based training block of the session.
  let block: Int
  /// A record event exists for this lift in this session.
  let isRecord: Bool
  var id: Date { date }
}

/// The window a trend is read over.
enum TrendRange: Hashable {
  case block(Int)
  case all
}

enum TrendStatus: Equatable {
  case stronger, holding, dipped
}

/// One lift's workouts, oldest first and never empty.
struct LiftTrend: Identifiable {
  let exercise: Exercise
  let area: BodyArea
  let workouts: [LiftWorkout]

  var id: String { exercise.id }
  var first: LiftWorkout { workouts[0] }
  var latest: LiftWorkout { workouts[workouts.count - 1] }
  var latestIsRecord: Bool { latest.isRecord }

  func workouts(in range: TrendRange) -> [LiftWorkout] {
    switch range {
    case .all: return workouts
    case .block(let n): return workouts.filter { $0.block == n }
    }
  }

  /// Newest minus oldest estimated max in the range, kg; nil with fewer than two workouts.
  func changeKg(in range: TrendRange) -> Double? {
    let scoped = workouts(in: range)
    return scoped.count >= 2 ? scoped.last!.e1rmKg - scoped.first!.e1rmKg : nil
  }

  /// Stronger at +0.5 kg or more, dipped at -0.5 kg or less, else holding.
  func status(in range: TrendRange) -> TrendStatus? {
    guard let change = changeKg(in: range) else { return nil }
    if change >= 0.5 { return .stronger }
    if change <= -0.5 { return .dipped }
    return .holding
  }
}
