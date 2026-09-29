import SwiftUI
import SwiftData
import Charts
import ForgeCore
import UIKit

/// One lift's detail: trend graph on the field, today's target, stats and recent workouts.
struct LiftDetailView: View {
  let exercise: Exercise
  let data: ProgressData
  let usesLb: Bool
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

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
  private var deloads: Set<Date> { StrengthV3.deloadDates(sessions: sessions) }

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

  /// The lift's slot in the day Today is offering, with its suggested load.
  private var todayPlanned: (day: PlannedDay, planned: PlannedExercise)? {
    StrengthV3.todayPlanned(exercise: exercise, sessions: sessions, profile: profiles.first)
  }

  private var todayWeightKg: Double? {
    todayPlanned.map { StrengthV3.suggestedKg($0.planned, sessions: sessions, profile: profiles.first) }
  }

  /// Today's planned single-set e1RM in display units, drawn as the target line on the hero chart.
  private var todayTargetDisplay: Double? {
    guard let planned = todayPlanned, let weightKg = todayWeightKg else { return nil }
    return display(Strength.epley(weightKg: weightKg, reps: planned.planned.repRange.lowerBound))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        field
        below
      }
    }
    .progressFieldPage(exercise.localizedName)
    .toolbar {
      ToolbarItem(placement: .principal) { Text("") }
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
          .accessibilityLabel("Share")
      }
    }
  }

  /// Header, latest estimated max, range picker and the hero trend graph on the peach field.
  private var field: some View {
    FieldSection(bottom: 16) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
          LiftToken(exercise: exercise, size: 48, record: record != nil, onSky: true)
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.localizedName)
              .forge(28, .bold)
              .tracking(-0.5)
              .foregroundStyle(Theme.text)
              .lineLimit(2)
              .accessibilityAddTraits(.isHeader)
            Text("\(exercise.primary.a11yName) · \(exercise.equipment.name)")
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        .padding(.top, 4)
        if let trend {
          VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(Fmt.num(display(trend.latest.e1rmKg).rounded()))
                .forge(48, .bold)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .lineLimit(1)
              Text(unit)
                .forge(22, .semibold)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
              Spacer(minLength: 8)
              changeText
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            }
            Text("estimated max")
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
          .padding(.top, 16)
          if shownBlocks.count >= 2 {
            rangePicker
              .padding(.top, 14)
          }
          trendChart
            .padding(.top, 8)
          Text("Estimated from your best set each session")
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
        } else {
          Text("No eligible sets for this lift yet.").forgeBody()
            .padding(.top, 16)
        }
      }
    }
  }

  /// Everything under the field, directly on white.
  private var below: some View {
    VStack(alignment: .leading, spacing: 0) {
      nextStep
        .padding(.top, 24)
      statsSection
        .padding(.top, 24)
      recentSection
        .padding(.top, 24)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 32)
    .background(Theme.page)
  }

  /// Today's single next step for this lift, replacing the old coach card.
  @ViewBuilder private var nextStep: some View {
    if let planned = todayPlanned, let weightKg = todayWeightKg {
      let dayName = localizedDayName(planned.day.name)
      let estimateKg = Strength.epley(weightKg: weightKg, reps: planned.planned.repRange.lowerBound)
      let bestKg = trend.map { $0.workouts.map(\.e1rmKg).max() } ?? nil
      let gainKg = bestKg.map { estimateKg - $0 }
      VStack(alignment: .leading, spacing: 0) {
        if let gainKg, gainKg >= 0.5 {
          Text(String(
            localized: "A new record by \(Fmt.num(display(gainKg).rounded())) \(unit)", bundle: L10n.bundle))
            .forge(20, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
        } else {
          Text("Today's target")
            .forge(20, .semibold)
            .foregroundStyle(Theme.text)
        }
        Text(String(
          localized: "Today in \(dayName): \(Fmt.num(display(weightKg), max: 2)) \(unit) × \(planned.planned.repRange.lowerBound)",
          bundle: L10n.bundle))
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .padding(.top, 4)
        Button {
          NotificationCenter.default.post(name: .forgeStartWorkout, object: nil)
        } label: {
          Text(String(localized: "Start \(dayName)", bundle: L10n.bundle))
            .forge(17, .semibold)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(Theme.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityIdentifier("lift.startToday")
        .padding(.top, 14)
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

  private func isDeload(_ workout: LiftWorkout) -> Bool {
    deloads.contains(workout.date)
  }

  /// First workout of each block inside the window, oldest first.
  private var blockStarts: [(block: Int, date: Date)] {
    var seen = Set<Int>()
    return window.filter { seen.insert($0.block).inserted }
      .map { (block: $0.block, date: $0.date) }
  }

  private var trendChart: some View {
    let plotted = window.filter { !isDeload($0) }
    let values = window.map { display($0.e1rmKg) }
    let baseLo = (((values.min() ?? 0) - 3) / 5).rounded(.down) * 5
    let baseHi = (((values.max() ?? 0) + Swift.max(4, ((values.max() ?? 0) - (values.min() ?? 0)) * 0.35)) / 5).rounded(.up) * 5
    let lo = todayTargetDisplay.map { Swift.min(baseLo, (($0 - 3) / 5).rounded(.down) * 5) } ?? baseLo
    let hi = todayTargetDisplay.map { Swift.max(baseHi, $0 + 3) } ?? baseHi
    let muted = window.contains { isMuted($0) }
    return Chart {
      if plotted.count > 1 {
        if muted {
          ForEach(plotted) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "all"))
              .foregroundStyle(Theme.accent.opacity(0.35))
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
          ForEach(plotted.filter { !isMuted($0) }) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "current"))
              .foregroundStyle(Theme.accent)
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
        } else {
          ForEach(plotted) { workout in
            LineMark(x: .value("Date", workout.date), y: .value("Estimated max", display(workout.e1rmKg)), series: .value("Series", "all"))
              .foregroundStyle(Theme.accent)
              .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.linear)
          }
        }
      }
      if let target = todayTargetDisplay, selected == nil {
        RuleMark(y: .value("Today's target", target))
          .foregroundStyle(Theme.accent)
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
          .annotation(position: .top, alignment: .trailing, spacing: 4) {
            Text(String(
              localized: "Today's target \(Fmt.num(target.rounded())) \(unit)", bundle: L10n.bundle))
              .forge(12, .semibold)
              .foregroundStyle(Theme.accentText)
              .monospacedDigit()
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
          .annotation(position: .bottom, spacing: 4) {
            if isDeload(workout), selected == nil {
              Text("Deload").forge(12, .regular).foregroundStyle(Theme.textSecondary)
            }
          }
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
            : .dateTime.month(.abbreviated).locale(L10n.locale),
          collisionResolution: .greedy
        )
        .font(.forge(13, .regular))
        .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(height: 240)
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
    if isDeload(workout) {
      return AnyView(
        Circle()
          .fill(Theme.card)
          .overlay(Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5))
          .frame(width: 9, height: 9)
          .opacity(0.7)
      )
    }
    let isSelected = selected == workout.date
    let fill: CGFloat = isSelected ? 13 : (workout.isRecord ? 11 : 8)
    let ring: CGFloat = isSelected ? 19 : (workout.isRecord ? 15 : 11)
    return AnyView(
      ZStack {
        Circle().fill(Theme.card)
        Circle().fill(workout.isRecord ? Theme.recordRing : Theme.accent)
          .padding((ring - fill) / 2)
      }
      .frame(width: ring, height: ring)
      .opacity(!isSelected && isMuted(workout) ? 0.45 : 1)
    )
  }

  private func accessibilityValue(for workout: LiftWorkout) -> String {
    var text =
      "\(Fmt.num(display(workout.e1rmKg).rounded())) \(unit), "
      + "\(Fmt.num(display(workout.weightKg), max: 2)) \(unit) × \(workout.reps)"
    if workout.isRecord {
      text += ", " + String(localized: "record", bundle: L10n.bundle)
    }
    if isDeload(workout) {
      text += ", " + String(localized: "deload week", bundle: L10n.bundle)
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

  /// Same three stat cells as before, now as a hairline-framed strip on white.
  @ViewBuilder private var statsSection: some View {
    if let trend {
      VStack(spacing: 0) {
        rowDivider
        HStack(spacing: 0) {
          if let heaviest = StrengthV3.heaviestSet(exerciseID: exercise.id, sessions: sessions) {
            statCell(
              label: String(localized: "Heaviest set", bundle: L10n.bundle),
              value: Fmt.num(display(heaviest.weightKg), max: 2),
              unit: unit,
              caption: heaviest.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
          }
          statDivider
          statCell(
            label: String(localized: "Workouts", bundle: L10n.bundle),
            value: "\(trend.workouts.count)",
            caption: String(
              localized: "since \(trend.first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
              bundle: L10n.bundle))
          statDivider
          statCell(
            label: String(localized: "Sets a week", bundle: L10n.bundle),
            value: "\(setsInLatestWeek)",
            caption: String(localized: "in Block \(trend.latest.block)", bundle: L10n.bundle))
        }
        .frame(minHeight: 76)
        rowDivider
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("lift.stats")
    }
  }

  private var statDivider: some View {
    Rectangle().fill(Theme.ring).frame(width: 1)
      .padding(.vertical, 14)
  }

  private func statCell(label: String, value: String, unit cellUnit: String? = nil, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).forge(13, .regular).foregroundStyle(Theme.textSecondary).lineLimit(1)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(value).forge(22, .bold).foregroundStyle(Theme.text).monospacedDigit()
        if let cellUnit {
          Text(cellUnit).forge(13, .regular).foregroundStyle(Theme.textSecondary)
        }
      }
      Text(caption).forge(13, .regular).foregroundStyle(Theme.textSecondary).lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.leading, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Sets of this lift in the trailing 7 days ending at its latest workout.
  private var setsInLatestWeek: Int {
    guard let latest = trend?.latest else { return 0 }
    let start = latest.date.addingTimeInterval(-7 * 86400)
    return sessions
      .filter { $0.completed && $0.date > start && $0.date <= latest.date }
      .reduce(0) { $0 + $1.sets.filter { $0.exerciseID == exercise.id }.count }
  }

  /// Recent workouts with the record summary line merged in, a hairline list on white.
  @ViewBuilder private var recentSection: some View {
    let all = trend?.workouts ?? []
    if !all.isEmpty {
      let recent = Array(all.suffix(4).reversed())
      let since = all.first?.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale))
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text("Recent").forge(20, .bold).foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          if let since {
            Text(String(localized: "\(all.count) since \(since)", bundle: L10n.bundle))
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
        }
        if !events.isEmpty, let trend, let newest = events.last {
          Text(String(
            localized: "\(events.count) records since \(trend.first.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale))) · newest \(newestSetText(newest)) · \(newestDayText(newest))",
            bundle: L10n.bundle))
            .forge(15, .regular)
            .foregroundStyle(Theme.recordInk)
            .monospacedDigit()
            .padding(.top, 4)
        }
        VStack(spacing: 0) {
          ForEach(Array(recent.enumerated()), id: \.element.id) { i, workout in
            if i > 0 { rowDivider }
            workoutRow(workout)
          }
          if all.count > recent.count {
            rowDivider
            NavigationLink {
              HistoryView(usesLb: usesLb)
            } label: {
              HStack(spacing: 8) {
                Text(String(localized: "All \(all.count) workouts", bundle: L10n.bundle))
                  .forge(15, .semibold)
                  .foregroundStyle(Theme.accentText)
                  .monospacedDigit()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Theme.accentText)
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("lift.allWorkouts")
          }
        }
        .padding(.top, 12)
      }
      .accessibilityIdentifier("lift.records")
    }
  }

  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1)
  }

  private func workoutRow(_ workout: LiftWorkout) -> some View {
    let deload = isDeload(workout)
    let day = workout.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let sets = setCounts[workout.date]
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          verbatim: "\(Fmt.num(display(workout.weightKg), max: 2)) \(unit) × \(workout.reps)"
        )
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
        Text(deload ? String(localized: "Deload week", bundle: L10n.bundle) : "\(day) · \(sets ?? 0) sets")
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(Fmt.num(display(workout.e1rmKg).rounded()))
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          Text(unit).forge(13, .regular).foregroundStyle(Theme.textSecondary)
        }
        if workout.isRecord {
          HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
              .font(.system(size: 12, weight: .semibold))
            Text("Record").forge(13, .semibold)
          }
          .foregroundStyle(Theme.recordInk)
        } else {
          Text("est. max").forge(13, .regular).foregroundStyle(Theme.textSecondary)
        }
      }
    }
    .padding(.vertical, 10)
    .frame(minHeight: 60)
    .accessibilityElement(children: .combine)
    .accessibilityValue(accessibilityValue(for: workout))
  }

  /// Sets of this lift per session date, for the workout rows.
  private var setCounts: [Date: Int] {
    var counts: [Date: Int] = [:]
    for session in sessions where session.completed {
      let n = session.sets.filter { $0.exerciseID == exercise.id }.count
      if n > 0 { counts[session.date] = n }
    }
    return counts
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
