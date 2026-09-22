import SwiftUI
import ForgeCore

struct AwardsView: View {
  let earned: [Badge]
  let progress: [BadgeProgress]
  @State private var selected: BadgeProgress?

  private var nextBadges: [BadgeProgress] {
    progress.filter { !earned.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 12) {
          Text("NEXT UP").forge(11, .semibold, tracking: 0.8).foregroundStyle(Theme.textTertiary)
          if nextBadges.isEmpty {
            Text("Every badge earned.").forgeLabel()
          } else {
            ForEach(nextBadges.prefix(3)) { entry in
              NextBadgeRow(symbol: entry.badge.symbol, title: entry.badge.title, progress: entry.progress, target: entry.target)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        categoryCard(title: String(localized: "Consistency", bundle: L10n.bundle), badges: [.firstSession, .tenSessions, .fiftySessions, .hundredSessions, .fourWeekStreak, .twelveWeekStreak])
        categoryCard(title: String(localized: "Strength", bundle: L10n.bundle), badges: [.firstPR, .tenPRs])
        categoryCard(title: String(localized: "Volume", bundle: L10n.bundle), badges: [.tonnage100k, .tonnage1M])
        Text("Badges come from logged sessions only.")
          .forgeCaption()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Awards")
    .sheet(item: $selected) { entry in
      BadgeDetailView(progress: entry, earned: earned.contains(entry.badge))
    }
  }

  private func categoryCard(title: String, badges: [Badge]) -> some View {
    let entries = badges.compactMap { b in progress.first { $0.badge == b } }
    let hero = entries.last { earned.contains($0.badge) } ?? entries.first
    let rest = entries.filter { $0.badge != hero?.badge }
    return VStack(alignment: .leading, spacing: 12) {
      Text(title).forgeSection()
      if let hero {
        Button { selected = hero } label: {
          VStack(spacing: 6) {
            Medallion(symbol: hero.badge.symbol, earned: earned.contains(hero.badge), size: 120)
            Text(hero.badge.title).forgeBodyStrong()
            Text(earned.contains(hero.badge) ? String(localized: "Earned", bundle: L10n.bundle) : "\(hero.progress) / \(hero.target)").forgeCaption()
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(earned.contains(hero.badge) ? String(localized: "\(hero.badge.title), earned", bundle: L10n.bundle) : String(localized: "\(hero.badge.title), \(hero.progress) of \(hero.target)", bundle: L10n.bundle))
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
        ForEach(rest) { entry in
          Button { selected = entry } label: {
            VStack(spacing: 6) {
              Medallion(symbol: entry.badge.symbol, earned: earned.contains(entry.badge), size: 44)
              Text(entry.badge.title).forgeCaption().multilineTextAlignment(.center).lineLimit(2)
            }
          }
          .buttonStyle(RowPressStyle())
          .accessibilityLabel(earned.contains(entry.badge) ? String(localized: "\(entry.badge.title), earned", bundle: L10n.bundle) : String(localized: "\(entry.badge.title), \(entry.progress) of \(entry.target)", bundle: L10n.bundle))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}
