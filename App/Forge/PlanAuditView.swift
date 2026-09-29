import ForgeCore
import SwiftData
import SwiftUI

struct PlanAuditView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var checkIns: [CheckIn]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }

  private var verifiedCompletedSessions: [WorkoutSession] {
    sessions.filter { $0.completed && !$0.tombstoned && $0.verified }
  }

  private var auditSets: [AuditSet] {
    verifiedCompletedSessions.flatMap { session in
      session.trustedSets.map { set in
        AuditSet(
          exerciseID: set.exerciseID, date: session.date, weightKg: set.weightKg, reps: set.reps,
          rpe: set.rpe)
      }
    }
  }

  private var audit: PlanAudit {
    PlanAuditEngine.audit(sets: auditSets, recoveryReduced: profile?.recoveryReduced ?? false)
  }

  private var input: ProfileInput? {
    guard let profile else { return nil }
    var inferred = profile.profileInput
    inferred.daysPerWeek = splitDays
    inferred.split = .auto
    return inferred
  }

  /// Inferred training frequency, clamped to the range `Program.split` can plan for.
  private var splitDays: Int {
    max(3, min(6, Int(audit.sessionsPerWeek.rounded())))
  }

  private var splitNames: [String] { Program.split(daysPerWeek: splitDays, style: .auto) }

  // MARK: - audit signals

  private var comparedTrends: [PlanAudit.LiftTrend] {
    audit.trends.filter { $0.sessions >= 2 }
  }

  private var risingTrends: [PlanAudit.LiftTrend] {
    comparedTrends.filter { $0.direction == .progressing }
  }

  private var trackedMuscles: [PlanAudit.MuscleVolume] {
    audit.muscles.filter { $0.verdict != .untrained }
  }

  private var inRangeMuscles: [PlanAudit.MuscleVolume] {
    audit.muscles.filter { $0.verdict == .inRange }
  }

  private var underMuscles: [PlanAudit.MuscleVolume] {
    audit.muscles.filter { $0.verdict == .under }
  }

  private var plan: (done: Int, planned: Int) {
    let totals = InsightsV3.planTotals(sessions: sessions, profile: profile)
    guard totals.planned > 0 else { return (audit.sessionCount, audit.sessionCount) }
    return totals
  }

  /// Lifts the current injury flags set aside. The plan substitutes them while the flag
  /// stands, so "holding" states the fact and the reason the app actually has.
  private struct HeldLift {
    let exercise: Exercise
    let flag: InjuryFlag
    let e1rm: Double
  }

  private var injuryFlags: Set<InjuryFlag> {
    Set((profile?.injuryFlags ?? []).compactMap(InjuryFlag.init(rawValue:)))
  }

  private var heldLifts: [HeldLift] {
    let flags = injuryFlags
    guard !flags.isEmpty else { return [] }
    return audit.trends.compactMap { trend -> HeldLift? in
      guard
        let flag = flags.first(where: {
          Substitution.replacement(for: trend.exercise.id, flags: [$0]) != nil
        })
      else { return nil }
      return HeldLift(exercise: trend.exercise, flag: flag, e1rm: trend.latestE1RM)
    }
  }

  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  private var firstSessionDate: Date? {
    verifiedCompletedSessions.map(\.date).min()
  }

  private var headerSubtitle: String? {
    guard let profile else {
      return String(
        localized: "\(verifiedCompletedSessions.count) sessions", bundle: L10n.bundle)
    }
    let blocks = LogV3.blocks(sessions: sessions, profile: profile)
    let number = blocks.last?.number ?? InsightsV3.blockNumber(
      of: .now, sessions: sessions, profile: profile)
    return String(
      localized: "Block \(number) · week \(profile.currentWeek(sessions: sessions)) of \(Mesocycle.weeks)",
      bundle: L10n.bundle)
  }

  // MARK: - verdict

  /// Most urgent failing signal first, so the verdict never says "working" over a real problem.
  private var verdictTitle: String {
    let sessionFraction = plan.planned > 0 ? Double(plan.done) / Double(plan.planned) : 1
    let risingFraction =
      comparedTrends.isEmpty ? 1 : Double(risingTrends.count) / Double(comparedTrends.count)
    let rangeFraction =
      trackedMuscles.isEmpty ? 1 : Double(inRangeMuscles.count) / Double(trackedMuscles.count)
    if sessionFraction < 0.75 {
      return String(localized: "You are training less than planned.", bundle: L10n.bundle)
    }
    if risingFraction < 0.5 {
      return String(localized: "Your lifts are mostly holding.", bundle: L10n.bundle)
    }
    if rangeFraction < 0.5 {
      return String(localized: "Several muscles are short on sets.", bundle: L10n.bundle)
    }
    return String(localized: "Your plan is working.", bundle: L10n.bundle)
  }

  private var verdictLine: String {
    switch (underMuscles.count, heldLifts.first) {
    case (0, nil):
      return String(
        localized: "Everything you track is inside its range.", bundle: L10n.bundle)
    case (1, nil):
      return String(
        localized: "One muscle is short on sets.", bundle: L10n.bundle)
    case (let n, nil):
      return String(
        localized: "\(n) muscles are short on sets.", bundle: L10n.bundle)
    case (0, .some(let held)):
      return String(
        localized: "\(held.exercise.localizedName) is held on purpose for your \(held.flag.name) flag.",
        bundle: L10n.bundle)
    case (1, .some(let held)):
      return String(
        localized: "One muscle is short on sets, and \(held.exercise.localizedName) is held for your \(held.flag.name) flag.",
        bundle: L10n.bundle)
    case (let n, .some(let held)):
      return String(
        localized: "\(n) muscles are short on sets, and \(held.exercise.localizedName) is held for your \(held.flag.name) flag.",
        bundle: L10n.bundle)
    }
  }

  private var statItems: [InsightsStatColumns.Item] {
    [
      InsightsStatColumns.Item(
        label: String(localized: "Sessions", bundle: L10n.bundle),
        value: "\(plan.done)",
        of: String(localized: "of \(plan.planned) done", bundle: L10n.bundle),
        fraction: plan.planned > 0 ? Double(plan.done) / Double(plan.planned) : 1,
        fill: [Theme.metricLoad] + Theme.gradMove),
      InsightsStatColumns.Item(
        label: String(localized: "Lifts", bundle: L10n.bundle),
        value: "\(risingTrends.count)",
        of: String(
          localized: "of \(comparedTrends.count) rising", bundle: L10n.bundle),
        fraction: comparedTrends.isEmpty ? 0 : Double(risingTrends.count) / Double(comparedTrends.count),
        fill: [Theme.positive] + Theme.gradDone),
      InsightsStatColumns.Item(
        label: String(localized: "Muscles", bundle: L10n.bundle),
        value: "\(inRangeMuscles.count)",
        of: String(
          localized: "of \(trackedMuscles.count) in range", bundle: L10n.bundle),
        fraction: trackedMuscles.isEmpty ? 0 : Double(inRangeMuscles.count) / Double(trackedMuscles.count),
        fill: [Theme.metricSets] + Theme.gradExercise),
    ]
  }

  // MARK: - body

  @State private var approving: VolumeIncrease?

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(title: "Plan audit", subtitle: headerSubtitle, art: "art-audit")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 8)
        if verifiedCompletedSessions.count < 2 {
          emptyCard
            .padding(.horizontal, Theme.margin)
            .padding(.top, 40)
        } else {
          InsightsVerdict(title: verdictTitle, line: verdictLine)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 20)
          InsightsStatColumns(items: statItems)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 24)
          LogBand().padding(.top, 24)
          attentionSection
          LogBand().padding(.top, 12)
          workingSection
          LogBand().padding(.top, 12)
          changesSection
          if let footer = footerText {
            Text(footer)
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Theme.margin)
              .padding(.top, 16)
          }
          cta
            .padding(.horizontal, Theme.margin)
            .padding(.top, 12)
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation(String(localized: "Plan audit", bundle: L10n.bundle))
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  // MARK: - empty state

  private var emptyCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-empty-progress", height: 120)
      Text(String(localized: "Not enough history", bundle: L10n.bundle))
        .forge(20, .semibold, tracking: -0.3)
      Text(
        String(
          localized:
            "The audit needs a workout or an import. Log a couple of sessions or bring your old log.",
          bundle: L10n.bundle)
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - needs attention

  private var attentionCount: Int { underMuscles.count + heldLifts.count }

  private var attentionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Needs attention", trailing: "\(attentionCount)"
      )
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 10)
      VStack(spacing: 0) {
        ForEach(Array(underMuscles.enumerated()), id: \.element.muscle) { index, volume in
          underRow(volume)
          if index < underMuscles.count - 1 || !pendingIncreases.isEmpty || !heldLifts.isEmpty {
            rowDivider
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      ForEach(pendingIncreases) { increase in
        InsightsPendingRow(increase: increase, onReview: { approving = increase })
          .padding(.horizontal, Theme.margin)
          .padding(.top, 12)
      }
      if !heldLifts.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(heldLifts.enumerated()), id: \.element.exercise.id) { index, held in
            heldRow(held)
            if index < heldLifts.count - 1 { rowDivider }
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, pendingIncreases.isEmpty ? 0 : 12)
      }
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 68)
  }

  private func underRow(_ volume: PlanAudit.MuscleVolume) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(volume.muscle.a11yName)
          .forge(17, .semibold, tracking: -0.17)
          .foregroundStyle(Theme.text)
        Spacer(minLength: 12)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(Fmt.int(volume.setsPerWeek))
            .forge(17, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "sets a week", bundle: L10n.bundle))
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      Text(
        String(
          localized: "Below its range of \(volume.mev) to \(volume.mrv) sets",
          bundle: L10n.bundle)
      )
      .forge(14)
      .foregroundStyle(Theme.textSecondary)
      .padding(.top, 2)
      InsightsRangeBar(value: volume.setsPerWeek, mev: volume.mev, mrv: volume.mrv)
        .padding(.top, 4)
    }
    .frame(minHeight: 60, alignment: .top)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private func heldRow(_ held: HeldLift) -> some View {
    HStack(spacing: 12) {
      WorkoutArtTile(exercise: held.exercise, size: 56)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(held.exercise.localizedName)
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 12)
          Text(String(localized: "Holding", bundle: L10n.bundle))
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
        Text(
          String(
            localized: "Held at \(displayKg(held.e1rm, id: held.exercise.id)) est. max for your \(held.flag.name) flag. \(coach.name) raises it once you clear the flag.",
            bundle: L10n.bundle)
        )
        .forge(14)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 60)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  // MARK: - working

  private var workingSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(title: "Working")
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        let rows = workingRows
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          row
          if index < rows.count - 1 { rowDivider }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  private var workingRows: [AnyView] {
    var rows: [AnyView] = []
    if plan.planned > 0 {
      let since = firstSessionDate.map {
        $0.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
      } ?? ""
      rows.append(
        AnyView(
          workingRow(
            symbol: "calendar", tint: Theme.metricLoad,
            title: String(localized: "You train as planned", bundle: L10n.bundle),
            detail: String(
              localized: "\(plan.done) of \(plan.planned) sessions since \(since)",
              bundle: L10n.bundle))))
    }
    if !risingTrends.isEmpty {
      let top = risingTrends
        .sorted { ($0.latestE1RM - $0.firstE1RM) > ($1.latestE1RM - $1.firstE1RM) }
        .prefix(3)
        .map { "\($0.exercise.localizedName) \(signedKg($0.latestE1RM - $0.firstE1RM, id: $0.exercise.id))" }
        .joined(separator: ", ")
      let since = firstSessionDate.map {
        $0.formatted(.dateTime.month().locale(L10n.locale))
      } ?? ""
      rows.append(
        AnyView(
          workingRow(
            symbol: "chart.line.uptrend.xyaxis", tint: Theme.positive,
            title: String(
              localized: "\(risingTrends.count) lifts are stronger", bundle: L10n.bundle),
            detail: String(
              localized: "\(top) since \(since)", bundle: L10n.bundle))))
    }
    if !inRangeMuscles.isEmpty {
      let names = inRangeMuscles.map(\.muscle.a11yName).joined(separator: ", ")
      rows.append(
        AnyView(
          workingRow(
            symbol: "square.stack.3d.up", tint: Theme.metricSets,
            title: String(
              localized: "\(inRangeMuscles.count) muscles get enough sets", bundle: L10n.bundle),
            detail: names)))
    }
    return rows
  }

  private func workingRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
    HStack(spacing: 12) {
      LogIconBadge(symbol: symbol, tint: tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .forge(17, .semibold, tracking: -0.17)
          .foregroundStyle(Theme.text)
        Text(detail)
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 60)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  // MARK: - changes this block

  private var blockStart: Date? {
    let blocks = LogV3.blocks(sessions: sessions, profile: profile)
    if let first = blocks.last?.firstDate { return LogV3.weekStart(containing: first) }
    if let mesoStart = profile?.mesoStart, mesoStart < .now { return mesoStart }
    return nil
  }

  private var blockChanges: [DecisionLogEntry] {
    guard let start = blockStart else { return [] }
    return decisions.filter { $0.date >= start }
  }

  private var changesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Changes this block",
        trailing: "\(blockChanges.count + (blockStartInfo == nil ? 0 : 1))"
      )
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(blockChanges.enumerated()), id: \.element.record.id) { index, entry in
          changeRow(entry)
          if index < blockChanges.count - 1 || blockStartInfo != nil { rowDivider }
        }
        if let info = blockStartInfo {
          blockStartRow(info)
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  private func changeRow(_ entry: DecisionLogEntry) -> some View {
    let record = entry.record
    let engineTypes = ["load_change", "volume_change", "swap", "session", "plateau"]
    let coachMade =
      engineTypes.contains(record.type)
      && !record.reasonCodes.contains(DecisionSignal.userOverride.code)
    return HStack(alignment: .top, spacing: 12) {
      if coachMade {
        CoachAvatar(size: 44)
      } else {
        LogIconBadge(symbol: badgeSymbol(record.type).symbol, tint: badgeSymbol(record.type).tint)
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(record.humanSummary.isEmpty ? "—" : record.humanSummary)
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Text(
            entry.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
          )
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
        if let detail = changeDetail(record) {
          Text(detail)
            .forge(14)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let values = changeValues(record) {
          HStack(alignment: .firstTextBaseline) {
            Spacer(minLength: 8)
            Text(values)
              .forge(15, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
          }
        }
      }
    }
    .frame(minHeight: 60, alignment: .top)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  /// The plain observation behind a change: the recorded evidence line, or the humanized
  /// signals when no evidence was written.
  private func changeDetail(_ record: DecisionRecord) -> String? {
    if let first = record.evidence.first { return first }
    guard !record.reasonCodes.isEmpty else { return nil }
    return record.reasonCodes.map { $0.replacingOccurrences(of: "_", with: " ") }
      .joined(separator: ", ")
  }

  private func changeValues(_ record: DecisionRecord) -> String? {
    guard let id = record.exerciseID, let from = record.fromValue, let to = record.toValue,
      from != to
    else { return nil }
    return "\(displayKg(from, id: id)) → \(displayKg(to, id: id))"
  }

  private func badgeSymbol(_ type: String) -> (symbol: String, tint: Color) {
    switch type {
    case "load_change": return ("chart.line.uptrend.xyaxis", Theme.positive)
    case "volume_change": return ("square.stack.3d.up", Theme.metricSets)
    case "swap": return ("arrow.2.squarepath", Theme.accentText)
    case "session", "weekplan": return ("calendar", Theme.metricTime)
    case "plateau": return ("flag", Theme.metricEffort)
    case "experiment", "experiment_result": return ("flask", Theme.accentText)
    case "import_plan": return ("tray.and.arrow.down", Theme.accentText)
    default: return ("slider.horizontal.3", Theme.accentText)
    }
  }

  /// The block's own start row, with the plan's set ramp — the one dated change that is
  /// not a decision-log entry.
  private var blockStartInfo: (number: Int, start: Date, line: String)? {
    guard let profile, let start = blockStart else { return nil }
    let number = LogV3.blocks(sessions: sessions, profile: profile).last?.number
      ?? InsightsV3.blockNumber(of: start, sessions: sessions, profile: profile)
    let first = LogV3.plannedSets(week: 1, profile: profile, sessions: sessions)
    let peak = LogV3.plannedSets(week: Mesocycle.weeks - 1, profile: profile, sessions: sessions)
    if let first, let peak, peak > first {
      let rise = Int((Double(peak - first) / Double(Mesocycle.weeks - 2)).rounded())
      return (
        number, start,
        String(
          localized: "Planned: sets rise about \(rise) a week, \(first) up to \(peak)",
          bundle: L10n.bundle))
    }
    if let first {
      return (number, start, String(localized: "Planned: \(first) sets a week", bundle: L10n.bundle))
    }
    return (number, start, "")
  }

  private func blockStartRow(_ info: (number: Int, start: Date, line: String)) -> some View {
    HStack(alignment: .top, spacing: 12) {
      LogIconBadge(symbol: "square.stack.3d.up", tint: Theme.accentText)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(String(localized: "Block \(info.number) started", bundle: L10n.bundle))
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          Text(
            info.start.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
          )
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
        if !info.line.isEmpty {
          Text(info.line)
            .forge(14)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(minHeight: 60, alignment: .top)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private var footerText: String? {
    guard let first = firstSessionDate else { return nil }
    return String(
      localized:
        "From \(verifiedCompletedSessions.count) sessions logged on this device since \(first.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))).",
      bundle: L10n.bundle)
  }

  // MARK: - CTA

  private var cta: some View {
    Button {
      startBlock()
    } label: {
      Text(String(localized: "Use recommended plan", bundle: L10n.bundle))
    }
    .buttonStyle(PillButtonStyle())
    .disabled(profile == nil)
  }

  private func startBlock() {
    guard let profile else { return }
    seedStartingLoads(profile)
    profile.daysPerWeek = splitDays
    profile.split = SplitStyle.auto.rawValue
    profile.startNewBlock()
    let evidence = [
      "\(auditSets.count) imported sets",
      "\(Fmt.num(audit.sessionsPerWeek)) sessions/week",
      "\(splitDays)-day \(splitNames.joined(separator: "/")) plan",
    ]
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "import-plan-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: "import_plan",
          exerciseID: nil,
          muscle: nil,
          fromValue: nil,
          toValue: Double(splitDays),
          reasonCodes: ["import_history", DecisionSignal.userOverride.code],
          evidence: evidence,
          humanSummary: "Built a \(splitDays)-day starting plan from the imported training history."
        )))
    try? modelContext.save()
    Analytics.track("audit_start_block", ["days": "\(splitDays)"])
    NotificationCenter.default.post(name: .forgeAuditStarted, object: nil)
    dismiss()
  }

  private func seedStartingLoads(_ profile: UserProfile) {
    var best: [String: Double] = [:]
    for set in auditSets {
      best[set.exerciseID] = max(best[set.exerciseID] ?? 0, set.weightKg)
    }
    for trend in audit.trends {
      if let weight = best[trend.exercise.id] {
        profile.startingLoads[trend.exercise.id] = max(
          profile.startingLoads[trend.exercise.id] ?? 0, weight)
      }
    }
  }

  private func displayKg(_ kg: Double, id: String) -> String {
    guard let profile else { return "\(Fmt.num(kg)) kg" }
    let value = profile.display(kg: kg, for: id)
    return "\(Fmt.num(value)) \(profile.unit(for: id))"
  }

  private func signedKg(_ kg: Double, id: String) -> String {
    guard let profile else {
      return (kg >= 0 ? "+" : "\u{2212}") + "\(Fmt.num(abs(kg))) kg"
    }
    let value = profile.display(kg: abs(kg), for: id)
    return (kg >= 0.5 ? "+" : "\u{2212}") + "\(Fmt.num(value)) \(profile.unit(for: id))"
  }
}

extension Notification.Name {
  /// Posted after "Start adaptive block" so the import sheet can close itself and the user returns to the app.
  static let forgeAuditStarted = Notification.Name("forge.audit.started")
}
