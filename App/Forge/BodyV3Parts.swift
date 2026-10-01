import Accessibility
import ForgeCore
import SwiftUI

/// Shared parts for the Body group v3 detail screens (Muscles, Awards, Body stats, Photos,
/// Recovery, Fuel): white pages with 8 pt grey bands (`LogBand`), one section header style,
/// one row style. Data helpers here are derivations every screen repeats.
enum BodyV3 {
  /// The mock's 4-step set ramp: 1–5, 6–8, 9–11, 12+. 0 stays untinted.
  static func rampStep(_ sets: Double) -> Int {
    switch sets {
    case ...0: return 0
    case ...5: return 1
    case ...8: return 2
    case ...11: return 3
    default: return 4
    }
  }

  /// Ramp color of one muscle's set count (matches the figure legend).
  static func rampColor(sets: Double) -> Color {
    let step = rampStep(sets)
    return step == 0 ? Theme.ramp[0] : Theme.ramp[step]
  }

  /// Target-zone grey of the range tracks (mock --zone), as a token-derived tint.
  static var zone: Color { Theme.textSecondary.opacity(0.3) }

  /// "Mon 12" / "Today" label for one calendar day.
  static func dayLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return String(localized: "Today", bundle: L10n.bundle) }
    return date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
  }

  /// Median whole-day gap between consecutive dates, when the rhythm is steady enough to
  /// predict the next one (weekly weigh-ins, photo cadences). nil when it is not.
  static func steadyGap(days: [Date]) -> Int? {
    let gaps = zip(days, days.dropFirst()).map { ($1.timeIntervalSince($0) / 86400).rounded() }
    guard gaps.count >= 2, gaps.allSatisfy({ $0 >= 4 && $0 <= 10 }) else { return nil }
    let sorted = gaps.sorted()
    return Int(sorted[sorted.count / 2])
  }

  /// Block number of a date from block first-session dates (LogV3.blocks walk callers reuse).
  static func block(of date: Date, starts: [Date]) -> Int {
    var number = 1
    for (index, start) in starts.enumerated() where start <= date { number = index + 1 }
    return number
  }
}

/// Section header on a white page: 20 pt bold title, optional trailing caption (mock .sh).
struct V3SectionHeader: View {
  let title: LocalizedStringKey
  var trailing: String? = nil

  init(_ title: LocalizedStringKey, trailing: String? = nil) {
    self.title = title
    self.trailing = trailing
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).forge(20, .bold).tracking(-0.3).foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      if let trailing {
        Text(verbatim: trailing)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 10)
  }
}

/// One list row on a white page: 32 pt icon badge, 17 pt title, 14 pt subtitle, right detail
/// (mock .row). Callers draw the hairline with `Divider().padding(.leading, 44)`.
struct V3DetailRow<Trailing: View>: View {
  let icon: String
  var tint: Color = Theme.accent
  let title: String
  var subtitle: String? = nil
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      LogIconBadge(symbol: icon, tint: tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title).forge(17, .semibold).foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(verbatim: subtitle).forge(14, .regular).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 8)
      trailing()
    }
    .padding(.vertical, 10)
    .frame(minHeight: 60, alignment: .center)
    .accessibilityElement(children: .combine)
  }
}

/// Flat inner-surface strip for a quiet fact (mock .note / .tint without the tint).
struct V3NoteRow<Trailing: View>: View {
  let icon: String
  var tint: Color = Theme.accent
  let title: String
  var subtitle: String? = nil
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      LogIconBadge(symbol: icon, tint: tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title).forge(17, .semibold).foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(verbatim: subtitle).forge(14, .regular).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .padding(.leading, 2)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
    .accessibilityElement(children: .combine)
  }
}

extension V3NoteRow where Trailing == EmptyView {
  init(icon: String, tint: Color = Theme.accent, title: String, subtitle: String? = nil) {
    self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
  }
}

/// Accent text link with a trailing chevron; a 44 pt touch target (mock .lk / .link).
struct V3Link: View {
  let text: String

  var body: some View {
    HStack(spacing: 2) {
      Text(verbatim: text)
      Image(systemName: "chevron.forward")
        .scaledSystemFont(15, weight: .semibold)
    }
    .forge(16, .medium)
    .foregroundStyle(Theme.accentText)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}

/// Full circle ring with a gradient fill arc (mock ring()); track behind, round caps.
struct V3GradientRing: View {
  let progress: Double
  let colors: [Color]
  var lineWidth: CGFloat = 6

  var body: some View {
    ZStack {
      Circle().inset(by: lineWidth / 2).stroke(Theme.track, lineWidth: lineWidth)
      Circle()
        .inset(by: lineWidth / 2)
        .trim(from: 0, to: max(0, min(1, progress)))
        .stroke(.mark(colors), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .accessibilityHidden(true)
  }
}

/// Seven-day bar chart: value above each bar, gradient bar, day letter below; a missing day
/// is a short dashed capsule, not zero (mock .sleep / .pbars). Optional dashed target line
/// with a right-aligned label chip.
struct V3WeekBars: View {
  struct Day {
    let label: String
    let value: Double?
    var isToday = false
  }

  let days: [Day]
  var maxV: Double
  var colors: [Color]
  var barHeight: CGFloat = 112
  var target: Double? = nil
  var targetLabel: String? = nil

  private var valueTop: CGFloat { 16 + 4 }  // value label height + gap

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(Array(days.enumerated()), id: \.offset) { _, day in
            column(day)
              .frame(maxWidth: .infinity)
          }
        }
        if let target {
          targetOverlay(y: valueTop + barHeight * (1 - CGFloat(target / max(maxV, 0.001))))
        }
      }
      HStack(spacing: 12) {
        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
          Text(verbatim: day.label)
            .forge(13, day.isToday ? .bold : .medium)
            .foregroundStyle(day.isToday ? Theme.text : Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.top, 8)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityChartDescriptor(self)
  }

  private var accessibilityText: String {
    days.compactMap { day in
      day.value.map { "\(day.label) \(Fmt.num($0))" }
    }.joined(separator: ", ")
  }

  private func column(_ day: Day) -> some View {
    VStack(spacing: 4) {
      if let value = day.value {
        Text(verbatim: Fmt.num(value))
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      } else {
        Text(verbatim: "—").forge(12, .medium).foregroundStyle(Theme.textSecondary)
      }
      if let value = day.value {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.mark(colors, startPoint: .bottom, endPoint: .top))
          .frame(width: 24, height: max(4, barHeight * CGFloat(value / max(maxV, 0.001))))
          .frame(maxHeight: .infinity, alignment: .bottom)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(BodyV3.zone, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
          .frame(width: 22, height: 30)
          .frame(maxHeight: .infinity, alignment: .bottom)
      }
    }
    .frame(height: valueTop + barHeight, alignment: .top)
  }

  /// Dashed target rule with a page-backed label at its right end (mock .tgt / .tl).
  private func targetOverlay(y: CGFloat) -> some View {
    Path { p in
      p.move(to: CGPoint(x: 0, y: 0))
      p.addLine(to: CGPoint(x: 1, y: 0))
    }
    .stroke(Theme.textSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    .frame(height: 0)
    .frame(maxWidth: .infinity)
    .overlay(alignment: .trailing) {
      if let targetLabel {
        Text(verbatim: targetLabel)
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .padding(.leading, 6)
          .background(Theme.page)
          .offset(y: -17)
      }
    }
    .offset(y: max(0, y))
    .allowsHitTesting(false)
  }
}

extension V3WeekBars: AXChartDescriptorRepresentable {
  func makeChartDescriptor() -> AXChartDescriptor {
    let entries = days.compactMap { day -> (label: String, value: Double)? in
      guard let value = day.value else { return nil }
      return (day.label, value)
    }
    let xAxis = AXCategoricalDataAxisDescriptor(
      title: String(localized: "Day", bundle: L10n.bundle),
      categoryOrder: entries.map(\.label))
    let yAxis = AXNumericDataAxisDescriptor(
      title: String(localized: "Value", bundle: L10n.bundle),
      range: (entries.map(\.value).min() ?? 0)...(entries.map(\.value).max() ?? 1),
      gridlinePositions: []) { Fmt.num($0) }
    let series = AXDataSeriesDescriptor(
      name: String(localized: "Value", bundle: L10n.bundle),
      isContinuous: false,
      dataPoints: entries.map { AXDataPoint(x: $0.label, y: $0.value) })
    return AXChartDescriptor(
      title: String(localized: "7-day chart", bundle: L10n.bundle),
      summary: accessibilityText,
      xAxis: xAxis,
      yAxis: yAxis,
      additionalAxes: [],
      series: [series])
  }
}

/// One "All muscles" row: name, landmark range line, range track (zone + sets fill), value
/// (mock .mr). The track's fill carries a page-colored edge so it reads over the zone.
struct V3MuscleRow: View {
  let muscle: Muscle
  let sets: Double
  let floor: Int
  let mrv: Int
  let scale: Double

  private var under: Int? {
    sets < Double(floor) ? Int((Double(floor) - sets).rounded(.up)) : nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 1) {
        Text(muscle.a11yName).forge(17, .semibold).foregroundStyle(Theme.text)
        if let under {
          Text(
            String(localized: "Range \(floor)–\(mrv) · \(under) under", bundle: L10n.bundle))
          .forge(13, .regular).foregroundStyle(Theme.textSecondary).monospacedDigit()
        } else {
          Text(verbatim: "Range \(floor)–\(mrv)")
            .forge(13, .regular).foregroundStyle(Theme.textSecondary).monospacedDigit()
        }
      }
      .frame(width: 122, alignment: .leading)
      track
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(verbatim: Fmt.num(sets)).forge(17, .semibold).monospacedDigit()
          .foregroundStyle(Theme.text)
        Text(String(localized: "sets", bundle: L10n.bundle))
          .forge(13, .regular).foregroundStyle(Theme.textSecondary)
      }
      .frame(minWidth: 48, alignment: .trailing)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 8)
    .frame(minHeight: 62)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(
        localized: "\(muscle.a11yName), \(Fmt.num(sets)) sets, range \(floor)–\(mrv)",
        bundle: L10n.bundle))
  }

  private var track: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let pct = { (v: Double) in CGFloat(v / scale) }
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.innerSurface)
        Capsule()
          .fill(BodyV3.zone)
          .frame(width: max(0, w * (pct(Double(mrv)) - pct(Double(floor)))))
          .offset(x: w * pct(Double(floor)))
        Capsule()
          .fill(.mark(Theme.gradBrand, startPoint: .leading, endPoint: .trailing))
          .overlay(
            Capsule().strokeBorder(Theme.page, lineWidth: 2)
              .frame(width: min(w, w * pct(sets))))
          .frame(width: min(w, max(0, w * pct(sets))))
      }
    }
    .frame(height: 10)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }
}

/// Bodyweight chart on the white page (mock wchart): gridlines at whole units, one dot per
/// weigh-in, the current block full strength with an area fill, earlier blocks muted, the
/// block change marked by a dashed rule.
struct V3WeightChart: View {
  /// Ascending by date, already in the display unit.
  let points: [(date: Date, value: Double)]
  /// Index of the first point inside the current block; nil when blocks are unknown.
  var currentBlockStart: Int? = nil
  var blockLabel: String? = nil

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width - 34
      let h = geo.size.height - 22
      if points.count >= 2, let loV = points.map(\.value).min(), let hiV = points.map(\.value).max() {
        let pad = max(0.2, (hiV - loV) * 0.12)
        let lo = floor(loV - pad), hi = ceil(hiV + pad)
        let first = points.first!.date.timeIntervalSince1970
        let last = points.last!.date.timeIntervalSince1970
        let span = max(last - first, 1)
        let x = { (d: Date) in CGFloat((d.timeIntervalSince1970 - first) / span) * w }
        let y = { (v: Double) in h - (h - 12) * CGFloat((v - lo) / max(hi - lo, 0.001)) }
        let blockStart = min(currentBlockStart ?? points.count, points.count)
        let path = { (from: Int, to: Int) in
          Path { p in
            p.move(to: CGPoint(x: x(points[from].date), y: y(points[from].value)))
            for i in (from + 1)..<to { p.addLine(to: CGPoint(x: x(points[i].date), y: y(points[i].value))) }
          }
        }
        ZStack(alignment: .topLeading) {
          gridlines(lo: lo, hi: hi, y: y, w: w)
          if blockStart < points.count - 1, let label = blockLabel {
            blockRule(at: x(points[blockStart].date), label: label, h: h)
          }
          if blockStart < points.count {
            area(path: path(blockStart, points.count), baseline: h)
            path(blockStart, points.count)
              .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
          }
          if blockStart > 0 {
            path(0, min(blockStart + 1, points.count))
              .stroke(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
          }
          dots(x: x, y: y, blockStart: blockStart)
          xLabels(first: points.first!.date, mid: points[points.count / 2].date, last: points.last!.date)
            .frame(width: w)
            .offset(y: h + 6)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
    .accessibilityChartDescriptor(self)
  }

  private var accessibilitySummary: String {
    let format = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(L10n.locale)
    guard let first = points.first else { return "" }
    let firstText = "\(first.date.formatted(format)) \(Fmt.num(first.value))"
    guard let last = points.last, points.count >= 2 else { return firstText }
    let change = last.value - first.value
    let changeText = (change >= 0 ? "+" : "") + Fmt.num(change)
    return "\(firstText), \(last.date.formatted(format)) \(Fmt.num(last.value)), \(changeText)"
  }

  private func gridlines(lo: Double, hi: Double, y: @escaping (Double) -> CGFloat, w: CGFloat) -> some View {
    let step = max(1, (Int(hi - lo) + 2) / 3)
    let loInt = Int(lo)
    return ZStack(alignment: .topLeading) {
      ForEach(Array(stride(from: loInt, through: Int(hi), by: step).enumerated()), id: \.offset) { _, v in
        let value = Double(v)
        Path { p in
          p.move(to: CGPoint(x: 0, y: y(value)))
          p.addLine(to: CGPoint(x: w, y: y(value)))
        }
        .stroke(Theme.ring, lineWidth: 1)
        Text(verbatim: Fmt.num(value, max: 0))
          .forge(12, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .position(x: w + 22, y: y(value) + 4)
      }
    }
  }

  private func blockRule(at x: CGFloat, label: String, h: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      Path { p in
        p.move(to: CGPoint(x: x, y: 6))
        p.addLine(to: CGPoint(x: x, y: h))
      }
      .stroke(BodyV3.zone, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
      Text(verbatim: label)
        .forge(12, .regular)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize()
        .offset(x: x + 6, y: 0)
    }
  }

  private func area(path: Path, baseline: CGFloat) -> some View {
    Path { p in
      p.addPath(path)
      p.addLine(to: CGPoint(x: path.boundingRect.maxX, y: baseline))
      p.addLine(to: CGPoint(x: path.boundingRect.minX, y: baseline))
      p.closeSubpath()
    }
    .fill(.fade(Theme.accent, opacity: 0.22))
  }

  private func dots(x: @escaping (Date) -> CGFloat, y: @escaping (Double) -> CGFloat, blockStart: Int) -> some View {
    ForEach(Array(points.enumerated()), id: \.offset) { i, point in
      let last = i == points.count - 1
      let earlier = i < blockStart
      if last {
        Circle()
          .fill(Theme.accent)
          .frame(width: 10, height: 10)
          .overlay(Circle().strokeBorder(Theme.page, lineWidth: 2))
          .position(x: x(point.date), y: y(point.value))
      } else {
        Circle()
          .fill(Theme.page)
          .overlay(
            Circle().strokeBorder(Theme.accent.opacity(earlier ? 0.45 : 1), lineWidth: 2))
          .frame(width: 6, height: 6)
          .position(x: x(point.date), y: y(point.value))
      }
    }
  }

  private func xLabels(first: Date, mid: Date, last: Date) -> some View {
    let format = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(L10n.locale)
    return HStack {
      Text(first.formatted(format)).frame(maxWidth: .infinity, alignment: .leading)
      Text(mid.formatted(format))
      Text(last.formatted(format)).frame(maxWidth: .infinity, alignment: .trailing)
    }
    .forge(12, .regular)
    .foregroundStyle(Theme.textSecondary)
    .monospacedDigit()
  }
}

extension V3WeightChart: AXChartDescriptorRepresentable {
  func makeChartDescriptor() -> AXChartDescriptor {
    let format = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(L10n.locale)
    let dateAxis = AXNumericDataAxisDescriptor(
      title: String(localized: "Date", bundle: L10n.bundle),
      range: (points.first?.date.timeIntervalSince1970 ?? 0)...(points.last?.date.timeIntervalSince1970 ?? 1),
      gridlinePositions: []) { Date(timeIntervalSince1970: $0).formatted(format) }
    let values = points.map(\.value)
    let valueAxis = AXNumericDataAxisDescriptor(
      title: String(localized: "Weight", bundle: L10n.bundle),
      range: (values.min() ?? 0)...(values.max() ?? 1),
      gridlinePositions: []) { Fmt.num($0) }
    let series = AXDataSeriesDescriptor(
      name: String(localized: "Weight", bundle: L10n.bundle),
      isContinuous: true,
      dataPoints: points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) })
    return AXChartDescriptor(
      title: String(localized: "Weight chart", bundle: L10n.bundle),
      summary: accessibilitySummary,
      xAxis: dateAxis,
      yAxis: valueAxis,
      additionalAxes: [],
      series: [series])
  }
}
