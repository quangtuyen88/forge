import SwiftUI

enum TrendDirection {
  case up, down, flat
}

struct TrendRow: View {
  let direction: TrendDirection
  let label: String
  let value: String
  var unit: String? = nil
  var detail: String? = nil
  var valueColor: Color = Theme.text
  var metricSymbol: String = "chart.bar.fill"

  private var directionSymbol: String? {
    switch direction {
    case .up: return "chevron.up"
    case .down: return "chevron.down"
    case .flat: return nil
    }
  }

  private var directionTint: Color {
    switch direction {
    case .up: return Theme.positive
    case .down: return Theme.negative
    case .flat: return Theme.textTertiary
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: metricSymbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(valueColor)
          .frame(width: 40, height: 40)
          .background(Circle().fill(valueColor.opacity(0.12)))
        if let directionSymbol {
          Image(systemName: directionSymbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 15, height: 15)
            .background(Circle().fill(directionTint))
            .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
        }
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(label).forgeBodyStrong()
        MetricValue(value: value, unit: unit, size: 20, color: valueColor)
        if let detail { Text(detail).forgeCaption() }
      }
      Spacer()
    }
    .accessibilityElement(children: .combine)
  }
}
