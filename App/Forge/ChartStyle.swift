import SwiftUI
import Charts

extension View {
  func forgeChart() -> some View {
    self
      .chartYAxis {
        AxisMarks(position: .trailing) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
          AxisValueLabel().font(.forge(11, .medium)).foregroundStyle(Theme.textTertiary)
        }
      }
      .chartXAxis {
        AxisMarks { _ in
          AxisValueLabel().font(.forge(11, .medium)).foregroundStyle(Theme.textTertiary)
        }
      }
  }
}

struct ChartCallout: View {
  let value: String
  let caption: String

  var body: some View {
    VStack(spacing: 1) {
      Text(value).forge(15, .bold).monospacedDigit()
      Text(caption).forge(11, .medium)
    }
    .foregroundColor(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
  }
}
