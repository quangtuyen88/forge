import SwiftUI

struct Medallion: View {
  let symbol: String
  var earned: Bool = true
  var size: CGFloat = 64

  var body: some View {
    ZStack {
      if earned {
        Circle().fill(Theme.accent)
        Circle().fill(Theme.page).padding(size * 0.12)
        Image(systemName: symbol)
          .font(.system(size: size * 0.36, weight: .semibold))
          .foregroundStyle(Theme.text)
      } else {
        Circle().strokeBorder(Theme.track, lineWidth: max(2, size * 0.06))
        Image(systemName: symbol)
          .font(.system(size: size * 0.36, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct NextBadgeRow: View {
  let symbol: String
  let title: String
  let progress: Int
  let target: Int

  var body: some View {
    HStack(spacing: 12) {
      Medallion(symbol: symbol, earned: false, size: 48)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).forgeBodyStrong()
        Text("\(progress) / \(target)").forgeLabel().monospacedDigit()
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.track)
            Capsule().fill(Theme.accent)
              .frame(width: g.size.width * CGFloat(min(1, Double(progress) / Double(max(target, 1)))))
          }
        }
        .frame(height: 6)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
