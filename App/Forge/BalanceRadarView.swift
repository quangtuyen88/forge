import ForgeCore
import SwiftData
import SwiftUI

/// Balance of the last four weeks: push / pull / legs shares on the peach field, the
/// row / pulldown split, and how often each muscle trains. Every number comes from the
/// analysis-eligible sets of the window.
struct BalanceRadarView: View {
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @Query private var checkIns: [CheckIn]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var approving: VolumeIncrease?

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }

  /// The same predicate Progress and History use. Counting a session Balance cannot read
  /// sets from is what made "2 eligible sessions · 1 eligible set" possible.
  private var recentSessions: [WorkoutSession] {
    sessions.filter { $0.date > Date.now.addingTimeInterval(-28 * 86400) }
      .analysisEligibleSessions
  }

  private var sets: [LoggedSet] { recentSessions.flatMap(\.trustedSets) }

  private var counts: [Pattern: Int] {
    var out: [Pattern: Int] = [:]
    for set in sets {
      guard let exercise = ExerciseDB.find(set.exerciseID) else { continue }
      switch exercise.pattern {
      case .horizontalPush, .verticalPush: out[.push, default: 0] += 1
      case .horizontalPull, .verticalPull: out[.pull, default: 0] += 1
      case .squat, .hinge: out[.legs, default: 0] += 1
      default: break
      }
    }
    return out
  }

  private enum Pattern { case push, pull, legs }

  private var shares: [Pattern: Double] {
    let total = Double(counts.values.reduce(0, +))
    guard total > 0 else { return [:] }
    return counts.mapValues { Double($0) / total * 100 }
  }

  private var rowSets: Int { sets.filter { ExerciseDB.find($0.exerciseID)?.pattern == .horizontalPull }.count }
  private var pulldownSets: Int {
    sets.filter { ExerciseDB.find($0.exerciseID)?.pattern == .verticalPull }.count
  }

  private var presentation: BalancePresentation {
    let push = Double(counts[.push, default: 0])
    let pull = Double(counts[.pull, default: 0])
    let legs = Double(counts[.legs, default: 0])
    return BalancePresentationPolicy.presentation(
      push: push,
      pull: pull,
      upper: push + pull,
      lower: legs,
      sessionCount: recentSessions.count,
      setCount: sets.count)
  }

  /// Increases still waiting for the lifter's OK; approved ones no longer wait.
  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
      .filter { $0.answer == nil }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        switch presentation {
        case .collecting:
          FieldSection(bottom: 20) {
            collectingContent
              .padding(.top, 4)
          }
          VStack(spacing: 0) {
            basedOnSection
          }
          .background(Theme.page)
        case .assessed(let pushPull, _, _, _):
          FieldSection(bottom: 20) {
            fieldContent(pushPull: pushPull)
          }
          VStack(spacing: 0) {
            splitSection
            frequencySection
            basedOnSection
          }
          .background(Theme.page)
        }
      }
      .padding(.bottom, 24)
    }
    .progressFieldPage(String(localized: "Balance", bundle: L10n.bundle))
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  // MARK: - field

  /// The v6 field: headline verdict, share note, the three-segment bar and the three shares.
  private func fieldContent(pushPull: Double?) -> some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topTrailing) {
        VStack(alignment: .leading, spacing: 8) {
          Text(headline(pushPull: pushPull))
            .forge(28, .bold, tracking: -0.5)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 76)
            .accessibilityAddTraits(.isHeader)
          Text(headlineLine(pushPull: pushPull))
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image("art-balance")
          .resizable()
          .scaledToFit()
          .frame(width: 64, height: 64)
          .offset(y: -6)
          .accessibilityHidden(true)
      }
      .padding(.top, 4)
      shareBar
        .padding(.top, 16)
      HStack(alignment: .top, spacing: 16) {
        shareStat(String(localized: "Push", bundle: L10n.bundle), shares[.push, default: 0], color: Theme.ramp[4])
        shareStat(String(localized: "Pull", bundle: L10n.bundle), shares[.pull, default: 0], color: Theme.ramp[3])
        shareStat(String(localized: "Legs", bundle: L10n.bundle), shares[.legs, default: 0], color: Theme.ramp[2])
      }
      .padding(.top, 12)
    }
  }

  /// True when all three shares sit within 5 points of an even third.
  private var isEven: Bool {
    guard !shares.isEmpty else { return false }
    return shares.values.allSatisfy { abs($0 - 100.0 / 3) <= 5 }
  }

  /// The field headline: the even rule first, otherwise the existing push/pull verdicts.
  private func headline(pushPull: Double?) -> String {
    if isEven {
      return String(localized: "Push, pull and legs are even.", bundle: L10n.bundle)
    }
    return verdictTitle(pushPull: pushPull)
  }

  /// The field note: the deviation caption when even, otherwise the existing verdict line.
  private func headlineLine(pushPull: Double?) -> String {
    if isEven {
      return String(
        localized: "Share of your working sets, last 4 weeks. None is more than \(maxDeviation) points off a third.",
        bundle: L10n.bundle)
    }
    return verdictLine(pushPull: pushPull)
  }

  /// The same ratio the previous screen judged by (0.75–1.35 push:pull stays balanced).
  private func verdictTitle(pushPull: Double?) -> String {
    guard let ratio = pushPull else {
      return String(localized: "One side has no sets yet.", bundle: L10n.bundle)
    }
    if ratio > 1.35 {
      return String(localized: "Your training leans push.", bundle: L10n.bundle)
    }
    if ratio < 0.75 {
      return String(localized: "Your training leans pull.", bundle: L10n.bundle)
    }
    return String(localized: "Your training is balanced.", bundle: L10n.bundle)
  }

  private var maxDeviation: Int {
    let even = 100.0 / 3
    return shares.values.map { abs($0 - even) }.max().map { Int($0.rounded()) } ?? 0
  }

  private func verdictLine(pushPull: Double?) -> String {
    guard let ratio = pushPull, 0.75...1.35 ~= ratio else {
      let push = Int(shares[.push, default: 0].rounded())
      let pull = Int(shares[.pull, default: 0].rounded())
      if push > pull {
        return String(
          localized: "Push takes \(push)\u{00A0}% of your sets, pull only \(pull)\u{00A0}%.",
          bundle: L10n.bundle)
      }
      return String(
        localized: "Pull takes \(pull)\u{00A0}% of your sets, push only \(push)\u{00A0}%.", bundle: L10n.bundle)
    }
    return String(
      localized: "None is more than \(maxDeviation) points off an even split.",
      bundle: L10n.bundle)
  }

  /// The three shares as one 14 pt bar: ramp fills, 2 pt gaps, capsule ends outside only.
  private var shareBar: some View {
    GeometryReader { geo in
      let usable = max(0, geo.size.width - 4)
      HStack(spacing: 2) {
        if shares[.push, default: 0] > 0 {
          Capsule()
            .fill(Theme.ramp[4])
            .frame(width: usable * shares[.push, default: 0] / 100)
        }
        if shares[.pull, default: 0] > 0 {
          Capsule()
            .fill(Theme.ramp[3])
            .frame(width: usable * shares[.pull, default: 0] / 100)
        }
        if shares[.legs, default: 0] > 0 {
          Capsule()
            .fill(Theme.ramp[2])
        }
      }
    }
    .frame(height: 14)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(shareBarLabel)
  }

  private var shareBarLabel: String {
    let push = Int(shares[.push, default: 0].rounded())
    let pull = Int(shares[.pull, default: 0].rounded())
    let legs = Int(shares[.legs, default: 0].rounded())
    return String(
      localized: "Push \(push) %, Pull \(pull) %, Legs \(legs) %", bundle: L10n.bundle)
  }

  /// One share column: quiet label over a 28-bold value with the % tail.
  private func shareStat(_ label: String, _ share: Double, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 8, height: 8)
          .accessibilityHidden(true)
        Text(label)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text("\(Int(share.rounded()))")
          .forge(28, .bold, tracking: -0.56)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text("%")
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  // MARK: - rows and pulldowns

  private var splitSection: some View {
    let note = splitNote
    return VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Rows and pulldowns",
        trailing: String(
          localized: "\(Int(shares[.pull, default: 0].rounded()))\u{00A0}% of sets", bundle: L10n.bundle)
      )
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      VStack(spacing: 0) {
        pullRow(
          title: String(localized: "Rows", bundle: L10n.bundle),
          direction: String(localized: "Horizontal pull", bundle: L10n.bundle),
          pattern: .horizontalPull)
        rowDivider(leading: 56)
        pullRow(
          title: String(localized: "Pulldowns", bundle: L10n.bundle),
          direction: String(localized: "Vertical pull", bundle: L10n.bundle),
          pattern: .verticalPull)
      }
      .padding(.horizontal, Theme.margin)
      if !note.isEmpty {
        Text(note)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 10)
      }
    }
    .padding(.bottom, 20)
  }

  /// One pull-direction row: the group's top exercise token, its name list and share.
  private func pullRow(title: String, direction: String, pattern: MovementPattern) -> some View {
    let exercises = pullExercises(pattern)
    let names = exercises.map(\.localizedName).joined(separator: ", ")
    return HStack(spacing: 12) {
      LiftToken(exercise: exercises.first, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Text("\(direction) · \(names)")
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text("\(pullPercent(of: pattern == .horizontalPull ? rowSets : pulldownSets))")
          .forge(15, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text("%")
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }

  /// Exercises of one pull direction in the window, most-used first.
  private func pullExercises(_ pattern: MovementPattern) -> [Exercise] {
    var counts: [String: (exercise: Exercise, sets: Int)] = [:]
    for set in sets {
      guard let exercise = ExerciseDB.find(set.exerciseID), exercise.pattern == pattern
      else { continue }
      counts[exercise.id, default: (exercise, 0)].sets += 1
    }
    return counts.values.sorted { $0.sets > $1.sets }.map(\.exercise)
  }

  /// Share of all pattern sets, the denominator the header uses.
  private func pullPercent(of sets: Int) -> Int {
    let total = counts.values.reduce(0, +)
    guard total > 0 else { return 0 }
    return Int((Double(sets) / Double(total) * 100).rounded())
  }

  /// The rows/pulldowns ratio as the closest small integers, b no larger than 4.
  private func rowRatio(_ rows: Int, _ downs: Int) -> (a: Int, b: Int)? {
    guard rows > 0, downs > 0 else { return nil }
    let ratio = Double(rows) / Double(downs)
    var best: (a: Int, b: Int, error: Double) = (1, 1, .infinity)
    for b in 1...4 {
      let a = max(1, Int((ratio * Double(b)).rounded()))
      let error = abs(ratio - Double(a) / Double(b))
      if error < best.error { best = (a, b, error) }
    }
    return (best.a, best.b)
  }

  /// The pull lift the next block would add, with its block number and join date.
  private var joinLift: (lift: Exercise, block: Int, dateText: String)? {
    guard let profile,
      let lift = LogV3.nextBlockNewLifts(sessions: sessions, profile: profile)
        .first(where: { $0.pattern == .verticalPull || $0.pattern == .horizontalPull })
    else { return nil }
    let date = LogV3.nextBlockStart(profile: profile, sessions: sessions)
    let block = InsightsV3.blockNumber(of: date, sessions: sessions, profile: profile)
    return (lift, block, date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
  }

  /// The small-integer ratio note, plus the pull lift that joins the next block.
  private var splitNote: String {
    var note = ""
    if let ratio = rowRatio(rowSets, pulldownSets) {
      note =
        ratio.a == 1 && ratio.b == 1
        ? String(localized: "You row about as often as you pulldown.", bundle: L10n.bundle)
        : String(
          localized: "About \(ratio.a) row sets for every \(ratio.b) pulldown sets.",
          bundle: L10n.bundle)
    }
    if let join = joinLift {
      let clause = String(
        localized: "\(join.lift.localizedName) joins with Block \(join.block) on \(join.dateText).",
        bundle: L10n.bundle)
      note = note.isEmpty ? clause : note + " " + clause
    }
    return note
  }

  // MARK: - trained twice a week

  private struct FrequencyStat {
    let muscle: Muscle
    let average: Double
  }

  /// Direct (primary-muscle) training days per reporting week, averaged over trained weeks.
  private var frequencyStats: [FrequencyStat] {
    let cal = TrainingMetrics.reportingCalendar()
    let weeks = Dictionary(grouping: recentSessions) {
      TrainingMetrics.reportingWeek(containing: $0.date, calendar: cal).start
    }
    guard !weeks.isEmpty else { return [] }
    var dayTotals: [Muscle: Int] = [:]
    for weekSessions in weeks.values {
      var days: [Muscle: Set<Date>] = [:]
      for session in weekSessions {
        let day = Calendar.current.startOfDay(for: session.date)
        for set in session.trustedSets {
          guard let exercise = ExerciseDB.find(set.exerciseID) else { continue }
          days[exercise.primary, default: []].insert(day)
        }
      }
      for (muscle, trained) in days { dayTotals[muscle, default: 0] += trained.count }
    }
    let weekCount = Double(weeks.count)
    return dayTotals
      .map { FrequencyStat(muscle: $0.key, average: Double($0.value) / weekCount) }
      .sorted { $0.muscle.a11yName < $1.muscle.a11yName }
  }

  private var frequencySection: some View {
    let stats = frequencyStats
    let under = stats.filter { $0.average < 1.5 }
    return VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Trained twice a week",
        trailing: String(
          localized: "\(stats.count - under.count) of \(stats.count)", bundle: L10n.bundle)
      )
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      Text(String(localized: "Muscle groups worked on 2 or more days a week.", bundle: L10n.bundle))
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 6)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(under.enumerated()), id: \.element.muscle) { index, stat in
          underRow(stat)
          if index < under.count - 1 || stats.count > under.count { rowDivider(leading: 56) }
        }
        if stats.count > under.count {
          othersRow(stats.filter { $0.average >= 1.5 })
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
  }

  /// A muscle under twice a week, with its pending second-day ask when one waits.
  private func underRow(_ stat: FrequencyStat) -> some View {
    let increase = pendingIncreases.first { $0.muscle == stat.muscle }
    return HStack(spacing: 12) {
      MuscleRegionThumb(muscle: stat.muscle)
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.muscle.a11yName)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        underSubtitle(stat, increase: increase)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if let increase {
        ReviewPill(
          accessibilityLabel: String(
            localized: "Review \(increase.muscle.a11yName) change", bundle: L10n.bundle),
          action: { approving = increase })
      }
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: increase == nil ? .combine : .contain)
  }

  /// The frequency fact, plus the pending ask that would add the second day.
  private func underSubtitle(_ stat: FrequencyStat, increase: VolumeIncrease?) -> Text {
    let base =
      stat.average < 1
      ? String(localized: "Less than once a week", bundle: L10n.bundle)
      : String(localized: "Once a week", bundle: L10n.bundle)
    var text = Text(base)
    if let increase {
      let added = increase.toSets - increase.fromSets
      text = text + Text(" · ") + Text(
        String(
          localized: "\(coach.name)'s \(added) set\(L10n.pluralSuffix(added)) in \(localizedDayName(increase.dayName)) add a second day.",
          bundle: L10n.bundle))
    }
    return text
  }

  /// The muscles already at twice a week, folded into one row with their names.
  private func othersRow(_ others: [FrequencyStat]) -> some View {
    let names = others.map { $0.muscle.a11yName }
      .formatted(.list(type: .and).locale(L10n.locale))
    return HStack(spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .scaledSystemFont(22, weight: .semibold)
        .foregroundStyle(Theme.positive)
        .frame(width: 44)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "The other \(others.count)", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Text(names)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }

  /// The hairline between rows of one section, starting past the leading icon.
  private func rowDivider(leading: CGFloat) -> some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, leading)
  }

  // MARK: - collecting & basis

  private var collectingContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Collecting balance evidence")
        .forge(22, .semibold, tracking: -0.33)
        .foregroundStyle(Theme.text)
      Text(
        String(
          localized:
            "Balance needs \(BalancePresentationPolicy.minimumSessions) sessions and \(BalancePresentationPolicy.minimumSets) sets to judge. You have \(recentSessions.count) session\(L10n.pluralSuffix(recentSessions.count)) and \(sets.count) set\(L10n.pluralSuffix(sets.count)) so far.",
          bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 4)
  }

  private var basedOnSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(title: "What this is based on")
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(alignment: .leading, spacing: 0) {
        basedRow(
          symbol: "calendar",
          tint: Theme.metricTime,
          title: basisTitle,
          detail: basisWindowLine)
        rowDivider(leading: 56)
        basedRow(
          symbol: "checkmark.circle.fill",
          tint: Theme.positive,
          title: String(localized: "Working sets only", bundle: L10n.bundle),
          detail: String(localized: "Warm-ups and left-out sets do not count", bundle: L10n.bundle))
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 20)
  }

  private var basisTitle: String {
    let dates = recentSessions.map(\.date).sorted()
    let head = dates.first?.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)) ?? ""
    let tail = dates.last?.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)) ?? ""
    return String(
      localized: "\(recentSessions.count) sessions, \(head) to \(tail)", bundle: L10n.bundle)
  }

  /// "The last 4 weeks", plus the deload count when the window holds deload sessions.
  private var basisWindowLine: String {
    let deloads = recentSessions.filter { $0.week == Mesocycle.deloadWeek }.count
    if deloads > 0 {
      return String(
        localized: "The last 4 weeks, \(deloads) deload sessions included", bundle: L10n.bundle)
    }
    return String(localized: "The last 4 weeks", bundle: L10n.bundle)
  }

  /// One basis row: bare metric-coloured glyph, title, quiet subtitle.
  private func basedRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .scaledSystemFont(22, weight: .semibold)
        .foregroundStyle(tint)
        .frame(width: 44)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
        Text(detail)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .accessibilityElement(children: .combine)
  }
}
