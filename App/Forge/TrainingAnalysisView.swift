import SwiftData
import SwiftUI

struct TrainingAnalysisView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]

  private var profile: UserProfile? { profiles.first }

  /// One recorded block per span of non-decreasing weeks, copied from ProgressView's rule.
  private var mesoBlockCount: Int {
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    guard !completed.isEmpty else { return 0 }
    return 1 + zip(completed, completed.dropFirst()).filter { $0.1.week < $0.0.week }.count
  }

  private var heroSubtitle: String {
    let eligible = sessions.analysisEligibleSessions
    guard let earliest = eligible.min(by: { $0.date < $1.date }) else {
      return String(localized: "Your analysis fills in as you train", bundle: L10n.bundle)
    }
    let inCurrentYear = Calendar.current.isDate(earliest.date, equalTo: .now, toGranularity: .year)
    let date = inCurrentYear
      ? earliest.date.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
      : earliest.date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale))
    return String(
      localized: "From \(eligible.count) workout\(L10n.pluralSuffix(eligible.count)) since \(date)",
      bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        heroCard
        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
          ],
          spacing: 12
        ) {
          tile(
            title: String(localized: "Plan review", bundle: L10n.bundle),
            caption: String(localized: "What works and what changed", bundle: L10n.bundle),
            art: "art-plan", tint: Theme.accent, id: "progress.planAudit"
          ) { PlanAuditView() }
          tile(
            title: String(localized: "Adjustment results", bundle: L10n.bundle),
            caption: String(localized: "Proposed, applied, measured", bundle: L10n.bundle),
            art: "art-goal", tint: Theme.metricRecord, id: "progress.recommendations"
          ) { RecommendationEffectivenessView() }
          tile(
            title: String(localized: "Recovery", bundle: L10n.bundle),
            caption: String(localized: "Inputs and 7\u{2011}day coverage", bundle: L10n.bundle),
            art: "art-injury", tint: Theme.metricHeart, id: "progress.recovery"
          ) { RecoveryReportView() }
          tile(
            title: String(localized: "Balance", bundle: L10n.bundle),
            caption: String(localized: "Push, pull and legs coverage", bundle: L10n.bundle),
            art: "art-equipment", tint: Theme.positive, id: "progress.balance"
          ) { BalanceRadarView() }
          tile(
            title: String(localized: "Experiments", bundle: L10n.bundle),
            caption: profile?.trainingExperiment == nil
              ? String(localized: "Test one change", bundle: L10n.bundle)
              : String(localized: "4-week protocol", bundle: L10n.bundle),
            art: "art-rest", tint: Theme.metricTime, id: "progress.experiments"
          ) { TrainingExperimentsView() }
          tile(
            title: String(localized: "Training blocks", bundle: L10n.bundle),
            caption: String(
              localized: "\(mesoBlockCount) recorded block\(L10n.pluralSuffix(mesoBlockCount))",
              bundle: L10n.bundle),
            art: "art-schedule", tint: Theme.metricEffort, id: "progress.mesocycles"
          ) { MesoHistoryView(usesLb: usesLb) }
        }
        footnote
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Training analysis")
    .navigationBarTitleDisplayMode(.large)
  }

  private var heroCard: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: 148)
      .overlay {
        Image("tile-progress")
          .resizable()
          .scaledToFill()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .overlay { Theme.shareSurface.opacity(0.42) }
      .overlay(alignment: .bottomLeading) {
        VStack(alignment: .leading, spacing: 2) {
          Text("How your plan is working")
            .forge(20, .bold)
            .foregroundStyle(Theme.onAccent)
          Text(heroSubtitle)
            .forge(13, .medium)
            .foregroundStyle(Theme.onAccent.opacity(0.85))
        }
        .padding(16)
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .strokeBorder(Theme.imageOutline, lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
  }

  private var footnote: some View {
    Text(
      "Adjustment results show what happened after each change. They do not prove the change caused it."
    )
    .forge(12, .medium)
    .foregroundStyle(Theme.textSecondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 4)
  }

  private func tile<Destination: View>(
    title: String,
    caption: String,
    art: String,
    tint: Color,
    id: String,
    @ViewBuilder destination: () -> Destination
  ) -> some View {
    NavigationLink(destination: destination()) {
      VStack(alignment: .leading, spacing: 0) {
        Image(art)
          .resizable()
          .scaledToFit()
          .frame(width: 76, height: 76)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityHidden(true)
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .forge(16, .semibold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(caption)
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .fill(tint.opacity(0.08))
      )
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel("\(title), \(caption)")
    .accessibilityIdentifier(id)
  }
}
