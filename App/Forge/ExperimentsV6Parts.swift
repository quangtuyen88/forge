import ForgeCore
import SwiftUI

// v6 Experiments focal and choice tiles. Static: no gradients or shadows here.

/// A flask tile ringed by ten Apple-Health metric glyphs on an ellipse.
struct ExperimentConstellation: View {
  private let icons: [(String, Color)] = [
    ("chart.bar.fill", Theme.metricSets),
    ("dumbbell.fill", Theme.accent),
    ("arrow.triangle.2.circlepath", Theme.metricSets),
    ("stopwatch.fill", Theme.metricTime),
    ("bed.double.fill", Theme.metricSleep),
    ("fork.knife", Theme.positive),
    ("heart.fill", Theme.metricHeart),
    ("flame.fill", Theme.accent),
    ("trophy.fill", Theme.recordRing),
    ("calendar", Theme.metricTime),
  ]

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(Theme.card)
        .frame(width: 96, height: 96)
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Theme.ring, lineWidth: 1))
      Image(systemName: "flask.fill")
        .font(.system(size: 44))
        .foregroundStyle(Theme.accent)
      ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
        Image(systemName: icon.0)
          .font(.system(size: 20))
          .foregroundStyle(icon.1)
          .offset(x: offsetX(index), y: offsetY(index))
      }
    }
    .frame(width: 220, height: 200)
    .accessibilityHidden(true)
  }

  private func offsetX(_ index: Int) -> CGFloat {
    100 * cos(angle(index))
  }

  private func offsetY(_ index: Int) -> CGFloat {
    88 * sin(angle(index))
  }

  private func angle(_ index: Int) -> Double {
    -Double.pi / 2 + Double(index) * (2 * Double.pi / Double(icons.count))
  }
}

/// One illustrated experiment choice: art clipped to the top corners above a text block.
struct ExperimentCandidateTile: View {
  let imageName: String
  let title: String
  let detail: String
  let hint: String
  let isSelected: Bool
  let action: () -> Void

  private var corner: RoundedRectangle {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
  }

  private var topClip: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
      topTrailingRadius: 16, style: .continuous)
  }

  /// Word joiner after the en dash keeps "5–8" from breaking after the dash.
  private var displayTitle: String {
    title.replacingOccurrences(of: "–", with: "–\u{2060}")
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          .frame(height: 128)
          .frame(maxWidth: .infinity)
          .overlay(alignment: .top) {
            Image(imageName)
              .resizable()
              .scaledToFill()
              .allowsHitTesting(false)
          }
          .clipShape(topClip)
          .accessibilityHidden(true)
        ZStack(alignment: .topTrailing) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: displayTitle)
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            Text(detail)
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.trailing, isSelected ? 24 : 0)
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 20))
              .foregroundStyle(Theme.accent)
              .accessibilityHidden(true)
          }
        }
        .padding(12)
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .background(corner.fill(Theme.card))
      .overlay(corner.strokeBorder(isSelected ? Theme.accent : Theme.ring, lineWidth: isSelected ? 2 : 1))
      .contentShape(corner)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(title)
    .accessibilityHint(hint)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
