import Charts
import ForgeCore
import SwiftUI

/// Compact trend of one lift: a blue line through the values, a dot on the newest (gold after a record).
struct LiftSparkline: View {
  let valuesKg: [Double]
  var endIsRecord = false
  var lineWidth: CGFloat = 2
  var dotDiameter: CGFloat = 6
  /// Colour of the surface behind the end dot; drawn as a thin ring around it.
  var ringColor: Color = Theme.card

  /// Honest per-row scale: anchored on the first value, floored so noise stays calm.
  static func domain(_ values: [Double]) -> ClosedRange<Double> {
    guard let first = values.first else { return 0...1 }
    guard values.count > 1, let last = values.last else { return (first - 2)...(first + 2) }
    let d = values.map { $0 - first }
    let lo = min(0, d.min()!)
    let hi = max(0, d.max()!)
    var span = max(hi - lo, 0.10 * first, 4)
    if abs(last - first) < 0.5 {
      span = max(span, 8)
      let mid = (lo + hi) / 2
      return (first + mid - span / 2)...(first + mid + span / 2)
    }
    if hi > 0 || lo == 0 { return (first + lo)...(first + lo + span) }
    return (first + hi - span)...(first + hi)
  }

  var body: some View {
    GeometryReader { geo in
      let inset = dotDiameter / 2 + 1.5
      let frame = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset, dy: inset)
      if valuesKg.count > 1 {
        let points = screenPoints(in: frame)
        ZStack {
          Self.monotonePath(through: points)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
          endDot.position(points.last!)
        }
      } else if let only = valuesKg.first {
        endDot.position(x: frame.midX, y: y(of: only, in: frame, domain: Self.domain(valuesKg)))
      }
    }
    .accessibilityHidden(true)
  }

  private var endDot: some View {
    ZStack {
      Circle().fill(ringColor)
      Circle().fill(endIsRecord ? Theme.recordRing : Theme.accent).padding(1.5)
    }
    .frame(width: dotDiameter + 3, height: dotDiameter + 3)
  }

  private func screenPoints(in frame: CGRect) -> [CGPoint] {
    let range = Self.domain(valuesKg)
    let step = frame.width / CGFloat(valuesKg.count - 1)
    return valuesKg.enumerated().map { i, v in
      CGPoint(x: frame.minX + CGFloat(i) * step, y: y(of: v, in: frame, domain: range))
    }
  }

  private func y(of value: Double, in frame: CGRect, domain: ClosedRange<Double>) -> CGFloat {
    let t = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
    return frame.maxY - CGFloat(t) * frame.height
  }

  /// Fritsch–Carlson monotone cubic: tangents go flat where the slope flips, never overshoots.
  private static func monotonePath(through points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    let m = tangents(of: points)
    for i in 0..<(points.count - 1) {
      let p0 = points[i]
      let p1 = points[i + 1]
      let dx = (p1.x - p0.x) / 3
      path.addCurve(
        to: p1,
        control1: CGPoint(x: p0.x + dx, y: p0.y + dx * m[i]),
        control2: CGPoint(x: p1.x - dx, y: p1.y - dx * m[i + 1]))
    }
    return path
  }

  private static func tangents(of points: [CGPoint]) -> [CGFloat] {
    let n = points.count
    guard n > 1 else { return [] }
    var slopes: [CGFloat] = []
    for i in 0..<(n - 1) {
      let dx = points[i + 1].x - points[i].x
      slopes.append(dx > 0 ? (points[i + 1].y - points[i].y) / dx : 0)
    }
    var m = [CGFloat](repeating: 0, count: n)
    m[0] = slopes[0]
    m[n - 1] = slopes[n - 2]
    for i in 1..<(n - 1) {
      let a = slopes[i - 1]
      let b = slopes[i]
      m[i] = a * b <= 0 ? 0 : 2 * a * b / (a + b)
    }
    return m
  }
}

/// "+19 kg", "Holding", "−2 kg", or "—" when there is nothing to compare.
struct TrendChangeText: View {
  let changeKg: Double?
  let isLb: Bool
  var size: CGFloat = 17

  /// The words the view shows, for accessibility labels and values.
  static func label(changeKg: Double?, isLb: Bool) -> String {
    guard let kg = changeKg else { return "" }
    if abs(kg) < 0.5 { return String(localized: "Holding", bundle: L10n.bundle) }
    let display = (isLb ? Plates.kgToLb(kg) : kg).rounded()
    let unit = isLb ? "lb" : "kg"
    if kg >= 0.5 { return "+\(Fmt.num(display)) \(unit)" }
    return "\u{2212}\(Fmt.num(abs(display))) \(unit)"
  }

  var body: some View {
    Text(verbatim: string.isEmpty ? "—" : string)
      .foregroundStyle(tint)
      .font(.forge(size, .semibold).monospacedDigit())
      .lineLimit(1)
      .fixedSize()
  }

  private var string: String {
    Self.label(changeKg: changeKg, isLb: isLb)
  }

  private var tint: Color {
    guard let kg = changeKg, kg >= 0.5 else { return Theme.textSecondary }
    return Theme.positiveText
  }
}

/// One step per record: the line holds the best estimated max until the next record, then steps up.
struct RecordStaircase: View {
  struct Step: Identifiable {
    let date: Date
    let e1rmKg: Double
    var id: Date { date }
  }

  /// The lift's first workout: where the staircase starts.
  let start: Step
  /// Record events, oldest first.
  let records: [Step]
  /// The newest workout; the last step runs on to this date.
  let endDate: Date
  let isLb: Bool
  var height: CGFloat = 132

  var body: some View {
    let steps = linePoints
    let marked = [start] + records
    let values = steps.map { display($0.e1rmKg) }
    let pad = max(2, (values.max()! - values.min()!) * 0.12)
    Chart {
      ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
        LineMark(
          x: .value("Date", step.date),
          y: .value("Weight", display(step.e1rmKg)))
          .interpolationMethod(.stepEnd)  // holds until the record's date; .stepStart jumps one interval early
          .foregroundStyle(Theme.accent)
          .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
      }
      ForEach(Array(marked.enumerated()), id: \.offset) { i, step in
        PointMark(
          x: .value("Date", step.date),
          y: .value("Weight", display(step.e1rmKg)))
          .symbol {
            let isStart = i == 0
            let isLast = i == marked.count - 1
            let frame: CGFloat = isStart ? 10 : 14
            ZStack {
              Circle().fill(Theme.card)
              Circle().fill(isStart ? Theme.textTertiary : Theme.recordRing).padding(1.5)
            }
            .frame(width: frame, height: frame)
            .overlay {
              Text(verbatim: Fmt.num(display(step.e1rmKg).rounded()))
                .font(isLast ? .forge(13, .semibold) : .forge(12, .regular))
                .foregroundStyle(isLast ? Theme.text : Theme.textSecondary)
                .fixedSize()
                .offset(y: -(frame / 2 + 11))
            }
          }
      }
    }
    .chartYScale(domain: (values.min()! - pad)...(values.max()! + 2 * pad))
    .chartYAxis(.hidden)
    .chartXAxis {
      if usesDayTicks {
        AxisMarks(values: .automatic(desiredCount: 3)) {
          AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(L10n.locale))
            .font(.forge(12, .regular))
            .foregroundStyle(Theme.textSecondary)
        }
      } else {
        AxisMarks(values: .stride(by: .month)) {
          AxisValueLabel(format: .dateTime.month(.abbreviated).locale(L10n.locale))
            .font(.forge(12, .regular))
            .foregroundStyle(Theme.textSecondary)
        }
      }
    }
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(localized: "\(records.count) records, from \(startText) to \(endText)", bundle: L10n.bundle))
  }

  private var linePoints: [Step] {
    let lastValue = records.last?.e1rmKg ?? start.e1rmKg
    let lastDate = records.last?.date ?? start.date
    return [start] + records + [Step(date: max(endDate, lastDate), e1rmKg: lastValue)]
  }

  private var usesDayTicks: Bool {
    endDate.timeIntervalSince(start.date) < 60 * 86400
  }

  private var unit: String { isLb ? "lb" : "kg" }

  private var startText: String {
    "\(Fmt.num(display(start.e1rmKg).rounded())) \(unit)"
  }

  private var endText: String {
    "\(Fmt.num(display(records.last?.e1rmKg ?? start.e1rmKg).rounded())) \(unit)"
  }

  private func display(_ kg: Double) -> Double {
    isLb ? Plates.kgToLb(kg) : kg
  }
}

#Preview {
  let cal = Calendar.current
  let now = Date.now
  return VStack(alignment: .leading, spacing: 24) {
    LiftSparkline(valuesKg: [82.5, 83, 85, 86, 86, 88, 90], endIsRecord: true)
      .frame(width: 160, height: 44)
    LiftSparkline(valuesKg: [100, 100.5, 100, 100.4, 100])
      .frame(width: 160, height: 44)
    HStack(spacing: 16) {
      TrendChangeText(changeKg: 19.4, isLb: false)
      TrendChangeText(changeKg: 0.2, isLb: false)
      TrendChangeText(changeKg: -2.1, isLb: false)
      TrendChangeText(changeKg: nil, isLb: false)
    }
    RecordStaircase(
      start: RecordStaircase.Step(
        date: cal.date(byAdding: .day, value: -320, to: now)!,
        e1rmKg: 80),
      records: [
        .init(date: cal.date(byAdding: .day, value: -260, to: now)!, e1rmKg: 84),
        .init(date: cal.date(byAdding: .day, value: -200, to: now)!, e1rmKg: 88),
        .init(date: cal.date(byAdding: .day, value: -140, to: now)!, e1rmKg: 91),
        .init(date: cal.date(byAdding: .day, value: -80, to: now)!, e1rmKg: 94),
        .init(date: cal.date(byAdding: .day, value: -24, to: now)!, e1rmKg: 97.5),
      ],
      endDate: now,
      isLb: false)
  }
  .padding()
}
