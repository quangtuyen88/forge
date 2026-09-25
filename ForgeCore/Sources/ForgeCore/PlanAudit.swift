import Foundation

public struct AuditSet: Sendable {
  public let exerciseID: String
  public let date: Date
  public let weightKg: Double
  public let reps: Int
  public let rpe: Double?

  public init(exerciseID: String, date: Date, weightKg: Double, reps: Int, rpe: Double? = nil) {
    self.exerciseID = exerciseID
    self.date = date
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
  }
}

public struct PlanAudit: Sendable {
  public struct LiftTrend: Sendable, Identifiable {
    public enum Direction: Sendable { case progressing, flat, declining, tooFewSessions }
    public let exercise: Exercise
    public let direction: Direction
    public let firstE1RM: Double
    public let latestE1RM: Double
    public let sessions: Int
    public var id: String { exercise.id }
    /// Percent change first → latest, 0 when fewer than two sessions.
    public var changePercent: Double {
      sessions < 2 ? 0 : (firstE1RM > 0 ? (latestE1RM - firstE1RM) / firstE1RM * 100 : 0)
    }
  }

  public struct MuscleVolume: Sendable, Identifiable {
    public enum Verdict: Sendable { case under, inRange, over, untrained }
    public let muscle: Muscle
    public let setsPerWeek: Double
    public let mev: Int
    public let mrv: Int
    public let verdict: Verdict
    public var id: Muscle { muscle }
  }

  public let weeks: Int
  public let sessionCount: Int
  public let sessionsPerWeek: Double
  public let trends: [LiftTrend]
  public let muscles: [MuscleVolume]
  public let headline: String
}

public enum PlanAuditEngine {
  public static func audit(sets: [AuditSet], recoveryReduced: Bool, now: Date = .now) -> PlanAudit {
    let cal = Calendar.current
    let window = 8 * 7 * 24 * 3600.0
    let recent = sets.filter { $0.date > now.addingTimeInterval(-window) && $0.date <= now }

    guard !recent.isEmpty else {
      return PlanAudit(
        weeks: 0, sessionCount: 0, sessionsPerWeek: 0,
        trends: [], muscles: [],
        headline: String(localized: "No recent training data.", bundle: ForgeCoreResources.bundle))
    }

    let sessionCount = Set(recent.map { cal.startOfDay(for: $0.date) }).count
    let weeks = Set(recent.map { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }).count
    let weeksD = Double(weeks)

    var trends: [PlanAudit.LiftTrend] = []
    for (id, sets) in Dictionary(grouping: recent, by: \.exerciseID) {
      guard let exercise = ExerciseDB.find(id) else { continue }
      let byDay = Dictionary(grouping: sets, by: { cal.startOfDay(for: $0.date) })
      let daysSorted = byDay.keys.sorted()
      let bestPerDay = daysSorted.map { day in
        byDay[day]!.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()!
      }
      let sessions = daysSorted.count
      guard sessions >= 2, let first = bestPerDay.first, let latest = bestPerDay.last else {
        trends.append(PlanAudit.LiftTrend(
          exercise: exercise, direction: .tooFewSessions,
          firstE1RM: bestPerDay.first ?? 0, latestE1RM: bestPerDay.last ?? 0, sessions: sessions))
        continue
      }
      let change = first > 0 ? (latest - first) / first * 100 : 0
      let direction: PlanAudit.LiftTrend.Direction = change >= 3 ? .progressing : (change <= -3 ? .declining : .flat)
      trends.append(PlanAudit.LiftTrend(exercise: exercise, direction: direction, firstE1RM: first, latestE1RM: latest, sessions: sessions))
    }
    let trendOrder: [PlanAudit.LiftTrend.Direction] = [.progressing, .flat, .declining, .tooFewSessions]
    trends.sort { trendOrder.firstIndex(of: $0.direction)! < trendOrder.firstIndex(of: $1.direction)! }

    var muscleSets: [Muscle: Double] = [:]
    for set in recent {
      guard let exercise = ExerciseDB.find(set.exerciseID) else { continue }
      muscleSets[exercise.primary, default: 0] += 1
      if exercise.isCompound {
        for m in exercise.synergists { muscleSets[m, default: 0] += 0.5 }
      }
    }
    var muscles: [PlanAudit.MuscleVolume] = []
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: recoveryReduced) else { continue }
      let total = muscleSets[muscle] ?? 0
      let perWeek = total / weeksD
      let floor = l.floor(recoveryReduced: recoveryReduced)
      let verdict: PlanAudit.MuscleVolume.Verdict =
        total == 0 ? .untrained
        : perWeek < Double(floor) ? .under
        : perWeek > Double(l.mrv) ? .over
        : .inRange
      muscles.append(PlanAudit.MuscleVolume(muscle: muscle, setsPerWeek: perWeek, mev: floor, mrv: l.mrv, verdict: verdict))
    }
    let verdictOrder: [PlanAudit.MuscleVolume.Verdict] = [.untrained, .under, .over, .inRange]
    muscles.sort { verdictOrder.firstIndex(of: $0.verdict)! < verdictOrder.firstIndex(of: $1.verdict)! }

    let progressing = trends.filter { $0.direction == .progressing }.count
    let stalled = trends.count - progressing
    let headline = String(localized: "\(progressing) lifts progressing, \(stalled) stalled.", bundle: ForgeCoreResources.bundle)

    return PlanAudit(
      weeks: weeks, sessionCount: sessionCount, sessionsPerWeek: Double(sessionCount) / weeksD,
      trends: trends, muscles: muscles, headline: headline)
  }
}
