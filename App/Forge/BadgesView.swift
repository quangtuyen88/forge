import SwiftUI
import ForgeCore

struct BadgeDetailView: View {
  let progress: BadgeProgress
  let earned: Bool

  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      Medallion(symbol: progress.badge.symbol, earned: earned, size: 200)
      Text(progress.badge.title).forgeTitle()
      Text(progress.badge.rule).forgeLabel().multilineTextAlignment(.center)
      if earned {
        Text(progress.badge.detail).forgeBody().multilineTextAlignment(.center)
      } else {
        Text("\(progress.progress) / \(progress.target)").forgeLabel().monospacedDigit()
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.track)
            Capsule().fill(Theme.accent)
              .frame(width: g.size.width * progress.fraction)
          }
        }
        .frame(width: 160, height: 6)
      }
      Spacer()
    }
    .padding(Theme.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.page)
    .presentationBackground(Theme.page)
  }
}
