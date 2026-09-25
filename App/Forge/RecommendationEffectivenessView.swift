import ForgeCore
import SwiftData
import SwiftUI

// MARK: - Card model
//
// One recommendation, described only with facts the app actually recorded. Every
// field is either read straight out of `RecommendationSnapshot` /
// `RecommendationOutcome` / `RecommendationExposure`, or is a plain-language
// rendering of those values. Nothing is inferred, scored or summarised into a
// "success rate".

private struct EffectivenessCard: Identifiable {
  enum Status: Equatable {
    case proposed, applied, stale, conflict, failed, reverted

    var symbol: String {
      switch self {
      case .applied: return "checkmark.circle.fill"
      case .proposed: return "circle.dashed"
      case .stale: return "hourglass"
      case .conflict: return "arrow.triangle.branch"
      case .failed: return "exclamationmark.octagon.fill"
      case .reverted: return "arrow.uturn.backward.circle.fill"
      }
    }

    var tint: Color {
      switch self {
      case .applied: return Theme.metricSets
      case .proposed: return Theme.textSecondary
      case .stale: return Theme.metricTime
      case .conflict: return Theme.accentValue
      case .failed: return Theme.negative
      case .reverted: return Theme.textSecondary
      }
    }
  }

  let id: String
  let title: String
  let subject: String
  let typeLabel: String?
  let recordedAt: Date
  let status: Status
  let chipLabel: String
  let isCollecting: Bool
  let coverageFraction: Double?
  let coverageHeadline: String
  let coverageDetail: String?
  let evidence: [String]
  let exposureHeadline: String
  let exposureDetail: String?
  let outcomeHeadline: String
  let outcomeDetail: String?
  let limitations: [String]
}

// MARK: - View

/// What the engine recommended, what backed it, whether it was ever shown, and what
/// happened afterwards — reported without promotional certainty.
///
/// Two recorded sources feed the same card shape:
///
///   * the persisted `RecommendationLedger`: immutable snapshots plus exposures plus
///     outcomes. Exposures are stored separately from outcomes on purpose, so "we
///     never showed this" and "we showed it and it was not applied" stay distinct.
///   * `DecisionLogEntry` records, written when a workout started with an adjusted
///     prescription. These predate the ledger and therefore have no exposure history.
///
/// A card never claims a recommendation *caused* a result. An applied change is
/// reported as applied; its effect is reported as unmeasured until the evidence that
/// could measure it exists.
struct RecommendationEffectivenessView: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @State private var now = Date.now

  private var profile: UserProfile? { profiles.first }
  private var completedSessions: [WorkoutSession] { sessions.filter(\.completed) }
  private var completionDays: Set<Date> {
    let calendar = Calendar.current
    return Set(completedSessions.map { calendar.startOfDay(for: $0.date) })
  }

  private static let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  // MARK: - Cards

  /// Newest first. The ledger owns the ordering of its own ids, so sorting here is
  /// stable across launches.
  private var ledgerCards: [EffectivenessCard] {
    guard let ledger = profile?.recommendationLedger else { return [] }
    return ledger.orderedIDs
      .compactMap { ledgerCard($0, ledger) }
      .sorted { $0.recordedAt > $1.recordedAt }
  }

  private var logCards: [EffectivenessCard] {
    decisions.prefix(30).enumerated().map { logCard($0.element, index: $0.offset) }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if ledgerCards.isEmpty && logCards.isEmpty {
          collectingCard
        } else {
          summaryCard
          if !ledgerCards.isEmpty {
            sectionHeader(
              "Recommendation ledger",
              "Recorded by the engine with the observations it used.")
            ForEach(ledgerCards) { card($0) }
          }
          if !logCards.isEmpty {
            sectionHeader(
              "Decision log",
              "Written when a workout started with an adjusted plan.")
            ForEach(logCards) { card($0) }
          }
        }
        methodCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Recommendation effectiveness")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
    .onAppear { now = .now }
  }

  // MARK: - Sections

  @ViewBuilder
  private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).forgeSection()
      Text(subtitle).forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 4)
  }

  private func card(_ item: EffectivenessCard) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: item.status.symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(item.status.tint)
          .frame(width: 34, height: 34)
          .background(Circle().fill(item.status.tint.opacity(0.14)))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(item.title).forgeBodyStrong()
          Text(item.subject).forgeCaption()
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 4) {
          statusChip(item)
          if item.isCollecting {
            Text("Collecting")
              .forge(9, .semibold, tracking: 0)
              .foregroundStyle(Theme.textTertiary)
          }
        }
      }
      if let typeLabel = item.typeLabel {
        Text(typeLabel).forgeOverline()
      }
      Divider().overlay(Theme.ring)
      coverageBlock(item)
      detailRow("eye.fill", "Exposure", item.exposureHeadline, item.exposureDetail, Theme.metricTime)
      detailRow(
        "flag.checkered", "Outcome", item.outcomeHeadline, item.outcomeDetail, item.status.tint)
      limitationsBlock(item)
      Text("Recorded \(dateText(item.recordedAt))")
        .forgeCaption()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .card()
    .accessibilityElement(children: .contain)
  }

  private func statusChip(_ item: EffectivenessCard) -> some View {
    Text(item.chipLabel)
      .forge(9, .bold, tracking: 0)
      .foregroundStyle(item.status.tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(item.status.tint.opacity(0.14)))
  }

  @ViewBuilder
  private func coverageBlock(_ item: EffectivenessCard) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "checklist")
          .foregroundStyle(Theme.metricLoad)
          .frame(width: 24)
          .accessibilityHidden(true)
        Text("Evidence coverage").forgeBodyStrong()
        Spacer(minLength: 8)
        if let fraction = item.coverageFraction {
          Text("\(Int((fraction * 100).rounded()))%")
            .font(.forge(20, .bold).monospacedDigit())
            .foregroundStyle(Theme.rampColor(fraction))
        }
      }
      if let fraction = item.coverageFraction {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.track)
            Capsule()
              .fill(Theme.rampColor(fraction))
              .frame(width: geometry.size.width * min(1, max(0, fraction)))
          }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
      }
      Text(item.coverageHeadline).forgeLabel()
      if let detail = item.coverageDetail {
        Text(detail).forgeCaption()
      }
      if !item.evidence.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          Text("Observations used").forgeOverline()
          ForEach(item.evidence.prefix(6), id: \.self) { line in
            Text("· \(line)").forgeCaption()
          }
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Evidence coverage: \(item.coverageHeadline)")
  }

  private func detailRow(
    _ symbol: String, _ label: String, _ headline: String, _ detail: String?, _ tint: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(label).forgeOverline()
        Text(headline).forgeBody()
        if let detail {
          Text(detail).forgeCaption()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func limitationsBlock(_ item: EffectivenessCard) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Limitations").forgeOverline()
      ForEach(item.limitations, id: \.self) { line in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
          Text(line).forgeCaption()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Summary

  private var summaryCard: some View {
    let all = ledgerCards + logCards
    return VStack(alignment: .leading, spacing: 12) {
      Text("What the engine did").forgeTitle()
      Text("Counted from \(all.count) recorded recommendation\(L10n.pluralSuffix(all.count)).")
        .forgeCaption()
      LazyVGrid(columns: Self.columns, spacing: 8) {
        countTile("Applied", all.filter { $0.status == .applied }.count, Theme.metricSets)
        countTile("Undone", all.filter { $0.status == .reverted }.count, Theme.textSecondary)
        countTile("Waiting for you", all.filter { $0.status == .proposed }.count, Theme.textSecondary)
        countTile("Stale or expired", all.filter { $0.status == .stale }.count, Theme.metricTime)
        countTile("Conflicting", all.filter { $0.status == .conflict }.count, Theme.accentValue)
        countTile("Not applied", all.filter { $0.status == .failed }.count, Theme.negative)
        countTile("Never shown", all.filter { $0.exposureHeadline.hasPrefix("Never shown") }.count, Theme.textTertiary)
      }
      Divider().overlay(Theme.ring)
      Text(
        "This screen never reports a success rate. A change made inside a program that is also changing cannot be attributed to one recommendation."
      )
      .forgeCaption()
    }
    .card()
  }

  private func countTile(_ label: String, _ count: Int, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(count)")
        .font(.forge(24, .bold).monospacedDigit())
        .foregroundStyle(tint)
      Text(label).forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  // MARK: - States

  private var collectingCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "hourglass")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Theme.metricTime)
          .frame(width: 28)
          .accessibilityHidden(true)
        Text("Still collecting").forgeTitle()
      }
      Text(
        "No recommendation and no engine decision have been recorded yet. This screen stays empty rather than reporting a number."
      )
      .forgeBody()
      Text(
        "A recommendation is only recorded when the engine can show the observations it used and the values it changed. Until that exists, there is nothing to report here."
      )
      .forgeCaption()
    }
    .card()
  }

  private var methodCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("How to read this").forgeSection()
      methodRow(
        "checkmark.seal", "Applied",
        "The change was written to your program. It is not a result that was proved.", Theme.metricSets)
      methodRow(
        "eye.slash", "Never shown",
        "No exposure was recorded, so this recommendation cannot have influenced your training.",
        Theme.metricTime)
      methodRow(
        "hourglass", "Stale",
        "The program moved to a newer version, or the recommendation expired, before it was applied. Nothing changed.",
        Theme.metricTime)
      methodRow(
        "checklist", "Coverage",
        "The share of required observations that were actually recorded — not statistical confidence.",
        Theme.metricLoad)
      Divider().overlay(Theme.ring)
      Text(
        "Outcomes list what was logged after a change. They are not a measurement of what the change caused."
      )
      .forgeCaption()
    }
    .card()
  }

  private func methodRow(_ symbol: String, _ title: String, _ text: String, _ tint: Color)
    -> some View
  {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(text).forgeCaption()
      }
    }
  }

  // MARK: - Ledger → card

  private func ledgerCard(_ id: RecommendationID, _ ledger: RecommendationLedger) -> EffectivenessCard? {
    guard let snapshot = ledger.snapshot(for: id) else { return nil }
    let outcome = ledger.outcome(for: id)
    let eligibility = snapshot.eligibility()
    let exposures = ledger.exposures(for: id)
    let validation = RecommendationValidationPolicy.validate(snapshot)
    let coverage = snapshot.coverage
    let isStale = snapshot.isStale(against: ledger.currentProgramVersion, at: now)

    let status: EffectivenessCard.Status
    switch outcome?.state ?? .proposed {
    case .applied: status = .applied
    case .stale: status = .stale
    case .conflict: status = .conflict
    case .failed: status = .failed
    case .reverted: status = .reverted
    case .proposed: status = isStale ? .stale : .proposed
    }

    // Outcome — what the ledger itself can say, and nothing more.
    var outcomeHeadline: String
    var outcomeDetail: String?
    var isCollecting = false
    switch status {
    case .applied:
      let appliedVersion = outcome?.appliedProgramVersion.map { " to \($0.rawValue)" } ?? ""
      let appliedOn = outcome?.appliedAt.map { " on \(dateText($0))" } ?? ""
      outcomeHeadline = "Applied\(appliedVersion)\(appliedOn)."
      let since = outcome?.appliedAt.map { sessionsSince($0) } ?? 0
      isCollecting = since == 0
      outcomeDetail =
        since == 0
        ? "No completed session has been logged since it was applied, so there is nothing to measure yet."
        : "\(since) completed session\(since == 1 ? "" : "s") logged since. That is activity, not evidence the change caused anything."
    case .stale:
      if snapshot.isExpired(at: now), let expiresAt = snapshot.expiresAt {
        outcomeHeadline = "Never applied — it expired on \(dateText(expiresAt))."
      } else {
        outcomeHeadline = "Never applied — your program moved to a newer version first."
      }
      outcomeDetail = "Nothing was changed by this recommendation."
    case .conflict:
      outcomeHeadline = "Not applied — another recommendation already changed the same target."
      outcomeDetail = outcome?.conflictingRecommendationID.map { "Already applied: \($0.rawValue)." }
    case .failed:
      outcomeHeadline = "Not applied."
      outcomeDetail = failureText(outcome?.reason) ?? "The engine refused it."
    case .reverted:
      let on = outcome?.resolvedAt.map { " on \(dateText($0))" } ?? ""
      outcomeHeadline = "Applied, then undone\(on)."
      outcomeDetail = "The change was put back from the Coach, so it no longer shapes your plan."
    case .proposed:
      outcomeHeadline = "Waiting for your confirmation."
      outcomeDetail =
        eligibility.requiresConfirmation
        ? "A change like this always needs your explicit confirmation before it is applied."
        : "Nothing has been applied."
    }

    // Exposure — recorded separately from the outcome.
    let exposureHeadline: String
    let exposureDetail: String?
    if let last = exposures.last {
      exposureHeadline = "Shown \(exposures.count) time\(exposures.count == 1 ? "" : "s") · last \(dateText(last.exposedAt))"
      let surfaces = Set(exposures.map(\.surface)).sorted().joined(separator: ", ")
      exposureDetail =
        "Surfaces: \(surfaces)." + (last.wasConsequential ? " Consequential — confirmation was required." : "")
    } else {
      exposureHeadline = "Never shown"
      exposureDetail =
        "No exposure was recorded, so nothing here can be attributed to this recommendation."
    }

    // Coverage — required versus actually observed.
    let coverageFraction = coverage.requiredSignals.isEmpty ? nil : coverage.fraction
    let coverageHeadline: String
    let coverageDetail: String?
    if coverage.requiredSignals.isEmpty {
      coverageHeadline = "No evidence requirement was recorded for this recommendation."
      coverageDetail = nil
    } else {
      let present = coverage.requiredSignals.count - coverage.missingSignals.count
      coverageHeadline =
        "\(present) of \(coverage.requiredSignals.count) required observation\(coverage.requiredSignals.count == 1 ? "" : "s") recorded."
      coverageDetail =
        coverage.isComplete
        ? "Every observation the engine required was present."
        : "Missing: \(coverage.missingSignals.map(humanSignal).joined(separator: ", "))."
    }

    // Limitations — everything that keeps this card honest.
    var limitations: [String] = []
    if !validation.isEmpty {
      limitations.append(contentsOf: validation.map(validationText))
    }
    if !eligibility.isEligible, status != .applied {
      limitations.append(contentsOf: eligibility.reasons.map(ineligibilityText))
    }
    if !coverage.isComplete, !coverage.requiredSignals.isEmpty {
      limitations.append("Not every required observation was present, so this recommendation was never fully supported.")
    }
    if isStale {
      limitations.append("Its program version is no longer the current one.")
    }
    if exposures.isEmpty {
      limitations.append("It was never shown to you, so it cannot have influenced what you lifted.")
    }
    if status == .applied {
      limitations.append("No causal claim: the app never measured what would have happened without the change.")
    }
    if let maxAge = snapshot.policy.maxAge {
      limitations.append("Age limit: \(Fmt.int(maxAge / 86_400)) day\(Int(maxAge / 86_400) == 1 ? "" : "s").")
    }
    if limitations.isEmpty {
      limitations.append("No limitations were recorded.")
    }

    return EffectivenessCard(
      id: "ledger.\(id.rawValue)",
      title: snapshot.record.humanSummary.isEmpty
        ? "Untitled recommendation" : snapshot.record.humanSummary,
      subject: subjectText(exerciseID: snapshot.record.exerciseID, muscle: snapshot.record.muscle),
      typeLabel: "\(typeText(snapshot.record.type)) · \(snapshot.subjectKey)",
      recordedAt: snapshot.createdAt,
      status: status,
      chipLabel: chipLabel(status),
      isCollecting: isCollecting,
      coverageFraction: coverageFraction,
      coverageHeadline: coverageHeadline,
      coverageDetail: coverageDetail,
      evidence: snapshot.record.evidence,
      exposureHeadline: exposureHeadline,
      exposureDetail: exposureDetail,
      outcomeHeadline: outcomeHeadline,
      outcomeDetail: outcomeDetail,
      limitations: limitations)
  }

  // MARK: - Decision log → card

  private func logCard(_ entry: DecisionLogEntry, index: Int) -> EffectivenessCard {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: entry.date)
    let completed = completionDays.contains(day)
    let sets = loggedSetCount(on: entry.date)

    var limitations: [String] = []
    if entry.evidence.isEmpty {
      limitations.append("No evidence entries were recorded with it.")
    }
    limitations.append("This record has no exposure history, so it cannot support a claim about what you saw.")
    limitations.append("Effect is not measurable from a decision record: the app never measured what would have happened without the change.")
    if !completed {
      limitations.append("The session on \(dateText(entry.date)) never completed, so the planned adjustment was never carried out.")
    }

    return EffectivenessCard(
      id: "log.\(index).\(entry.record.id)",
      title: entry.humanSummary.isEmpty ? "Untitled decision" : entry.humanSummary,
      subject: subjectText(exerciseID: entry.exerciseID, muscle: entry.muscle),
      typeLabel: typeText(entry.type),
      recordedAt: entry.date,
      status: completed ? .applied : .proposed,
      chipLabel: completed ? "Applied" : "Recorded",
      isCollecting: !completed,
      coverageFraction: nil,
      coverageHeadline: "Coverage was not tracked for this decision.",
      coverageDetail: entry.reasonCodes.isEmpty
        ? nil
        : "Signals behind it: \(entry.reasonCodes.map(humanSignal).joined(separator: ", ")).",
      evidence: entry.evidence,
      exposureHeadline: "Not tracked",
      exposureDetail: "Written before the recommendation ledger existed, so we cannot say whether you saw it.",
      outcomeHeadline: completed
        ? "Applied when the session on \(dateText(entry.date)) started; that session was completed."
        : "No effect recorded.",
      outcomeDetail: completed
        ? "\(sets) set\(sets == 1 ? "" : "s") logged that day. Activity, not proof the adjustment caused it."
        : "The session never completed, so the change took effect nowhere.",
      limitations: limitations)
  }

  // MARK: - Text helpers

  private func chipLabel(_ status: EffectivenessCard.Status) -> String {
    switch status {
    case .applied: return "Applied"
    case .proposed: return "Proposed"
    case .stale: return "Stale"
    case .conflict: return "Conflict"
    case .failed: return "Failed"
    case .reverted: return "Undone"
    }
  }

  private func subjectText(exerciseID: String?, muscle: String?) -> String {
    if let exerciseID, !exerciseID.isEmpty {
      return ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID
    }
    if let muscle, let parsed = Muscle(rawValue: muscle) {
      return parsed.a11yName
    }
    if let muscle, !muscle.isEmpty { return muscle }
    return "Whole session"
  }

  private func typeText(_ type: String) -> String {
    switch type {
    case "load_change": return "Load change"
    case "volume_change": return "Volume change"
    case "swap": return "Exercise swap"
    case "session": return "Session change"
    case "plateau": return "Plateau response"
    default: return type.replacingOccurrences(of: "_", with: " ")
    }
  }

  private func humanSignal(_ code: String) -> String {
    code.replacingOccurrences(of: "_", with: " ")
  }

  private func validationText(_ issue: RecommendationValidationIssue) -> String {
    switch issue {
    case .emptyRecommendationID: return "It has no identifier, so it cannot be tracked."
    case .missingEvidence: return "No evidence was recorded with it."
    case .missingSummary: return "It has no plain-language summary."
    case .expiryBeforeCreation: return "Its expiry was recorded before it was created."
    case .nonPositiveTargetLoad: return "Its target load was not a positive number."
    case .unsupportedActionType: return "Its action type is not one this build understands."
    }
  }

  private func ineligibilityText(_ reason: RecommendationIneligibility) -> String {
    switch reason {
    case .insufficientEvidence: return "Not enough of the required evidence was observed."
    case .authorizationMissing: return "You have not been asked to allow this kind of change."
    case .authorizationDenied: return "You declined this kind of change."
    case .authorizationRevoked: return "Your allowance for this kind of change was revoked."
    }
  }

  /// The ledger stores failure reasons as raw codes; unknown codes are shown verbatim
  /// rather than hidden.
  private func failureText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    let readable = parts.map { code -> String in
      if let issue = RecommendationValidationIssue(rawValue: code) { return validationText(issue) }
      if let reason = RecommendationIneligibility(rawValue: code) { return ineligibilityText(reason) }
      switch code {
      case "expired": return "It expired before it was applied."
      case "version_drift": return "Your program moved on before it was applied."
      case "subject_conflict": return "Another recommendation already changed the same target."
      default: return humanSignal(code)
      }
    }
    return readable.joined(separator: " ")
  }

  private func dateText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
  }

  // MARK: - Session evidence

  private func sessionsSince(_ date: Date) -> Int {
    completedSessions.filter { $0.date >= date }.count
  }

  private func loggedSetCount(on date: Date) -> Int {
    let calendar = Calendar.current
    return completedSessions
      .filter { calendar.isDate($0.date, inSameDayAs: date) }
      .reduce(0) { $0 + $1.sets.count }
  }
}
