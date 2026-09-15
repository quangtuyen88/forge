import SwiftUI
import ForgeCore

/// "Badges" card: 4-column grid of every badge, earned highlighted, locked dimmed.
/// Tap opens a small detail sheet; celebration toast is owned by `ProgressTabView`.
struct BadgesView: View {
  let earned: [Badge]

  private struct Selection: Identifiable {
    let badge: Badge
    var id: String { badge.rawValue }
  }

  @State private var selected: Selection?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Badges").forgeSection()
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
        ForEach(Badge.allCases, id: \.rawValue) { badge in
          BadgeCell(badge: badge, isEarned: earned.contains(badge)) {
            selected = Selection(badge: badge)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(item: $selected) { selection in
      BadgeDetailSheet(badge: selection.badge, isEarned: earned.contains(selection.badge))
        .presentationDetents([.fraction(0.3)])
    }
  }
}

private struct BadgeCell: View {
  let badge: Badge
  let isEarned: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: badge.symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(isEarned ? Theme.onAccent : Theme.textTertiary)
          .frame(width: 44, height: 44)
          .background(Circle().fill(isEarned ? Theme.accent : Theme.track))
        Text(badge.title)
          .forgeCaption()
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .opacity(isEarned ? 1 : 0.5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(badge.title), \(isEarned ? "earned" : "locked")")
  }
}

private struct BadgeDetailSheet: View {
  let badge: Badge
  let isEarned: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: badge.symbol)
        .font(.system(size: 26, weight: .semibold))
        .foregroundColor(isEarned ? Theme.onAccent : Theme.textTertiary)
        .frame(width: 56, height: 56)
        .background(Circle().fill(isEarned ? Theme.accent : Theme.track))
      Text(badge.title).forgeSection()
      Text(badge.detail)
        .forgeLabel()
        .multilineTextAlignment(.center)
      Text(isEarned ? "Earned" : "Locked")
        .forge(11, .semibold)
        .foregroundColor(isEarned ? Theme.positive : Theme.textTertiary)
        .textCase(.uppercase)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
  }
}
