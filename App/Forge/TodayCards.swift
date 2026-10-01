import SwiftUI
import ForgeCore

/// Best-lift card: trophy art, the lift's name, its best estimate.
struct RecordCard: View {
  let label: String
  let value: String
  let unit: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image("art-pro")
          .resizable()
          .scaledToFit()
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(label).forgeLabel().lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
              .forge(28, .bold, tracking: -0.8)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
            Text(unit).forge(13, .semibold).foregroundStyle(Theme.textSecondary)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.forward")
          .scaledSystemFont(13, weight: .bold)
          .foregroundStyle(Theme.textTertiary)
      }
      .todayCard(padding: 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
  }
}
