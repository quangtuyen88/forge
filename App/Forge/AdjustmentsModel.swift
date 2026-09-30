import Foundation
import ForgeCore

/// Plain values for the Adjustments screen, built only from what the app recorded.
struct AdjustmentsModel {
  struct Step: Hashable {
    let week: Int        // program week (1...Mesocycle.weeks) the change landed in
    let delta: Double    // summed change of every entry of this lift in that week; never 0
  }
  struct Lane: Identifiable, Hashable {
    enum Unit: Hashable { case kg, sets }
    let exercise: Exercise
    let steps: [Step]    // one per week that had a change, oldest week first, only weeks inside `weeks`
    let total: Double    // sum of ALL changes of this lift inside the current block (may be < 0)
    let unit: Unit       // kg for load lanes, sets for volume lanes
    var id: String { exercise.id }
  }
  /// One applied change of the block and what it measured. Undo deletes the decision entry,
  /// so undone changes come from reverted ledger snapshots, not from surviving entries.
  struct AppliedChange: Identifiable {
    enum Outcome { case better, noChange, measuring, undone }
    let exerciseID: String
    let date: Date
    let outcome: Outcome
    var id: String { "\(exerciseID)|\(date.timeIntervalSince1970)" }
  }
  struct Other: Identifiable, Hashable {
    enum Status: Hashable { case applied, undone, notApplied }
    let id: String
    let title: String          // see rules below; never empty
    let date: Date
    let status: Status
    let fewerSets: Int?        // only for light-session rows when computable (see rules)
    let exerciseID: String?    // when the row is one lift's change, for the outcome word
  }

  let blockNumber: Int
  let currentWeek: Int
  let weeks: [Int]                 // columns, oldest first; last == currentWeek; at most 4
  let weekStarts: [Int: Date]
  let lanes: [Lane]
  let others: [Other]
  let changes: [AppliedChange]     // applied lift changes of the block, oldest first
  var isEmpty: Bool { lanes.isEmpty && others.isEmpty }
  var betterCount: Int { changes.filter { $0.outcome == .better }.count }
  var noChangeCount: Int { changes.filter { $0.outcome == .noChange }.count }
  var undoneCount: Int { changes.filter { $0.outcome == .undone }.count }
  var measuringCount: Int { changes.filter { $0.outcome == .measuring }.count }
  var measuredCount: Int { betterCount + noChangeCount + undoneCount }
  var earliestChangeDate: Date? { changes.map(\.date).min() }

  static func build(
    profile: UserProfile, sessions: [WorkoutSession], decisions: [DecisionLogEntry]
  ) -> AdjustmentsModel {
    let cal = Calendar.current
    let blockSessions = sessions
      .filter { !$0.tombstoned && $0.date >= profile.mesoStart }
      .sorted { $0.date < $1.date }
    let completed = blockSessions.filter(\.completed)
    let currentWeek = profile.currentWeek(sessions: sessions)
    let weeks = Array(max(1, currentWeek - 3)...currentWeek)

    func programWeek(of date: Date) -> Int {
      if let sameDay = blockSessions.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
        return min(max(sameDay.week, 1), currentWeek)
      }
      let before = completed.filter { $0.date < date }.count
      return min(max(before / max(profile.daysPerWeek, 1) + 1, 1), currentWeek)
    }

    var weekStarts: [Int: Date] = [:]
    for week in weeks where week != currentWeek {
      if let first = completed.first(where: { $0.week == week }) {
        weekStarts[week] = first.date
      }
    }

    let blockDecisions = decisions.filter { $0.date >= profile.mesoStart }
    func isLaneEligible(_ entry: DecisionLogEntry) -> Bool {
      guard entry.type == "load_change" || entry.type == "plateau",
        let id = entry.exerciseID,
        ExerciseDB.find(id) != nil,
        let from = entry.fromValue, let to = entry.toValue,
        abs(to - from) > 0.001
      else { return false }
      return true
    }
    // Holds, first-time loads and add-reps are noise: never a lane, never an "other".
    func isLoadNoise(_ entry: DecisionLogEntry) -> Bool {
      guard entry.type == "load_change" || entry.type == "plateau" else { return false }
      if entry.fromValue == nil || entry.toValue == nil { return true }
      if let from = entry.fromValue, let to = entry.toValue, abs(to - from) <= 0.001 { return true }
      return false
    }

    var weekly: [String: [Int: Double]] = [:]
    var totals: [String: Double] = [:]
    for entry in blockDecisions where isLaneEligible(entry) {
      let week = programWeek(of: entry.date)
      let kg = (entry.toValue ?? 0) - (entry.fromValue ?? 0)
      weekly[entry.exerciseID ?? "", default: [:]][week, default: 0] += kg
      totals[entry.exerciseID ?? "", default: 0] += kg
    }
    let lanes = weekly
      .compactMap { id, perWeek -> Lane? in
        guard let exercise = ExerciseDB.find(id) else { return nil }
        let steps = weeks.compactMap { week -> Step? in
          guard let kg = perWeek[week], abs(kg) > 0.001 else { return nil }
          return Step(week: week, delta: kg)
        }
        let total = totals[id] ?? 0
        guard abs(total) > 0.001 || !steps.isEmpty else { return nil }
        return Lane(exercise: exercise, steps: steps, total: total, unit: .kg)
      }
      .sorted {
        abs($0.total) != abs($1.total)
          ? abs($0.total) > abs($1.total) : $0.exercise.localizedName < $1.exercise.localizedName
      }

    // Per-lift volume changes become set-step lanes; whole-session volume stays an "other".
    func isVolumeLane(_ entry: DecisionLogEntry) -> Bool {
      guard entry.type == "volume_change", let id = entry.exerciseID,
        ExerciseDB.find(id) != nil,
        let from = entry.fromValue, let to = entry.toValue,
        abs(to - from) > 0.001
      else { return false }
      return true
    }
    var volumeWeekly: [String: [Int: Double]] = [:]
    var volumeTotals: [String: Double] = [:]
    for entry in blockDecisions where isVolumeLane(entry) {
      let week = programWeek(of: entry.date)
      let sets = (entry.toValue ?? 0) - (entry.fromValue ?? 0)
      volumeWeekly[entry.exerciseID ?? "", default: [:]][week, default: 0] += sets
      volumeTotals[entry.exerciseID ?? "", default: 0] += sets
    }
    let volumeLanes = volumeWeekly
      .compactMap { id, perWeek -> Lane? in
        guard let exercise = ExerciseDB.find(id) else { return nil }
        let steps = weeks.compactMap { week -> Step? in
          guard let sets = perWeek[week], abs(sets) > 0.001 else { return nil }
          return Step(week: week, delta: sets)
        }
        let total = volumeTotals[id] ?? 0
        guard total > 0.001, !steps.isEmpty else { return nil }
        return Lane(exercise: exercise, steps: steps, total: total, unit: .sets)
      }
      .sorted {
        abs($0.total) != abs($1.total)
          ? abs($0.total) > abs($1.total) : $0.exercise.localizedName < $1.exercise.localizedName
      }
    let allLanes = lanes + volumeLanes

    var others: [Other] = []
    for entry in blockDecisions
    where !isLaneEligible(entry) && !isLoadNoise(entry) && !isVolumeLane(entry) {
      let title: String
      var fewerSets: Int? = nil
      if entry.type == "session",
        let session = blockSessions.first(where: { cal.isDate($0.date, inSameDayAs: entry.date) })
      {
        title = String(localized: "\(localizedDayName(session.dayName)), lighter day", bundle: L10n.bundle)
        let normal = Program.week(session.week, profile: profile.profileInput)
          .first { $0.name == session.dayName }?
          .exercises.reduce(0) { $0 + $1.sets } ?? 0
        if session.plannedSetCount > 0 && normal > session.plannedSetCount {
          fewerSets = normal - session.plannedSetCount
        }
      } else {
        title = entry.humanSummary.isEmpty
          ? String(localized: "Plan change", bundle: L10n.bundle)
          : entry.humanSummary
      }
      others.append(
        Other(
          id: "log." + String(describing: entry.persistentModelID),
          title: title, date: entry.date, status: .applied, fewerSets: fewerSets,
          exerciseID: entry.exerciseID))
      }

    let ledger = profile.recommendationLedger
    // Applied lift changes and what they measured, for the field's dots and sentence.
    let changeTypes: Set<String> = ["load_change", "volume_change", "swap"]
    var changes: [AppliedChange] = []
    var undoneKeys = Set<String>()
    func changeKey(_ type: String, _ exerciseID: String, _ date: Date) -> String {
      "\(type)|\(exerciseID)|\(cal.startOfDay(for: date).timeIntervalSince1970)"
    }
    for (id, snapshot) in ledger.snapshots
    where snapshot.createdAt >= profile.mesoStart
      && snapshot.record.exerciseID != nil
      && changeTypes.contains(snapshot.record.type)
      && ledger.outcome(for: id)?.state == .reverted
    {
      let exerciseID = snapshot.record.exerciseID ?? ""
      guard undoneKeys.insert(changeKey(snapshot.record.type, exerciseID, snapshot.record.date)).inserted
      else { continue }
      changes.append(
        AppliedChange(exerciseID: exerciseID, date: snapshot.record.date, outcome: .undone))
    }
    for entry in blockDecisions {
      guard let exerciseID = entry.exerciseID, changeTypes.contains(entry.type) else { continue }
      if entry.type == "load_change" || entry.type == "volume_change" {
        guard let from = entry.fromValue, let to = entry.toValue, abs(to - from) > 0.001 else { continue }
      }
      guard !undoneKeys.contains(changeKey(entry.type, exerciseID, entry.date)) else { continue }
      let outcome: AppliedChange.Outcome
      switch InsightsV3.measurement(exerciseID: exerciseID, since: entry.date, sessions: sessions)?
        .outcome
      {
      case .better: outcome = .better
      case .noChange: outcome = .noChange
      case .measuring, nil: outcome = .measuring
      }
      changes.append(AppliedChange(exerciseID: exerciseID, date: entry.date, outcome: outcome))
    }
    changes.sort { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }

    for (id, snapshot) in ledger.snapshots where snapshot.createdAt >= profile.mesoStart {
      let outcome = ledger.outcome(for: id)
      let status: Other.Status
      switch outcome?.state ?? .proposed {
      case .reverted: status = .undone
      case .stale, .failed, .conflict: status = .notApplied
      case .applied: continue
      case .proposed:
        guard snapshot.isStale(against: ledger.currentProgramVersion, at: .now) else { continue }
        status = .notApplied
      }
      others.append(
        Other(
          id: "ledger." + id.rawValue,
          title: snapshot.record.humanSummary.isEmpty
            ? String(localized: "Plan change", bundle: L10n.bundle)
            : snapshot.record.humanSummary,
          date: outcome?.resolvedAt ?? snapshot.createdAt,
          status: status,
          fewerSets: nil,
          exerciseID: snapshot.record.exerciseID))
    }

    return AdjustmentsModel(
      blockNumber: profile.blockNumber(sessions: sessions),
      currentWeek: currentWeek,
      weeks: weeks,
      weekStarts: weekStarts,
      lanes: Array(allLanes.prefix(5)),
      others: Array(
        others
          .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
          .prefix(6)),
      changes: changes
    )
  }
}

/// One load change of a lift, shown on the detail page.
struct AdjustmentDetail {
  struct Side: Hashable {
    let date: Date
    let weightKg: Double
    let reps: [Int]        // working sets in logged order
    let effort: Double?    // mean RPE of those sets rounded to 0.5; nil when none reported
  }

  let exercise: Exercise
  let fromKg: Double
  let toKg: Double
  let date: Date
  let dayName: String?
  let before: Side?
  let after: Side?
  let repTop: Int
  let setCount: Int
  let byLifter: Bool         // the lifter made the change, not the coach
  let summary: String        // the change's own human summary
  let evidenceLine: String?  // first recorded evidence line, when any

  static func build(
    exerciseID: String, profile: UserProfile, sessions: [WorkoutSession],
    decisions: [DecisionLogEntry]
  ) -> AdjustmentDetail? {
    guard let exercise = ExerciseDB.find(exerciseID) else { return nil }
    let cal = Calendar.current
    let blockSessions = sessions
      .filter { !$0.tombstoned && $0.date >= profile.mesoStart }
      .sorted { $0.date < $1.date }
    guard let change = decisions
      .filter({ entry in
        entry.date >= profile.mesoStart && (entry.type == "load_change" || entry.type == "plateau")
      })
      .filter({ $0.exerciseID == exerciseID })
      .filter({ entry in
        guard let from = entry.fromValue, let to = entry.toValue else { return false }
        return abs(to - from) > 0.001
      })
      .max(by: { $0.date < $1.date })
    else { return nil }

    let dayName = blockSessions
      .first { cal.isDate($0.date, inSameDayAs: change.date) }?.dayName

    func side(_ session: WorkoutSession) -> Side {
      let working = session.sets.filter {
        $0.exerciseID == exerciseID && $0.variant != "warmup" && !$0.suspect
      }
      let top = working.map(\.weightKg).max() ?? 0
      let topSets = working.filter { $0.weightKg == top }.sorted { $0.setIndex < $1.setIndex }
      let reported = topSets.filter(\.effortReported).map(\.rpe)
      let effort: Double? = reported.isEmpty
        ? nil
        : (reported.reduce(0, +) / Double(reported.count) * 2).rounded() / 2
      return Side(date: session.date, weightKg: top, reps: topSets.map(\.reps), effort: effort)
    }

    let containsLift = { (session: WorkoutSession) in
      session.sets.contains { $0.exerciseID == exerciseID }
    }
    let dayStart = cal.startOfDay(for: change.date)
    let before = blockSessions
      .filter { $0.completed && $0.date < dayStart && containsLift($0) }
      .last.map(side)
    let after = blockSessions
      .filter { $0.completed && $0.date >= dayStart && containsLift($0) }
      .first.map(side)

    let repTop = Program.repRange(
      exercise, goal: Goal(rawValue: profile.goal) ?? .hypertrophy
    ).upperBound
    let setCount = after?.reps.count ?? before?.reps.count ?? 3
    return AdjustmentDetail(
      exercise: exercise,
      fromKg: change.fromValue ?? 0,
      toKg: change.toValue ?? 0,
      date: change.date,
      dayName: dayName,
      before: before,
      after: after,
      repTop: repTop,
      setCount: setCount,
      byLifter: change.reasonCodes.contains(DecisionSignal.userOverride.code),
      summary: change.humanSummary,
      evidenceLine: change.evidence.first)
  }
}

extension UserProfile {
  /// Block number shown by the roadmap's road strip (moved here so both screens share it).
  func blockNumber(sessions: [WorkoutSession]) -> Int {
    max(
      1,
      ProgressData.mesoBlockCount(sessions)
        + (mesoSessions(sessions) == 0 && sessions.contains(where: \.completed) ? 1 : 0))
  }
}
