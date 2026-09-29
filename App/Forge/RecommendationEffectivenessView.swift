import ForgeCore
import SwiftData
import SwiftUI

// MARK: - Card model
//
// One recommendation, described only with facts the app actually recorded. Every field is
// either read straight out of `RecommendationSnapshot` / `RecommendationOutcome` /
// `RecommendationExposure`, or is a plain-language rendering of those values. The screen
// shows counts of measured outcomes, each with its plain result — never a percentage or a
// "success rate".

private struct SuggestionItem: Identifiable {
  enum Outcome {
    case better, measuring, noChange, undone, declined, waiting, notApplied, applied

    var word: String {
      switch self {
      case .better: return String(localized: "Better", bundle: L10n.bundle)
      case .measuring: return String(localized: "Measuring", bundle: L10n.bundle)
      case .noChange: return String(localized: "No change", bundle: L10n.bundle)
      case .undone: return String(localized: "Undone", bundle: L10n.bundle)
      case .declined: return String(localized: "Declined", bundle: L10n.bundle)
      case .waiting: return String(localized: "Waiting", bundle: L10n.bundle)
      case .notApplied: return String(localized: "Not applied", bundle: L10n.bundle)
      case .applied: return String(localized: "Applied", bundle: L10n.bundle)
      }
    }

    var isBetter: Bool { self == .better }
  }

  let id: String
  let title: String
  let exerciseID: String?
  let date: Date
  let outcome: Outcome
  /// What was measured or recorded, without the date prefix ("est. max +6 kg by Sep 23").
  let resultLine: String?
  let measurement: InsightsV3.Measurement?
}

// MARK: - View

/// What the engine recommended and what happened afterwards — reported without promotional
/// certainty. Ledger snapshots and decision-log records feed the same row shape; items are
/// grouped by training block, and every measured outcome is stated as its own plain result.
struct RecommendationEffectivenessView: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var checkIns: [CheckIn]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var now = Date.now
  @State private var approving: VolumeIncrease?
  @State private var expandedBlocks: Set<Int> = []

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }
  private var completedSessions: [WorkoutSession] { sessions.filter(\.completed) }

  // MARK: - Items

  private var items: [SuggestionItem] {
    (ledgerItems + logItems).sorted { $0.date > $1.date }
  }

  private var ledgerItems: [SuggestionItem] {
    guard let ledger = profile?.recommendationLedger else { return [] }
    return ledger.orderedIDs.compactMap { ledgerItem($0, ledger) }
  }

  private var logItems: [SuggestionItem] {
    decisions.prefix(30).enumerated().map { logItem($0.element, index: $0.offset) }
  }

  /// Blocks newest first; the current block reads "This block".
  private var groups: [(block: Int, isCurrent: Bool, items: [SuggestionItem])] {
    let byBlock = Dictionary(grouping: items) {
      InsightsV3.blockNumber(of: $0.date, sessions: sessions, profile: profile)
    }
    let currentBlock = InsightsV3.blockNumber(of: .now, sessions: sessions, profile: profile)
    return byBlock.keys.sorted(by: >).map { number in
      (number, number == currentBlock, byBlock[number] ?? [])
    }
  }

  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  private var sinceDate: Date? {
    items.map(\.date).min() ?? completedSessions.map(\.date).min()
  }

  // MARK: - Body

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(
          title: LocalizedStringKey(String(localized: "\(coach.name)'s suggestions", bundle: L10n.bundle)),
          subtitle: headerSubtitle,
          art: coach.avatar
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)

        if items.isEmpty && pendingIncreases.isEmpty {
          collectingContent
        } else {
          InsightsVerdict(title: verdictTitle, line: verdictLine)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 20)
          funnel
            .padding(.horizontal, Theme.margin)
            .padding(.top, 20)
          ForEach(pendingIncreases) { increase in
            InsightsPendingRow(increase: increase, onReview: { approving = increase })
              .padding(.horizontal, Theme.margin)
              .padding(.top, 20)
          }
          ForEach(Array(groups.enumerated()), id: \.element.block) { index, group in
            LogBand()
              .padding(.top, index == 0 && pendingIncreases.isEmpty ? 24 : 12)
            blockSection(group)
          }
          LogBand().padding(.top, 12)
          methodSection
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation(String(localized: "\(coach.name)'s suggestions", bundle: L10n.bundle))
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
    .onAppear { now = .now }
  }

  private var headerSubtitle: String? {
    guard let since = sinceDate else { return nil }
    return String(
      localized:
        "What \(coach.name) proposed since \(since.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))), and what happened",
      bundle: L10n.bundle)
  }

  // MARK: - Verdict and funnel

  private var measured: [SuggestionItem] {
    items.filter { $0.outcome == .better || $0.outcome == .noChange }
  }

  private var verdictTitle: String {
    let better = items.filter { $0.outcome == .better }.count
    let noChange = items.filter { $0.outcome == .noChange }.count
    if measured.isEmpty {
      return String(localized: "\(coach.name) is still measuring.", bundle: L10n.bundle)
    }
    if better > noChange {
      return String(
        localized: "Most changes you applied helped.", bundle: L10n.bundle)
    }
    return String(
      localized: "The measured changes have not helped yet.", bundle: L10n.bundle)
  }

  private var verdictLine: String {
    String(
      localized:
        "Better means the lift beat its best estimated max after the change.",
      bundle: L10n.bundle)
  }

  private var funnel: some View {
    let applied = items.filter {
      [.better, .noChange, .measuring, .applied].contains($0.outcome)
    }.count
    let declined = items.filter { $0.outcome == .declined }.count
    let better = items.filter { $0.outcome == .better }.count
    let noChange = items.filter { $0.outcome == .noChange }.count
    let undone = items.filter { $0.outcome == .undone }.count
    let total = max(items.count, 1)
    var noteParts: [String] = []
    if noChange > 0 { noteParts.append(String(localized: "\(noChange) no change", bundle: L10n.bundle)) }
    if undone > 0 { noteParts.append(String(localized: "\(undone) undone", bundle: L10n.bundle)) }
    return VStack(spacing: 7) {
      InsightsFunnelRow(
        value: items.count,
        label: String(localized: "Proposed", bundle: L10n.bundle),
        fraction: 1,
        fill: [Theme.ramp[2]])
      InsightsFunnelRow(
        value: applied,
        label: String(localized: "Applied", bundle: L10n.bundle),
        note: declined > 0 ? String(localized: "\(declined) declined", bundle: L10n.bundle) : nil,
        fraction: Double(applied) / Double(total),
        fill: Theme.gradBrand)
      InsightsFunnelRow(
        value: better,
        label: String(localized: "Measured better", bundle: L10n.bundle),
        note: noteParts.isEmpty ? nil : noteParts.joined(separator: " · "),
        fraction: Double(better) / Double(total),
        fill: Theme.gradDone)
    }
  }

  // MARK: - Groups

  private func blockSection(_ group: (block: Int, isCurrent: Bool, items: [SuggestionItem])) -> some View {
    let shown = group.isCurrent || expandedBlocks.contains(group.block)
      ? group.items : Array(group.items.prefix(3))
    return VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: group.isCurrent ? "This block" : LocalizedStringKey(String(localized: "Block \(group.block)", bundle: L10n.bundle)),
        trailing: groupTrailing(group.items)
      )
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(shown) { item in
          itemRow(item)
          if item.id != shown.last?.id { rowDivider }
        }
        if shown.count < group.items.count {
          Button {
            expandedBlocks.insert(group.block)
          } label: {
            HStack(spacing: 2) {
              Text(String(localized: "All \(group.items.count) in Block \(group.block)", bundle: L10n.bundle))
              Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
            }
            .forge(16, .medium)
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
  }

  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 68)
  }

  private func groupTrailing(_ items: [SuggestionItem]) -> String {
    var parts: [String] = []
    for outcome in [SuggestionItem.Outcome.better, .noChange, .measuring, .undone, .declined] {
      let count = items.filter { $0.outcome == outcome }.count
      if count > 0 {
        parts.append("\(count) \(outcome.word.lowercased())")
      }
    }
    return parts.joined(separator: ", ")
  }

  private func itemRow(_ item: SuggestionItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      if let exercise = item.exerciseID.flatMap(ExerciseDB.find) {
        LiftToken(exercise: exercise, size: 44)
      } else {
        InsightsRoundBadge(symbol: "calendar", tint: Theme.accent)
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.title)
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          InsightsOutcomeWord(text: item.outcome.word, better: item.outcome.isBetter)
        }
        HStack(spacing: 0) {
          Text(dateText(item.date))
          if let line = item.resultLine { Text(" · \(line)") }
        }
        .forge(14)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 60, alignment: .top)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  // MARK: - States

  private var collectingContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Still collecting")
        .forge(22, .semibold, tracking: -0.33)
        .foregroundStyle(Theme.text)
      Text(
        "No recommendation and no engine decision have been recorded yet. This screen stays empty rather than reporting a number."
      )
      .forgeBody()
      Text(
        "A recommendation is only recorded when the engine can show the observations it used and the values it changed. Until that exists, there is nothing to report here."
      )
      .forgeCaption()
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.top, 20)
  }

  private var methodSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("How \(coach.name) measures")
        .forge(18, .semibold, tracking: -0.18)
        .foregroundStyle(Theme.text)
      Text(
        String(
          localized:
            "After a change, \(coach.name) compares your next sessions of that lift with your best before it. Other things change at the same time, so read “better” as a good sign, not proof. Declined changes are not measured.",
          bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.top, 24)
  }

  // MARK: - Ledger → item

  private func ledgerItem(_ id: RecommendationID, _ ledger: RecommendationLedger) -> SuggestionItem? {
    guard let snapshot = ledger.snapshot(for: id) else { return nil }
    let outcome = ledger.outcome(for: id)
    let isStale = snapshot.isStale(against: ledger.currentProgramVersion, at: now)
    let record = snapshot.record

    let state = outcome?.state ?? .proposed
    let itemOutcome: SuggestionItem.Outcome
    var resultLine: String?
    var measurement: InsightsV3.Measurement?

    switch state {
    case .applied:
      measurement = InsightsV3.measurement(
        exerciseID: record.exerciseID, since: outcome?.appliedAt ?? snapshot.createdAt,
        sessions: sessions)
      switch measurement?.outcome {
      case .better: itemOutcome = .better
      case .noChange: itemOutcome = .noChange
      case .measuring, nil: itemOutcome = measurement == nil ? .applied : .measuring
      }
      resultLine = measuredLine(measurement, exerciseID: record.exerciseID)
    case .reverted:
      itemOutcome = .undone
      resultLine = outcome?.resolvedAt.map {
        String(localized: "you undid it on \(dateText($0))", bundle: L10n.bundle)
      }
    case .failed:
      let reasons = (outcome?.reason ?? "").split(separator: ",").map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
      if reasons.contains(RecommendationIneligibility.authorizationDenied.rawValue) {
        itemOutcome = .declined
      } else {
        itemOutcome = .notApplied
      }
      resultLine = failureText(outcome?.reason)
    case .stale:
      itemOutcome = .notApplied
      resultLine = snapshot.isExpired(at: now)
        ? String(localized: "it expired before it was applied", bundle: L10n.bundle)
        : String(localized: "your program moved on before it was applied", bundle: L10n.bundle)
    case .conflict:
      itemOutcome = .notApplied
      resultLine = String(localized: "another change already touched the same lift", bundle: L10n.bundle)
    case .proposed:
      itemOutcome = isStale ? .notApplied : .waiting
      resultLine = String(localized: "waiting for your confirmation", bundle: L10n.bundle)
    }

    return SuggestionItem(
      id: "ledger.\(id.rawValue)",
      title: record.humanSummary.isEmpty
        ? String(localized: "Untitled recommendation", bundle: L10n.bundle)
        : record.humanSummary,
      exerciseID: record.exerciseID,
      date: snapshot.createdAt,
      outcome: itemOutcome,
      resultLine: resultLine,
      measurement: measurement)
  }

  // MARK: - Decision log → item

  private func logItem(_ entry: DecisionLogEntry, index: Int) -> SuggestionItem {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: entry.date)
    let completed = completedSessions.contains {
      calendar.isDate($0.date, inSameDayAs: day)
    }
    let record = entry.record

    var itemOutcome: SuggestionItem.Outcome = .waiting
    var resultLine: String?
    var measurement: InsightsV3.Measurement?
    if completed {
      measurement = InsightsV3.measurement(
        exerciseID: record.exerciseID, since: entry.date, sessions: sessions)
      switch measurement?.outcome {
      case .better: itemOutcome = .better
      case .noChange: itemOutcome = .noChange
      case .measuring, nil: itemOutcome = measurement == nil ? .applied : .measuring
      }
      resultLine = measuredLine(measurement, exerciseID: record.exerciseID)
    } else {
      resultLine = String(localized: "the session that day never finished", bundle: L10n.bundle)
    }

    return SuggestionItem(
      id: "log.\(index).\(record.id)",
      title: record.humanSummary.isEmpty
        ? String(localized: "Untitled decision", bundle: L10n.bundle)
        : record.humanSummary,
      exerciseID: record.exerciseID,
      date: entry.date,
      outcome: itemOutcome,
      resultLine: resultLine,
      measurement: measurement)
  }

  // MARK: - Text helpers

  /// "est. max +6 kg by Sep 23", "est. max 57 kg, same as before", or nil while measuring.
  private func measuredLine(_ measurement: InsightsV3.Measurement?, exerciseID: String?) -> String? {
    guard let measurement else { return nil }
    switch measurement.outcome {
    case .better:
      guard let after = measurement.bestAfter, let before = measurement.bestBefore,
        let date = measurement.bestAfterDate
      else { return nil }
      return String(
        localized: "est. max \(signedWeight(after - before, exerciseID: exerciseID)) by \(dateText(date))",
        bundle: L10n.bundle)
    case .noChange:
      guard let after = measurement.bestAfter else { return nil }
      return String(
        localized: "est. max \(weight(after, exerciseID: exerciseID)), same as before",
        bundle: L10n.bundle)
    case .measuring:
      return String(
        localized: "not trained since the change", bundle: L10n.bundle)
    }
  }

  private func weight(_ kg: Double, exerciseID: String? = nil) -> String {
    let lb = profile?.isLb(for: exerciseID ?? "") ?? (profile?.usesLb ?? false)
    return UnitFormat.weight(kg, usesLb: lb)
  }

  private func signedWeight(_ kg: Double, exerciseID: String? = nil) -> String {
    let lb = profile?.isLb(for: exerciseID ?? "") ?? (profile?.usesLb ?? false)
    let value = lb ? Plates.kgToLb(kg) : kg
    let sign = kg >= 0 ? "+" : "\u{2212}"
    return "\(sign)\(Fmt.num(abs(value))) \(lb ? "lb" : "kg")"
  }

  /// The ledger stores failure reasons as raw codes; unknown codes are shown verbatim
  /// rather than hidden.
  private func failureText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw.split(separator: ",")
      .map { humanSignal(String($0).trimmingCharacters(in: .whitespaces)) }
      .joined(separator: ", ")
  }

  private func humanSignal(_ code: String) -> String {
    switch code {
    case RecommendationIneligibility.insufficientEvidence.rawValue:
      return String(localized: "not enough evidence", bundle: L10n.bundle)
    case RecommendationIneligibility.authorizationMissing.rawValue:
      return String(localized: "you had not allowed this kind of change", bundle: L10n.bundle)
    case RecommendationIneligibility.authorizationDenied.rawValue:
      return String(localized: "you declined this kind of change", bundle: L10n.bundle)
    case RecommendationIneligibility.authorizationRevoked.rawValue:
      return String(localized: "your allowance for this change was revoked", bundle: L10n.bundle)
    default: return code.replacingOccurrences(of: "_", with: " ")
    }
  }

  private func dateText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
  }
}
