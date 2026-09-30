import SwiftUI
import SwiftData
import Charts
import ForgeCore
import UIKit

/// One lift's detail: trend graph on the field, the next planned session, stats and recent workouts.
struct LiftDetailView: View {
  let exercise: Exercise
  let data: ProgressData
  let usesLb: Bool
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  @State private var range: TrendRange = .all
  @State private var selected: Date?   // date of the scrubbed workout
  @State private var approvingIncrease: VolumeIncrease?

  private var coachName: String { Coach.from(coachID).name }

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

  /// The injury flag that parks this lift, if any (PlanAuditView's held test).
  private var heldFlag: InjuryFlag? {
    let flags = Set((profiles.first?.injuryFlags ?? []).compactMap(InjuryFlag.init(rawValue:)))
    guard !flags.isEmpty else { return nil }
    return flags.first { Substitution.replacement(for: exercise.id, flags: [$0]) != nil }
  }

  /// Everything the "Next time" section and the chart's target read from the next
  /// planned session that trains this lift.
  private struct NextTime {
    /// Plan day date, for the chart ring; nil without an accepted plan.
    let date: Date?
    /// "Wed, Sep 30" when a plan owns the day; nil when no date may be invented.
    let dateText: String?
    let dayName: String
    let isToday: Bool
    let planned: PlannedExercise?
    let loadKg: Double?
    let repRange: ClosedRange<Int>?
  }

  /// The earliest still-remaining session that trains this lift: the accepted plan's day
  /// (or the substitute's day for a held lift), else the program day at nextDayIndex.
  private var nextTime: NextTime? {
    guard let profile = profiles.first else { return nil }
    if let plan = profile.weekPlan {
      let liftID =
        heldFlag.flatMap { Substitution.replacement(for: exercise.id, flags: [$0]) }
        ?? exercise.id
      let rows = plan.evaluation(now: .now).days
        .filter { $0.state == .remaining }
        .sorted { $0.date < $1.date }
      guard
        let row = rows.first(where: { row in
          plan.days.first { $0.id == row.dayID }?.exerciseIDs.contains(liftID) ?? false
        }),
        let day = plan.days.first(where: { $0.id == row.dayID })
      else { return nil }
      var planned: PlannedExercise? = nil
      if !RoutineAdaptationService.needsReview(day, profile: profile, sessions: sessions) {
        let resolved = RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: sessions)
          ?? RoutineAdaptationService.generatedDay(day, profile: profile, sessions: sessions)
        planned = resolved?.exercises.first { $0.exercise.id == liftID }
      }
      return NextTime(
        date: row.date,
        dateText: row.date.formatted(
          .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale)),
        dayName: localizedDayName(day.sessionName),
        isToday: plan.resolvedCalendar().isDate(row.date, inSameDayAs: .now),
        planned: planned,
        loadKg: planned.map {
          resolvedLoadSuggestion(for: $0, sessions: sessions, profile: profile)
            ?? StrengthV3.suggestedKg($0, sessions: sessions, profile: profile)
        },
        repRange: planned?.repRange)
    }
    guard profile.weekPlan == nil,
      !RoutineAdaptationService.weekPlanUnreadable(profile)
    else { return nil }
    // `Program.week` swaps a held lift for its substitute, so look it up by that id.
    let liftID =
      heldFlag.flatMap { Substitution.replacement(for: exercise.id, flags: [$0]) }
      ?? exercise.id
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    guard !days.isEmpty else { return nil }
    let start = profile.nextDayIndex % days.count
    var match: (dayIndex: Int, planned: PlannedExercise)?
    for offset in 0..<days.count {
      let index = (start + offset) % days.count
      if let entry = days[index].exercises.first(where: { $0.exercise.id == liftID }) {
        match = (index, entry)
        break
      }
    }
    guard let match else { return nil }
    let completedToday = sessions.contains {
      $0.completed && Calendar.current.isDateInToday($0.date)
    }
    return NextTime(
      date: nil,
      dateText: nil,
      dayName: localizedDayName(days[match.dayIndex].name),
      isToday: match.dayIndex == start
        && (heldFlag == nil ? todayPlanned != nil : !completedToday),
      planned: match.planned,
      loadKg: resolvedLoadSuggestion(for: match.planned, sessions: sessions, profile: profile)
        ?? StrengthV3.suggestedKg(match.planned, sessions: sessions, profile: profile),
      repRange: match.planned.repRange)
  }

  /// The big value line: the planned load, or for a held lift the last best set.
  private func nextValue(_ next: NextTime) -> String? {
    if heldFlag != nil, let trend {
      return "\(Fmt.num(display(trend.latest.weightKg), max: 2)) \(unit) × \(trend.latest.reps)"
    }
    guard let loadKg = next.loadKg, let reps = next.repRange?.lowerBound else { return nil }
    return "\(Fmt.num(display(loadKg), max: 2)) \(unit) × \(reps)"
  }

  /// First caption that applies under the value, in the board's priority order.
  private func nextCaption(_ next: NextTime) -> String? {
    if let heldFlag {
      return String(
        localized:
          "Same as last time. \(coachName) holds this lift while your \(heldFlag.name.lowercased(with: L10n.locale)) is flagged.",
        bundle: L10n.bundle)
    }
    guard let loadKg = next.loadKg, let repRange = next.repRange, let trend,
      let best = trend.workouts.map(\.e1rmKg).max()
    else { return nil }
    let reps = repRange.lowerBound
    let load = Fmt.num(display(loadKg), max: 2)
    let estimate = Strength.epley(weightKg: loadKg, reps: reps)
    if estimate - best >= 0.05 {
      return String(
        localized: "Would be a record by \(Fmt.num(display(estimate - best), max: 1)) \(unit).",
        bundle: L10n.bundle)
    }
    guard let planned = next.planned else { return nil }
    switch buildDecision(for: planned, sessions: sessions, profile: profiles.first).action {
    case .holdLoad, .addReps:
      var text = String(
        localized:
          "\(coachName) keeps \(load) \(unit) until every set reaches \(repRange.upperBound) reps.",
        bundle: L10n.bundle)
      if reps < repRange.upperBound {
        for r in (reps + 1)...repRange.upperBound {
          let gain = Strength.epley(weightKg: loadKg, reps: r) - best
          if gain >= 0.05 {
            text += " " + String(
              localized: "\(r) reps would be a record by \(Fmt.num(display(gain), max: 1)) \(unit).",
              bundle: L10n.bundle)
            break
          }
        }
      }
      return text
    default:
      return nil
    }
  }

  /// The dashed target line's value, ring date and label, when the range may draw them.
  private var chartTarget: (value: Double, date: Date, label: String)? {
    guard heldFlag == nil, let next = nextTime, let loadKg = next.loadKg,
      let reps = next.repRange?.lowerBound
    else { return nil }
    switch range {
    case .all: break
    case .block(let n): guard n == data.currentBlock else { return nil }
    }
    guard let date = next.date ?? trend?.latest.date.addingTimeInterval(
      7 / Double(max(profiles.first?.daysPerWeek ?? 1, 1)) * 86400)
    else { return nil }
    return (
      display(Strength.epley(weightKg: loadKg, reps: reps)),
      date,
      String(localized: "Next · \(Fmt.num(display(loadKg), max: 2)) × \(reps)", bundle: L10n.bundle)
    )
  }

  /// A record inside the current reporting week earns the token's gold ring.
  private var recordThisWeek: Bool {
    let week = TrainingMetrics.reportingWeek(
      containing: .now, calendar: TrainingMetrics.reportingCalendar())
    return events.contains { TrainingMetrics.contains(week, $0.date) }
  }

  /// The coach's un-answered volume increase for this lift, if one is pending.
  private var pendingIncrease: VolumeIncrease? {
    guard let profile = profiles.first else { return nil }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
      .first { $0.exercise.id == exercise.id && $0.answer == nil }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        field
        below
      }
    }
    .progressFieldPage(exercise.localizedName)
    .sheet(item: $approvingIncrease) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coachName,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
    .toolbar {
      ToolbarItem(placement: .principal) { Text("") }
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: shareText) {
          Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.text)
        }
        .accessibilityLabel("Share")
      }
    }
  }

  /// Header, latest estimated max, the hero trend graph and its legend on the peach field.
  private var field: some View {
    FieldSection(bottom: 16) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
          LiftToken(exercise: exercise, size: 56, record: recordThisWeek, onSky: true)
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
          trendChart
            .padding(.top, 8)
          Text("Estimated from your best set each session")
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
          chartLegend
            .padding(.top, 10)
          if shownBlocks.count >= 2 {
            rangePicker
              .padding(.top, 14)
          }
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

  /// The next planned session for this lift: when, what to lift, and why that number.
  @ViewBuilder private var nextStep: some View {
    if let next = nextTime {
      let value = nextValue(next)
      let caption = nextCaption(next)
      let right =
        next.dateText.map { "\($0) · \(next.dayName)" } ?? next.dayName
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "Next time", bundle: L10n.bundle))
              .forge(17, .semibold)
              .foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            Text(verbatim: right)
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
          if let value {
            Text(verbatim: value)
              .forge(22, .bold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
              .padding(.top, 4)
          }
          if let caption {
            Text(verbatim: caption)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
              .padding(.top, 2)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(
            verbatim: (
              [String(localized: "Next time", bundle: L10n.bundle), right]
                + [value, caption].compactMap { $0 }
            ).joined(separator: ", ")))
        .accessibilityIdentifier("lift.next")
        if next.isToday, value != nil {
          Button {
            NotificationCenter.default.post(name: .forgeStartWorkout, object: nil)
          } label: {
            Text(String(localized: "Start \(next.dayName)", bundle: L10n.bundle))
          }
          .buttonStyle(PillButtonStyle())
          .accessibilityIdentifier("lift.startToday")
          .padding(.top, 14)
        }
        pendingVolumeRow
      }
    }
  }

  /// The coach's pending volume change on this lift, waiting for the lifter's OK.
  @ViewBuilder private var pendingVolumeRow: some View {
    if let increase = pendingIncrease {
      let added = increase.toSets - increase.fromSets
      Button {
        approvingIncrease = increase
      } label: {
        HStack(spacing: 12) {
          CoachAvatar(size: 32)
          VStack(alignment: .leading, spacing: 2) {
            Text(
              String(
                localized:
                  "Add \(added) \(exercise.localizedName) set\(L10n.pluralSuffix(added)) to \(localizedDayName(increase.dayName))",
                bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
            Text(
              String(
                localized:
                  "\(increase.muscle.a11yName) \(increase.weeklyFrom) of \(increase.weeklyTo) sets · needs your OK",
                bundle: L10n.bundle))
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
          Spacer(minLength: 8)
          Image(systemName: "chevron.forward")
            .scaledSystemFont(13, weight: .semibold)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("lift.needsOK")
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
        let best = trend.workouts.max { $0.e1rmKg < $1.e1rmKg }
        if abs(change) < 0.5 {
          VStack(alignment: .trailing, spacing: 2) {
            Text("Holding").foregroundStyle(Theme.textSecondary)
            if let best, best.date != trend.latest.date {
              Text(
                String(
                  localized:
                    "Best \(Fmt.num(display(best.e1rmKg).rounded())) \(unit) in \(best.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale)))",
                  bundle: L10n.bundle))
                .forge(12, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            }
          }
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
    let target = selected == nil ? chartTarget : nil
    let latestE1RM = window.last.map { display($0.e1rmKg) } ?? 0
    let values = window.map { display($0.e1rmKg) }
    let baseLo = (((values.min() ?? 0) - 3) / 5).rounded(.down) * 5
    let baseHi = (((values.max() ?? 0) + Swift.max(4, ((values.max() ?? 0) - (values.min() ?? 0)) * 0.35)) / 5).rounded(.up) * 5
    let lo = target.map { Swift.min(baseLo, (($0.value - 3) / 5).rounded(.down) * 5) } ?? baseLo
    let hi = target.map { Swift.max(baseHi, $0.value + 3) } ?? baseHi
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
      if let target {
        RuleMark(y: .value("Next target", target.value))
          .foregroundStyle(Theme.accent)
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        PointMark(x: .value("Next", target.date), y: .value("Next target", target.value))
          .symbol {
            Circle()
              .fill(Theme.page)
              .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
              .frame(width: 10, height: 10)
          }
          .annotation(position: target.value < latestE1RM ? .bottom : .top, spacing: 4) {
            Text(verbatim: target.label)
              .forge(12, .semibold)
              .foregroundStyle(Theme.accentText)
              .monospacedDigit()
              .padding(.horizontal, 3)
              .background(Theme.field)
          }
          .accessibilityLabel(String(localized: "Next target", bundle: L10n.bundle))
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
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
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
    .onChange(of: selected) { _, new in
      guard let new, let workout = window.first(where: { $0.date == new }) else { return }
      let label = new.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
      AccessibilityNotification.Announcement(
        "\(label), \(accessibilityValue(for: workout))"
      ).post()
    }
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

  /// Chart key row: only the marks the current window actually shows.
  private var chartLegend: some View {
    HStack(spacing: 14) {
      if window.contains(where: \.isRecord) {
        HStack(spacing: 5) {
          Circle().fill(Theme.recordRing).frame(width: 8, height: 8)
          Text("Record").forge(12, .regular).foregroundStyle(Theme.textSecondary)
        }
      }
      if window.contains(where: isDeload) {
        HStack(spacing: 5) {
          Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5).frame(width: 8, height: 8)
          Text("Deload").forge(12, .regular).foregroundStyle(Theme.textSecondary)
        }
      }
      if chartTarget != nil {
        HStack(spacing: 5) {
          Path { line in
            line.move(to: CGPoint(x: 0, y: 1))
            line.addLine(to: CGPoint(x: 14, y: 1))
          }
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
          .frame(width: 14, height: 2)
          Text(String(localized: "Next target", bundle: L10n.bundle))
            .forge(12, .regular)
            .foregroundStyle(Theme.textSecondary)
        }
      }
    }
    .accessibilityHidden(true)
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
              unit: "\(unit) × \(heaviest.reps)",
              caption: heaviest.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)),
              isFirst: true)
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
            label: String(localized: "Records", bundle: L10n.bundle),
            value: "\(events.count)",
            caption: events.last.map {
              String(
                localized: "last \($0.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
                bundle: L10n.bundle)
            } ?? String(localized: "None yet", bundle: L10n.bundle))
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

  /// Value and its unit as one line of text, so it scales down instead of wrapping.
  private func statValueLine(_ value: String, unit: String?) -> Text {
    let line = Text(value).forge(22, .bold).foregroundStyle(Theme.text).monospacedDigit()
    guard let unit else { return line }
    return line + Text(" \(unit)").forge(13, .regular).foregroundStyle(Theme.textSecondary)
  }

  private func statCell(
    label: String, value: String, unit cellUnit: String? = nil, caption: String, isFirst: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).forge(13, .regular).foregroundStyle(Theme.textSecondary).lineLimit(1)
      statValueLine(value, unit: cellUnit).lineLimit(1).minimumScaleFactor(0.6)
      Text(caption).forge(13, .regular).foregroundStyle(Theme.textSecondary).lineLimit(1)
    }
    .padding(.leading, isFirst ? 0 : 16)
    .padding(.trailing, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Recent workouts with the record summary line merged in, a hairline list on white.
  @ViewBuilder private var recentSection: some View {
    let all = trend?.workouts ?? []
    if !all.isEmpty {
      let recent = Array(all.suffix(4).reversed())
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text("Recent").forge(20, .bold).foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Text(String(localized: "Est. max", bundle: L10n.bundle))
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
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
                Text(String(localized: "Workout history", bundle: L10n.bundle))
                  .forge(15, .semibold)
                  .foregroundStyle(Theme.accentText)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                  .scaledSystemFont(14, weight: .semibold)
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
    let n = sets ?? 0
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          verbatim: "\(Fmt.num(display(workout.weightKg), max: 2)) \(unit) × \(workout.reps)"
        )
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
        Text(
          deload
            ? String(localized: "Deload week", bundle: L10n.bundle)
            : String(localized: "\(day) · \(n) set\(L10n.pluralSuffix(n))", bundle: L10n.bundle))
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
              .scaledSystemFont(12, weight: .semibold)
            Text("Record").forge(13, .semibold)
          }
          .foregroundStyle(Theme.recordInk)
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
