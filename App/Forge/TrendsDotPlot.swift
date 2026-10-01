import Accessibility
import SwiftUI

/// The one % scale every Trends row shares: floor/ceiling multiples of 5 around the row
/// percents, always spanning 0…10 at minimum.
struct TrendsScale {
  let lo: Int
  let hi: Int
  let ticks: [Int]

  init(rowPercents: [Double]) {
    let rawLo = min(0, Int(floor((rowPercents.min() ?? 0) / 5)) * 5)
    let rawHi = max(10, Int(ceil((rowPercents.max() ?? 0) / 5)) * 5)
    let step = rawHi - rawLo <= 20 ? 5 : (rawHi - rawLo <= 50 ? 10 : 20)
    // Round the ends to multiples of the step so 0 % and both ends are always ticks.
    lo = Int(floor(Double(rawLo) / Double(step))) * step
    hi = Int(ceil(Double(rawHi) / Double(step))) * step
    ticks = Array(stride(from: lo, through: hi, by: step))
  }

  /// Tick x inside a plot of `width`: 8 pt inset on both sides so end dots never clip.
  func x(of percent: Double, width: CGFloat) -> CGFloat {
    8 + (width - 16) * CGFloat((percent - Double(lo)) / Double(hi - lo))
  }
}

/// Scale header's tick labels, centered on each tick x of the plot column.
struct TrendsScaleTicks: View {
  let scale: TrendsScale

  var body: some View {
    GeometryReader { geo in
      ForEach(visibleTicks(width: geo.size.width), id: \.self) { t in
        Text(verbatim: "\(t) %")
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .fixedSize()
          .position(x: scale.x(of: Double(t), width: geo.size.width), y: geo.size.height / 2)
      }
    }
  }

  /// Labels are ~30 pt wide; hide any whose centre sits closer than 36 pt to the previous shown.
  private func visibleTicks(width: CGFloat) -> [Int] {
    var shown: [Int] = []
    var lastX: CGFloat?
    for t in scale.ticks {
      let x = scale.x(of: Double(t), width: width)
      if let lastX, x - lastX < 36 { continue }
      shown.append(t)
      lastX = x
    }
    return shown
  }
}

/// One lift's mark on the shared % scale: dashed gridlines, open start circle at 0,
/// line and end dot at the percent. Holding or no change draws the start circle only.
struct TrendsDotRow: View {
  let scale: TrendsScale
  let percent: Double?
  let status: TrendStatus?
  let recordFresh: Bool

  var body: some View {
    Canvas { ctx, size in
      let midY = size.height / 2
      for t in scale.ticks {
        let x = scale.x(of: Double(t), width: size.width)
        var grid = Path()
        grid.move(to: CGPoint(x: x, y: 0))
        grid.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(grid, with: .color(Theme.track), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
      }
      let startX = scale.x(of: 0, width: size.width)
      if let percent, status == .stronger || status == .dipped {
        let ink = status == .dipped ? Theme.textSecondary : Theme.accent
        let endX = scale.x(of: percent, width: size.width)
        var line = Path()
        line.move(to: CGPoint(x: startX, y: midY))
        line.addLine(to: CGPoint(x: endX, y: midY))
        ctx.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(
          Path(ellipseIn: CGRect(x: endX - 5, y: midY - 5, width: 10, height: 10)),
          with: .color(ink))
        if status == .stronger, recordFresh {
          ctx.stroke(
            Path(ellipseIn: CGRect(x: endX - 7, y: midY - 7, width: 14, height: 14)),
            with: .color(Theme.recordRing),
            style: StrokeStyle(lineWidth: 2))
        }
      }
      // Start circle last: its page fill keeps the line out of the open circle.
      let start = CGRect(x: startX - 4.5, y: midY - 4.5, width: 9, height: 9)
      ctx.fill(Path(ellipseIn: start), with: .color(Theme.page))
      ctx.stroke(
        Path(ellipseIn: start),
        with: .color(Theme.textSecondary),
        style: StrokeStyle(lineWidth: 1.5))
    }
    .accessibilityHidden(true)
  }
}

/// One lift's dot plot as a chart descriptor, so VoiceOver can explore it as a chart.
struct TrendsDotDescriptor: AXChartDescriptorRepresentable {
  let liftName: String
  let percent: Double?

  func makeChartDescriptor() -> AXChartDescriptor {
    let value = percent ?? 0
    let categoryAxis = AXCategoricalDataAxisDescriptor(
      title: String(localized: "Lift", bundle: L10n.bundle),
      categoryOrder: [liftName])
    let valueAxis = AXNumericDataAxisDescriptor(
      title: String(localized: "Change", bundle: L10n.bundle),
      range: min(0, value)...max(1, value),
      gridlinePositions: []) { Fmt.num($0) }
    let series = AXDataSeriesDescriptor(
      name: String(localized: "Change", bundle: L10n.bundle),
      isContinuous: false,
      dataPoints: [AXDataPoint(x: liftName, y: value)])
    return AXChartDescriptor(
      title: String(localized: "Lift trend", bundle: L10n.bundle),
      summary: liftName,
      xAxis: categoryAxis,
      yAxis: valueAxis,
      additionalAxes: [],
      series: [series])
  }
}
