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
  private var short: [MuscleStat] {
    worked.filter { $0.sets < Double($0.floor) }.sorted { $0.sets / Double($0.floor) < $1.sets / Double($1.floor) }
  }
  private var inRangeCount: Int {
    worked.filter { $0.sets >= Double($0.floor) && $0.sets <= Double($0.mrv) }.count
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
        ProgressLargeTitle(
          title: "Muscles",
          subtitle: String(
            localized: "Sets in the last 7 days · \(subtitleRange)", bundle: L10n.bundle),
          art: "goal-hypertrophy"
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)

        headline
        figuresAndLegend
          .padding(.bottom, 20)
        LogBand()
        whatChangesNext
        LogBand()
        allMuscles
          .padding(.bottom, 20)
        Text("Each muscle has its own range. Small muscles need fewer direct sets than big ones.")
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 24)
      }
    }
    .background(Theme.page)
    .progressTitleNavigation("Muscles")
    .sheet(item: $approvingIncrease) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  private var subtitleRange: String {
    LogV3.spanText(from: Date.now.addingTimeInterval(-7 * 86400), to: Date.now)
  }

  // MARK: headline

  @ViewBuilder private var headline: some View {
    if worked.isEmpty {
      Text("Log a set in the last 7 days to see which muscles worked.")
        .forgeLabel()
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(verbatim: "\(inRangeCount)")
            .forge(44, .bold)
            .tracking(-1)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "of \(worked.count) muscles in range", bundle: L10n.bundle))
            .forge(22, .semibold)
            .foregroundStyle(Theme.textSecondary)
        }
        Text(shortLine)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
      .accessibilityElement(children: .combine)
    }
  }

  private var shortLine: String {
    if short.isEmpty {
      return String(localized: "Every worked muscle got enough sets.", bundle: L10n.bundle)
    }
    let names = short.map(\.muscle.a11yName)
    let list = names.formatted(.list(type: .and).locale(L10n.locale))
    return String(localized: "\(list) are short of their weekly range.", bundle: L10n.bundle)
  }

  // MARK: figures

  private var figuresAndLegend: some View {
    HStack(alignment: .bottom, spacing: 16) {
      MuscleMapView(intensity: figureIntensity)
        .frame(height: 240)
      legend
    }
    .padding(.horizontal, Theme.margin)
  }

  private var figureIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for stat in stats where stat.sets > 0 {
      result[stat.muscle] = Double(BodyV3.rampStep(stat.sets)) / 4
    }
    return result
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Sets").forge(15, .semibold).foregroundStyle(Theme.text)
      ForEach([(4, "12+"), (3, "9–11"), (2, "6–8"), (1, "1–5")], id: \.0) { step, label in
        HStack(spacing: 8) {
          Circle()
            .fill(Theme.ramp[step])
            .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
            .frame(width: 16, height: 16)
          Text(verbatim: label)
            .forge(14, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
    }
    .accessibilityHidden(true)
  }

  // MARK: what changes next

  private var whatChangesNext: some View {
    VStack(spacing: 0) {
      V3SectionHeader("What changes next")
      if let ask = pendingAsk {
        askRow(ask)
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 8)
      }
      if let title = plannedSetsTitle {
        V3DetailRow(icon: "chart.bar.fill", tint: Theme.metricSets, title: title) {
          if let line = plannedSetsLine {
            Text(verbatim: line)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
        }
        .padding(.horizontal, Theme.margin)
      }
    }
    .padding(.bottom, 20)
  }

  private var pendingAsk: VolumeIncrease? {
    guard let profile else { return nil }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
      .first { $0.answer == nil }
  }

  /// The pending volume increase as a tint row: the same source and review sheet as Today.
  private func askRow(_ increase: VolumeIncrease) -> some View {
    Button {
      approvingIncrease = increase
    } label: {
      HStack(spacing: 12) {
        CoachAvatar(size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(askTitle(increase))
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 4) {
            Text(verbatim: askDetail(increase))
            Text(String(localized: "Needs your OK", bundle: L10n.bundle))
              .foregroundStyle(Theme.accentText)
          }
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
          .opacity(0.7)
      }
      .padding(12)
      .frame(minHeight: 62)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.accentTint))
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(String(localized: "Review \(askTitle(increase))", bundle: L10n.bundle))
  }

  private func askTitle(_ increase: VolumeIncrease) -> String {
    let added = increase.toSets - increase.fromSets
    return String(
      localized: "Add \(added) \(increase.exercise.localizedName) set\(L10n.pluralSuffix(added)) in \(localizedDayName(increase.dayName))",
      bundle: L10n.bundle)
  }

  private func askDetail(_ increase: VolumeIncrease) -> String {
    String(localized: "For \(increase.muscle.a11yName) ·", bundle: L10n.bundle)
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

  // MARK: all muscles

  private var allMuscles: some View {
    VStack(spacing: 0) {
      V3SectionHeader("All muscles", trailing: "\(Int(totalSets.rounded())) sets")
      zoneLegend
      axisRow
      ForEach([BodyArea.push, .pull, .legs, .core], id: \.self) { area in
        let rows = stats.filter { $0.area == area }
        if !rows.isEmpty {
          groupHeader(area, rows: rows)
          ForEach(Array(rows.enumerated()), id: \.element.muscle) { index, stat in
            if index > 0 { Divider().padding(.horizontal, Theme.margin) }
            V3MuscleRow(
              muscle: stat.muscle, sets: stat.sets, floor: stat.floor, mrv: stat.mrv,
              scale: scale)
          }
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

  private var zoneLegend: some View {
    HStack(spacing: 8) {
      Capsule().fill(BodyV3.zone).frame(width: 28, height: 10)
      Text("Target range")
      Capsule()
        .fill(.mark(Theme.gradBrand, startPoint: .leading, endPoint: .trailing))
        .frame(width: 20, height: 10)
        .padding(.leading, 8)
      Text("Sets done")
    }
    .forge(14, .regular)
    .foregroundStyle(Theme.textSecondary)
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 10)
    .accessibilityElement(children: .combine)
  }

  private var axisRow: some View {
    GeometryReader { geo in
      let w = geo.size.width - Theme.margin * 2
      ZStack(alignment: .leading) {
        ForEach([0, 10, 20], id: \.self) { v in
          Text(verbatim: "\(v)")
            .forge(12, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .fixedSize()
            .offset(x: w * CGFloat(v / scale))
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .frame(height: 16)
    .accessibilityHidden(true)
  }
}
