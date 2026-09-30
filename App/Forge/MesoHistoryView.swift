import ForgeCore
import SwiftData
import SwiftUI

struct MesoHistoryView: View {
  let usesLb: Bool
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var profile: UserProfile? { profiles.first }
  private var blocks: [LogV3.BlockGroup] {
    LogV3.blocks(sessions: sessions, profile: profile)
  }

  private var events: [LogV3.RecordEvent] {
    LogV3.recordEvents(sessions: sessions)
  }

  private var headerSubtitle: String? {
    guard let profile else { return nil }
    let goalName = Goal(rawValue: profile.goal)?.name ?? Goal.hypertrophy.name
    return String(
      localized: "\(goalName) · \(profile.daysPerWeek) days a week", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(title: "Training blocks", subtitle: headerSubtitle, art: "art-blocks")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 8)
        if profile != nil {
          blockStrip
            .padding(.horizontal, Theme.margin)
            .padding(.top, 16)
            .padding(.bottom, 22)
          LogBand()
        }
        if blocks.isEmpty {
          Text(String(localized: "No training blocks yet.", bundle: L10n.bundle))
            .forgeLabel()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        ForEach(blocks.reversed()) { block in
          blockSection(block)
            .padding(.bottom, 22)
          LogBand()
          if block.isCurrent {
            futureSection
              .padding(.bottom, 22)
            LogBand()
          }
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation("Training blocks")
  }

  // MARK: road strip

  /// Three-segment block road: previous complete, current with its progress, next with its
  /// start date (the same strip the roadmap shows, scoped to blocks).
  private var blockStrip: some View {
    guard let profile, let current = blocks.last else { return AnyView(EmptyView()) }
    let number = current.number
    let daysPerWeek = max(1, profile.daysPerWeek)
    let done = current.sessions.count
    let total = max(Mesocycle.weeks, current.maxWeek) * daysPerWeek
    let week = profile.currentWeek(sessions: sessions)
    return AnyView(
      HStack(spacing: 4) {
        if number > 1 {
          stripSegment(
            fraction: 1,
            name: String(localized: "Block \(number - 1)", bundle: L10n.bundle),
            status: String(localized: "Complete", bundle: L10n.bundle),
            isCurrent: false)
        }
        stripSegment(
          fraction: total > 0 ? Double(done) / Double(total) : 0,
          name: String(localized: "Block \(number)", bundle: L10n.bundle),
          status: String(
            localized: "Now · week \(week) of \(Mesocycle.weeks)", bundle: L10n.bundle),
          isCurrent: true)
        stripSegment(
          fraction: 0,
          name: String(localized: "Block \(number + 1)", bundle: L10n.bundle),
          status: String(
            localized: "Starts \(nextBlockStart.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
            bundle: L10n.bundle),
          isCurrent: false)
      }
      .accessibilityElement(children: .combine)
    )
  }

  private var nextBlockStart: Date {
    LogV3.nextBlockStart(profile: profile, sessions: sessions)
  }

  private func stripSegment(fraction: Double, name: String, status: String, isCurrent: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule()
            .fill(.mark(Theme.gradExercise, startPoint: .leading, endPoint: .trailing))
            .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
        }
      }
      .frame(height: 6)
      Text(name)
        .forge(13, .semibold)
        .foregroundStyle(isCurrent ? Theme.text : Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, 8)
      Text(status)
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: block sections

  private func blockSection(_ block: LogV3.BlockGroup) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(String(localized: "Block \(block.number)", bundle: L10n.bundle))
          .forge(22, .bold, tracking: -0.33)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 12)
        Text(blockRange(block))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 22)
      if let summary = blockSummaryLine(block) {
        Text(summary)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 2)
      }
      LogStatsRow(items: statItems(block))
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
      chart(block)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
      gains(block)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
    }
  }

  /// "Sep 7 – Oct 18": the block's first trained Monday through the Sunday six weeks out —
  /// or through its last trained Sunday when the block ran short.
  private func blockRange(_ block: LogV3.BlockGroup) -> String {
    guard let first = block.firstDate else { return "" }
    let startMonday = LogV3.weekStart(containing: first)
    let lastSunday = block.lastDate.map { LogV3.weekStart(containing: $0).addingTimeInterval(6 * 86400) }
    let fullEnd = startMonday.addingTimeInterval(Double(Mesocycle.weeks * 7 - 1) * 86400)
    let end = min(fullEnd, lastSunday ?? fullEnd)
    return LogV3.spanText(from: startMonday, to: max(end, startMonday))
  }

  private func blockSummaryLine(_ block: LogV3.BlockGroup) -> String? {
    guard let profile else { return nil }
    let week = profile.currentWeek(sessions: sessions)
    let deloadStart = block.firstDate.map {
      LogV3.weekStart(containing: $0)
        .addingTimeInterval(Double(Mesocycle.deloadWeek - 1) * 7 * 86400)
    }
    if block.isCurrent {
      switch week {
      case Mesocycle.deloadWeek:
        return String(
          localized: "Deload week. Recover before the next block.", bundle: L10n.bundle)
      case Mesocycle.deloadWeek - 1:
        return deloadStart.map {
          String(
            localized: "Peak week next, then a deload from \($0.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))).",
            bundle: L10n.bundle)
        }
      default:
        return String(
          localized: "Volume builds each week, then a deload.", bundle: L10n.bundle)
      }
    }
    return String(
      localized: "Complete. \(Mesocycle.deloadWeek - 1) build weeks and a deload.",
      bundle: L10n.bundle)
  }

  private func statItems(_ block: LogV3.BlockGroup) -> [LogStatsRow.Item] {
    let blockSessions = Set(block.sessions.map(ObjectIdentifier.init))
    let records = events.filter { blockSessions.contains(ObjectIdentifier($0.session)) }.count
    let gains = liftGains(block)
    var items: [LogStatsRow.Item] = [
      LogStatsRow.Item(
        label: String(localized: "Sessions", bundle: L10n.bundle),
        value: "\(block.sessions.count)",
        unit: plannedText(block),
        color: Theme.metricLoad),
      LogStatsRow.Item(
        label: String(localized: "Records", bundle: L10n.bundle),
        value: "\(records)",
        trophy: true),
    ]
    if gains.compared > 0 {
      items.append(
        LogStatsRow.Item(
          label: String(localized: "Lifts up", bundle: L10n.bundle),
          value: "\(gains.up)",
          unit: String(localized: "of \(gains.compared)", bundle: L10n.bundle),
          color: Theme.positive))
    }
    return items
  }

  private func plannedText(_ block: LogV3.BlockGroup) -> String? {
    guard let profile, profile.daysPerWeek > 0 else { return nil }
    let weeks = max(Mesocycle.weeks, block.maxWeek)
    return String(
      localized: "of \(weeks * profile.daysPerWeek)", bundle: L10n.bundle)
  }

  /// Lifts with at least two comparable workouts in the block: how many closed higher than
  /// they opened.
  private func liftGains(_ block: LogV3.BlockGroup) -> (up: Int, compared: Int) {
    let ids = Set(block.sessions.flatMap { $0.sets.map(\.exerciseID) })
    var up = 0
    var compared = 0
    for id in ids {
      let history = LogV3.e1rmHistory(exerciseID: id, sessions: block.sessions)
      guard history.count >= 2, let first = history.first, let last = history.last else {
        continue
      }
      compared += 1
      if last.e1rm - first.e1rm >= 0.5 { up += 1 }
    }
    return (up, compared)
  }

  // MARK: sets-per-week chart

  private func chart(_ block: LogV3.BlockGroup) -> some View {
    guard let profile else { return AnyView(EmptyView()) }
    let week = profile.currentWeek(sessions: sessions)
    // A finished block shows the weeks it actually ran; the current one extends through the
    // plan with dashed columns.
    let weekCount = block.isCurrent ? max(Mesocycle.weeks, block.maxWeek) : block.maxWeek
    let daysPerWeek = profile.daysPerWeek
    let byWeek = Dictionary(grouping: block.sessions, by: \.week)

    // Column dates anchor to each week's first session; empty weeks continue in 7-day steps.
    var columns: [LogSetsChart.Column] = []
    var anchor: Date?
    for w in 1...weekCount {
      let weekSessions = (byWeek[w] ?? []).sorted { $0.date < $1.date }
      let logged = weekSessions.reduce(0) { $0 + $1.sets.count }
      if let first = weekSessions.first?.date {
        anchor = LogV3.weekStart(containing: first)
      } else if let previous = anchor {
        anchor = previous.addingTimeInterval(7 * 86400)
      } else if let blockStart = block.firstDate {
        anchor = LogV3.weekStart(containing: blockStart)
          .addingTimeInterval(Double(w - 1) * 7 * 86400)
      }
      let isPast = !block.isCurrent || w < week
      let isNow = block.isCurrent && w == week
      let planned = LogV3.plannedSets(week: w, profile: profile, sessions: sessions)
      let missedSessions =
        (isPast && daysPerWeek > 0) ? max(0, daysPerWeek - weekSessions.count) : 0
      var status: String? = nil
      if isNow {
        status = String(localized: "Now", bundle: L10n.bundle)
      } else if w == Mesocycle.deloadWeek {
        status = String(localized: "Deload", bundle: L10n.bundle)
      } else if block.isCurrent, w == Mesocycle.deloadWeek - 1 {
        status = String(localized: "Peak", bundle: L10n.bundle)
      } else if missedSessions > 0 {
        status = String(
          localized: "\(missedSessions) missed", bundle: L10n.bundle)
      }
      columns.append(
        LogSetsChart.Column(
          value: isPast || isNow ? logged : (planned ?? 0),
          planned: isPast || isNow ? planned : nil,
          kind: isPast ? .past : (isNow ? .now : .plan),
          date: anchor?.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)),
          status: status,
          current: isNow))
    }
    return AnyView(LogSetsChart(columns: columns))
  }

  // MARK: biggest gains

  private struct GainRow: Identifiable {
    let exercise: Exercise
    let from: Double
    let to: Double
    var delta: Double { to - from }
    var id: String { exercise.id }
  }

  /// The running block is measured against the previous block's best; older blocks against
  /// their own first workout.
  private func gains(_ block: LogV3.BlockGroup) -> some View {
    let previous = blocks.first { $0.number == block.number - 1 }
    let rows = biggestGains(block, versus: previous)
    guard !rows.isEmpty else { return AnyView(EmptyView()) }
    let header =
      previous != nil
      ? String(
        localized: "Biggest gains over Block \(previous!.number)'s best", bundle: L10n.bundle)
      : String(localized: "Biggest gains, first to best workout", bundle: L10n.bundle)
    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        Text(header)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .padding(.bottom, 2)
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          gainRow(row)
          if index < rows.count - 1 {
            Rectangle().fill(Theme.ring).frame(height: 1)
          }
        }
      }
    )
  }

  private func biggestGains(_ block: LogV3.BlockGroup, versus previous: LogV3.BlockGroup?)
    -> [GainRow]
  {
    let ids = Set(block.sessions.flatMap { $0.sets.map(\.exerciseID) })
    var rows: [GainRow] = []
    for id in ids {
      let inBlock = LogV3.e1rmHistory(exerciseID: id, sessions: block.sessions)
      guard let best = inBlock.map(\.e1rm).max(),
        let bestExercise = ExerciseDB.find(id)
      else { continue }
      let from: Double?
      if let previous {
        from = LogV3.e1rmHistory(exerciseID: id, sessions: previous.sessions)
          .map(\.e1rm).max()
      } else {
        from = inBlock.first?.e1rm
      }
      guard let from, best - from >= 0.5 else { continue }
      rows.append(GainRow(exercise: bestExercise, from: from, to: best))
    }
    return rows.sorted { $0.delta > $1.delta }.prefix(3).map { $0 }
  }

  private func gainRow(_ row: GainRow) -> some View {
    let lb = profiles.first?.isLb(for: row.exercise.id) ?? usesLb
    let unit = lb ? "lb" : "kg"
    let from = Fmt.int(UnitFormat.plain(row.from, usesLb: lb))
    let to = Fmt.int(UnitFormat.plain(row.to, usesLb: lb))
    return HStack(spacing: 8) {
      Text(row.exercise.localizedName)
        .forge(16)
        .foregroundStyle(Theme.text)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text("\(from) → \(to) \(unit)")
        .forge(15)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
      TrendChangeText(changeKg: row.delta, isLb: lb, size: 16)
        .frame(width: 64, alignment: .trailing)
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
  }

  // MARK: next block

  /// The next block's never-logged lifts, as quiet locked tokens. Omitted entirely when the
  /// generator has nothing new to say.
  @ViewBuilder
  private var futureSection: some View {
    if let profile {
      let newLifts = LogV3.nextBlockNewLifts(sessions: sessions, profile: profile)
      if !newLifts.isEmpty, let current = blocks.last {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "Block \(current.number + 1)", bundle: L10n.bundle))
              .forge(22, .bold, tracking: -0.33)
              .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Text(
              nextBlockStart.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
            )
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          }
          .padding(.horizontal, Theme.margin)
          .padding(.top, 22)
          Text(
            String(
              localized: "Adds \(newLifts.count) lifts you haven't logged yet.",
              bundle: L10n.bundle)
          )
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 2)
          HStack(alignment: .top, spacing: 12) {
            ForEach(Array(newLifts.prefix(4)), id: \.id) { exercise in
              VStack(spacing: 6) {
                LockedToken(size: 52)
                Text(exercise.localizedName)
                  .forge(12)
                  .foregroundStyle(Theme.textSecondary)
                  .multilineTextAlignment(.center)
              }
              .frame(width: 72)
            }
          }
          .padding(.horizontal, Theme.margin)
          .padding(.top, 14)
        }
      }
    }
  }
}
