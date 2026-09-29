import ForgeCore
import Foundation
import SwiftUI

/// Shared derivations and small parts for the training log v3 screens: History, session
/// detail, Training blocks and the PR board. Data helpers live here so every screen reads
/// the same block walk and the same record walk.
enum LogV3 {
  // MARK: - blocks

  /// One program week of one block. `week` is the session-count program week the app
  /// assigns on start (`profile.currentWeek`), NOT a calendar week — planned and missed
  /// arithmetic therefore runs on calendar weeks (`weekColumns`), never on these.
  struct WeekGroup {
    let week: Int
    /// Newest first, for display.
    let sessions: [WorkoutSession]
    let firstDate: Date
    let lastDate: Date
    /// Template days no session of the week claims by name. Empty when undecidable.
    let missedDays: [PlannedDay]
    let isCurrentWeek: Bool
  }

  struct BlockGroup: Identifiable {
    let number: Int
    /// Ascending by week number.
    let weeks: [WeekGroup]
    let isCurrent: Bool
    var id: Int { number }

    var sessions: [WorkoutSession] {
      weeks.flatMap(\.sessions).sorted { $0.date < $1.date }
    }
    var firstDate: Date? { sessions.first?.date }
    var lastDate: Date? { sessions.last?.date }
    var maxWeek: Int { weeks.map(\.week).max() ?? 0 }
  }

  /// Blocks by the week-reset walk ProgressData uses: a program week number that drops
  /// starts a new block.
  static func blocks(sessions: [WorkoutSession], profile: UserProfile?) -> [BlockGroup] {
    let completed = sessions
      .filter { $0.completed && !$0.tombstoned }
      .sorted { $0.date < $1.date }
    guard !completed.isEmpty else { return [] }

    var numbers: [ObjectIdentifier: Int] = [:]
    var block = 0
    var previousWeek = Int.max
    for session in completed {
      if session.week < previousWeek { block += 1 }
      numbers[ObjectIdentifier(session)] = block
      previousWeek = session.week
    }

    let currentWeek = profile?.currentWeek(sessions: sessions)
    let hasPlan = (profile?.daysPerWeek ?? 0) > 0

    var out: [BlockGroup] = []
    for n in 1...block {
      let inBlock = completed.filter { numbers[ObjectIdentifier($0)] == n }
      guard !inBlock.isEmpty else { continue }
      let isCurrent = n == block
      let byWeek = Dictionary(grouping: inBlock, by: \.week)
      var weeks: [WeekGroup] = []
      for week in byWeek.keys.sorted() {
        guard let weekSessions = byWeek[week]?.sorted(by: { $0.date < $1.date }),
          let firstDate = weekSessions.first?.date
        else { continue }
        let past = isCurrent ? week < (currentWeek ?? week) : true
        var missed: [PlannedDay] = []
        if past, hasPlan, let profile {
          missed = unmatchedDays(
            template: template(week: week, profile: profile, sessions: sessions),
            sessions: weekSessions)
        }
        weeks.append(
          WeekGroup(
            week: week,
            sessions: weekSessions.reversed(),
            firstDate: firstDate,
            lastDate: weekSessions.last?.date ?? firstDate,
            missedDays: missed,
            isCurrentWeek: isCurrent && week == (currentWeek ?? week)))
      }
      out.append(
        BlockGroup(number: n, weeks: weeks, isCurrent: isCurrent))
    }
    return out
  }

  /// The week's own template, generated the same way Today and the roadmap generate it.
  private static func template(week: Int, profile: UserProfile, sessions: [WorkoutSession])
    -> [PlannedDay]
  {
    Program.week(
      week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
  }

  /// Template days no session of the week claims by day name. When a session matches no
  /// template day the split has changed since that week and nothing is claimed — an
  /// unmatched session is a fact, an unmatched guess is not.
  private static func unmatchedDays(template: [PlannedDay], sessions: [WorkoutSession])
    -> [PlannedDay]
  {
    guard !sessions.isEmpty else { return [] }
    var used: Set<ObjectIdentifier> = []
    var unmatched: [PlannedDay] = []
    for day in template {
      if let hit = sessions.first(where: {
        $0.dayName == day.name && !used.contains(ObjectIdentifier($0))
      }) {
        used.insert(ObjectIdentifier(hit))
      } else {
        unmatched.append(day)
      }
    }
    guard used.count == sessions.count else { return [] }
    return unmatched
  }

  /// Block number of one session, by the same week-reset walk. nil for sessions outside
  /// the completed walk (open or tombstoned).
  static func blockNumber(of session: WorkoutSession, sessions: [WorkoutSession]) -> Int? {
    let completed = sessions
      .filter { $0.completed && !$0.tombstoned }
      .sorted { $0.date < $1.date }
    var block = 0
    var previousWeek = Int.max
    for walked in completed {
      if walked.week < previousWeek { block += 1 }
      if walked === session { return block }
      previousWeek = walked.week
    }
    return nil
  }

  // MARK: - calendar-week plan math

  /// One calendar week column of the summary dot grid: how many sessions landed in the
  /// week, how many planned ones did not, and whether the week is still running.
  /// Planned/missed arithmetic runs on calendar weeks because program weeks are
  /// session-count based and hold exactly `daysPerWeek` sessions by construction.
  struct WeekColumn {
    let start: Date
    let done: Int
    let missed: Int
    let isCurrent: Bool
  }

  /// Calendar weeks of one block, first trained week through the last week with sessions
  /// (through the current week for the current block). Trailing and interior weeks with
  /// no sessions keep their columns — empty weeks are exactly what a miss looks like.
  static func weekColumns(
    block: BlockGroup, daysPerWeek: Int, now: Date = .now
  ) -> [WeekColumn] {
    let cal = TrainingMetrics.reportingCalendar()
    let dates = block.sessions.map(\.date)
    guard let firstDate = dates.first else { return [] }
    let first = TrainingMetrics.reportingWeek(containing: firstDate, calendar: cal).start
    let lastAnchor = block.isCurrent ? now : (dates.last ?? firstDate)
    let last = TrainingMetrics.reportingWeek(containing: lastAnchor, calendar: cal).start
    let current = TrainingMetrics.reportingWeek(containing: now, calendar: cal).start

    var columns: [WeekColumn] = []
    var cursor = first
    while cursor <= last {
      let done = dates.filter {
        TrainingMetrics.reportingWeek(containing: $0, calendar: cal).start == cursor
      }.count
      let isCurrentWeek = cursor == current
      columns.append(
        WeekColumn(
          start: cursor, done: done,
          missed: isCurrentWeek ? 0 : max(0, daysPerWeek - done),
          isCurrent: isCurrentWeek))
      guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor), next > cursor
      else { break }
      cursor = next
    }
    return columns
  }

  // MARK: - records

  struct RecordEvent {
    let exercise: Exercise
    let weightKg: Double
    let reps: Int
    let e1rm: Double
    let previousE1RM: Double
    let date: Date
    let session: WorkoutSession
  }

  /// Every record event in order: the walk ProgressData uses, with the session kept so
  /// callers can group by session or by block. One event per exercise per session, at the
  /// session's best comparable achievement set.
  static func recordEvents(sessions: [WorkoutSession]) -> [RecordEvent] {
    var events: [RecordEvent] = []
    var bests: [String: Double] = [:]
    for session in sessions.filter({ $0.verified && $0.completed }).sorted(by: { $0.date < $1.date }) {
      let sets = session.analysisSets(.achievements)
      for id in Set(sets.map(\.exerciseID)) {
        guard let exercise = ExerciseDB.find(id),
          let set = comparableSets(sets.filter { $0.exerciseID == id })
            .max(by: { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) < Strength.epley(weightKg: $1.weightKg, reps: $1.reps) })
        else { continue }
        let value = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if let previous = bests[id], value > previous {
          events.append(
            RecordEvent(
              exercise: exercise, weightKg: set.weightKg, reps: set.reps, e1rm: value,
              previousE1RM: previous, date: session.date, session: session))
        }
        bests[id] = max(bests[id] ?? 0, value)
      }
    }
    return events
  }

  /// Records set in each session, for the History row chips.
  static func recordCounts(sessions: [WorkoutSession]) -> [ObjectIdentifier: Int] {
    var out: [ObjectIdentifier: Int] = [:]
    for event in recordEvents(sessions: sessions) {
      out[ObjectIdentifier(event.session), default: 0] += 1
    }
    return out
  }

  /// Best comparable e1RM of one exercise per session that trained it, oldest first.
  static func e1rmHistory(exerciseID: String, sessions: [WorkoutSession]) -> [(
    date: Date, e1rm: Double
  )] {
    var out: [(date: Date, e1rm: Double)] = []
    for session in sessions.filter({ $0.verified && $0.completed }).sorted(by: { $0.date < $1.date }) {
      let sets = session.analysisSets(.achievements).filter { $0.exerciseID == exerciseID }
      guard let best = comparableSets(sets)
        .map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max() else { continue }
      out.append((session.date, best))
    }
    return out
  }

  /// Copy of ProgressData.comparableSets: the newest verified equipment context decides
  /// which sets of one exercise are comparable.
  private static func comparableSets(_ sets: [LoggedSet]) -> [LoggedSet] {
    let reference =
      sets
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return sets }
    return sets.filter { $0.isComparableForBaseline(to: reference) }
  }

  // MARK: - plan

  /// Planned sets of a program week, nil when the generator has nothing for it.
  static func plannedSets(week: Int, profile: UserProfile, sessions: [WorkoutSession]) -> Int? {
    let days = template(week: week, profile: profile, sessions: sessions)
    guard !days.isEmpty else { return nil }
    return days.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
  }

  /// Lifts the first week of the next block would add that have never been logged.
  static func nextBlockNewLifts(sessions: [WorkoutSession], profile: UserProfile) -> [Exercise] {
    let logged = Set(
      sessions.filter(\.completed).flatMap { $0.sets.map(\.exerciseID) })
    var seen: Set<String> = []
    var out: [Exercise] = []
    for planned in template(week: 1, profile: profile, sessions: sessions).flatMap(\.exercises)
    where !logged.contains(planned.exercise.id) && seen.insert(planned.exercise.id).inserted {
      out.append(planned.exercise)
    }
    return out
  }

  /// Monday of the week holding `date`.
  static func weekStart(containing date: Date) -> Date {
    TrainingMetrics.reportingWeek(
      containing: date, calendar: TrainingMetrics.reportingCalendar()
    ).start
  }

  /// "Sep 21 – 27", or "Sep 28 – Oct 4" when the span crosses a month.
  static func spanText(from start: Date, to end: Date) -> String {
    let cal = Calendar.current
    let head = start.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    let tail =
      cal.isDate(start, equalTo: end, toGranularity: .month)
      ? end.formatted(.dateTime.day().locale(L10n.locale))
      : end.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    return "\(head) – \(tail)"
  }
}

// MARK: - shared parts

/// 8 pt grey band between sections of a white detail page (DESIGN §2).
struct LogBand: View {
  var body: some View { Theme.pageGrey.frame(height: 8) }
}

/// Gold record chip: trophy and count.
struct LogRecordChip: View {
  let count: Int

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: "trophy.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.recordRing)
      Text("\(count)")
        .forge(13, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.recordInk)
    }
    .padding(.leading, 5)
    .padding(.trailing, 7)
    .frame(height: 22)
    .background(Capsule().fill(Theme.recordTint))
    .accessibilityLabel(String(localized: "\(count) records", bundle: L10n.bundle))
  }
}

/// Icon badge: the symbol in its category color on a 14 % fill (DESIGN §5).
struct LogIconBadge: View {
  let symbol: String
  let tint: Color
  var round = false

  @ViewBuilder
  private var badgeBackground: some View {
    if round {
      Circle().fill(tint.opacity(0.14))
    } else {
      RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .fill(tint.opacity(0.14))
    }
  }

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: 32, height: 32)
      .background(badgeBackground)
      .accessibilityHidden(true)
  }
}

/// Three-stat row of the log screens: colored dot (or trophy) and label above a large
/// tabular value with a quieter unit (mock `.stats`).
struct LogStatsRow: View {
  struct Item {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.text
    var trophy = false
  }

  let items: [Item]

  var body: some View {
    HStack(spacing: 12) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            if item.trophy {
              Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.recordRing)
                .accessibilityHidden(true)
            } else {
              Circle().fill(item.color).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text(item.label)
              .forge(13, .medium)
              .foregroundStyle(Theme.textSecondary)
          }
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(item.value)
              .forge(28, .bold, tracking: -0.56)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
            if let unit = item.unit {
              Text(unit)
                .forge(15, .medium)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(item))
      }
    }
  }

  /// The flows assert the old MetricGrid reading: "Tonnage, 5,860 kg" — one comma after the
  /// label, the value and its unit joined by a space.
  private func accessibilityText(_ item: Item) -> String {
    item.unit.map { unit in
      "\(item.label), \(item.value) \(unit)"
    } ?? "\(item.label), \(item.value)"
  }
}

/// Capsule segmented control (mock `.segctl`: 36 pt tall, selected segment lifted).
struct LogSegmented<T: Hashable>: View {
  struct Choice {
    let value: T
    let label: String
  }

  let choices: [Choice]
  @Binding var selection: T
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
        let selected = choice.value == selection
        Button {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            selection = choice.value
          }
        } label: {
          Text(choice.label)
            .forge(15, selected ? .semibold : .medium)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
              Capsule().fill(selected ? Theme.card : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Capsule().fill(Theme.innerSurface))
    .accessibilityElement(children: .contain)
  }
}

/// Summary dot grid: one dot per planned session, grouped by training block. Done is
/// accent, a missed planned session hollow, the current week's next slot a ring, the rest
/// track (mock `.dots`).
struct LogDotGrid: View {
  enum Dot { case done, missed, planned, today }

  struct Week {
    let dots: [Dot]
  }

  struct BlockDots {
    let label: String
    let weeks: [Week]
  }

  let groups: [BlockDots]

  @ViewBuilder
  private func dot(_ kind: Dot) -> some View {
    Group {
      switch kind {
      case .done: Circle().fill(Theme.accent)
      case .planned: Circle().fill(Theme.track)
      case .missed: Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5)
      case .today: Circle().strokeBorder(Theme.accent, lineWidth: 2)
      }
    }
    .frame(width: 10, height: 10)
    .accessibilityHidden(true)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            ForEach(Array(group.weeks.enumerated()), id: \.offset) { _, week in
              VStack(spacing: 5) {
                ForEach(Array(week.dots.enumerated()), id: \.offset) { _, kind in
                  dot(kind)
                }
              }
            }
          }
          Text(group.label)
            .forge(12)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize()
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let done = groups.flatMap(\.weeks).flatMap(\.dots).filter { $0 == .done }.count
    let planned = groups.flatMap(\.weeks).flatMap(\.dots)
      .filter { $0 != .planned }.count
    let missed = groups.flatMap(\.weeks).flatMap(\.dots).filter { $0 == .missed }.count
    return String(
      localized: "\(done) of \(planned) planned sessions, \(missed) missed",
      bundle: L10n.bundle)
  }
}

/// Sets-per-week bar chart of the Training blocks screen: done weeks solid gradExercise,
/// the current week an outline, planned weeks dashed, a dashed ghost to the planned height
/// where a week fell short. Labels under the columns: date, then Now / Peak / Deload /
/// missed counts. Same visual grammar as the roadmap chart (DESIGN §8).
struct LogSetsChart: View {
  enum Kind { case past, now, plan }

  struct Column: Identifiable {
    let value: Int
    var planned: Int? = nil
    let kind: Kind
    let date: String?
    var status: String? = nil
    var current = false
    var id: String { "\(date ?? "")-\(value)-\(kind)" }
  }

  let columns: [Column]
  @Environment(\.colorScheme) private var colorScheme

  private var maxValue: Int {
    max(1, columns.map { max($0.value, $0.planned ?? $0.value) }.max() ?? 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Sets per week")
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(columns) { column in
          chartColumn(column)
        }
      }
      .padding(.top, 8)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(chartAccessibilityText)
    }
  }

  private func chartColumn(_ column: Column) -> some View {
    let plotHeight: CGFloat = 84
    let scale = { (v: Int) in
      plotHeight * CGFloat(v) / CGFloat(maxValue)
    }
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
      topTrailingRadius: 8, style: .continuous)
    let barHeight = max(2, scale(column.value))
    let ghostHeight = column.planned.map { max(0, $0 - column.value) }.map { scale($0) } ?? 0
    // A ghost sits on top of the solid part, so the solid part loses its top corners.
    let barShape = UnevenRoundedRectangle(
      topLeadingRadius: ghostHeight > 0 ? 0 : 8, bottomLeadingRadius: 0,
      bottomTrailingRadius: 0, topTrailingRadius: ghostHeight > 0 ? 0 : 8,
      style: .continuous)

    return VStack(spacing: 0) {
      Text("\(column.value)")
        .forge(12, .semibold)
        .monospacedDigit()
        .foregroundStyle(column.current ? Theme.text : Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        if ghostHeight > 0 {
          shape
            .stroke(
              Theme.gradExercise[0].opacity(0.75),
              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: 26, height: max(3, ghostHeight))
        }
        Group {
          switch column.kind {
          case .past:
            barShape
              .fill(.mark(Theme.gradExercise, startPoint: .bottom, endPoint: .top))
              .frame(width: 26, height: barHeight)
          case .now:
            ZStack(alignment: .bottom) {
              Rectangle().fill(
                colorScheme == .dark ? Color.clear : Theme.gradExercise[0].opacity(0.12))
            }
            .frame(width: 26, height: barHeight)
            .clipShape(barShape)
            .overlay(barShape.stroke(Theme.gradExercise[0], lineWidth: 1.5))
          case .plan:
            barShape
              .stroke(
                Theme.gradExercise[0].opacity(0.75),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
              .frame(width: 26, height: barHeight)
          }
        }
      }
      Rectangle().fill(Theme.ring).frame(height: 1)
      Text(column.date ?? "")
        .forge(12)
        .monospacedDigit()
        .foregroundStyle(column.current ? Theme.text : Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.top, 7)
      Text(column.status ?? "")
        .forge(12, column.current ? .semibold : .regular)
        .foregroundStyle(column.current ? Theme.text : Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
  }

  private var chartAccessibilityText: String {
    columns
      .map { column in
        String(
          localized: "\(column.date ?? ""): \(column.value) sets", bundle: L10n.bundle)
      }
      .joined(separator: ", ")
  }
}
