import ForgeCore
import SwiftData
import SwiftUI

/// Balance of the last four weeks: push / pull / legs shares with the even-split line, the
/// row / pulldown split, and how often each muscle trains. White detail page with 8 pt
/// bands; every number comes from the analysis-eligible sets of the window.
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

  private var muscleDays: [Muscle: Int] { InsightsV3.muscleDays(sessions: recentSessions) }

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

  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(
          title: "Balance",
          subtitle: String(
            localized: "Last 4 weeks · \(recentSessions.count) session\(L10n.pluralSuffix(recentSessions.count))",
            bundle: L10n.bundle),
          art: "art-balance"
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)

        switch presentation {
        case .collecting:
          collectingContent
          LogBand().padding(.top, 24)
          basedOnSection
        case .assessed(let pushPull, _, _, _):
          InsightsVerdict(
            title: verdictTitle(pushPull: pushPull),
            line: verdictLine(pushPull: pushPull)
          )
          .padding(.horizontal, Theme.margin)
          .padding(.top, 20)
          LogBand().padding(.top, 24)
          sharesSection
          LogBand().padding(.top, 24)
          splitSection
          LogBand().padding(.top, 24)
          frequencySection
          LogBand().padding(.top, 24)
          basedOnSection
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation(String(localized: "Balance", bundle: L10n.bundle))
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: coach.name,
        onApprove: { VolumeApprovals.approve(increase) },
        onKeep: { VolumeApprovals.keep(increase) })
    }
  }

  // MARK: - verdict

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
          localized: "Push takes \(push) % of your sets, pull only \(pull) %.",
          bundle: L10n.bundle)
      }
      return String(
        localized: "Pull takes \(pull) % of your sets, push only \(push) %.", bundle: L10n.bundle)
    }
    return String(
      localized: "None is more than \(maxDeviation) points off an even split.",
      bundle: L10n.bundle)
  }

  // MARK: - share of your sets

  private var scaleMax: Double { max(40, (shares.values.max() ?? 0).rounded(.up)) }

  private var sharesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(title: "Share of your sets", minor: true)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)
      shareBars
        .padding(.horizontal, Theme.margin)
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  /// Bars with the dashed even-split line drawn across all three (mock `.shares`, `.even`).
  private var shareBars: some View {
    GeometryReader { geo in
      let labelWidth: CGFloat = 48
      let valueWidth: CGFloat = 52
      let gap: CGFloat = 12
      let barX = labelWidth + gap
      let barWidth = geo.size.width - barX - valueWidth - gap
      let evenX = barX + barWidth * CGFloat((100.0 / 3) / scaleMax)
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          shareRow(String(localized: "Push", bundle: L10n.bundle), shares[.push, default: 0])
          shareRow(String(localized: "Pull", bundle: L10n.bundle), shares[.pull, default: 0])
          shareRow(String(localized: "Legs", bundle: L10n.bundle), shares[.legs, default: 0])
        }
        Path { path in
          path.move(to: CGPoint(x: evenX, y: -4))
          path.addLine(to: CGPoint(x: evenX, y: 124))
        }
        .stroke(
          Theme.textSecondary,
          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        .opacity(0.7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .overlay(alignment: .topLeading) {
        Text(
          String(
            localized: "Even split, 33 %", bundle: L10n.bundle)
        )
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .fixedSize()
        .position(
          x: min(max(evenX, 34), geo.size.width - 34), y: 138)
        .accessibilityHidden(true)
      }
    }
    .frame(height: 156)
  }

  private func shareRow(_ name: String, _ share: Double) -> some View {
    HStack(spacing: 12) {
      Text(name)
        .forge(17, .semibold, tracking: -0.17)
        .foregroundStyle(Theme.text)
        .frame(width: 48, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule()
            .fill(.mark(Theme.gradBrand, startPoint: .leading, endPoint: .trailing))
            .frame(width: geo.size.width * CGFloat(min(1, share / scaleMax)))
        }
      }
      .frame(height: 12)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text("\(Int(share.rounded()))")
          .forge(17, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text("%")
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
      }
      .frame(width: 52, alignment: .trailing)
    }
    .frame(height: 40)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name) \(Int(share.rounded()))%")
  }

  // MARK: - rows and pulldowns

  private var splitSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Rows and pulldowns",
        trailing: String(
          localized: "\(Int(shares[.pull, default: 0].rounded())) % of sets", bundle: L10n.bundle)
      )
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 12)
      splitBar
        .padding(.horizontal, Theme.margin)
      Text(splitLine)
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 20)
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  /// One bar split by pull direction, with each side's share labelled.
  private var splitBar: some View {
    VStack(spacing: 0) {
      GeometryReader { geo in
        let total = max(1, rowSets + pulldownSets)
        HStack(spacing: 3) {
          Capsule()
            .fill(.mark(Theme.gradBrand, startPoint: .leading, endPoint: .trailing))
            .frame(width: geo.size.width * CGFloat(Double(rowSets) / Double(total)))
          Capsule()
            .fill(Theme.ramp[2])
        }
      }
      .frame(height: 12)
      HStack(alignment: .top) {
        HStack(spacing: 6) {
          GradientDot(colors: Theme.gradBrand)
          VStack(alignment: .leading, spacing: 1) {
            Text(
              String(
                localized: "Rows \(pullPercent(of: rowSets))%", bundle: L10n.bundle)
            )
            .forge(15, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            Text(String(localized: "Horizontal pull", bundle: L10n.bundle))
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 1) {
          HStack(spacing: 6) {
            Text(
              String(
                localized: "Pulldowns \(pullPercent(of: pulldownSets))%", bundle: L10n.bundle)
            )
            .forge(15, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            Circle().fill(Theme.ramp[2]).frame(width: 10, height: 10).accessibilityHidden(true)
          }
          Text(String(localized: "Vertical pull", bundle: L10n.bundle))
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      .padding(.top, 10)
    }
    .accessibilityElement(children: .combine)
  }

  /// Share of all pattern sets, the denominator the header uses.
  private func pullPercent(of sets: Int) -> Int {
    let total = counts.values.reduce(0, +)
    guard total > 0 else { return 0 }
    return Int((Double(sets) / Double(total) * 100).rounded())
  }

  /// "You row about 3 sets for every 2 pulldowns." — the reduced ratio of the two counts.
  private var splitLine: String {
    switch (rowSets, pulldownSets) {
    case (0, 0):
      return String(localized: "No pulling sets in the window.", bundle: L10n.bundle)
    case (0, _):
      return String(localized: "All your pulling is pulldowns.", bundle: L10n.bundle)
    case (_, 0):
      return String(localized: "All your pulling is rows.", bundle: L10n.bundle)
    case let (rows, downs):
      let gcd = Self.gcd(rows, downs)
      let a = rows / gcd
      let b = downs / gcd
      if a == b {
        return String(
          localized: "You row about as often as you pulldown.", bundle: L10n.bundle)
      }
      if b == 1 {
        return String(
          localized: "You row about \(a) sets for every pulldown.", bundle: L10n.bundle)
      }
      return String(
        localized: "You row about \(a) sets for every \(b) pulldowns.", bundle: L10n.bundle)
    }
  }

  private static func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
  }

  // MARK: - trained twice a week

  private var trainedMuscles: [Muscle] {
    muscleDays.keys.filter { (muscleDays[$0] ?? 0) > 0 }.sorted { $0.a11yName < $1.a11yName }
  }

  private var twiceMuscles: [Muscle] {
    trainedMuscles.filter { (muscleDays[$0] ?? 0) >= 2 }
  }

  private var onceMuscles: [Muscle] {
    trainedMuscles.filter { (muscleDays[$0] ?? 0) == 1 }
  }

  /// A pending change that would give a once-a-week muscle its second day.
  private var reviewableIncrease: VolumeIncrease? {
    pendingIncreases.first { onceMuscles.contains($0.muscle) }
  }

  private var frequencySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(
        title: "Trained twice a week",
        trailing: "\(twiceMuscles.count) of \(trainedMuscles.count)"
      )
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 12)
      HStack(spacing: 28) {
        MuscleFigure(side: .front, tint: frequencyTint)
        MuscleFigure(side: .back, tint: frequencyTint)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 200)
      .padding(.horizontal, Theme.margin)
      HStack(spacing: 20) {
        legendSwatch(Theme.accent, String(localized: "2 or more days", bundle: L10n.bundle))
        legendSwatch(Theme.ramp[2], String(localized: "1 day", bundle: L10n.bundle))
      }
      .padding(.top, 14)
      Text(frequencyLine)
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 20)
      if let increase = reviewableIncrease {
        Button {
          approving = increase
        } label: {
          HStack(spacing: 2) {
            Text(String(localized: "Review \(coach.name)'s change", bundle: L10n.bundle))
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
          }
          .forge(16, .medium)
          .foregroundStyle(Theme.accentText)
          .frame(minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, Theme.margin)
        .padding(.top, 2)
      }
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  private func frequencyTint(_ muscle: Muscle) -> Color? {
    guard let days = muscleDays[muscle], days > 0 else { return nil }
    return days >= 2 ? Theme.accent : Theme.ramp[2]
  }

  private func legendSwatch(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
        .accessibilityHidden(true)
      Text(label)
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
    }
  }

  private var frequencyLine: String {
    if onceMuscles.isEmpty {
      return String(
        localized: "Every trained muscle gets two or more days a week.", bundle: L10n.bundle)
    }
    let names = onceMuscles.map(\.a11yName).joined(separator: ", ")
    if let increase = reviewableIncrease {
      return String(
        localized:
          "\(names) train one day a week. \(coach.name)'s \(increase.exercise.localizedName) +1 set would add a second day.",
        bundle: L10n.bundle)
    }
    return String(
      localized: "\(names) train one day a week.", bundle: L10n.bundle)
  }

  // MARK: - collecting & basis

  private var collectingContent: some View {
    VStack(alignment: .leading, spacing: 6) {
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
    .padding(.horizontal, Theme.margin)
    .padding(.top, 20)
    .padding(.bottom, 20)
  }

  private var basedOnSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(title: "What this is based on")
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        basedRow(
          symbol: "calendar", tint: Theme.metricLoad,
          title: basisTitle,
          detail: String(
            localized:
              "Balance needs \(BalancePresentationPolicy.minimumSessions) sessions and \(BalancePresentationPolicy.minimumSets) sets to judge",
            bundle: L10n.bundle))
        Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 44)
        basedRow(
          symbol: "checkmark", tint: Theme.accent,
          title: String(localized: "Working sets only", bundle: L10n.bundle),
          detail: String(
            localized: "Warm-ups and left-out sets do not count", bundle: L10n.bundle))
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  private var basisTitle: String {
    let dates = recentSessions.map(\.date).sorted()
    let head = dates.first?.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)) ?? ""
    let tail = dates.last?.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)) ?? ""
    return String(
      localized: "\(recentSessions.count) sessions, \(head) to \(tail)", bundle: L10n.bundle)
  }

  private func basedRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
    HStack(spacing: 12) {
      LogIconBadge(symbol: symbol, tint: tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .forge(17, .semibold, tracking: -0.17)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
        Text(detail)
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 60)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }
}
