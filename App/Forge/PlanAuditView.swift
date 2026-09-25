import ForgeCore
import SwiftData
import SwiftUI

struct PlanAuditView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

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

  /// How much of the volume signal rests on effort nobody reported.
  ///
  /// `SetLog.rpe` always holds a number — the plan's target stands in until the lifter rates
  /// the set — and `Autoregulation.signals` compares that field against the same target, so
  /// an unrated set agrees with the plan by construction. This runs the same rule twice, once
  /// as stored and once over rated sets only, and reports where the two disagree. It changes
  /// nothing: the audit reads it, the engine does not.
  private var effortDivergence: EffortDivergenceReport {
    let recent = verifiedCompletedSessions.suffix(8)
    let performances: [ExercisePerformance] = Dictionary(
      grouping: recent.flatMap(\.trustedSets), by: \.exerciseID
    )
    .compactMap { exerciseID, sets in
      guard let exercise = ExerciseDB.find(exerciseID) else { return nil }
      return ExercisePerformance(
        exercise: exercise,
        repRange: 8...12,
        targetRPE: sets.first?.targetRPE ?? 8,
        sets: sets.map {
          SetLog(
            weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe,
            effortReported: $0.effortReported)
        })
    }
    return EffortDivergence.report(performances)
  }

  /// Shown only when it is actually true: some of the recent volume signal came from sets the
  /// lifter never rated. Saying so is the difference between a reading and a guess.
  @ViewBuilder private var effortCoverageCard: some View {
    let report = effortDivergence
    if report.unratedSetsRead > 0 {
      VStack(alignment: .leading, spacing: 8) {
        Text("Effort coverage").forgeSection()
        Text(
          String(
            localized:
              "\(report.unratedSetsRead) of your recent counting sets carry the plan's target rather than a rating you gave.",
            bundle: L10n.bundle)
        )
        .forgeBody()
        Text(
          String(
            localized:
              "Volume decisions read that field either way. Rate your hard sets and this page describes what you actually did.",
            bundle: L10n.bundle)
        )
        .forgeCaption()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
      .accessibilityIdentifier("planAudit.effortCoverage")
    }
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

  private var progressing: [PlanAudit.LiftTrend] {
    audit.trends.filter { $0.direction == .progressing }
  }
  private var stalled: [PlanAudit.LiftTrend] {
    audit.trends.filter { $0.direction == .flat || $0.direction == .declining }
  }
  private var offVolume: [PlanAudit.MuscleVolume] {
    audit.muscles.filter { $0.verdict != .inRange }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        effortCoverageCard
        if verifiedCompletedSessions.count < 2 {
          emptyCard
        } else {
          whatILearned
          if !progressing.isEmpty { progressingCard }
          if !stalled.isEmpty { stalledCard }
          if !offVolume.isEmpty { volumeCard }
          firstWeekCard
          cta
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(String(localized: "Plan review", bundle: L10n.bundle))
  }

  // MARK: - Empty state

  private var emptyCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-empty-progress", height: 120)
      Text(String(localized: "Not enough history", bundle: L10n.bundle)).forgeSection()
      Text(
        String(
          localized:
            "The audit needs a workout or an import. Log a couple of sessions or bring your old log.",
          bundle: L10n.bundle)
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .card()
  }

  // MARK: - What I learned

  private var whatILearned: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(audit.headline).forgeTitle()
      MetricGrid(items: [
        MetricItem(String(localized: "Sessions", bundle: L10n.bundle), "\(audit.sessionCount)"),
        MetricItem(String(localized: "Weeks", bundle: L10n.bundle), "\(audit.weeks)"),
        MetricItem(
          String(localized: "Per week", bundle: L10n.bundle), Fmt.num(audit.sessionsPerWeek),
          unit: "/wk"),
        MetricItem(
          String(localized: "Split", bundle: L10n.bundle), splitNames.joined(separator: " · ")),
      ])
      Divider().overlay(Theme.ring)
      infoLine(
        String(localized: "Frequency", bundle: L10n.bundle),
        String(localized: "\(Int(audit.sessionsPerWeek.rounded())) a week", bundle: L10n.bundle))
      infoLine(
        String(localized: "Preferred rep range", bundle: L10n.bundle),
        String(localized: "\(preferredRepBand) reps", bundle: L10n.bundle))
      if !topLiftsText.isEmpty {
        infoLine(String(localized: "Top lifts", bundle: L10n.bundle), topLiftsText)
      }
      Text(
        String(
          localized: "Suggested split: \(splitNames.joined(separator: " · "))", bundle: L10n.bundle)
      )
      .forgeBodyStrong()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func infoLine(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label).forgeLabel()
      Spacer()
      Text(value).forgeBodyStrong().multilineTextAlignment(.trailing)
    }
  }

  private var preferredRepBand: String {
    var counts: [String: Int] = [:]
    for set in auditSets { counts[repBand(set.reps), default: 0] += 1 }
    return ["3–6", "5–8", "8–12", "12–20"].max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? "8–12"
  }

  private func repBand(_ reps: Int) -> String {
    switch reps {
    case 12...20: return "12–20"
    case 8...11: return "8–12"
    case 5...7: return "5–8"
    default: return "3–6"
    }
  }

  private var topLiftsText: String {
    audit.trends
      .sorted { $0.latestE1RM > $1.latestE1RM }
      .prefix(3)
      .map { "\($0.exercise.localizedName) \(displayKg($0.latestE1RM, id: $0.exercise.id))" }
      .joined(separator: " · ")
  }

  // MARK: - Progressing / Stalled

  private var progressingCard: some View {
    sectionCard(String(localized: "Progressing", bundle: L10n.bundle)) {
      ForEach(progressing) { t in
        trendRow(t, color: Theme.positive)
      }
    }
  }

  private var stalledCard: some View {
    sectionCard(String(localized: "Stalled", bundle: L10n.bundle)) {
      ForEach(stalled) { t in
        trendRow(
          t,
          color: t.direction == .declining ? Theme.negative : Theme.metricEffort,
          note: t.direction == .flat
            ? String(localized: "Candidate for a variant swap", bundle: L10n.bundle) : nil)
      }
    }
  }

  private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).forgeSection()
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func trendRow(_ t: PlanAudit.LiftTrend, color: Color, note: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(t.exercise.localizedName).forgeBodyStrong()
        Spacer()
        Text(signedPercent(t.changePercent))
          .foregroundStyle(color)
          .forgeBodyStrong()
          .monospacedDigit()
      }
      Text(
        "\(displayKg(t.firstE1RM, id: t.exercise.id)) → \(displayKg(t.latestE1RM, id: t.exercise.id))"
      )
      .forgeCaption()
      .foregroundStyle(color)
      if let note {
        Text(note).forgeCaption()
      }
    }
  }

  private func signedPercent(_ v: Double) -> String {
    (v >= 0 ? "+" : "") + Fmt.num(v) + "%"
  }

  // MARK: - Volume

  private var volumeCard: some View {
    sectionCard(String(localized: "Volume", bundle: L10n.bundle)) {
      ForEach(offVolume) { v in
        volumeRow(v)
        if v.id != offVolume.last?.id { Divider().overlay(Theme.ring) }
      }
    }
  }

  private func volumeRow(_ v: PlanAudit.MuscleVolume) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(v.muscle.a11yName).forgeBodyStrong()
        Spacer()
        Text(String(localized: "\(Fmt.num(v.setsPerWeek)) /wk", bundle: L10n.bundle)).forgeLabel()
          .monospacedDigit()
      }
      bandBar(v)
      HStack {
        Text(verdictText(v.verdict)).forgeCaption().foregroundStyle(verdictColor(v.verdict))
        Spacer()
        Text("\(v.mev)–\(v.mrv)").forgeCaption()
      }
    }
  }

  private func bandBar(_ v: PlanAudit.MuscleVolume) -> some View {
    let scale = Double(max(v.mrv, 1)) * 1.25
    return GeometryReader { geo in
      let w = geo.size.width
      let mevX = Double(v.mev) / scale * w
      let mrvX = Double(v.mrv) / scale * w
      let valX = min(v.setsPerWeek, scale) / scale * w
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track).frame(height: 8)
        Capsule().fill(Theme.accent.opacity(0.25)).frame(width: max(0, mrvX - mevX), height: 8)
          .offset(x: mevX)
        Circle().fill(verdictColor(v.verdict)).frame(width: 12, height: 12).offset(
          x: max(0, valX - 6))
      }
    }
    .frame(height: 12)
  }

  private func verdictText(_ v: PlanAudit.MuscleVolume.Verdict) -> String {
    switch v {
    case .under: return String(localized: "Under MEV", bundle: L10n.bundle)
    case .over: return String(localized: "Over MRV", bundle: L10n.bundle)
    case .untrained: return String(localized: "Not trained", bundle: L10n.bundle)
    case .inRange: return String(localized: "In range", bundle: L10n.bundle)
    }
  }

  private func verdictColor(_ v: PlanAudit.MuscleVolume.Verdict) -> Color {
    switch v {
    case .under: return Theme.metricEffort
    case .over: return Theme.negative
    case .untrained: return Theme.textTertiary
    case .inRange: return Theme.positive
    }
  }

  // MARK: - First week

  @ViewBuilder
  private var firstWeekCard: some View {
    if let input {
      VStack(alignment: .leading, spacing: 12) {
        Text(String(localized: "Your first week", bundle: L10n.bundle)).forgeSection()
        if let firstDay = Program.week(1, profile: input).first {
          ForEach(firstDay.exercises) { planned in
            HStack {
              Text(planned.exercise.localizedName).forgeBodyStrong()
              Spacer()
              Text(
                String(
                  localized:
                    "\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) reps",
                  bundle: L10n.bundle)
              )
              .forgeLabel()
              .monospacedDigit()
            }
          }
        }
        Divider().overlay(Theme.ring)
        Text(String(localized: "Planned sets per week", bundle: L10n.bundle)).forgeLabel()
        HStack(spacing: 8) {
          ForEach(weeklySetTotals(input)) { entry in
            VStack(spacing: 4) {
              Text("W\(entry.week)").forgeCaption()
              Text("\(entry.sets)").forgeBodyStrong().monospacedDigit()
              if entry.deload {
                Text(String(localized: "Deload", bundle: L10n.bundle)).forgeCaption()
                  .foregroundStyle(Theme.metricEffort)
              }
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
    }
  }

  private struct WeekTotal: Identifiable {
    let week: Int
    let sets: Int
    let deload: Bool
    var id: Int { week }
  }

  private func weeklySetTotals(_ input: ProfileInput) -> [WeekTotal] {
    (1...Mesocycle.weeks).map { w in
      let total = Program.week(w, profile: input).reduce(0) {
        $0 + $1.exercises.reduce(0) { $0 + $1.sets }
      }
      return WeekTotal(week: w, sets: total, deload: w == Mesocycle.deloadWeek)
    }
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
}

extension Notification.Name {
  /// Posted after "Start adaptive block" so the import sheet can close itself and the user returns to the app.
  static let forgeAuditStarted = Notification.Name("forge.audit.started")
}
