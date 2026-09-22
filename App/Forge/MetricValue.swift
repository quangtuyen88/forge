import SwiftUI

struct MetricValue: View {
  let value: String
  var unit: String? = nil
  var size: CGFloat = 28
  var color: Color = Theme.text
  var unitColor: Color = Theme.textSecondary
  var numeric: Bool = true

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 3) {
      Text(value)
        .forge(size, .bold)
        .monospacedDigit()
        .tracking(size >= 40 ? -1.5 : -0.7)
        .foregroundStyle(color)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .contentTransition(numeric ? .numericText() : .identity)
      if let unit {
        Text(unit)
          .forge(size * 0.55, .semibold, tracking: 0)
          .foregroundStyle(unitColor)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(value) \(unit ?? "")".trimmingCharacters(in: .whitespaces))
  }
}
