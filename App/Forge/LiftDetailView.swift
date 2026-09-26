import SwiftUI
import SwiftData
import Charts
import ForgeCore
import UIKit

/// One lift's detail: hero on the sky, estimated-max trend card, records.
struct LiftDetailView: View {
  let exercise: Exercise
  let data: ProgressData
  let usesLb: Bool
  @Query private var profiles: [UserProfile]

  @State private var range: TrendRange = .all
  @State private var selected: Date?   // date of the scrubbed workout

  /// Per-exercise kg/lb override beats the profile-wide default.
  private var isLb: Bool {
    profiles.first?.isLb(for: exercise.id) ?? usesLb
  }

  private var trend: LiftTrend? { data.trend(for: exercise.id) }
  private var events: [ProgressData.Record] { data.recordEvents(for: exercise.id) }

  private var series: [E1RMPoint] { data.e1rmSeries(for: exercise.id) }
  private var record: ProgressData.Record? { data.bestSet(for: exercise.id) }
  private var next: ProgressData.NextTarget? { data.nextTarget(for: exercise) }
  private var recent: Bool {
    record.map { $0.date >= Date.now.addingTimeInterval(-30 * 86400) } ?? false
  }

  private var unit: String { isLb ? "lb" : "kg" }

  /// e1RM series converted to display units.
  private var points: [(date: Date, value: Double)] {
    series.map { (date: $0.date, value: isLb ? Plates.kgToLb($0.e1rm) : $0.e1rm) }
  }

  private var shareText: String {
    let name = exercise.localizedName
    if points.count >= 2, let first = points.first, let last = points.last {
      let delta = last.value - first.value
      let signedDelta = "\(delta >= 0 ? "+" : "−")\(Fmt.num(abs(delta).rounded()))"
      let month = first.date.formatted(.dateTime.month(.wide).locale(L10n.locale))
      return String(
        localized:
          "\(name): estimated max \(Fmt.num(last.value.rounded())) \(unit) · \(signedDelta) \(unit) since \(month) — Regulift",
        bundle: L10n.bundle)
    }
    let value = points.last.map { Fmt.num($0.value.rounded()) }
      ?? record.map { Fmt.num(display($0.e1rm).rounded()) } ?? ""
    return String(
      localized: "\(name): estimated max \(value) \(unit) — Regulift",
      bundle: L10n.bundle)
  }

  private func display(_ kg: Double) -> Double {
    isLb ? Plates.kgToLb(kg) : kg
  }

  private func recordPillText(for record: ProgressData.Record) -> String {
    if Calendar.current.isDateInToday(record.date) {
      return String(localized: "Record today", bundle: L10n.bundle)
    }
    return String(
      localized: "Record \(record.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  private func repRangeText(_ range: ClosedRange<Int>) -> String {
    range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        hero
        strengthCard
        recordsCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationTitle(exercise.localizedName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) { Text("") }
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
          .accessibilityLabel("Share")
      }
    }
  }

  private var hero: some View {
    VStack(spacing: 12) {
      LiftToken(exercise: exercise, size: 148, record: recent, onSky: true)
      Text(exercise.localizedName)
        .forge(34, .bold)
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 8) {
        SkyPill(exercise.primary.a11yName, style: .neutral)
        if recent, let record {
          SkyPill(recordPillText(for: record), symbol: "trophy.fill", style: .gold)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var strengthCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        if let trend {
          Text("Estimated max").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Fmt.num(display(trend.latest.e1rmKg).rounded()))
              .forge(56, .bold)
              .foregroundStyle(Theme.accent)
              .monospacedDigit()
              .lineLimit(1)
              .fixedSize()
            Text(unit)
              .forge(22, .semibold)
              .foregroundStyle(Theme.textSecondary)
              .lineLimit(1)
              .fixedSize()
            Spacer(minLength: 8)
            changeText
              .multilineTextAlignment(.trailing)
              .lineLimit(2)
          }
          if shownBlocks.count >= 2 {
            rangePicker
          }
          trendChart
        } else {
          Text("No eligible sets for this lift yet.").forgeBody()
        }
        Text("Estimated from your best set each session").forge(13, .regular).foregroundStyle(Theme.textTertiary)
      }
    } footer: {
      if let next {
        HStack(spacing: 12) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Next: \(Fmt.num(display(next.weightKg))) \(unit) × \(repRangeText(next.repRange))")
              .forge(17, .semibold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
            Text(next.dayName).forge(15, .regular).foregroundStyle(Theme.textSecondary)
          }
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.todayFooter)
      }
    }
  }

  /// Blocks that appear in the trend, newest two; the picker shows itself only from two up.
  private var shownBlocks: [Int] {
    guard let trend else { return [] }
    return Array(Set(trend.workouts.map(\.block)).sorted().suffix(2))
  }

  private var rangePicker: some View {
    Picker("Range", selection: $range) {
      ForEach(shownBlocks, id: \.self) { n in
        Text(String(localized: "Block \(n)", bundle: L10n.bundle)).tag(TrendRange.block(n))
      }
      Text("All").tag(TrendRange.all)
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("lift.range")
    .onChange(of: range) { _, _ in selected = nil }
  }

  @ViewBuilder private var changeText: some View {
    if let trend, let change = trend.changeKg(in: range) {
      Group {
        if abs(change) < 0.5 {
          Text("Holding").foregroundStyle(Theme.textSecondary)
        } else {
          let sign = change >= 0 ? "+" : "\u{2212}"
          let value = Fmt.num(abs(display(change)).rounded())
          switch range {
          case .all:
            let month = trend.workouts(in: range).first!.date
              .formatted(.dateTime.month(.abbreviated).locale(L10n.locale))
            Text(
              String(localized: "\(sign)\(value) \(unit) since \(month)", bundle: L10n.bundle)
            )
            .foregroundStyle(change >= 0.5 ? Theme.positiveText : Theme.textSecondary)
          case .block(let n):
            Text(
              String(localized: "\(sign)\(value) \(unit) in Block \(n)", bundle: L10n.bundle)
            )
            .foregroundStyle(change >= 0.5 ? Theme.positiveText : Theme.textSecondary)
          }
        }
      }
      .forge(17, .semibold)
      .monospacedDigit()
    }
  }

  private var window: [LiftWorkout] {
    trend?.workouts(in: range) ?? []
  }

  /// Under two months of history, month-only axis labels would repeat ("Sep Sep Sep").
  private var shortHistory: Bool {
    guard let first = window.first?.date, let last = window.last?.date else { return true }
    return last.timeIntervalSince(first) < 60 * 86400
  }

  private func isMuted(_ workout: LiftWorkout) -> Bool {
    guard case .all = range else { return false }
    return workout.block < data.currentBlock
  }

  /// First workout of each block inside the window, oldest first.
  private var blockStarts: [(block: Int, date: Date)] {
    var seen = Set<Int>()
    return window.filter { seen.insert($0.block).inserted }
      .map { (block: $0.block, date: $0.date) }
  }

  private var trendChart: some View {
    let values = window.map { display($0.e1rmKg) }
    let lo = ((values.min()! - 3) / 5).rounded(.down) * 5
    let hi = ((values.max()! + Swift.max(4, (values.max()! - values.min()!) * 0.35)) / 5).rounded(.up) * 5
    let muted = window.contains { isMuted($0) }
    return Chart {
      if window.count > 1 {
        if muted {
          ForEach(window) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "all"))
              .foregroundStyle(Theme.accent.opacity(0.35))
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
          ForEach(window.filter { !isMuted($0) }) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "current"))
              .foregroundStyle(Theme.accent)
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
        } else {
          ForEach(window) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "all"))
              .foregroundStyle(Theme.accent)
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
        }
      }
      if let selected, let selectedWorkout = window.first(where: { $0.date == selected }) {
        RuleMark(x: .value("Selected", selected))
          .foregroundStyle(Theme.textTertiary)
          .lineStyle(StrokeStyle(lineWidth: 1.5))
          .zIndex(-1)
          .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
            popup(for: selectedWorkout)
          }
      }
      if blockStarts.count >= 2 {
        ForEach(Array(blockStarts.enumerated()), id: \.element.block) { i, start in
          RuleMark(x: .value("Block", start.date))
            .foregroundStyle(i == 0 ? .clear : Theme.ring)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, alignment: .leading, spacing: 4) {
              Text(String(localized: "Block \(start.block)", bundle: L10n.bundle))
                .forge(12, .medium)
                .foregroundStyle(Theme.textSecondary)
                .opacity(selected == nil ? 1 : 0)
            }
        }
      }
      ForEach(window) { workout in
        PointMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)))
          .symbol { dotSymbol(for: workout) }
          .accessibilityLabel(
            workout.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
          .accessibilityValue(accessibilityValue(for: workout))
      }
    }
    .chartYScale(domain: lo...hi)
    .chartXScale(range: .plotDimension(padding: 10))
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
        AxisGridLine().foregroundStyle(Theme.track)
        AxisValueLabel().font(.forge(13, .regular)).foregroundStyle(Theme.textTertiary)
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) {
        AxisGridLine().foregroundStyle(Theme.track)
        AxisValueLabel(
          format: shortHistory
            ? .dateTime.day().month(.abbreviated).locale(L10n.locale)
            : .dateTime.month(.abbreviated).locale(L10n.locale)
        )
        .font(.forge(13, .regular))
        .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(height: 190)
    .padding(.top, 18)
    .accessibilityIdentifier("lift.chart")
    .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
    .chartOverlay { proxy in
      GeometryReader { geo in
        ChartScrubRecognizer { x in
          guard let x, let plotFrame = proxy.plotFrame else {
            selected = nil
            return
          }
          if let date: Date = proxy.value(atX: x - geo[plotFrame].origin.x) {
            selected = window.min(by: {
              abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            })?.date
          }
        }
        .accessibilityHidden(true)
      }
    }
  }

  private func dotSymbol(for workout: LiftWorkout) -> some View {
    let isSelected = selected == workout.date
    let fill: CGFloat = isSelected ? 13 : (workout.isRecord ? 11 : 8)
    let ring: CGFloat = isSelected ? 19 : (workout.isRecord ? 15 : 11)
    return ZStack {
      Circle().fill(Theme.card)
      Circle().fill(workout.isRecord ? Theme.recordRing : Theme.accent)
        .padding((ring - fill) / 2)
    }
    .frame(width: ring, height: ring)
    .opacity(!isSelected && isMuted(workout) ? 0.45 : 1)
  }

  private func accessibilityValue(for workout: LiftWorkout) -> String {
    var text =
      "\(Fmt.num(display(workout.e1rmKg).rounded())) \(unit), "
      + "\(Fmt.num(display(workout.weightKg), max: 2)) \(unit) × \(workout.reps)"
    if workout.isRecord {
      text += ", " + String(localized: "record", bundle: L10n.bundle)
    }
    return text
  }

  private func popup(for workout: LiftWorkout) -> some View {
    VStack(spacing: 2) {
      HStack(spacing: 4) {
        Text(workout.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
        if workout.isRecord {
          Text(verbatim: "·").foregroundStyle(Theme.textSecondary)
          Text("Record").forge(13, .semibold).foregroundStyle(Theme.recordInk)
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(Fmt.num(display(workout.e1rmKg).rounded()))
          .forge(20, .bold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
        Text(unit).forge(14, .semibold).foregroundStyle(Theme.textSecondary)
      }
      Text(verbatim: "\(Fmt.num(display(workout.weightKg), max: 2)) \(unit) × \(workout.reps)")
        .forge(13, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .strokeBorder(Theme.ring, lineWidth: 1))
    .accessibilityIdentifier("lift.chart.popup")
  }

  private var recordsCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Records").forge(17, .semibold).foregroundStyle(Theme.text)
          Spacer()
          if !events.isEmpty, let trend {
            let monthWide = trend.first.date.formatted(.dateTime.month(.wide).locale(L10n.locale))
            Text(String(localized: "\(events.count) since \(monthWide)", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.recordInk)
              .monospacedDigit()
          }
        }
        if let trend, !events.isEmpty, let newest = events.last {
          RecordStaircase(
            start: .init(date: trend.first.date, e1rmKg: trend.first.e1rmKg),
            records: events.map { .init(date: $0.date, e1rmKg: $0.e1rm) },
            endDate: trend.latest.date,
            isLb: isLb)
          Text(
            String(
              localized: "Newest · \(newestSetText(newest)) · \(newestDayText(newest))",
              bundle: L10n.bundle)
          )
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        } else {
          Text("Beat a lift's best and it lands here.").forgeLabel()
        }
      }
    }
    .accessibilityIdentifier("lift.records")
  }

  private func newestSetText(_ newest: ProgressData.Record) -> String {
    "\(Fmt.num(display(newest.weightKg), max: 2)) \(unit) × \(newest.reps)"
  }

  private func newestDayText(_ newest: ProgressData.Record) -> String {
    newest.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
  }
}

/// Press-and-hold scrubbing that leaves the page scrollable: moving before 0.15 s scrolls the page.
private struct ChartScrubRecognizer: UIViewRepresentable {
  let onChange: (CGFloat?) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    let press = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handle(_:)))
    press.minimumPressDuration = 0.15
    press.allowableMovement = 10
    view.addGestureRecognizer(press)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.onChange = onChange
  }

  func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

  @MainActor final class Coordinator: NSObject {
    var onChange: (CGFloat?) -> Void
    init(onChange: @escaping (CGFloat?) -> Void) { self.onChange = onChange }

    @objc func handle(_ press: UILongPressGestureRecognizer) {
      switch press.state {
      case .began, .changed: onChange(press.location(in: press.view).x)
      default: onChange(nil)
      }
    }
  }
}
