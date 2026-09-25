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
      VStack(alignment: .leading, spacing: 24) {
        hero
        categoryCard("Sessions", badges: [.firstSession, .tenSessions, .fiftySessions, .hundredSessions])
        categoryCard("Streaks and records", badges: [.fourWeekStreak, .twelveWeekStreak, .firstPR, .tenPRs])
        categoryCard("Volume", badges: [.tonnage100k, .tonnage1M])
        Text("Badges come from logged sessions only.")
          .forgeCaption()
          .foregroundStyle(Theme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationTitle("Awards")
    .sheet(item: $selected) { entry in
      BadgeDetailView(progress: entry, earned: earned.contains(entry.badge))
    }
  }

  private var hero: some View {
    VStack(spacing: 8) {
      Illustration(name: "art-pro", height: 120)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(earned.count)").forge(56, .bold).foregroundStyle(Theme.text).monospacedDigit()
        Text("of \(Badge.allCases.count) earned").forge(22, .semibold).foregroundStyle(Theme.text)
      }
      // The hero sits where the sky turns light; white text would drop below AA contrast there.
      Text("Next up").forge(15, .semibold).foregroundStyle(Theme.text)
      if let next = nextBadges.first {
        Text("\(next.badge.title) · \(next.target - next.progress) to go")
          .forge(15, .regular)
          .foregroundStyle(Theme.text)
      } else {
        Text("Every badge earned.").forge(15, .regular).foregroundStyle(Theme.text)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func categoryCard(_ title: LocalizedStringKey, badges: [Badge]) -> some View {
    let entries = badges.compactMap { b in progress.first { $0.badge == b } }
    return SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(title).forge(17, .semibold)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 4), spacing: 16) {
          ForEach(entries) { entry in
            let isEarned = earned.contains(entry.badge)
            Button { selected = entry } label: {
              VStack(spacing: 6) {
                MedalArt(badge: entry.badge, earned: isEarned, fraction: entry.fraction, size: 64)
                Text(entry.badge.title)
                  .forge(13, .regular)
                  .foregroundStyle(Theme.text)
                  .multilineTextAlignment(.center)
                  .lineLimit(2)
                if !isEarned {
                  Text("\(entry.progress) of \(entry.target)")
                    .forge(13, .regular)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                }
              }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(
              isEarned
              ? String(localized: "\(entry.badge.title), earned", bundle: L10n.bundle)
              : String(localized: "\(entry.badge.title), \(entry.progress) of \(entry.target)", bundle: L10n.bundle))
          }
        }
      }
    }
  }
}
