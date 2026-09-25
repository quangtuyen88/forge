import Foundation
import ForgeCore

enum ProgramChangeState: Equatable, Sendable { case scheduled, applied }

struct ProgramChangeRow: Identifiable, Equatable {
  enum Change: Equatable {
    case increase(fromKg: Double, toKg: Double)
    case decrease(fromKg: Double, toKg: Double)
    case unchanged(kg: Double)
    case starting(kg: Double)
    case addReps(kg: Double)
    case other(String)

    /// The load "Keep … instead" would hold, when the change carries one.
    var originalKg: Double? {
      switch self {
      case .increase(let fromKg, _), .decrease(let fromKg, _): return fromKg
      case .unchanged(let kg): return kg
      case .starting, .addReps, .other: return nil
      }
    }
  }
  let id: String
  let exerciseID: String?
  let name: String
  let change: Change
  let reason: String
  let kept: Bool
  let sourceID: String?

  var originalKg: Double? { change.originalKg }
}

struct ProgramChangeGroup: Identifiable, Equatable {
  let id: String
  let state: ProgramChangeState
  let dayName: String
  let anchorDate: Date
  let effectiveDate: Date?
  let rows: [ProgramChangeRow]
}

struct ProgramChangeStep: Equatable {
  let title: String
  let detail: String?
  let done: Bool
}

struct ProgramChangeDetail: Equatable {
  struct SetChip: Equatable { let weightKg: Double; let reps: Int }
  let row: ProgramChangeRow
  let state: ProgramChangeState
  let dayName: String
  let planContext: String?
  let effectiveDate: Date?
  let evidence: [String]
  let lastSessionDate: Date?
  let lastSessionDayName: String?
  let lastSets: [SetChip]
  let calculation: [String]
  let steps: [ProgramChangeStep]
  let canKeepOriginal: Bool
  let originalKg: Double?
  /// The engine's target before any override; the keep-undo button returns to it.
  let proposedKg: Double?
}

/// The pure model the timeline's program-change cards and the change sheet read.
enum ProgramChanges {

  // MARK: - Scheduled groups

  /// The load changes the engine will propose the next time each day type runs, derived from
  /// the latest finished session of that day type. Never stored.
  @MainActor
  static func scheduled(sessions: [WorkoutSession], profile: UserProfile, now: Date = .now) -> [ProgramChangeGroup] {
    let usable = sessions.filter { !$0.tombstoned }
    let latestByDay = Dictionary(grouping: usable.filter(\.completed), by: \.dayName)
      .compactMapValues { $0.max { $0.date < $1.date } }
    var groups: [ProgramChangeGroup] = []
    for (dayName, source) in latestByDay {
      // A session of the same day type after the source one means the change is already
      // being applied, so there is nothing upcoming to propose.
      guard !usable.contains(where: { $0.dayName == dayName && $0.date > source.date }) else { continue }
      guard let day = resolvedDay(for: source, dayName: dayName, sessions: sessions, profile: profile, now: now)
      else { continue }
      let rows = day.exercises.map { scheduledRow(for: $0, sessions: sessions, profile: profile) }
      guard rows.contains(where: { $0.kept || !isUnchanged($0.change) }) else { continue }
      groups.append(ProgramChangeGroup(
        id: "scheduled|\(dayName)|\(Int(source.date.timeIntervalSince1970))",
        state: .scheduled,
        dayName: dayName,
        anchorDate: source.date,
        effectiveDate: nextPlannedDate(dayName: dayName, profile: profile, now: now),
        rows: rows))
    }
    return groups.sorted { $0.anchorDate > $1.anchorDate }
  }

  @MainActor
  private static func scheduledRow(for planned: PlannedExercise, sessions: [WorkoutSession], profile: UserProfile) -> ProgramChangeRow {
    let base = buildDecision(for: planned, sessions: sessions, profile: profile)
    let stored = DecisionOverrides.get(planned.exercise.id)
    let decision = stored.map { base.applying($0) } ?? base
    let kept = stored == .keepOriginal
    let change: ProgramChangeRow.Change
    if kept, case .increaseLoad(let fromKg, _) = base.action {
      change = .unchanged(kg: fromKg)
    } else if kept, case .decreaseLoad(let fromKg, _) = base.action {
      change = .unchanged(kg: fromKg)
    } else {
      switch decision.action {
      case .increaseLoad(let fromKg, let toKg): change = .increase(fromKg: fromKg, toKg: toKg)
      case .decreaseLoad(let fromKg, let toKg): change = .decrease(fromKg: fromKg, toKg: toKg)
      case .holdLoad(let kg): change = .unchanged(kg: kg)
      case .firstTime(let kg): change = .starting(kg: kg)
      case .addReps(let kg): change = .addReps(kg: kg)
      default:
        change = .other(decision.headline(
          name: planned.exercise.localizedName,
          weight: { loadText($0, exerciseID: planned.exercise.id, profile: profile) }))
      }
    }
    let last = lastSets(planned.exercise.id, in: sessions, profile: profile)
    let keptProposalKg: Double?
    if kept, case .increaseLoad(_, let toKg) = base.action {
      keptProposalKg = toKg
    } else if kept, case .decreaseLoad(_, let toKg) = base.action {
      keptProposalKg = toKg
    } else {
      keptProposalKg = nil
    }
    let reason = shortReason(
      decision: decision, change: change, keptProposalKg: keptProposalKg, exerciseID: planned.exercise.id,
      repRange: planned.repRange, last: last, profile: profile)
    return ProgramChangeRow(
      id: planned.exercise.id,
      exerciseID: planned.exercise.id,
      name: planned.exercise.localizedName,
      change: change,
      reason: reason,
      kept: kept,
      sourceID: nil)
  }

  /// The day's prescription, resolved the way Today resumes a day: the started session's
  /// snapshot first, then the generated program day with that name.
  private static func resolvedDay(
    for source: WorkoutSession, dayName: String, sessions: [WorkoutSession],
    profile: UserProfile?, now: Date = .now
  ) -> PlannedDay? {
    if let snapshot = source.routinePrescription.flatMap(RoutineAdaptation.plannedDay) { return snapshot }
    guard let profile else { return nil }
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions, now: now)),
      volumeDelta: [:])
    return days.first { $0.name == dayName }
  }

  private static func isUnchanged(_ change: ProgramChangeRow.Change) -> Bool {
    if case .unchanged = change { return true }
    return false
  }

  // MARK: - Applied groups

  /// Committed ledger entries grouped into one card per session start.
  static func applied(entries: [DecisionLogEntry], sessions: [WorkoutSession], profile: UserProfile?) -> [ProgramChangeGroup] {
    var byFingerprint: [String: [(Int, DecisionLogEntry)]] = [:]
    var byDate: [Date: [(Int, DecisionLogEntry)]] = [:]
    for (index, entry) in entries.enumerated() {
      if entry.operationFingerprint.isEmpty {
        byDate[entry.date, default: []].append((index, entry))
      } else {
        byFingerprint[entry.operationFingerprint, default: []].append((index, entry))
      }
    }
    let buckets: [(key: String, members: [(Int, DecisionLogEntry)], fingerprinted: Bool)] =
      byFingerprint.map { ($0.key, $0.value, true) }
      + byDate.map { (String(Int($0.key.timeIntervalSince1970)), $0.value, false) }
    let usable = sessions.filter { !$0.tombstoned }
    return buckets.map { key, members, fingerprinted -> ProgramChangeGroup in
      let anchor: Date = members.map { $0.1.date }.min() ?? .now
      // Only fingerprinted rows were written by a session start; the rest must not claim one.
      let session = fingerprinted ? nearestSession(to: anchor, in: usable) : nil
      let indexed: [(index: Int, row: ProgramChangeRow)] = members.map { member in
        (index: member.0, row: appliedRow(for: member.1, index: member.0))
      }
      let sorted = indexed.sorted { lhs, rhs in
        lhs.row.name == rhs.row.name ? lhs.index < rhs.index : lhs.row.name < rhs.row.name
      }
      let rows: [ProgramChangeRow] = sorted.map { $0.row }
      return ProgramChangeGroup(
        id: "applied|\(key)",
        state: .applied,
        dayName: session?.dayName ?? "",
        anchorDate: anchor,
        effectiveDate: session?.date,
        rows: rows)
    }
    .sorted { $0.anchorDate > $1.anchorDate }
  }

  /// The session that started within six hours of `anchor`, closest first.
  private static func nearestSession(to anchor: Date, in sessions: [WorkoutSession]) -> WorkoutSession? {
    let distance: (WorkoutSession) -> TimeInterval = { abs($0.date.timeIntervalSince(anchor)) }
    guard let nearest = sessions.min(by: { distance($0) < distance($1) }), distance(nearest) <= 6 * 60 * 60
    else { return nil }
    return nearest
  }

  private static func appliedRow(for entry: DecisionLogEntry, index: Int) -> ProgramChangeRow {
    let title = JourneyProgramChangePolicy.title(for: entry.type, from: entry.fromValue, to: entry.toValue)
    var name = title
    var change: ProgramChangeRow.Change
    if entry.type == "load_change", let exerciseID = entry.exerciseID {
      name = ExerciseDB.find(exerciseID)?.localizedName ?? title
      switch (entry.fromValue, entry.toValue) {
      case (nil, let toKg?): change = .starting(kg: toKg)
      case (let fromKg?, let toKg?) where fromKg < toKg: change = .increase(fromKg: fromKg, toKg: toKg)
      case (let fromKg?, let toKg?) where fromKg > toKg: change = .decrease(fromKg: fromKg, toKg: toKg)
      case (let fromKg?, let toKg?) where fromKg == toKg: change = .unchanged(kg: fromKg)
      default: change = .other(entry.humanSummary.isEmpty ? title : entry.humanSummary)
      }
    } else {
      change = .other(entry.humanSummary.isEmpty ? title : entry.humanSummary)
    }
    return ProgramChangeRow(
      id: entry.journeyID.isEmpty ? "\(entry.type)-\(index)" : entry.journeyID,
      exerciseID: entry.exerciseID,
      name: name,
      change: change,
      reason: appliedReason(for: entry),
      kept: false,
      sourceID: entry.journeyID.isEmpty ? nil : entry.journeyID)
  }

  /// The first reason code that maps to a sentence this record can fill on its own; entries
  /// carry no rep range or RPE, so other codes stay with the recorded plain summary.
  private static func appliedReason(for entry: DecisionLogEntry) -> String {
    for code in entry.reasonCodes {
      if signal(for: code) == .firstExposure {
        return String(localized: "First session of this exercise", bundle: L10n.bundle)
      }
    }
    return entry.humanSummary
  }

  private static func signal(for code: String) -> DecisionSignal? {
    DecisionSignal(rawValue: code) ?? DecisionSignal.allCases.first { $0.code == code }
  }

  // MARK: - Detail sheet

  @MainActor
  static func detail(
    for row: ProgramChangeRow, in group: ProgramChangeGroup, sessions: [WorkoutSession],
    entries: [DecisionLogEntry], profile: UserProfile?
  ) -> ProgramChangeDetail {
    switch group.state {
    case .scheduled: return scheduledDetail(for: row, in: group, sessions: sessions, profile: profile)
    case .applied: return appliedDetail(for: row, in: group, sessions: sessions, entries: entries, profile: profile)
    }
  }

  @MainActor
  private static func scheduledDetail(
    for row: ProgramChangeRow, in group: ProgramChangeGroup, sessions: [WorkoutSession],
    profile: UserProfile?
  ) -> ProgramChangeDetail {
    let source = sessions
      .filter { !$0.tombstoned && $0.completed && $0.dayName == group.dayName }
      .max { $0.date < $1.date }
    let day = source.flatMap { resolvedDay(for: $0, dayName: group.dayName, sessions: sessions, profile: profile) }
    let planned = day?.exercises.first { $0.exercise.id == row.exerciseID }
    let read = row.exerciseID.flatMap { lastSetsWithSession($0, in: sessions, profile: profile) }
    let last = read.map(\.sets) ?? []
    let base = planned.map { buildDecision(for: $0, sessions: sessions, profile: profile) }
    // The engine's own target before any override, when it proposed a load change.
    let proposedKg: Double?
    switch base?.action {
    case .increaseLoad(_, let toKg), .decreaseLoad(_, let toKg): proposedKg = toKg
    default: proposedKg = nil
    }
    let stored = row.exerciseID.flatMap { DecisionOverrides.get($0) }
    let decision = base.map { b in stored.map { b.applying($0) } ?? b }
    let dayText = localizedDayName(group.dayName)

    var steps: [ProgramChangeStep] = []
    let proposedAt = source.flatMap { s in s.sets.map(\.loggedAt).max() } ?? source?.date
    steps.append(ProgramChangeStep(
      title: String(localized: "Proposed by your plan", bundle: L10n.bundle),
      detail: proposedAt.map {
        String(localized: "\(dateText($0)) · \(timeText($0)), after \(dayText)", bundle: L10n.bundle)
      },
      done: true))
    steps.append(ProgramChangeStep(
      title: String(localized: "Checked again when \(dayText) starts", bundle: L10n.bundle),
      detail: String(localized: "New sets or a low readiness check-in can still change it.", bundle: L10n.bundle),
      done: false))
    steps.append(ProgramChangeStep(
      title: String(localized: "Takes effect", bundle: L10n.bundle),
      detail: group.effectiveDate.map {
        String(localized: "Next \(dayText) · \(dateText($0))", bundle: L10n.bundle)
      } ?? String(localized: "Your next \(dayText)", bundle: L10n.bundle),
      done: false))

    let canKeep = {
      if row.kept { return false }
      switch row.change {
      case .increase, .decrease: return decision?.overridable ?? false
      default: return false
      }
    }()

    // A kept row still explains what the plan proposed; the sheet adds the keep line live.
    var explainDecision = decision
    var explainChange = row.change
    if row.kept, let base {
      switch base.action {
      case .increaseLoad(let fromKg, let toKg):
        explainDecision = base
        explainChange = .increase(fromKg: fromKg, toKg: toKg)
      case .decreaseLoad(let fromKg, let toKg):
        explainDecision = base
        explainChange = .decrease(fromKg: fromKg, toKg: toKg)
      default:
        break
      }
    }

    return ProgramChangeDetail(
      row: row,
      state: .scheduled,
      dayName: group.dayName,
      planContext: planned.map {
        String(localized: "\(dayText) · \($0.sets) sets of \($0.repRange.lowerBound)–\($0.repRange.upperBound) reps", bundle: L10n.bundle)
      },
      effectiveDate: group.effectiveDate,
      evidence: evidence(
        decision: explainDecision, change: explainChange, repRange: planned?.repRange, last: last),
      lastSessionDate: read?.session.date,
      lastSessionDayName: read?.session.dayName,
      lastSets: last.map { ProgramChangeDetail.SetChip(weightKg: $0.weightKg, reps: $0.reps) },
      calculation: calculationLines(decision: explainDecision, planned: planned, entry: nil),
      steps: steps,
      canKeepOriginal: canKeep,
      originalKg: row.originalKg,
      proposedKg: proposedKg)
  }

  private static func appliedDetail(
    for row: ProgramChangeRow, in group: ProgramChangeGroup, sessions: [WorkoutSession],
    entries: [DecisionLogEntry], profile: UserProfile?
  ) -> ProgramChangeDetail {
    let entry = entries.first { $0.journeyID == row.sourceID }
    let anchor = group.anchorDate
    // Only fingerprinted rows were written by a session start; the rest must not claim one.
    let fingerprinted = entry.map { !$0.operationFingerprint.isEmpty } ?? false
    let session = fingerprinted ? nearestSession(to: anchor, in: sessions.filter { !$0.tombstoned }) : nil
    let day = session.flatMap { resolvedDay(for: $0, dayName: $0.dayName, sessions: sessions, profile: profile) }
    let planned = day?.exercises.first { $0.exercise.id == row.exerciseID }
    let prior = sessions.filter { $0.date < anchor }
    let read = row.exerciseID.flatMap { lastSetsWithSession($0, in: prior, profile: profile) }
    let dayText = group.dayName.isEmpty ? nil : localizedDayName(group.dayName)

    var steps: [ProgramChangeStep] = []
    if fingerprinted {
      steps.append(ProgramChangeStep(
        title: String(localized: "Proposed by your plan", bundle: L10n.bundle),
        detail: entry.map { String(localized: "\(dateText($0.date)) · \(timeText($0.date))", bundle: L10n.bundle) },
        done: true))
      steps.append(ProgramChangeStep(
        title: dayText.map { String(localized: "Applied when \($0) started", bundle: L10n.bundle) }
          ?? String(localized: "Applied when the session started", bundle: L10n.bundle),
        detail: session.map { String(localized: "\(dateText($0.date)) · \(timeText($0.date))", bundle: L10n.bundle) },
        done: true))
    } else {
      steps.append(ProgramChangeStep(
        title: String(localized: "Applied", bundle: L10n.bundle),
        detail: entry.map { String(localized: "\(dateText($0.date)) · \(timeText($0.date))", bundle: L10n.bundle) },
        done: true))
    }

    var sentences: [String] = []
    if let entry {
      if entry.reasonCodes.contains(where: { signal(for: $0) == .firstExposure }) {
        sentences.append(String(localized: "First session of this exercise.", bundle: L10n.bundle))
      } else if !entry.humanSummary.isEmpty {
        sentences.append(entry.humanSummary)
      }
    }

    return ProgramChangeDetail(
      row: row,
      state: .applied,
      dayName: group.dayName,
      planContext: planned.map {
        let dayText = localizedDayName(group.dayName)
        return String(localized: "\(dayText) · \($0.sets) sets of \($0.repRange.lowerBound)–\($0.repRange.upperBound) reps", bundle: L10n.bundle)
      },
      effectiveDate: group.effectiveDate,
      evidence: sentences,
      lastSessionDate: read?.session.date,
      lastSessionDayName: read?.session.dayName,
      lastSets: (read?.sets ?? []).map { ProgramChangeDetail.SetChip(weightKg: $0.weightKg, reps: $0.reps) },
      calculation: calculationLines(decision: nil, planned: planned, entry: entry),
      steps: steps,
      canKeepOriginal: false,
      originalKg: row.originalKg,
      proposedKg: nil)
  }

  // MARK: - Reason sentences

  /// One plain sentence for the card row, keyed on the change it explains: a claim may
  /// only appear on the change kind that actually earned it.
  private static func shortReason(
    decision: Decision, change: ProgramChangeRow.Change, keptProposalKg: Double?, exerciseID: String?,
    repRange: ClosedRange<Int>, last: [LoggedSet], profile: UserProfile?
  ) -> String {
    let lo = repRange.lowerBound
    let hi = repRange.upperBound
    let n = last.count
    let rpe = last.last.map { String(format: "%g", $0.reportedRPE ?? $0.targetRPE) } ?? ""
    let target = last.last.map { String(format: "%g", $0.targetRPE) } ?? ""
    if let keptProposalKg {
      return String(localized: "Plan proposed \(loadText(keptProposalKg, exerciseID: exerciseID, profile: profile))", bundle: L10n.bundle)
    }
    let logs = last.map {
      SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.reportedRPE ?? $0.targetRPE, effortReported: $0.effortReported)
    }
    let signals = Set(decision.causes.map(\.signal))
    let effortMissing = last.isEmpty || last.contains { !$0.effortReported }
    switch change {
    case .starting:
      return String(localized: "First session of this exercise", bundle: L10n.bundle)
    case .increase:
      if n > 0, last.allSatisfy({ $0.reps >= hi }), signals.contains(.repsAtTopOfRange)
        || Progression.shouldIncreaseLoad(sets: logs, repRange: repRange, targetRPE: last.last?.targetRPE ?? 8) {
        return String(localized: "All \(n) sets reached \(hi) reps", bundle: L10n.bundle)
      }
      if signals.contains(.rpeBelowTarget) {
        return String(localized: "Effort RPE \(rpe), under the target of \(target)", bundle: L10n.bundle)
      }
    case .decrease:
      if signals.contains(.rpeAboveTarget) {
        return String(localized: "Effort RPE \(rpe), over the target of \(target)", bundle: L10n.bundle)
      }
    case .unchanged:
      if effortMissing {
        return String(localized: "Effort not recorded, load held", bundle: L10n.bundle)
      }
      if last.allSatisfy({ repRange.contains($0.reps) }) {
        return String(localized: "Reps still inside \(lo)–\(hi)", bundle: L10n.bundle)
      }
    case .addReps, .other:
      break
    }
    return decision.reason
  }

  /// Every sentence that applies to the sheet's evidence block, most important first. Like
  /// the row reason, each claim is keyed on the change kind that earned it.
  private static func evidence(
    decision: Decision?, change: ProgramChangeRow.Change, repRange: ClosedRange<Int>?, last: [LoggedSet]
  ) -> [String] {
    guard let repRange else { return decision.map { [$0.reason] } ?? [] }
    let lo = repRange.lowerBound
    let hi = repRange.upperBound
    let n = last.count
    let rpe = last.last.map { String(format: "%g", $0.reportedRPE ?? $0.targetRPE) } ?? ""
    let target = last.last.map { String(format: "%g", $0.targetRPE) } ?? ""
    let logs = last.map {
      SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.reportedRPE ?? $0.targetRPE, effortReported: $0.effortReported)
    }
    let signals = Set(decision?.causes.map(\.signal) ?? [])
    let effortMissing = last.isEmpty || last.contains { !$0.effortReported }
    var out: [String] = []
    switch change {
    case .increase:
      if n > 0, last.allSatisfy({ $0.reps >= hi }), (signals.contains(.repsAtTopOfRange)
        || Progression.shouldIncreaseLoad(sets: logs, repRange: repRange, targetRPE: last.last?.targetRPE ?? 8)) {
        out.append(String(localized: "All \(n) sets reached \(hi) reps, the top of your \(lo)–\(hi) range.", bundle: L10n.bundle))
      }
      if signals.contains(.rpeBelowTarget) {
        out.append(String(localized: "Your effort was RPE \(rpe), easier than the target of \(target).", bundle: L10n.bundle))
      }
    case .decrease:
      if signals.contains(.rpeAboveTarget) {
        out.append(String(localized: "Your effort was RPE \(rpe), harder than the target of \(target).", bundle: L10n.bundle))
      }
    case .starting:
      out.append(String(localized: "First session of this exercise.", bundle: L10n.bundle))
    case .unchanged:
      if effortMissing {
        out.append(String(localized: "Effort was not recorded on the last session, so the load holds.", bundle: L10n.bundle))
      } else {
        out.append(String(localized: "Your reps stayed inside \(lo)–\(hi), so the load holds.", bundle: L10n.bundle))
      }
    case .addReps, .other:
      break
    }
    if out.isEmpty, let decision { out = [decision.reason] }
    return out
  }

  private static func calculationLines(decision: Decision?, planned: PlannedExercise?, entry: DecisionLogEntry?) -> [String] {
    var lines: [String] = []
    if let decision {
      lines.append(contentsOf: decision.causes.map(\.evidence).filter { !$0.isEmpty })
    }
    if let entry {
      lines.append(contentsOf: entry.evidence)
    }
    if let planned {
      let target = String(format: "%g", planned.targetRPE)
      lines.append(String(localized: "RPE target \(target) · range \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)", bundle: L10n.bundle))
    }
    return lines
  }

  /// The latest readable sets of one lift and the session they came from, mirroring the
  /// progression read in Adjustments so the sheet shows exactly the sets the engine saw.
  private static func lastSetsWithSession(
    _ exerciseID: String, in sessions: [WorkoutSession], profile: UserProfile?
  ) -> (session: WorkoutSession, sets: [LoggedSet])? {
    let descriptor = profile?.equipmentLoadDescriptor(
      exerciseID: exerciseID, variant: "straight", displayValue: "", displayUnit: "kg", weightKg: 0,
      side: UserProfile.defaultSide(for: ExerciseDB.find(exerciseID).map { EquipmentKind(equipment: $0.equipment) } ?? .unknown))
    let reference = descriptor.map {
      ComparisonContext(exerciseID: exerciseID, variantID: "straight",
        equipmentInstanceID: $0.equipmentInstanceID, loadModelRevision: $0.loadModelRevision,
        convention: $0.convention, side: $0.side, normalizationStatus: $0.normalizationStatus)
    }
    for s in sessions.filter(\.completed).sorted(by: { $0.date > $1.date }) {
      let sets = s.analysisSets(.progression)
        .filter { $0.exerciseID == exerciseID }
        .filter { set in
          guard let reference, reference.normalizationStatus == .verified else { return true }
          return set.comparisonContext.normalizationStatus == .verified && set.comparisonContext.isComparable(to: reference)
        }
        .sorted { $0.setIndex < $1.setIndex }
      if !sets.isEmpty { return (s, sets) }
    }
    return nil
  }

  // MARK: - Dates and loads

  /// The next accepted-plan date this day type is scheduled for, from the week plan only.
  static func nextPlannedDate(dayName: String, profile: UserProfile, now: Date = .now) -> Date? {
    guard let plan = profile.weekPlan else { return nil }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    return plan.days
      .filter { $0.state == .planned }
      .filter { calendar.startOfDay(for: $0.date) >= today }
      .filter { $0.sessionName == dayName || $0.plannedSessionID == dayName }
      .min { $0.date < $1.date }?
      .date
  }

  /// "43 kg" / "95 lb" in the unit this exercise is logged in.
  static func loadText(_ kg: Double, exerciseID: String?, profile: UserProfile?) -> String {
    let lb = profile.map { p -> Bool in
      exerciseID.map { p.isLb(for: $0) } ?? p.usesLb
    } ?? false
    return Fmt.kg(lb ? Plates.kgToLb(kg) : kg, lb: lb)
  }

  private static func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
  }

  private static func timeText(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute().locale(L10n.locale))
  }
}
