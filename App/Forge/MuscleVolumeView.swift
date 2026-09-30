import ForgeCore
import SwiftData
import SwiftUI

/// The muscles detail page: which muscles got enough work in the last 7 days, and what
/// changes next. `weekSets` is the rolling 7-day window the Overview card passes in.
struct MuscleVolumeView: View {
  let weekSets: [Muscle: Double]
  let recoveryReduced: Bool

  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var approvingIncrease: VolumeIncrease?

  private var profile: UserProfile? { profiles.first }
  private var coach: Coach { Coach.from(coachID) }

  private struct MuscleStat {
    let muscle: Muscle
    let sets: Double
    let floor: Int
    let mrv: Int
    let area: BodyArea
  }

  private var stats: [MuscleStat] {
    Muscle.allCases.compactMap { muscle in
      guard let l = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: recoveryReduced)
      else { return nil }
      return MuscleStat(
        muscle: muscle, sets: weekSets[muscle] ?? 0,
        floor: l.floor(recoveryReduced: recoveryReduced), mrv: l.mrv, area: BodyArea(muscle))
    }
  }

  private var worked: [MuscleStat] { stats.filter { $0.sets > 0 } }
  /// Short includes muscles with 0 sets: a tracked muscle with no work is the shortest case.
  private var short: [MuscleStat] {
    stats.filter { $0.sets < Double($0.floor) }.sorted { $0.sets / Double($0.floor) < $1.sets / Double($1.floor) }
  }
  private var inRangeCount: Int {
    stats.filter { $0.sets >= Double($0.floor) && $0.sets <= Double($0.mrv) }.count
  }
  private var totalSets: Double { stats.reduce(0) { $0 + $1.sets } }

  /// The track scale: 24 covers every landmark (max MRV 22); grows only past that.
  private var scale: Double {
    let maxMrv = stats.map(\.mrv).max() ?? 22
    let maxSets = stats.map(\.sets).max() ?? 0
    return max(24, Double(max(maxMrv, Int(maxSets.rounded(.up))) + 2))
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        FieldSection(bottom: 20) {
          fieldContent
        }
        VStack(spacing: 0) {
          whatChangesNext
          allMuscles
            .padding(.bottom, 20)
          Text("Each muscle has its own range. Small muscles need fewer direct sets than big ones.")
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.page)
      }
    }
    .progressFieldPage(String(localized: "Muscles", bundle: L10n.bundle))
    .sheet(item: $approvingIncrease) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  // MARK: field

  @ViewBuilder private var fieldContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if worked.isEmpty {
        Text("Log a set in the last 7 days to see which muscles worked.")
          .forgeLabel()
          .padding(.top, 16)
      } else {
        HStack(alignment: .top, spacing: 12) {
          Text(String(localized: "\(inRangeCount) of \(stats.count) muscles in range", bundle: L10n.bundle))
            .forge(28, .bold)
            .tracking(-0.5)
            .foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          Image("goal-hypertrophy")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
        }
        Text(verbatim: caption)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 8)
        figureRow
          .padding(.top, 16)
        legendRow
          .padding(.top, 12)
      }
    }
  }

  /// The field caption: the 7-day window, then the short muscles and by how much.
  private var caption: String {
    var text = String(
      localized: "Last 7 days, \(rangeText) · \(Int(totalSets.rounded())) sets.", bundle: L10n.bundle)
    if !short.isEmpty { text += " " + shortSentence }
    return text
  }

  /// Today and the six days before, the window the mock's "Sep 23–29" shows.
  private var rangeText: String {
    let formatter = DateIntervalFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = L10n.locale
    formatter.dateTemplate = "MMMd"
    let start = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    return formatter.string(from: start, to: .now)
  }

  private var shortSentence: String {
    let deficits = short.map {
      (name: $0.muscle.a11yName, d: Int((Double($0.floor) - $0.sets).rounded(.up)))
    }
    if deficits.count == 1, let only = deficits.first {
      return String(
        localized: "\(only.name) is \(only.d) set\(L10n.pluralSuffix(only.d)) short.",
        bundle: L10n.bundle)
    }
    let names = deficits.map(\.name).formatted(.list(type: .and).locale(L10n.locale))
    let values = Set(deficits.map(\.d))
    if values.count == 1, let d = values.first {
      return String(
        localized: "\(names) are \(d) set\(L10n.pluralSuffix(d)) short.", bundle: L10n.bundle)
    }
    let lo = values.min() ?? 0
    let hi = values.max() ?? 0
    return String(localized: "\(names) are \(lo)–\(hi) sets short.", bundle: L10n.bundle)
  }

  private var figureRow: some View {
    HStack(alignment: .top, spacing: 16) {
      ForEach([MuscleSide.front, .back], id: \.self) { side in
        shortFigure(side)
          .frame(width: 112)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }

  /// One figure side with a dimmed base, ramped in-range muscles and outlined short ones.
  private func shortFigure(_ side: MuscleSide) -> some View {
    ZStack {
      Image(side.assetName).resizable().scaledToFit().opacity(0.55)
      ForEach(side.muscles, id: \.self) { muscle in
        figureLayer(side, muscle)
      }
    }
    .aspectRatio(MuscleFigureRegions.aspect, contentMode: .fit)
    .accessibilityHidden(true)
  }

  @ViewBuilder private func figureLayer(_ side: MuscleSide, _ muscle: Muscle) -> some View {
    if let stat = stats.first(where: { $0.muscle == muscle }) {
      if stat.sets < Double(stat.floor) {
        // A short muscle with 0 sets shows the outline only — no ramp fill it has not earned.
        if stat.sets > 0 { shortLayer(side, muscle) } else { outlineLayer(side, muscle) }
      } else if let v = figureIntensity[muscle] {
        overlay(side, muscle, Theme.rampColor(v))
      }
    }
  }

  /// A short muscle: ramp[1] fill with a 1 pt accent outline behind it.
  private func shortLayer(_ side: MuscleSide, _ muscle: Muscle) -> some View {
    ZStack {
      outlineLayer(side, muscle)
      overlay(side, muscle, Theme.ramp[1])
    }
  }

  /// The 1 pt accent outline that marks a muscle short of its range: four offset copies
  /// with the centre punched out, so an untrained muscle shows a rim, not a solid fill.
  private func outlineLayer(_ side: MuscleSide, _ muscle: Muscle) -> some View {
    ZStack {
      overlay(side, muscle, Theme.accent).offset(y: -1)
      overlay(side, muscle, Theme.accent).offset(y: 1)
      overlay(side, muscle, Theme.accent).offset(x: -1)
      overlay(side, muscle, Theme.accent).offset(x: 1)
      overlay(side, muscle, .black).blendMode(.destinationOut)
    }
    .compositingGroup()
  }

  private func overlay(_ side: MuscleSide, _ muscle: Muscle, _ color: Color) -> some View {
    Image("\(side.assetName)-\(muscle)")
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .foregroundStyle(color)
  }

  private var figureIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for stat in stats where stat.sets > 0 {
      result[stat.muscle] = Double(BodyV3.rampStep(stat.sets)) / 4
    }
    return result
  }

  private var legendRow: some View {
    HStack(spacing: 14) {
      HStack(spacing: 5) {
        Circle().strokeBorder(Theme.accent, lineWidth: 1.5).frame(width: 10, height: 10)
        Text(String(localized: "Short of range", bundle: L10n.bundle))
          .forge(12, .regular)
          .foregroundStyle(Theme.textSecondary)
      }
      HStack(spacing: 5) {
        HStack(spacing: 3) {
          ForEach([2, 3, 4], id: \.self) { step in
            Circle().fill(Theme.ramp[step]).frame(width: 7, height: 7)
          }
        }
        Text("In range").forge(12, .regular).foregroundStyle(Theme.textSecondary)
      }
    }
    .accessibilityHidden(true)
  }

  // MARK: what changes next

  private var whatChangesNext: some View {
    VStack(spacing: 0) {
      InsightsSectionHeader(title: "What changes next")
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        if let ask = pendingAsk {
          askRow(ask)
          if plannedSetsTitle != nil || !shortLifts.isEmpty {
            rowDivider
          }
        }
        if plannedSetsTitle != nil {
          plannedSetsRow
          if !shortLifts.isEmpty {
            rowDivider
          }
        }
        if !shortLifts.isEmpty {
          nextLiftsRow
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
  }

  private var pendingAsk: VolumeIncrease? {
    guard let profile else { return nil }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
      .first { $0.answer == nil }
  }

  /// The coach's pending volume ask, a hairline row with a Review pill.
  private func askRow(_ increase: VolumeIncrease) -> some View {
    let added = increase.toSets - increase.fromSets
    let now = Int((weekSets[increase.muscle] ?? 0).rounded())
    let title = String(
      localized:
        "Add \(added) \(increase.exercise.localizedName) set\(L10n.pluralSuffix(added)) to \(localizedDayName(increase.dayName))",
        bundle: L10n.bundle)
    return HStack(spacing: 12) {
      CoachAvatar(size: 32)
        .frame(width: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(String(
          localized: "Needs your OK · \(increase.muscle.a11yName) \(now)\u{00A0}→\u{00A0}\(now + added)",
          bundle: L10n.bundle))
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      ReviewPill(
        accessibilityLabel: String(localized: "Review \(title)", bundle: L10n.bundle),
        action: { approvingIncrease = increase })
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
  }

  private var plannedSetsRow: some View {
    HStack(spacing: 12) {
      leadIcon("chart.bar.fill", tint: Theme.metricSets)
      VStack(alignment: .leading, spacing: 2) {
        if let title = plannedSetsTitle {
          Text(verbatim: title)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let line = plannedSetsLine {
          Text(verbatim: line)
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      Spacer(minLength: 8)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }

  private func leadIcon(_ symbol: String, tint: Color) -> some View {
    Image(systemName: symbol)
      .scaledSystemFont(20, weight: .semibold)
      .foregroundStyle(tint)
      .frame(width: 44)
      .accessibilityHidden(true)
  }

  private var plannedSetsTitle: String? {
    guard let profile else { return nil }
    let week = profile.currentWeek(sessions: sessions)
    if let plan = profile.weekPlan {
      let inWeek = plan.days.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
      guard !inWeek.isEmpty else { return nil }
      return String(localized: "\(inWeek.reduce(0) { $0 + $1.plannedSetCount }) sets planned this week", bundle: L10n.bundle)
    }
    guard RoutineAdaptationService.weekPlanUnreadable(profile) == false else { return nil }
    return LogV3.plannedSets(week: week, profile: profile, sessions: sessions)
      .map { String(localized: "\($0) sets planned this week", bundle: L10n.bundle) }
  }

  private var plannedSetsLine: String? {
    guard let profile else { return nil }
    let week = profile.currentWeek(sessions: sessions)
    let peakWeek = Mesocycle.deloadWeek - 1
    if week < peakWeek,
      let peak = LogV3.plannedSets(week: peakWeek, profile: profile, sessions: sessions)
    {
      return String(
        localized: "\(peak) in peak week \(peakWeek), then a deload week", bundle: L10n.bundle)
    }
    guard profile.weekPlan == nil,
      RoutineAdaptationService.weekPlanUnreadable(profile) == false,
      let this = LogV3.plannedSets(week: week, profile: profile, sessions: sessions),
      let previous = LogV3.plannedSets(week: week - 1, profile: profile, sessions: sessions)
    else { return nil }
    if this > previous {
      return String(localized: "+\(this - previous) vs last week", bundle: L10n.bundle)
    }
    if this < previous {
      return String(localized: "−\(previous - this) vs last week", bundle: L10n.bundle)
    }
    return String(localized: "Same as last week", bundle: L10n.bundle)
  }

  private var nextLifts: [Exercise] {
    guard let profile else { return [] }
    return LogV3.nextBlockNewLifts(sessions: sessions, profile: profile)
  }

  /// First day of the next block, the way MesoHistoryView's strip computes it.
  private var nextBlockStart: Date {
    LogV3.nextBlockStart(profile: profile, sessions: sessions)
  }

  /// Only lifts that train a currently short muscle, the ones that fix the deficits.
  private var shortLifts: [Exercise] {
    let shortMuscles = Set(short.map(\.muscle))
    return nextLifts.filter {
      shortMuscles.contains($0.primary) || !$0.synergists.filter(shortMuscles.contains).isEmpty
    }
  }

  private var nextLiftsRow: some View {
    let lifts = shortLifts
    let shown = lifts.prefix(2).map(\.localizedName)
    let names = lifts.count > 2
      ? shown.joined(separator: ", ") + " "
        + String(localized: "and \(lifts.count - 2) more", bundle: L10n.bundle)
      : shown.formatted(.list(type: .and).locale(L10n.locale))
    return HStack(spacing: 12) {
      leadIcon("calendar", tint: Theme.metricTime)
      VStack(alignment: .leading, spacing: 2) {
        Text(String(
          localized: "New lifts from \(nextBlockStart.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
          bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: names)
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }

  // MARK: all muscles

  /// Core stays off the board and a muscle hides only when it is both unworked and in range.
  private func isVisible(_ stat: MuscleStat) -> Bool {
    let inRange = stat.sets >= Double(stat.floor) && stat.sets <= Double(stat.mrv)
    return !(stat.sets == 0 && inRange)
  }

  private var allMuscles: some View {
    VStack(spacing: 0) {
      InsightsSectionHeader(
        title: "All muscles",
        trailing: String(localized: "\(Int(totalSets.rounded())) sets", bundle: L10n.bundle))
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      Text(String(
        localized: "Sets in the last 7 days. The shaded part of each bar is the muscle's target range.",
        bundle: L10n.bundle))
        .forge(13, .regular)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 2)
        .padding(.bottom, 8)
      ForEach([BodyArea.push, .pull, .legs], id: \.self) { area in
        let rows = stats.filter { $0.area == area && isVisible($0) }
        if !rows.isEmpty {
          groupHeader(area, rows: rows)
          VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.muscle) { index, stat in
              if index > 0 { muscleDivider }
              muscleRow(stat)
            }
          }
          .padding(.horizontal, Theme.margin)
        }
      }
    }
  }

  private func groupHeader(_ area: BodyArea, rows: [MuscleStat]) -> some View {
    let sum = rows.reduce(0) { $0 + $1.sets }
    return HStack(alignment: .firstTextBaseline) {
      Text(area.shortTitle).forge(15, .semibold).foregroundStyle(Theme.textSecondary)
      Spacer()
      Text("\(Int(sum.rounded())) sets")
        .forge(14, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
    .padding(.bottom, 2)
  }

  /// One muscle row: region thumbnail, range subtitle, target track and set count.
  private func muscleRow(_ stat: MuscleStat) -> some View {
    let count = Int(stat.sets.rounded())
    let shortBy = stat.sets < Double(stat.floor)
      ? Int((Double(stat.floor) - stat.sets).rounded(.up)) : nil
    return HStack(spacing: 12) {
      MuscleRegionThumb(muscle: stat.muscle)
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.muscle.a11yName).forge(15, .semibold).foregroundStyle(Theme.text)
        if let shortBy {
          Text(String(
            localized: "Range \(stat.floor)–\(stat.mrv) · \(shortBy) short", bundle: L10n.bundle))
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        } else {
          Text(String(localized: "Range \(stat.floor)–\(stat.mrv)", bundle: L10n.bundle))
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      Spacer(minLength: 8)
      muscleTrack(stat)
        .frame(width: 84, height: 4)
      Text(verbatim: "\(count)")
        .forge(17, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .frame(minWidth: 28, alignment: .trailing)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      shortBy.map {
        String(
          localized: "\(stat.muscle.a11yName), \(count) sets, range \(stat.floor) to \(stat.mrv), \($0) short",
          bundle: L10n.bundle)
      }
        ?? String(
          localized: "\(stat.muscle.a11yName), \(count) sets, range \(stat.floor) to \(stat.mrv)",
          bundle: L10n.bundle))
  }

  /// 84 pt track: the target range shaded ramp[2], the set count a dot clamped inside.
  private func muscleTrack(_ stat: MuscleStat) -> some View {
    let x = { (v: Double) -> CGFloat in
      CGFloat(min(max(v / scale, 0), 1)) * 84
    }
    let lo = x(Double(stat.floor))
    let hi = x(Double(stat.mrv))
    let dotX = min(max(x(stat.sets), 5), 79)
    let inRange = stat.sets >= Double(stat.floor)
    return ZStack(alignment: .leading) {
      Capsule().fill(Theme.track)
      Capsule()
        .fill(Theme.ramp[2])
        .frame(width: max(0, hi - lo))
        .padding(.leading, lo)
      Circle()
        .fill(inRange ? Theme.accent : Theme.textSecondary)
        .frame(width: 10, height: 10)
        .padding(.leading, dotX - 5)
    }
    .accessibilityHidden(true)
  }

  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 56)
  }

  private var muscleDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 56)
  }
}
