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

  private var tint: Color {
    switch direction {
    case .up: Theme.positive
    case .down: Theme.negative
    case .flat: Theme.textTertiary
    }
  }

  private var symbol: String {
    switch direction {
    case .up: "chevron.up"
    case .down: "chevron.down"
    case .flat: "minus"
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(tint)
        .frame(width: 40, height: 40)
        .background(Circle().fill(tint.opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(label).forgeBodyStrong()
        MetricValue(value: value, unit: unit, size: 20, color: direction == .flat ? Theme.text : tint)
        if let detail {
          Text(detail).forgeCaption()
        }
      }
      Spacer()
    }
    .accessibilityElement(children: .combine)
  }
}
