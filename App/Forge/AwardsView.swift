import ForgeCore
import SwiftData
import SwiftUI

/// The awards page: what is earned, what is next. Grey Progress page with flat white cards.
struct AwardsView: View {
  let earned: [Badge]
  let progress: [BadgeProgress]
  @State private var selected: BadgeProgress?
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var nextBadges: [BadgeProgress] {
    progress.filter { !earned.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
  }

  private var since: Date? {
    sessions.filter(\.completed).map(\.date).min()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ProgressLargeTitle(
          title: "Awards",
          subtitle: since.map {
            String(
              localized: "From logged sessions since \($0.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
              bundle: L10n.bundle)
          },
          art: "art-pro")
        counterCard
        if !earned.isEmpty {
          V3SectionHeader("Earned")
          earnedCard
        }
        if !nextBadges.isEmpty {
          V3SectionHeader("Still to earn")
          laterCard
        }
        Text("Awards come from logged sessions only.")
          .forgeCaption()
          .foregroundStyle(Theme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .progressTitleNavigation("Awards")
    .sheet(item: $selected) { entry in
      BadgeDetailView(progress: entry, earned: earned.contains(entry.badge))
    }
  }

  // MARK: counter + next award

  private var counterCard: some View {
    SkyCard(padding: 0) {
      VStack(spacing: 14) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(verbatim: "\(earned.count)")
            .forge(44, .bold)
            .tracking(-1)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "of \(Badge.allCases.count) earned", bundle: L10n.bundle))
            .forge(22, .semibold)
            .foregroundStyle(Theme.textSecondary)
        }
        HStack(spacing: 4) {
          ForEach(0..<Badge.allCases.count, id: \.self) { i in
            Capsule()
              .fill(i < earned.count ? Theme.accent : Theme.track)
              .frame(height: 8)
          }
        }
      }
      .padding(16)
      Divider().overlay(Theme.ring)
      nextAward
        .padding(16)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var nextAward: some View {
    if let next = nextBadges.first {
      HStack(spacing: 16) {
        ZStack {
          V3GradientRing(progress: next.fraction, colors: Theme.gradMove)
            .frame(width: 84, height: 84)
          quietMedal(next.badge)
            .frame(width: 60, height: 60)
        }
        .frame(width: 84, height: 84)
        VStack(alignment: .leading, spacing: 2) {
          Text(next.badge.title).forge(19, .semibold).foregroundStyle(Theme.text)
          Text(
            String(
              localized: "Next award · \(next.progress) of \(next.target)", bundle: L10n.bundle))
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          Text(nextStep(next)).forge(14, .regular).foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .combine)
    } else {
      Text("Every badge earned.").forge(17, .semibold).foregroundStyle(Theme.text)
    }
  }

  /// The medal art greyed out, the way unearned awards read (mock .quiet).
  private func quietMedal(_ badge: Badge) -> some View {
    Image(MedalArt.assetName(badge))
      .resizable()
      .scaledToFit()
      .saturation(0)
      .opacity(0.42)
      .accessibilityHidden(true)
  }

  /// One plain sentence about what closes the gap, from the badge rule.
  private func nextStep(_ entry: BadgeProgress) -> String {
    let left = entry.target - entry.progress
    switch entry.badge {
    case .firstSession, .tenSessions, .fiftySessions, .hundredSessions:
      return String(
        localized: "Log \(left) more session\(L10n.pluralSuffix(left)).", bundle: L10n.bundle)
    case .fourWeekStreak, .twelveWeekStreak:
      return String(
        localized: "Train once a week for \(left) more week\(L10n.pluralSuffix(left)).",
        bundle: L10n.bundle)
    case .tonnage100k, .tonnage1M:
      return String(
        localized: "Lift \(Fmt.grouped(Double(left * 1000))) kg more.", bundle: L10n.bundle)
    case .firstPR, .tenPRs:
      return String(
        localized: "Set \(left) more record\(L10n.pluralSuffix(left)).", bundle: L10n.bundle)
    }
  }

  // MARK: earned grid

  private var earnedCard: some View {
    SkyCard {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), alignment: .center), count: 3),
        spacing: 22
      ) {
        ForEach(earned, id: \.self) { badge in
          Button {
            if let entry = progress.first(where: { $0.badge == badge }) { selected = entry }
          } label: {
            VStack(spacing: 8) {
              Image(MedalArt.assetName(badge))
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
              Text(badge.title)
                .forge(15, .semibold)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(RowPressStyle())
          .accessibilityLabel(
            String(localized: "\(badge.title), earned", bundle: L10n.bundle))
        }
      }
    }
  }

  // MARK: still to earn

  private var laterCard: some View {
    SkyCard(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(nextBadges.enumerated()), id: \.element.id) { index, entry in
          if index > 0 { Divider().overlay(Theme.ring).padding(.leading, 78) }
          Button {
            selected = entry
          } label: {
            HStack(spacing: 14) {
              quietMedal(entry.badge)
                .frame(width: 48, height: 48)
              VStack(alignment: .leading, spacing: 6) {
                Text(entry.badge.title).forge(17, .semibold).foregroundStyle(Theme.text)
                GeometryReader { geo in
                  ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                      .fill(.mark(Theme.gradMove, startPoint: .leading, endPoint: .trailing))
                      .frame(width: geo.size.width * entry.fraction)
                  }
                }
                .frame(height: 6)
                Text(
                  String(
                    localized: "\(entry.progress) of \(entry.target)", bundle: L10n.bundle))
                  .forge(14, .regular)
                  .foregroundStyle(Theme.textSecondary)
                  .monospacedDigit()
              }
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
          .accessibilityLabel(
            String(
              localized: "\(entry.badge.title), \(entry.progress) of \(entry.target)",
              bundle: L10n.bundle))
        }
      }
    }
  }
}
