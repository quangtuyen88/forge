import ForgeCore
import SwiftData
import SwiftUI

/// One goal at a time, judged only from what actually happened.
///
/// Progress never comes from a typed number: it comes from verified sets in completed
/// sessions (`WorkoutSession.trustedSets`), filtered again by load comparability, and then
/// handed to `GoalProgressPolicy`. If there is not enough verified evidence the screen says
/// so and shows no progress figure at all — a goal can never be presented as achieved from
/// insufficient data, and excluded evidence is listed rather than quietly dropped.
struct GoalRoadmapView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  @State private var goals: [GoalRecord] = []
  @State private var didLoad = false
  @State private var editorTarget: GoalRoadmapEditorTarget?
  @State private var archiveCandidate: GoalRecord?
  @State private var showsArchived = false
  @State private var banner: String?

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }

  private var activeGoals: [GoalRecord] {
    goals.filter { $0.status != .abandoned }.sorted { $0.createdAt > $1.createdAt }
  }

  private var archivedGoals: [GoalRecord] {
    goals.filter { $0.status == .abandoned }.sorted { $0.createdAt > $1.createdAt }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        introCard
        if let banner {
          Text(banner).forgeCaption().frame(maxWidth: .infinity, alignment: .leading)
        }
        if activeGoals.isEmpty {
          emptyCard
        } else {
          ForEach(activeGoals) { goal in goalCard(goal) }
        }
        if !archivedGoals.isEmpty { archivedCard }
        rulesCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Goal roadmap")
    .onAppear { load() }
    .onChange(of: profiles.count) { _, _ in load() }
    .sheet(item: $editorTarget) { target in
      GoalRoadmapEditorSheet(
        existing: target.record, sessions: sessions, usesLb: usesLb
      ) { record in
        save(record)
      }
    }
    .confirmationDialog(
      "Archive this goal?", isPresented: archivePresented, titleVisibility: .visible
    ) {
      Button("Archive", role: .destructive) {
        if let goal = archiveCandidate { archive(goal) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Archiving stops progress tracking and moves the goal to your archive. The evidence stays in your session history, and you can restore the goal later."
      )
    }
  }

  // MARK: - Loading and persistence

  private func load() {
    guard !didLoad, let profile else { return }
    didLoad = true
    goals = profile.goalRecords
  }

  private func persist() {
    guard let profile else { return }
    profile.goalRecords = goals
    try? modelContext.save()
  }

  private func save(_ record: GoalRecord) {
    var record = record
    // Keep the stored evidence count equal to the records that count right now.
    record.evidenceCount =
      GoalEvidenceDerivation.derive(goal: record, sessions: sessions).evidence.count
    if let index = goals.firstIndex(where: { $0.id == record.id }) {
      goals[index] = record
    } else {
      goals.append(record)
    }
    log(
      record, type: "goal",
      summary:
        "Goal saved: \(record.title.isEmpty ? record.kind.rawValue : record.title) "
        + "(\(record.kind.rawValue), target \(numberText(record.targetValue, goal: record)) \(unitLabel(record)))"
    )
    persist()
    banner = "Saved. Progress is derived from your recorded sessions."
    Analytics.track("goal_saved", ["kind": record.kind.rawValue])
  }

  private func archive(_ goal: GoalRecord) {
    guard var record = goals.first(where: { $0.id == goal.id }) else { return }
    record.status = .abandoned
    if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = record }
    log(
      record, type: "goal.archive",
      summary: "Goal archived: \(record.title.isEmpty ? record.kind.rawValue : record.title)")
    persist()
    banner = "Archived. Restore it any time — the evidence was never deleted."
    Analytics.track("goal_archived", ["kind": record.kind.rawValue])
  }

  private func restore(_ goal: GoalRecord) {
    guard var record = goals.first(where: { $0.id == goal.id }) else { return }
    record.status = .notStarted
    if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = record }
    log(
      record, type: "goal.restore",
      summary: "Goal restored: \(record.title.isEmpty ? record.kind.rawValue : record.title)")
    persist()
    banner = "Restored. It is collecting evidence again."
  }

  /// Used only when a stored record claims more than the evidence supports.
  private func correctStatus(_ goal: GoalRecord) {
    guard var record = goals.first(where: { $0.id == goal.id }) else { return }
    let evidence = GoalEvidenceDerivation.derive(goal: record, sessions: sessions).evidence
    let progress = GoalProgressPolicy.progress(goal: record, evidence: evidence)
    record.status = .notStarted
    if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = record }
    log(
      record, type: "goal.statusCorrection",
      summary:
        "Goal status corrected: the stored record claimed achievement with "
        + "\(progress.verifiedEvidenceCount) verified of \(record.minimumVerifiedEvidence) required records"
    )
    persist()
    banner = "Status corrected. Progress shown here is derived from evidence only."
  }

  private func log(_ goal: GoalRecord, type: String, summary: String) {
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "\(type)-\(goal.id)-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: type,
          exerciseID: benchmarkExerciseID(goal),
          muscle: nil,
          fromValue: nil,
          toValue: goal.targetValue,
          reasonCodes: [DecisionSignal.userOverride.code],
          evidence: [
            goal.kind.rawValue,
            "baseline \(numberText(goal.baseline, goal: goal)) \(unitLabel(goal))",
            "target \(numberText(goal.targetValue, goal: goal)) \(unitLabel(goal))",
            "\(goal.evidenceCount) counting records",
          ],
          humanSummary: summary)))
  }

  private var archivePresented: Binding<Bool> {
    Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })
  }

  private func benchmarkExerciseID(_ goal: GoalRecord) -> String? {
    if case .benchmark(let target) = goal.target { return target.exerciseID }
    return nil
  }

  // MARK: - Cards

  private var introCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("One goal, judged on evidence").forgeTitle()
      Text(
        "Progress comes from verified sets in your completed sessions, never from a number typed into this screen."
      )
      .forgeLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var emptyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("No goal set", systemImage: "target").forgeSection()
      Text(
        "Pick one thing to work toward: a benchmark on one lift, a skill that needs repeated practice, or an adherence target counted in sessions."
      )
      .forgeCaption()
      Button("Set a goal") { editorTarget = .new }
        .buttonStyle(PillButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func goalCard(_ goal: GoalRecord) -> some View {
    let derivation = GoalEvidenceDerivation.derive(goal: goal, sessions: sessions)
    let progress = GoalProgressPolicy.progress(goal: goal, evidence: derivation.evidence)
    let validation = GoalValidationPolicy.validate(goal: goal, evidence: derivation.evidence)
    let status = displayedStatus(progress: progress)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(goal.title.isEmpty ? kindTitle(goal) : goal.title).forgeSection()
          Text(targetLine(goal)).forgeLabel()
        }
        Spacer(minLength: 8)
        GoalRoadmapStatusChip(status: status)
      }

      if let note = measurabilityNote(goal) {
        Label(note, systemImage: "info.circle")
          .forgeCaption()
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      evidenceCoverage(goal, progress)

      if progress.isConclusive, let current = progress.current {
        progressBlock(goal, progress, current: current)
        milestoneLadder(goal, progress)
      }

      if let reason = progress.reason {
        Text(reason).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }

      if !derivation.evidence.isEmpty { evidenceList(goal, derivation) }
      if !derivation.exclusions.isEmpty { exclusionList(derivation) }
      if let note = goal.note, !note.isEmpty {
        Text(note).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }

      goalWarning(goal: goal, progress: progress, validation: validation)

      HStack(spacing: 8) {
        Button("Edit goal") { editorTarget = .existing(goal) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        if goal.status == .abandoned {
          Button("Restore") { restore(goal) }
            .buttonStyle(PillSecondaryButtonStyle())
        } else {
          Button("Archive") { archiveCandidate = goal }
            .buttonStyle(PillSecondaryButtonStyle())
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func evidenceCoverage(_ goal: GoalRecord, _ progress: GoalProgress) -> some View {
    let required = goal.minimumVerifiedEvidence
    let have = progress.verifiedEvidenceCount
    let fraction = required > 0 ? min(1, Double(have) / Double(required)) : 0
    let complete = have >= required
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Evidence coverage").forgeOverline()
        Spacer(minLength: 8)
        Text("\(have) of \(required) verified").forgeCaption().monospacedDigit()
      }
      GoalRoadmapBar(
        fraction: fraction, color: complete ? Theme.metricSets : Theme.rampColor(max(fraction, 0.02)))
      Text(
        complete
          ? "Enough verified records to judge this goal."
          : "Needs \(required - have) more verified record\(L10n.pluralSuffix(required - have)). Until then no progress figure is shown and the goal cannot be marked achieved."
      )
      .forgeCaption()
      .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Evidence coverage")
    .accessibilityValue("\(have) of \(required) required verified records")
  }

  private func progressBlock(_ goal: GoalRecord, _ progress: GoalProgress, current: Double)
    -> some View
  {
    let fraction = progress.fraction ?? 0
    let color = progressColor(goal)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .lastTextBaseline, spacing: 8) {
        MetricValue(
          value: numberText(current, goal: goal), unit: unitLabel(goal), size: 30, color: color)
        Spacer(minLength: 8)
        Text("Target \(numberText(goal.targetValue, goal: goal)) \(unitLabel(goal))")
          .forgeCaption()
          .monospacedDigit()
      }
      GoalRoadmapBar(fraction: fraction, color: color)
      Text(
        "Baseline \(numberText(goal.baseline, goal: goal)) \(unitLabel(goal)) · \(Int((fraction * 100).rounded()))% of the distance to target"
      )
      .forgeCaption()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Progress")
    .accessibilityValue(
      "\(numberText(current, goal: goal)) of \(numberText(goal.targetValue, goal: goal)) \(unitLabel(goal))")
  }

  private func milestoneLadder(_ goal: GoalRecord, _ progress: GoalProgress) -> some View {
    let color = progressColor(goal)
    return VStack(alignment: .leading, spacing: 4) {
      Text("Milestones").forgeOverline()
      ForEach(progress.milestones) { milestone in
        let reached = progress.hasReached(milestone)
        HStack(spacing: 10) {
          Image(systemName: reached ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(reached ? color : Theme.textTertiary)
            .frame(width: 18)
          Text(milestone.label)
            .forge(12, .semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 42, alignment: .leading)
          Text("\(numberText(milestone.value, goal: goal)) \(unitLabel(goal))").forge(13, .medium)
          Spacer(minLength: 8)
          if !reached && progress.nextMilestone?.id == milestone.id {
            Text("Next").forgeOverline()
          }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func evidenceList(_ goal: GoalRecord, _ derivation: GoalEvidenceDerivation.Result)
    -> some View
  {
    let recent = Array(derivation.evidence.sorted { $0.occurredAt > $1.occurredAt }.prefix(3))
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Counting records").forgeOverline()
        Spacer(minLength: 8)
        Text("\(derivation.evidence.count) total").forgeCaption().monospacedDigit()
      }
      ForEach(recent) { item in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "checkmark.seal").foregroundStyle(Theme.metricSets).frame(width: 18)
          VStack(alignment: .leading, spacing: 2) {
            Text(evidenceLine(goal, item)).forgeBodyStrong().monospacedDigit()
            Text(item.note.map { localizedDayName($0) } ?? "Recorded session").forgeCaption()
          }
        }
        .accessibilityElement(children: .combine)
      }
      if derivation.evidence.count > recent.count {
        Text("+\(derivation.evidence.count - recent.count) older records").forgeCaption()
      }
    }
  }

  private func exclusionList(_ derivation: GoalEvidenceDerivation.Result) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Not counted").forgeOverline()
      ForEach(derivation.exclusions) { exclusion in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "minus.circle").foregroundStyle(Theme.textTertiary).frame(width: 18)
          Text(
            exclusion.count > 0
              ? "\(exclusion.count) \(exclusion.reason), not counted"
              : exclusion.reason
          )
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  @ViewBuilder
  private func goalWarning(goal: GoalRecord, progress: GoalProgress, validation: GoalValidation)
    -> some View
  {
    let claimsAchievement =
      validation.contains(.achievedWithoutSufficientEvidence)
      || validation.contains(.achievedBelowTarget)
    if claimsAchievement {
      VStack(alignment: .leading, spacing: 8) {
        Label("Not backed by evidence", systemImage: "exclamationmark.triangle.fill")
          .forgeBodyStrong()
          .foregroundStyle(Theme.negative)
        Text(
          "This goal is stored as achieved, but \(progress.verifiedEvidenceCount) of \(goal.minimumVerifiedEvidence) required verified record\(L10n.pluralSuffix(goal.minimumVerifiedEvidence)) count for it. It is not shown as achieved here."
        )
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
        Button("Correct the stored status") { correctStatus(goal) }
          .buttonStyle(PillSecondaryButtonStyle())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card(fill: Theme.negative.opacity(0.07))
    } else if !validation.issues.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Image(systemName: "info.circle").foregroundStyle(Theme.textSecondary)
          Text("Check this goal").forgeSection()
        }
        ForEach(validation.issues.prefix(2)) { issue in
          Text(warningText(issue.code)).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
    }
  }

  private var archivedCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(.snappy) { showsArchived.toggle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "archivebox").foregroundStyle(Theme.textSecondary)
          Text("Archived goals").forgeSection()
          Spacer(minLength: 8)
          Text("\(archivedGoals.count)").forgeCaption().monospacedDigit()
          Image(systemName: showsArchived ? "chevron.up" : "chevron.down")
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Archived goals, \(archivedGoals.count)")
      if showsArchived {
        ForEach(archivedGoals) { goal in
          Divider().overlay(Theme.ring)
          VStack(alignment: .leading, spacing: 8) {
            Text(goal.title.isEmpty ? kindTitle(goal) : goal.title).forgeBodyStrong()
            Text(targetLine(goal)).forgeCaption()
            HStack(spacing: 8) {
              Button("Restore") { restore(goal) }
                .buttonStyle(GoalRoadmapCompactButtonStyle())
              Button("Review evidence") { editorTarget = .existing(goal) }
                .buttonStyle(GoalRoadmapCompactButtonStyle())
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var rulesCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("How a goal is judged").forgeSection()
      ruleRow(
        "checkmark.seal", "Verified sets only",
        "Evidence comes from completed sessions whose sets passed the plausibility guard. One good day is never enough: a benchmark needs 1 verified record, a skill needs \(GoalEvidencePolicy.minimumVerifiedEvidence(for: .skill)).",
        Theme.metricSets)
      ruleRow(
        "arrow.left.arrow.right", "Comparable loads only",
        "Sets on a machine or cable with an ambiguous load model, and band tension, are listed but never counted toward a load target — they are not comparable.",
        Theme.metricTime)
      ruleRow(
        "chart.line.uptrend.xyaxis", "Estimated 1RM",
        "Estimated 1RM uses the Epley formula on sets of 1–15 reps. Sets outside that range are listed as excluded.",
        Theme.accentValue)
      ruleRow(
        "archivebox", "One at a time",
        "Archive a goal before starting another, so the roadmap always answers one question honestly.",
        Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func ruleRow(_ symbol: String, _ title: String, _ text: String, _ color: Color)
    -> some View
  {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(text).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Presentation helpers

  private func displayedStatus(progress: GoalProgress) -> GoalRoadmapStatus {
    if progress.status == .achieved && !progress.isConclusive {
      return GoalRoadmapStatus(
        label: "Needs evidence", color: Theme.negative, symbol: "exclamationmark.triangle.fill")
    }
    switch progress.status {
    case .achieved:
      return GoalRoadmapStatus(
        label: "Achieved", color: Theme.metricSets, symbol: "checkmark.seal.fill")
    case .onTrack:
      return GoalRoadmapStatus(
        label: "On track", color: Theme.metricSets, symbol: "arrow.up.right.circle.fill")
    case .atRisk:
      return GoalRoadmapStatus(
        label: "At risk", color: Theme.negative, symbol: "exclamationmark.circle.fill")
    case .expired:
      return GoalRoadmapStatus(
        label: "Expired", color: Theme.textSecondary, symbol: "calendar.badge.exclamationmark")
    case .abandoned:
      return GoalRoadmapStatus(label: "Archived", color: Theme.textSecondary, symbol: "archivebox")
    case .notStarted:
      return GoalRoadmapStatus(label: "Collecting", color: Theme.metricTime, symbol: "hourglass")
    }
  }

  private func progressColor(_ goal: GoalRecord) -> Color {
    switch goal.target {
    case .benchmark: return Theme.accentValue
    case .skill: return Theme.metricSets
    case .adherence: return Theme.accentValue
    }
  }

  private func kindTitle(_ goal: GoalRecord) -> String {
    switch goal.kind {
    case .benchmark: return "Benchmark goal"
    case .skill: return "Skill goal"
    case .adherence: return "Adherence goal"
    }
  }

  private func targetLine(_ goal: GoalRecord) -> String {
    let deadlineText = goal.deadline.map { " · by \(GoalRoadmapText.shortDate($0))" } ?? ""
    switch goal.target {
    case .benchmark(let target):
      let exercise = ExerciseDB.find(target.exerciseID)?.localizedName ?? target.exerciseID
      let comparison = target.comparator == .atLeast ? "at least" : "at most"
      return
        "Benchmark · \(exercise) · \(metricName(target.metric)) \(comparison) \(numberText(target.target, goal: goal)) \(unitLabel(goal))\(deadlineText)"
    case .skill(let target):
      let needs = target.requiredEvidenceKind.map { " · verified \(evidenceKindName($0)) records" } ?? ""
      return
        "Skill · \(target.skillName) · \(numberText(target.target, goal: goal)) \(unitLabel(goal))\(needs)\(deadlineText)"
    case .adherence(let target):
      return
        "Adherence · \(adherenceName(target.metric)) · \(numberText(target.target, goal: goal)) \(unitLabel(goal)) over \(target.windowWeeks) week\(target.windowWeeks == 1 ? "" : "s")\(deadlineText)"
    }
  }

  private func measurabilityNote(_ goal: GoalRecord) -> String? {
    switch goal.target {
    case .benchmark:
      return nil
    case .skill(let target):
      guard let kind = target.requiredEvidenceKind, kind != .measured else { return nil }
      return
        "This target needs verified \(evidenceKindName(kind)) records, which session history cannot supply. Progress stays at collecting until those records exist."
    case .adherence(let target):
      guard target.metric == .completionRate else { return nil }
      return
        "A completion-rate target is a percentage. This app counts adherence from verified session records, so it cannot judge a rate and this goal is never marked achieved here."
    }
  }

  private func warningText(_ code: GoalValidationCode) -> String {
    switch code {
    case .emptyTitle: return "Give this goal a title so you can recognise it later."
    case .deadlineBeforeCreation: return "The deadline is before the goal was created."
    case .targetEqualsBaseline: return "Target equals baseline, so there is no distance to close."
    case .evidenceCountMismatch:
      return
        "The stored evidence count differs from the records that count now. Saving this goal refreshes it."
    case .unsupportedVersion: return "This goal was written by a newer version of the app."
    case .emptyIdentifier: return "This goal has no stable identifier."
    case .achievedWithoutSufficientEvidence, .achievedBelowTarget:
      return "The stored status claims more than the evidence supports."
    }
  }

  private func evidenceLine(_ goal: GoalRecord, _ item: GoalEvidence) -> String {
    let date = GoalRoadmapText.shortDate(item.occurredAt)
    guard let value = item.value else { return date }
    return "\(date) · \(numberText(value, goal: goal)) \(unitLabel(goal))"
  }

  private func numberText(_ value: Double, goal: GoalRecord) -> String {
    switch goal.unit {
    case .kilograms, .pounds:
      return Fmt.num(usesLb ? Plates.kgToLb(value) : value)
    case .repetitions, .sessions, .count:
      return Fmt.num(value, max: 0)
    default:
      return Fmt.num(value)
    }
  }

  private func unitLabel(_ goal: GoalRecord) -> String {
    if case .benchmark(let target) = goal.target, target.metric == .volume {
      return usesLb ? "lb·reps" : "kg·reps"
    }
    if goal.kind == .skill { return "records" }
    switch goal.unit {
    case .kilograms, .pounds: return usesLb ? "lb" : "kg"
    default: return goal.unit.name
    }
  }

  private func metricName(_ metric: BenchmarkMetric) -> String {
    switch metric {
    case .estimatedOneRepMax: return "estimated 1RM"
    case .topSetLoad: return "top set load"
    case .reps: return "most reps"
    case .volume: return "session volume"
    }
  }

  private func adherenceName(_ metric: AdherenceMetric) -> String {
    switch metric {
    case .completedSessions: return "sessions completed"
    case .sessionsPerWeek: return "sessions per week"
    case .completionRate: return "completion rate"
    }
  }

  private func evidenceKindName(_ kind: GoalEvidenceKind) -> String {
    switch kind {
    case .measured: return "measured"
    case .manual: return "manual"
    case .coachSignOff: return "coach sign-off"
    case .video: return "video"
    case .imported: return "imported"
    }
  }
}

// MARK: - Pieces

private struct GoalRoadmapStatus {
  let label: String
  let color: Color
  let symbol: String
}

private struct GoalRoadmapStatusChip: View {
  let status: GoalRoadmapStatus

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: status.symbol).font(.system(size: 11, weight: .semibold))
      Text(status.label).forge(12, .semibold)
    }
    .foregroundStyle(status.color)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(Capsule().fill(status.color.opacity(0.14)))
    .accessibilityLabel("Status")
    .accessibilityValue(status.label)
  }
}

private struct GoalRoadmapBar: View {
  let fraction: Double
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track)
        Capsule().fill(color)
          .frame(width: geometry.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 8)
    .accessibilityHidden(true)
  }
}

private struct GoalRoadmapCompactButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .forge(14, .semibold)
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background(Capsule().fill(Theme.innerSurface))
      .overlay(Capsule().strokeBorder(Theme.ring, lineWidth: 1))
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
  }
}

private enum GoalRoadmapEditorTarget: Identifiable {
  case new
  case existing(GoalRecord)

  var id: String {
    switch self {
    case .new: return "new"
    case .existing(let record): return record.id
    }
  }

  var record: GoalRecord? {
    switch self {
    case .new: return nil
    case .existing(let record): return record
    }
  }
}

// MARK: - Evidence derivation

/// Turns recorded sessions into the evidence a goal is allowed to be judged on.
///
/// Deliberately conservative: only completed sessions, only sets the plausibility guard
/// trusted, only loads whose normalization is verified, and only inside the goal's own
/// window. Everything dropped is reported with a reason.
enum GoalEvidenceDerivation {
  struct Exclusion: Identifiable {
    let id = UUID()
    let reason: String
    let count: Int
  }

  struct Result {
    let evidence: [GoalEvidence]
    let exclusions: [Exclusion]
  }

  static func derive(goal: GoalRecord, sessions: [WorkoutSession], now: Date = .now) -> Result {
    var exclusions: [Exclusion] = []
    var inWindow: [WorkoutSession] = []
    var afterDeadline = 0
    var beforeCreation = 0
    for session in sessions where session.completed {
      guard session.date <= now else { continue }
      if session.date < goal.createdAt {
        beforeCreation += 1
        continue
      }
      if let deadline = goal.deadline, session.date > deadline {
        afterDeadline += 1
        continue
      }
      inWindow.append(session)
    }
    if beforeCreation > 0 {
      exclusions.append(
        Exclusion(reason: "sessions from before this goal existed", count: beforeCreation))
    }
    if afterDeadline > 0 {
      exclusions.append(
        Exclusion(reason: "sessions recorded after the deadline", count: afterDeadline))
    }

    let outcome: (evidence: [GoalEvidence], exclusions: [Exclusion])
    switch goal.target {
    case .benchmark(let target):
      outcome = benchmark(goal: goal, target: target, sessions: inWindow)
    case .skill(let target):
      outcome = skill(goal: goal, target: target, sessions: inWindow)
    case .adherence(let target):
      outcome = adherence(goal: goal, target: target, sessions: inWindow)
    }
    return Result(evidence: outcome.evidence, exclusions: exclusions + outcome.exclusions)
  }

  /// The best value the lifter has actually recorded for an exercise — used to seed a
  /// baseline from history instead of asking them to invent one.
  static func recordedBest(
    exerciseID: String, metric: BenchmarkMetric, sessions: [WorkoutSession], now: Date = .now
  ) -> (value: Double, date: Date, source: String)? {
    var best: (value: Double, date: Date, source: String)?
    for session in sessions where session.completed && session.date <= now {
      let outcome = sessionValue(session: session, exerciseID: exerciseID, metric: metric)
      guard let value = outcome.value, value > 0 else { continue }
      if best == nil || value > best!.value {
        best = (value, session.date, localizedDayName(session.dayName))
      }
    }
    return best
  }

  // MARK: per target kind

  private static func benchmark(
    goal: GoalRecord, target: BenchmarkTarget, sessions: [WorkoutSession]
  ) -> (evidence: [GoalEvidence], exclusions: [Exclusion]) {
    var evidence: [GoalEvidence] = []
    var ambiguous = 0
    var unsupported = 0
    var outsideRepRange = 0
    var withoutValue = 0

    for session in sessions {
      let outcome = sessionValue(
        session: session, exerciseID: target.exerciseID, metric: target.metric)
      ambiguous += outcome.ambiguousSets
      unsupported += outcome.unsupportedSets
      outsideRepRange += outcome.outsideRepRangeSets
      guard let value = outcome.value, value > 0 else {
        if outcome.ambiguousSets == 0 && outcome.unsupportedSets == 0
          && session.sets.contains(where: { $0.exerciseID == target.exerciseID })
        {
          withoutValue += 1
        }
        continue
      }
      evidence.append(
        GoalEvidence(
          id: "\(goal.id)#\(Int(session.date.timeIntervalSince1970))",
          goalID: goal.id,
          kind: .measured,
          exerciseID: target.exerciseID,
          verified: true,
          value: value,
          occurredAt: session.date,
          note: session.dayName))
    }

    var exclusions: [Exclusion] = []
    if ambiguous > 0 {
      exclusions.append(
        Exclusion(reason: "sets on a machine or cable with an ambiguous load model", count: ambiguous))
    }
    if unsupported > 0 {
      exclusions.append(Exclusion(reason: "sets recorded against band tension", count: unsupported))
    }
    if outsideRepRange > 0 {
      exclusions.append(
        Exclusion(reason: "sets outside the 1–15 reps e1RM is estimated from", count: outsideRepRange)
      )
    }
    if withoutValue > 0 {
      exclusions.append(
        Exclusion(reason: "sessions with no usable recorded value", count: withoutValue))
    }
    return (evidence, exclusions)
  }

  private static func skill(goal: GoalRecord, target: SkillTarget, sessions: [WorkoutSession])
    -> (evidence: [GoalEvidence], exclusions: [Exclusion])
  {
    if let kind = target.requiredEvidenceKind, kind != .measured {
      return (
        [],
        [
          Exclusion(
            reason:
              "A verified \(kind.rawValue) record can only be added by you or your coach, so session history cannot satisfy this target.",
            count: 0)
        ])
    }
    let evidence = sessions.filter { session in
      trainedExerciseIDs(session).contains(target.skillID)
    }.map { session in
      GoalEvidence(
        id: "\(goal.id)#\(Int(session.date.timeIntervalSince1970))",
        goalID: goal.id,
        kind: .measured,
        exerciseID: target.skillID,
        verified: true,
        value: nil,
        occurredAt: session.date,
        note: session.dayName)
    }
    let missing = sessions.count - evidence.count
    var exclusions: [Exclusion] = []
    if missing > 0 {
      exclusions.append(
        Exclusion(
          reason: "completed sessions that did not include \(target.skillName)", count: missing))
    }
    return (evidence, exclusions)
  }

  private static func adherence(
    goal: GoalRecord, target: AdherenceTarget, sessions: [WorkoutSession]
  ) -> (evidence: [GoalEvidence], exclusions: [Exclusion]) {
    switch target.metric {
    case .completedSessions, .sessionsPerWeek:
      let evidence = sessions.map { session in
        GoalEvidence(
          id: "\(goal.id)#\(Int(session.date.timeIntervalSince1970))",
          goalID: goal.id,
          kind: .measured,
          exerciseID: nil,
          verified: true,
          value: 1,
          occurredAt: session.date,
          note: session.dayName)
      }
      return (evidence, [])
    case .completionRate:
      return (
        [],
        [
          Exclusion(
            reason:
              "A completion-rate target is a percentage, and this app counts adherence from session records, so this goal is never judged here.",
            count: 0)
        ])
    }
  }

  private static func trainedExerciseIDs(_ session: WorkoutSession) -> Set<String> {
    var ids = Set(session.sets.map(\.exerciseID))
    ids.formUnion(session.order)
    ids.formUnion(session.extraExerciseIDs)
    return ids.subtracting(session.removedExerciseIDs)
  }

  private struct SessionValue {
    var value: Double?
    var ambiguousSets = 0
    var unsupportedSets = 0
    var outsideRepRangeSets = 0
  }

  private static func sessionValue(
    session: WorkoutSession, exerciseID: String, metric: BenchmarkMetric
  ) -> SessionValue {
    var outcome = SessionValue()
    guard session.completed else { return outcome }
    let sets = session.trustedSets.filter { $0.exerciseID == exerciseID }
    guard !sets.isEmpty else { return outcome }

    var verified: [LoggedSet] = []
    for set in sets {
      switch set.descriptor.normalizationStatus {
      case .verified: verified.append(set)
      case .ambiguous: outcome.ambiguousSets += 1
      case .unsupported: outcome.unsupportedSets += 1
      }
    }
    guard !verified.isEmpty else { return outcome }

    switch metric {
    case .estimatedOneRepMax:
      let usable = verified.filter { (1...15).contains($0.reps) && $0.weightKg > 0 }
      outcome.outsideRepRangeSets = verified.count - usable.count
      outcome.value = usable.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
    case .topSetLoad:
      outcome.value = verified.map(\.weightKg).filter { $0 > 0 }.max()
    case .reps:
      outcome.value = verified.map { Double($0.reps) }.max()
    case .volume:
      let total = verified.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
      outcome.value = total > 0 ? total : nil
    }
    return outcome
  }
}

private enum GoalRoadmapText {
  static func shortDate(_ date: Date) -> String {
    Date.FormatStyle().day().month(.abbreviated).locale(L10n.locale).format(date)
  }
}

// MARK: - Editor

private struct GoalRoadmapEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let existing: GoalRecord?
  let sessions: [WorkoutSession]
  let usesLb: Bool
  let onSave: (GoalRecord) -> Void

  @State private var serves: Goal = .hypertrophy
  @State private var title = ""
  @State private var kind: GoalTargetKind = .benchmark
  @State private var exerciseID = ""
  @State private var metric: BenchmarkMetric = .estimatedOneRepMax
  @State private var comparator: GoalComparator = .atLeast
  @State private var baselineText = ""
  @State private var targetText = ""
  @State private var skillName = ""
  @State private var skillExerciseID = ""
  @State private var practiceTarget = "2"
  @State private var requiredEvidence: GoalEvidenceKind? = nil
  @State private var adherenceMetric: AdherenceMetric = .completedSessions
  @State private var windowWeeks = 4
  @State private var adherenceTarget = "12"
  @State private var hasDeadline = false
  @State private var deadline = Date().addingTimeInterval(8 * 7 * 86_400)
  @State private var note = ""
  @State private var loaded = false

  private var loadMetric: Bool { metric != .reps }
  private var createdAt: Date { existing?.createdAt ?? .now }
  private var displayUnit: String {
    switch kind {
    case .benchmark:
      if metric == .volume { return usesLb ? "lb·reps" : "kg·reps" }
      return metric == .reps ? "reps" : (usesLb ? "lb" : "kg")
    case .skill:
      return "records"
    case .adherence:
      return "sessions"
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          goalCard
          switch kind {
          case .benchmark: benchmarkCard
          case .skill: skillCard
          case .adherence: adherenceCard
          }
          deadlineCard
          noteCard
          if !validationMessages.isEmpty { validationCard }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle(existing == nil ? "New goal" : "Edit goal")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .safeAreaInset(edge: .bottom) { saveBar }
      .onAppear { load() }
    }
  }

  private var goalCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("What this goal serves").forgeSection()
      Picker("Serves", selection: $serves) {
        ForEach(Goal.allCases, id: \.self) { goal in Text(goal.name).tag(goal) }
      }
      .pickerStyle(.segmented)
      Divider().overlay(Theme.ring)
      TextField("Title", text: $title)
        .forgeBody()
        .textFieldStyle(.plain)
        .padding(Theme.inner)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .fill(Theme.innerSurface)
        )
        .accessibilityLabel("Goal title")
      VStack(alignment: .leading, spacing: 6) {
        Text("Type").forgeOverline()
        Picker("Type", selection: $kind) {
          Text("Benchmark").tag(GoalTargetKind.benchmark)
          Text("Skill").tag(GoalTargetKind.skill)
          Text("Adherence").tag(GoalTargetKind.adherence)
        }
        .pickerStyle(.segmented)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var benchmarkCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Benchmark").forgeSection()
      NavigationLink {
        GoalExercisePickerView(selectedID: exerciseID) { picked in
          exerciseID = picked
          if baselineText.isEmpty || baselineText == "0" { prefillBaseline() }
        }
      } label: {
        row(
          title: exerciseID.isEmpty
            ? "Choose exercise" : (ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID),
          detail: "Counts only this exercise")
      }
      .buttonStyle(RowPressStyle())
      Divider().overlay(Theme.ring)
      Picker("Measure", selection: $metric) {
        Text("e1RM").tag(BenchmarkMetric.estimatedOneRepMax)
        Text("Top set").tag(BenchmarkMetric.topSetLoad)
        Text("Reps").tag(BenchmarkMetric.reps)
        Text("Volume").tag(BenchmarkMetric.volume)
      }
      .pickerStyle(.menu)
      if metric != .reps {
        Divider().overlay(Theme.ring)
        Picker("Direction", selection: $comparator) {
          Text("At least").tag(GoalComparator.atLeast)
          Text("At most").tag(GoalComparator.atMost)
        }
        .pickerStyle(.menu)
      }
      Divider().overlay(Theme.ring)
      numberField("Baseline", text: $baselineText, unit: displayUnit)
      if let best = recordedBest {
        HStack(spacing: 8) {
          Text(
            "Best recorded \(metricName(metric)): \(Fmt.num(enteredValue(best.value))) \(displayUnit) on \(GoalRoadmapText.shortDate(best.date))"
          )
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Button("Use") { baselineText = Fmt.num(enteredValue(best.value)) }
            .forge(13, .semibold)
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .accessibilityLabel("Use recorded best as the baseline")
        }
      } else if !exerciseID.isEmpty {
        Text(
          "No recorded sets for this exercise yet, so the baseline starts at 0. Progress needs verified sets of your own."
        )
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      }
      numberField("Target", text: $targetText, unit: displayUnit)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var skillCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Skill").forgeSection()
      TextField("Skill name", text: $skillName)
        .forgeBody()
        .textFieldStyle(.plain)
        .padding(Theme.inner)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .fill(Theme.innerSurface)
        )
        .accessibilityLabel("Skill name")
      NavigationLink {
        GoalExercisePickerView(selectedID: skillExerciseID) { picked in
          skillExerciseID = picked
          if skillName.isEmpty { skillName = ExerciseDB.find(picked)?.localizedName ?? picked }
        }
      } label: {
        row(
          title: skillExerciseID.isEmpty
            ? "Link an exercise (optional)"
            : (ExerciseDB.find(skillExerciseID)?.localizedName ?? skillExerciseID),
          detail: skillExerciseID.isEmpty
            ? "Without a link, sessions cannot count as practice"
            : "Sessions containing this exercise count as practice")
      }
      .buttonStyle(RowPressStyle())
      Divider().overlay(Theme.ring)
      numberField("Practice records needed", text: $practiceTarget, unit: "records")
      Text("A skill needs repeated proof, so the minimum is 2 verified records.")
        .forgeCaption()
      Divider().overlay(Theme.ring)
      Picker("Evidence", selection: $requiredEvidence) {
        Text("Measured from sessions").tag(GoalEvidenceKind?.none)
        Text("Coach sign-off").tag(GoalEvidenceKind?.some(.coachSignOff))
        Text("Video").tag(GoalEvidenceKind?.some(.video))
      }
      .pickerStyle(.menu)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var adherenceCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Adherence").forgeSection()
      Picker("Measure", selection: $adherenceMetric) {
        Text("Sessions completed").tag(AdherenceMetric.completedSessions)
        Text("Sessions per week").tag(AdherenceMetric.sessionsPerWeek)
      }
      .pickerStyle(.menu)
      Stepper(
        "Window · \(windowWeeks) week\(L10n.pluralSuffix(windowWeeks))", value: $windowWeeks, in: 1...12
      )
      .forgeBody()
      Divider().overlay(Theme.ring)
      numberField(
        adherenceMetric == .sessionsPerWeek ? "Sessions per week" : "Sessions",
        text: $adherenceTarget, unit: "sessions")
      Text(
        adherenceMetric == .sessionsPerWeek
          ? "Counted as \(parsedInt(adherenceTarget) ?? 0) sessions per week × \(windowWeeks) weeks = \(adherenceTotal) completed sessions."
          : "Counted from completed sessions after this goal was created. A percentage target is not offered: a rate cannot be counted from records without inventing one."
      )
      .forgeCaption()
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var deadlineCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Deadline", isOn: $hasDeadline).tint(Theme.accent).forgeBody()
      if hasDeadline {
        DatePicker("Target date", selection: $deadline, in: createdAt..., displayedComponents: .date)
          .forgeBody()
        Text("After this date the goal reads as expired rather than failed.")
          .forgeCaption()
      } else {
        Text("No deadline: the goal stays open and keeps collecting evidence.")
          .forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var noteCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Note").forgeSection()
      TextField("Optional", text: $note, axis: .vertical)
        .forgeBody()
        .lineLimit(2...4)
        .textFieldStyle(.plain)
        .padding(Theme.inner)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .fill(Theme.innerSurface)
        )
        .accessibilityLabel("Goal note")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var validationCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: hasErrors ? "exclamationmark.triangle.fill" : "info.circle")
          .foregroundStyle(hasErrors ? Theme.negative : Theme.textSecondary)
        Text("Before saving").forgeSection()
      }
      ForEach(validationMessages, id: \.self) { message in
        Text(message).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var saveBar: some View {
    VStack(spacing: 6) {
      if hasErrors {
        Text("Fix the problem above to save").forgeCaption().foregroundStyle(Theme.negative)
      }
      Button(existing == nil ? "Save goal" : "Save changes") { save() }
        .buttonStyle(PillButtonStyle())
        .disabled(hasErrors)
        .opacity(hasErrors ? 0.45 : 1)
    }
    .padding(.horizontal, Theme.barMargin)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(Theme.page.opacity(0.92))
    .background(.ultraThinMaterial)
  }

  private func row(title: String, detail: String) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(detail).forgeCaption()
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }

  private func numberField(_ label: String, text: Binding<String>, unit: String) -> some View {
    HStack(spacing: 10) {
      Text(label).forgeBody()
      Spacer(minLength: 8)
      TextField("0", text: text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .forge(18, .semibold)
        .frame(minWidth: 72)
        .accessibilityLabel("\(label) in \(unit)")
      Text(unit).forgeLabel()
    }
    .frame(minHeight: 44)
  }

  // MARK: values

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let existing else { return }
    serves = existing.goal
    title = existing.title
    kind = existing.kind
    note = existing.note ?? ""
    if let existingDeadline = existing.deadline {
      hasDeadline = true
      deadline = existingDeadline
    }
    switch existing.target {
    case .benchmark(let target):
      exerciseID = target.exerciseID
      metric = target.metric
      comparator = target.comparator
      baselineText = Fmt.num(enteredValue(target.baseline))
      targetText = Fmt.num(enteredValue(target.target))
    case .skill(let target):
      skillName = target.skillName
      skillExerciseID = target.skillID
      practiceTarget = Fmt.num(target.target, max: 0)
      requiredEvidence = target.requiredEvidenceKind
    case .adherence(let target):
      adherenceMetric = target.metric == .completionRate ? .completedSessions : target.metric
      windowWeeks = target.windowWeeks
      adherenceTarget = Fmt.num(
        target.metric == .sessionsPerWeek
          ? target.target / Double(max(1, target.windowWeeks)) : target.target, max: 0)
    }
  }

  /// Converts a stored (kg) value into what this lifter types and reads.
  private func enteredValue(_ stored: Double) -> Double {
    guard kind == .benchmark, loadMetric else { return stored }
    return usesLb ? Plates.kgToLb(stored) : stored
  }

  /// Converts a typed value back into what is stored (kg for load metrics).
  private func storedValue(_ entered: Double) -> Double {
    guard kind == .benchmark, loadMetric else { return entered }
    return usesLb ? Plates.lbToKg(entered) : entered
  }

  private var recordedBest: (value: Double, date: Date, source: String)? {
    guard kind == .benchmark, !exerciseID.isEmpty, metric != .reps else { return nil }
    return GoalEvidenceDerivation.recordedBest(
      exerciseID: exerciseID, metric: metric, sessions: sessions)
  }

  private func prefillBaseline() {
    guard let best = recordedBest else { return }
    baselineText = Fmt.num(enteredValue(best.value))
  }

  private func parsedInt(_ text: String) -> Int? {
    Int(text.trimmingCharacters(in: .whitespaces))
  }

  private func parsedDouble(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
  }

  private var adherenceTotal: Int {
    let per = parsedInt(adherenceTarget) ?? 0
    return adherenceMetric == .sessionsPerWeek ? per * windowWeeks : per
  }

  private var builtTarget: GoalTarget {
    switch kind {
    case .benchmark:
      return .benchmark(
        BenchmarkTarget(
          exerciseID: exerciseID,
          metric: metric,
          baseline: storedValue(parsedDouble(baselineText) ?? 0),
          target: storedValue(parsedDouble(targetText) ?? 0),
          unit: metric == .reps ? .repetitions : .kilograms,
          comparator: comparator))
    case .skill:
      let fallbackID = skillExerciseID.isEmpty ? skillName : skillExerciseID
      return .skill(
        SkillTarget(
          skillID: fallbackID,
          skillName: skillName.isEmpty
            ? (ExerciseDB.find(skillExerciseID)?.localizedName ?? "Skill") : skillName,
          baseline: 0,
          target: Double(max(0, parsedInt(practiceTarget) ?? 0)),
          unit: .count,
          requiredEvidenceKind: requiredEvidence))
    case .adherence:
      return .adherence(
        AdherenceTarget(
          metric: adherenceMetric,
          baseline: 0,
          target: Double(adherenceTotal),
          unit: .sessions,
          windowWeeks: windowWeeks))
    }
  }

  private func builtRecord() -> GoalRecord {
    GoalRecord(
      id: existing?.id ?? UUID().uuidString,
      goal: serves,
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      target: builtTarget,
      deadline: hasDeadline ? deadline : nil,
      createdAt: createdAt,
      status: existing?.status ?? .notStarted,
      evidenceCount: 0,
      note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
  }

  private var validationMessages: [String] {
    var messages: [String] = []
    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      messages.append("Add a title so the roadmap is readable at a glance.")
    }
    switch kind {
    case .benchmark:
      if exerciseID.isEmpty { messages.append("Choose the exercise this benchmark measures.") }
      guard let target = parsedDouble(targetText), target > 0 else {
        messages.append("Enter a positive target.")
        return messages
      }
      let baseline = parsedDouble(baselineText) ?? 0
      if baseline == target {
        messages.append("Target equals baseline, so there is no distance to close.")
      }
      if comparator == .atLeast && target < baseline {
        messages.append("An 'at least' target below the baseline would already be met.")
      }
    case .skill:
      if skillName.isEmpty && skillExerciseID.isEmpty {
        messages.append("Name the skill, or link it to an exercise.")
      }
      if (parsedInt(practiceTarget) ?? 0) < GoalEvidencePolicy.minimumVerifiedEvidence(for: .skill) {
        messages.append("A skill needs at least 2 verified practice records.")
      }
      if skillExerciseID.isEmpty && requiredEvidence == nil {
        messages.append("Link an exercise so recorded sessions can count as practice.")
      }
    case .adherence:
      if adherenceTotal <= 0 { messages.append("Enter how many sessions this target means.") }
      if adherenceTotal > windowWeeks * 14 {
        messages.append("That is more than two sessions a day across this window.")
      }
    }
    if hasDeadline {
      messages.append(
        "Deadline \(GoalRoadmapText.shortDate(deadline)) — after it the goal reads as expired.")
    }
    return messages
  }

  private var hasErrors: Bool {
    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
    switch kind {
    case .benchmark:
      return exerciseID.isEmpty || (parsedDouble(targetText) ?? 0) <= 0
    case .skill:
      if skillName.isEmpty && skillExerciseID.isEmpty { return true }
      if skillExerciseID.isEmpty && requiredEvidence == nil { return true }
      return (parsedInt(practiceTarget) ?? 0)
        < GoalEvidencePolicy.minimumVerifiedEvidence(for: .skill)
    case .adherence:
      if adherenceTotal <= 0 { return true }
      return adherenceTotal > windowWeeks * 14
    }
  }

  private func save() {
    onSave(builtRecord())
    dismiss()
  }

  private func metricName(_ metric: BenchmarkMetric) -> String {
    switch metric {
    case .estimatedOneRepMax: return "e1RM"
    case .topSetLoad: return "top set"
    case .reps: return "reps"
    case .volume: return "volume"
    }
  }
}

private struct GoalExercisePickerView: View {
  @Environment(\.dismiss) private var dismiss
  let selectedID: String
  let onPick: (String) -> Void
  @State private var query = ""

  private var results: [Exercise] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = ExerciseDB.everything
    guard !trimmed.isEmpty else { return all.sorted { $0.name < $1.name } }
    return all.filter { $0.name.lowercased().contains(trimmed) || $0.id.contains(trimmed) }
      .sorted { $0.name < $1.name }
  }

  var body: some View {
    List(results) { exercise in
      Button {
        onPick(exercise.id)
        dismiss()
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.localizedName).forgeBodyStrong()
            Text(exercise.primary.a11yName).forgeCaption()
          }
          Spacer(minLength: 8)
          if exercise.id == selectedID {
            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
          }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(exercise.localizedName)
      .accessibilityAddTraits(exercise.id == selectedID ? [.isSelected] : [])
    }
    .listStyle(.plain)
    .searchable(text: $query, prompt: "Search exercises")
    .navigationTitle("Exercise")
  }
}
