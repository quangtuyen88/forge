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

  /// The "Use recommended plan" CTA only makes sense right after an import; Progress's
  /// audit link must not offer to start a block over the running plan.
  var showsStartPlan = false

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }

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

  /// Increases still waiting for the lifter's OK; approved ones no longer wait.
  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
      .filter { $0.answer == nil }
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
  /// Uses the same numbers as the stats row and the Needs attention rows.
  private func verdictTitle(_ data: ProgressData, _ split: MuscleSplit) -> String {
    let sessionFraction = plan.planned > 0 ? Double(plan.done) / Double(plan.planned) : 1
    let liftFraction =
      data.comparedLiftCount == 0
      ? 1 : Double(data.strongerLifts.count) / Double(data.comparedLiftCount)
    let rangeFraction =
      split.trackedCount == 0 ? 1 : Double(split.inRange.count) / Double(split.trackedCount)
    if sessionFraction < 0.75 {
      return String(localized: "You are training less than planned.", bundle: L10n.bundle)
    }
    if liftFraction < 0.5 {
      return String(localized: "Your lifts are mostly holding.", bundle: L10n.bundle)
    }
    if rangeFraction < 0.5 {
      return String(localized: "Several muscles are short on sets.", bundle: L10n.bundle)
    }
    return String(localized: "Your plan is working.", bundle: L10n.bundle)
  }

  private func verdictLine(_ split: MuscleSplit) -> String {
    switch (split.short.count, heldLifts.first) {
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

  // MARK: - 7-day muscle split

  private struct WeekMuscleStat {
    let muscle: Muscle
    let sets: Double
    let floor: Int
    let mrv: Int
  }

  private struct MuscleSplit {
    let worked: [WeekMuscleStat]
    let short: [WeekMuscleStat]
    let inRange: [WeekMuscleStat]
    /// Every tracked muscle with landmarks — the 0-set ones count as short.
    let trackedCount: Int
  }

  /// Muscle stats on the rolling 7-day window, mirroring MuscleVolumeView so both screens agree.
  private func muscleSplit(_ weekSets: [Muscle: Double]) -> MuscleSplit {
    let reduced = profile?.recoveryReduced ?? false
    let stats = Muscle.allCases.compactMap { muscle -> WeekMuscleStat? in
      guard let landmark = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: reduced)
      else { return nil }
      return WeekMuscleStat(
        muscle: muscle, sets: weekSets[muscle] ?? 0,
        floor: landmark.floor(recoveryReduced: reduced), mrv: landmark.mrv)
    }
    let short = stats.filter { $0.sets < Double($0.floor) }
      .sorted { $0.sets / Double($0.floor) < $1.sets / Double($1.floor) }
    let inRange = stats.filter { $0.sets >= Double($0.floor) && $0.sets <= Double($0.mrv) }
    return MuscleSplit(
      worked: stats.filter { $0.sets > 0 }, short: short, inRange: inRange, trackedCount: stats.count)
  }

  // MARK: - body

  @State private var approving: VolumeIncrease?
  @State private var confirmingStartPlan = false

  var body: some View {
    let data = ProgressData(sessions: sessions, profile: profile)
    let split = muscleSplit(data.last7DaySets)
    return ScrollView {
      VStack(spacing: 0) {
        if verifiedCompletedSessions.count < 2 {
          FieldSection(bottom: 24) {
            emptyCard
              .padding(.top, 8)
          }
        } else {
          FieldSection(bottom: 24) {
            fieldContent(data, split)
          }
          VStack(spacing: 0) {
            attentionSection(split)
            workingSection(data, split)
            changesSection
            if let footer = footerText {
              Text(footer)
                .forge(13)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.margin)
                .padding(.top, 16)
            }
            if showsStartPlan {
              cta
                .padding(.horizontal, Theme.margin)
                .padding(.top, 12)
            }
          }
          .background(Theme.page)
        }
      }
      .padding(.bottom, 24)
    }
    .progressFieldPage(String(localized: "Plan audit", bundle: L10n.bundle))
    .confirmationDialog(
      String(localized: "Start the recommended plan?", bundle: L10n.bundle),
      isPresented: $confirmingStartPlan,
      titleVisibility: .visible
    ) {
      Button(String(localized: "Start the recommended plan", bundle: L10n.bundle), role: .destructive) {
        startBlock()
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized: "The current block restarts with the new split and loads.",
          bundle: L10n.bundle))
    }
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  // MARK: - field

  /// The v6 field hero: verdict, block note and the three "n of m" stats.
  private func fieldContent(_ data: ProgressData, _ split: MuscleSplit) -> some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topTrailing) {
        VStack(alignment: .leading, spacing: 8) {
          Text(verdictTitle(data, split))
            .forge(28, .bold, tracking: -0.5)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          Text(fieldSubtitle(split))
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 76)
        .frame(maxWidth: .infinity, alignment: .leading)
        Image("art-audit")
          .resizable()
          .scaledToFit()
          .frame(width: 64, height: 64)
          .offset(y: -6)
          .accessibilityHidden(true)
      }
      .padding(.top, 4)
      InsightsStatColumns(items: statItems(data, split))
        .padding(.top, 16)
    }
  }

  /// The block line and the verdict sentence joined as the field note.
  private func fieldSubtitle(_ split: MuscleSplit) -> String {
    [headerSubtitle, verdictLine(split)].compactMap { $0 }.joined(separator: ". ")
  }

  /// The three field stats: sessions, lifts and muscles, each "n of m".
  private func statItems(_ data: ProgressData, _ split: MuscleSplit) -> [InsightsStatColumns.Item] {
    [
      InsightsStatColumns.Item(
        label: String(localized: "Sessions done", bundle: L10n.bundle),
        value: "\(plan.done)",
        of: String(localized: "of \(plan.planned)", bundle: L10n.bundle)),
      InsightsStatColumns.Item(
        label: String(localized: "Lifts rising", bundle: L10n.bundle),
        value: "\(data.strongerLifts.count)",
        of: String(localized: "of \(data.comparedLiftCount)", bundle: L10n.bundle)),
      InsightsStatColumns.Item(
        label: String(localized: "Muscles in range", bundle: L10n.bundle),
        value: "\(split.inRange.count)",
        of: String(localized: "of \(split.trackedCount)", bundle: L10n.bundle)),
    ]
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
      Button {
        NotificationCenter.default.post(name: .forgeStartWorkout, object: nil)
      } label: {
        Text(String(localized: "Log a workout", bundle: L10n.bundle))
      }
      .buttonStyle(PillButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - needs attention

  /// Short muscles first, worst first, then held lifts — the rows that ask for a decision.
  /// Empty sections are hidden rather than shown with a "0" count.
  @ViewBuilder
  private func attentionSection(_ split: MuscleSplit) -> some View {
    let newLifts = profile.map { LogV3.nextBlockNewLifts(sessions: sessions, profile: $0) } ?? []
    let rows = split.short.map { stat in
      (stat: stat, increase: pendingIncreases.first { $0.muscle == stat.muscle })
    }
    if !rows.isEmpty || !heldLifts.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Needs attention",
        trailing: "\(rows.count + heldLifts.count)"
      )
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.stat.muscle) { index, row in
          underRow(row.stat, increase: row.increase, newLifts: newLifts)
          if index < rows.count - 1 || !heldLifts.isEmpty { rowDivider(leading: 56) }
        }
        ForEach(Array(heldLifts.enumerated()), id: \.element.exercise.id) { index, held in
          heldRow(held)
          if index < heldLifts.count - 1 { rowDivider(leading: 56) }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
    }
  }

  private func underRow(
    _ stat: WeekMuscleStat, increase: VolumeIncrease?, newLifts: [Exercise]
  ) -> some View {
    HStack(spacing: 12) {
      MuscleRegionThumb(muscle: stat.muscle)
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.muscle.a11yName)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        underSubtitle(stat, increase: increase, newLifts: newLifts)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if let increase {
        ReviewPill(
          accessibilityLabel: String(
            localized: "Review \(stat.muscle.a11yName) change", bundle: L10n.bundle),
          action: { approving = increase })
      }
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: increase == nil ? .combine : .contain)
  }

  /// The sets-versus-floor fact, then the waiting ask or the lift that joins this muscle.
  private func underSubtitle(
    _ stat: WeekMuscleStat, increase: VolumeIncrease?, newLifts: [Exercise]
  ) -> Text {
    var text = Text(
      String(localized: "\(Fmt.num(stat.sets)) of \(stat.floor) sets.", bundle: L10n.bundle))
    if let increase {
      let added = increase.toSets - increase.fromSets
      text = text + Text(" ") + Text(
        String(
          localized: "\(coach.name)'s \(added) set\(L10n.pluralSuffix(added)) in \(localizedDayName(increase.dayName)) wait for you.",
          bundle: L10n.bundle))
    } else if let lift = newLifts.first(where: {
      $0.primary == stat.muscle || $0.synergists.contains(stat.muscle)
    }), let profile {
      let joinDate = LogV3.nextBlockStart(profile: profile, sessions: sessions)
      text = text + Text(" ") + Text(
        String(
          localized: "\(lift.localizedName) joins on \(joinDate.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))).",
          bundle: L10n.bundle))
    }
    return text
  }

  private func heldRow(_ held: HeldLift) -> some View {
    HStack(spacing: 12) {
      LiftToken(exercise: held.exercise, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(held.exercise.localizedName)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        heldSubtitle(held)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(String(localized: "Holding", bundle: L10n.bundle))
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }

  /// The held-lift fact, plus the best-ever line when the latest session is not the best.
  private func heldSubtitle(_ held: HeldLift) -> Text {
    var text = Text(
      String(
        localized: "Held at \(displayKg(held.e1rm, id: held.exercise.id)) est. max for your \(held.flag.name) flag.",
        bundle: L10n.bundle))
    let history = LogV3.e1rmHistory(exerciseID: held.exercise.id, sessions: sessions)
    if let best = history.max(by: { $0.e1rm < $1.e1rm }), let latest = history.last,
      best.e1rm > latest.e1rm
    {
      let month = best.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale))
      text = text + Text(" ") + Text(
        String(
          localized: "Best was \(displayKg(best.e1rm, id: held.exercise.id)) in \(month).",
          bundle: L10n.bundle))
    }
    return text
  }

  /// The hairline between rows of one section, starting past the leading icon.
  private func rowDivider(leading: CGFloat) -> some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, leading)
  }

  // MARK: - working

  /// What the plan already gets right, each row linking to the screen that proves it.
  @ViewBuilder
  private func workingSection(_ data: ProgressData, _ split: MuscleSplit) -> some View {
    let rows = workingRows(data, split)
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Working", trailing: "\(rows.count)"
      )
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          row
          if index < rows.count - 1 { rowDivider(leading: 56) }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
    }
  }

  private func workingRows(_ data: ProgressData, _ split: MuscleSplit) -> [AnyView] {
    var rows: [AnyView] = []
    if plan.planned > 0 {
      let since = firstSessionDate.map {
        $0.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
      } ?? ""
      var subtitle = String(
        localized: "\(plan.done) of \(plan.planned) sessions since \(since)", bundle: L10n.bundle)
      let missed = max(0, plan.planned - plan.done)
      if missed > 0 {
        subtitle += " · " + String(localized: "\(missed) missed", bundle: L10n.bundle)
      }
      rows.append(
        AnyView(
          NavigationLink {
            HistoryView(usesLb: usesLb)
          } label: {
            workingRow(
              symbol: "calendar",
              tint: Theme.metricTime,
              title: String(localized: "You train as planned", bundle: L10n.bundle),
              subtitle: Text(subtitle))
          }
          .buttonStyle(RowPressStyle())))
    }
    if !data.strongerLifts.isEmpty {
      rows.append(
        AnyView(
          NavigationLink {
            ProgressTrendsView(usesLb: usesLb)
          } label: {
            workingRow(
              symbol: "chart.bar.fill",
              tint: Theme.metricSets,
              title: String(
                localized: "\(data.strongerLifts.count) of \(data.comparedLiftCount) lifts are stronger",
                bundle: L10n.bundle),
              subtitle: gainsLine(data.strongerLifts, since: firstSessionDate))
          }
          .buttonStyle(RowPressStyle())))
    }
    if !split.inRange.isEmpty {
      rows.append(
        AnyView(
          NavigationLink {
            MuscleVolumeView(
              weekSets: data.last7DaySets, recoveryReduced: profile?.recoveryReduced ?? false)
          } label: {
            workingRow(
              symbol: "figure.strengthtraining.traditional",
              tint: Theme.positive,
              title: String(
                localized: "\(split.inRange.count) muscles get enough sets", bundle: L10n.bundle),
              subtitle: Text(inRangeNames(split)))
          }
          .buttonStyle(RowPressStyle())))
    }
    return rows
  }

  /// One "Working" row: metric-coloured symbol, title, quiet subtitle, trailing chevron.
  private func workingRow(symbol: String, tint: Color, title: String, subtitle: Text) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .scaledSystemFont(22, weight: .semibold)
        .foregroundStyle(tint)
        .frame(width: 44)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        subtitle
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.forward")
        .scaledSystemFont(13, weight: .semibold)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .contentShape(Rectangle())
  }

  /// The top three gains on one line, the +kg parts in the gain color.
  private func gainsLine(_ lifts: [ProgressData.LiftDelta], since: Date?) -> Text {
    var line = Text("")
    for (index, lift) in lifts.prefix(3).enumerated() {
      if index > 0 { line = line + Text(", ") }
      line = line + Text("\(lift.exercise.localizedName) ")
        + Text(signedKg(lift.deltaKg, id: lift.exercise.id)).foregroundStyle(Theme.positiveText)
    }
    if let since {
      let month = since.formatted(.dateTime.month().locale(L10n.locale))
      line = line + Text(" ") + Text(String(localized: "since \(month)", bundle: L10n.bundle))
    }
    return line
  }

  /// In-range muscle names, comma-separated, lowercase except the first.
  private func inRangeNames(_ split: MuscleSplit) -> String {
    let names = split.inRange.map { $0.muscle.a11yName.lowercased() }.joined(separator: ", ")
    return names.prefix(1).uppercased() + String(names.dropFirst())
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

  private struct ChangeRowModel: Identifiable {
    enum Lead { case coach, lifter, block }
    let id: String
    let date: Date
    let lead: Lead
    let title: String
    let subtitle: String
  }

  @ViewBuilder
  private var changesSection: some View {
    let rows = changeRows
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Changes this block", trailing: "\(rows.count)"
      )
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          changeRow(row)
          if index < rows.count - 1 { rowDivider(leading: 56) }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
    }
  }

  /// Every dated change of this block, newest first, same-day coach loads grouped to one row.
  private var changeRows: [ChangeRowModel] {
    let cal = Calendar.current
    let coachLoads = blockChanges.filter { isCoachMade($0.record) && $0.record.type == "load_change" }
    let groupedIDs = Set(coachLoads.map { $0.record.id })
    var out: [ChangeRowModel] = []
    for (day, entries) in Dictionary(grouping: coachLoads, by: { cal.startOfDay(for: $0.date) }) {
      out.append(loadGroupRow(id: "loads-\(day.timeIntervalSince1970)", entries: entries))
    }
    for entry in blockChanges where !groupedIDs.contains(entry.record.id) {
      out.append(singleChangeRow(entry))
    }
    out.sort { $0.date > $1.date }
    if let info = blockStartInfo {
      out.append(
        ChangeRowModel(
          id: "block-\(info.number)", date: info.start, lead: .block,
          title: String(
            localized: "Block \(info.number) added \(info.rise) sets a week", bundle: L10n.bundle),
          subtitle: "\(shortDate(info.start)) · \(String(localized: "new block volume", bundle: L10n.bundle))"))
    }
    return out
  }

  /// One row for all same-day coach load changes: the shared delta when every lift moved the same.
  private func loadGroupRow(id: String, entries: [DecisionLogEntry]) -> ChangeRowModel {
    let sorted = entries.sorted { $0.date > $1.date }
    let deltas = sorted.compactMap { entry -> Double? in
      guard let from = entry.record.fromValue, let to = entry.record.toValue else { return nil }
      return to - from
    }
    let names = sorted.compactMap { entry in
      entry.record.exerciseID.flatMap { ExerciseDB.find($0)?.localizedName }
    }
    var title = String(localized: "\(sorted.count) loads changed", bundle: L10n.bundle)
    if let delta = deltas.first, delta > 0, deltas.count == sorted.count,
      deltas.allSatisfy { $0 == delta }
    {
      title = String(
        localized: "\(sorted.count) loads up \(displayKg(delta, id: sorted.first?.record.exerciseID ?? ""))",
        bundle: L10n.bundle)
    }
    var parts: [String] = []
    if !names.isEmpty { parts.append(names.joined(separator: ", ") + ".") }
    if let summary = sorted.first?.record.humanSummary, !summary.isEmpty { parts.append(summary) }
    var subtitle = shortDate(sorted.first?.date ?? .now)
    if !parts.isEmpty { subtitle += " · " + parts.joined(separator: " ") }
    return ChangeRowModel(
      id: id, date: sorted.first?.date ?? .now, lead: .coach, title: title, subtitle: subtitle)
  }

  /// One non-grouped decision as a row; volume changes state the applied delta.
  private func singleChangeRow(_ entry: DecisionLogEntry) -> ChangeRowModel {
    let record = entry.record
    let coachMade = isCoachMade(record)
    if coachMade, record.type == "volume_change",
      let exercise = record.exerciseID.flatMap(ExerciseDB.find),
      let from = record.fromValue, let to = record.toValue
    {
      return ChangeRowModel(
        id: record.id, date: entry.date, lead: .coach,
        title: String(
          localized: "\(exercise.localizedName) \(Int(from))\u{00A0}→\u{00A0}\(Int(to)) sets",
          bundle: L10n.bundle),
        subtitle: "\(shortDate(entry.date)) · \(String(localized: "\(coach.name) applied it", bundle: L10n.bundle))")
    }
    var subtitle = shortDate(entry.date)
    if let detail = changeDetail(record) { subtitle += " · \(detail)" }
    return ChangeRowModel(
      id: record.id, date: entry.date, lead: coachMade ? .coach : .lifter,
      title: record.humanSummary.isEmpty ? "—" : record.humanSummary, subtitle: subtitle)
  }

  private func changeRow(_ row: ChangeRowModel) -> some View {
    HStack(alignment: .top, spacing: 12) {
      switch row.lead {
      case .coach:
        CoachAvatar(size: 32)
          .frame(width: 44)
      case .lifter:
        Image(systemName: "slider.horizontal.3")
          .scaledSystemFont(22, weight: .semibold)
          .foregroundStyle(Theme.metricSets)
          .frame(width: 44)
          .accessibilityHidden(true)
      case .block:
        Image(systemName: "calendar")
          .scaledSystemFont(22, weight: .semibold)
          .foregroundStyle(Theme.metricTime)
          .frame(width: 44)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(row.title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(row.subtitle)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64, alignment: .top)
    .accessibilityElement(children: .combine)
  }

  /// Engine decision types the coach made without the lifter overriding them.
  private func isCoachMade(_ record: DecisionRecord) -> Bool {
    ["load_change", "volume_change", "swap", "session", "plateau"].contains(record.type)
      && !record.reasonCodes.contains(DecisionSignal.userOverride.code)
  }

  /// "Tue Sep 22" — the short date every change row leads its subtitle with.
  private func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
  }

  /// The plain observation behind a change: the recorded evidence line, or the humanized
  /// signals when no evidence was written.
  private func changeDetail(_ record: DecisionRecord) -> String? {
    if let first = record.evidence.first { return first }
    guard !record.reasonCodes.isEmpty else { return nil }
    return record.reasonCodes.map { $0.replacingOccurrences(of: "_", with: " ") }
      .joined(separator: ", ")
  }

  /// The block's own set ramp when the plan adds volume week over week — the one dated
  /// change that is not a decision-log entry.
  private var blockStartInfo: (number: Int, start: Date, rise: Int)? {
    guard let profile, let start = blockStart else { return nil }
    let number = LogV3.blocks(sessions: sessions, profile: profile).last?.number
      ?? InsightsV3.blockNumber(of: start, sessions: sessions, profile: profile)
    guard
      let first = LogV3.plannedSets(week: 1, profile: profile, sessions: sessions),
      let peak = LogV3.plannedSets(week: Mesocycle.weeks - 1, profile: profile, sessions: sessions),
      peak > first
    else { return nil }
    let rise = Int((Double(peak - first) / Double(Mesocycle.weeks - 2)).rounded())
    guard rise > 0 else { return nil }
    return (number, start, rise)
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
      confirmingStartPlan = true
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
    guard let profile else { return "\(Fmt.num(kg))\u{00A0}kg" }
    let value = profile.display(kg: kg, for: id)
    return "\(Fmt.num(value))\u{00A0}\(profile.unit(for: id))"
  }

  private func signedKg(_ kg: Double, id: String) -> String {
    guard let profile else {
      return (kg >= 0 ? "+" : "\u{2212}") + "\(Fmt.num(abs(kg)))\u{00A0}kg"
    }
    let value = profile.display(kg: abs(kg), for: id)
    return (kg >= 0.5 ? "+" : "\u{2212}") + "\(Fmt.num(value))\u{00A0}\(profile.unit(for: id))"
  }
}

extension Notification.Name {
  /// Posted after "Start adaptive block" so the import sheet can close itself and the user returns to the app.
  static let forgeAuditStarted = Notification.Name("forge.audit.started")
}
