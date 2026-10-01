import ForgeCore
import SwiftData
import SwiftUI

/// Every lift's trend in one scan: which lifts are moving and which are stuck.
struct ProgressTrendsView: View {
  let usesLb: Bool

  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var range: TrendRange = .all
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    let data = ProgressData(sessions: sessions, profile: profile)
    return ScrollView {
      if data.liftTrends.isEmpty {
        FieldSection(bottom: 32) { emptyStrength }
      } else {
        let groups = BodyArea.allCases.compactMap { area -> (BodyArea, [LiftTrend])? in
          let rows = self.rows(for: area, data: data)
          return rows.isEmpty ? nil : (area, rows)
        }
        let scale = TrendsScale(
          rowPercents: groups.flatMap(\.1).compactMap { Self.percent($0, in: range) })
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
          FieldSection(bottom: 20) { hero(data) }
          Section(header: scaleHeader(scale)) {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
              groupBlock(
                group.0, rows: group.1, scale: scale, data: data,
                isFirst: i == 0, isLast: i == groups.count - 1)
            }
            footnote
          }
        }
      }
    }
    .progressFieldPage(String(localized: "Trends", bundle: L10n.bundle))
  }

  private var emptyStrength: some View {
    VStack(spacing: 8) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No lifts yet").forgeSection()
      Text("Finish a workout to see your e1RM trend.")
        .forgeLabel()
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  // MARK: hero

  private func hero(_ data: ProgressData) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      heroSentence(data)
        .forge(28, .bold, tracking: -0.5)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("trends.summary")
      HStack(spacing: 16) {
        legend(data)
        Spacer(minLength: 16)
        if data.currentBlock >= 2 {
          rangePicker(data)
        }
      }
    }
  }

  @ViewBuilder
  private func heroSentence(_ data: ProgressData) -> some View {
    let counts = summaryCounts(data)
    switch range {
    case .all:
      let month = (data.strengthSince ?? .now)
        .formatted(.dateTime.month(.wide).locale(L10n.locale))
      Text(
        String(
          localized: "\(counts.stronger) of your \(counts.compared) lifts got stronger since \(month).",
          bundle: L10n.bundle))
    case .block(let n):
      Text(
        String(
          localized: "\(counts.stronger) of your \(counts.compared) lifts got stronger in Block \(n).",
          bundle: L10n.bundle))
    }
  }

  private func summaryCounts(_ data: ProgressData) -> (stronger: Int, compared: Int) {
    var stronger = 0
    var compared = 0
    for trend in data.liftTrends {
      switch trend.status(in: range) {
      case .stronger: stronger += 1; compared += 1
      case .holding, .dipped: compared += 1
      case nil: break
      }
    }
    return (stronger, compared)
  }

  private func legend(_ data: ProgressData) -> some View {
    HStack(spacing: 16) {
      HStack(spacing: 6) {
        Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5).frame(width: 13, height: 13)
        Text(verbatim: startLabel(data))
      }
      HStack(spacing: 6) {
        Circle().fill(Theme.accent).frame(width: 10, height: 10)
        Text("Now")
      }
    }
    .forge(15, .regular)
    .foregroundStyle(Theme.textSecondary)
    .accessibilityHidden(true)
  }

  private func startLabel(_ data: ProgressData) -> String {
    switch range {
    case .all:
      return (data.strengthSince ?? .now)
        .formatted(.dateTime.month(.abbreviated).locale(L10n.locale))
    case .block(let n):
      return String(localized: "Block \(n) start", bundle: L10n.bundle)
    }
  }

  private func rangePicker(_ data: ProgressData) -> some View {
    Picker("Range", selection: $range) {
      Text(String(localized: "Block \(data.currentBlock)", bundle: L10n.bundle))
        .tag(TrendRange.block(data.currentBlock))
      Text("All").tag(TrendRange.all)
    }
    .pickerStyle(.segmented)
    .fixedSize()
    .accessibilityIdentifier("trends.range")
  }

  // MARK: groups

  private func scaleHeader(_ scale: TrendsScale) -> some View {
    HStack(spacing: 12) {
      Color.clear.frame(width: 132)
      TrendsScaleTicks(scale: scale)
      Color.clear.frame(width: 64)
    }
    .padding(.horizontal, Theme.margin)
    .frame(height: 32)
    .frame(maxWidth: .infinity)
    .background(Theme.page)
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.ring).frame(height: 1) }
    .accessibilityHidden(true)
  }

  private func groupBlock(
    _ area: BodyArea, rows: [LiftTrend], scale: TrendsScale, data: ProgressData,
    isFirst: Bool, isLast: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      groupHeader(area, rows: rows, topPadding: isFirst ? 8 : 16)
      ForEach(rows) { trend in
        NavigationLink {
          LiftDetailView(exercise: trend.exercise, data: data, usesLb: usesLb)
        } label: {
          row(trend, scale: scale)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("trends.row.\(trend.exercise.id)")
      }
      Rectangle().fill(Theme.ring).frame(height: 1).padding(.horizontal, Theme.margin)
      if !isLast {
        Color.clear.frame(height: 24)
      }
    }
    .background(Theme.page)
  }

  private func groupHeader(_ area: BodyArea, rows: [LiftTrend], topPadding: CGFloat) -> some View {
    let up = rows.filter { $0.status(in: range) == .stronger }.count
    let change = groupChange(rows)
    return HStack(spacing: 12) {
      ArtThumb(name: Coach.from(coachID).scene(area.scene), size: 36)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: area.shortTitle).forge(20, .semibold).foregroundStyle(Theme.text)
        Text(String(localized: "\(up) of \(rows.count) stronger", bundle: L10n.bundle))
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Spacer(minLength: 12)
      groupChangeText(change)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, topPadding)
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityLabel(
      Text(
        String(
          localized: "\(area.shortTitle), \(up) of \(rows.count) stronger, \(groupChangeString(change))",
          bundle: L10n.bundle)))
  }

  private func groupChange(_ rows: [LiftTrend]) -> Int {
    let pcts = rows.compactMap { Self.percent($0, in: range) }
    let mean = pcts.isEmpty ? 0 : pcts.reduce(0, +) / Double(pcts.count)
    return Int(mean.rounded())
  }

  private func groupChangeString(_ n: Int) -> String {
    if n >= 1 { return "+\(n) %" }
    if n <= -1 { return "\u{2212}\(abs(n)) %" }
    return String(localized: "Holding", bundle: L10n.bundle)
  }

  @ViewBuilder
  private func groupChangeText(_ n: Int) -> some View {
    if n == 0 {
      Text("Holding").forge(17, .regular).foregroundStyle(Theme.textSecondary)
    } else {
      Text(verbatim: groupChangeString(n))
        .forge(20, .semibold)
        .foregroundStyle(n > 0 ? Theme.positiveText : Theme.textSecondary)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private func row(_ trend: LiftTrend, scale: TrendsScale) -> some View {
    let isLb = profile?.isLb(for: trend.exercise.id) ?? usesLb
    let pct = Self.percent(trend, in: range)
    let recordFresh =
      trend.latestIsRecord && trend.latest.date > Date.now.addingTimeInterval(-7 * 86400)
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          Text(trend.exercise.localizedName)
            .forge(17, .regular)
            .foregroundStyle(Theme.text)
            .lineLimit(2)
          TrendsDotRow(
            scale: scale, percent: pct, status: trend.status(in: range),
            recordFresh: recordFresh)
            .frame(height: 44)
          valueColumn(trend, isLb: isLb)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(spacing: 12) {
          Text(trend.exercise.localizedName)
            .forge(17, .regular)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 132, alignment: .leading)
          TrendsDotRow(
            scale: scale, percent: pct, status: trend.status(in: range),
            recordFresh: recordFresh)
            .frame(height: 44)
          valueColumn(trend, isLb: isLb)
            .frame(width: 64, alignment: .trailing)
        }
      }
    }
    .padding(.horizontal, Theme.margin)
    .frame(minHeight: 44)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: trend.exercise.localizedName))
    .accessibilityValue(
      Text(verbatim: rowValue(trend, isLb: isLb, percent: pct, recordFresh: recordFresh)))
    .accessibilityChartDescriptor(
      TrendsDotDescriptor(liftName: trend.exercise.localizedName, percent: pct))
  }

  @ViewBuilder
  private func valueColumn(_ trend: LiftTrend, isLb: Bool) -> some View {
    let status = trend.status(in: range)
    let text = TrendChangeText.label(changeKg: trend.changeKg(in: range), isLb: isLb)
    if text.isEmpty {
      Text("—")
        .forge(17, .regular)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    } else {
      Text(verbatim: text)
        .forge(17, status == .holding ? .regular : .medium)
        .foregroundStyle(status == .stronger ? Theme.text : Theme.textSecondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  private func rowValue(_ trend: LiftTrend, isLb: Bool, percent: Double?, recordFresh: Bool)
    -> String
  {
    var value = TrendChangeText.label(changeKg: trend.changeKg(in: range), isLb: isLb)
    if value.isEmpty {
      value = String(localized: "Not enough workouts yet", bundle: L10n.bundle)
    }
    if let percent {
      value += String(localized: ", \(Int(percent.rounded())) percent", bundle: L10n.bundle)
    }
    if recordFresh {
      value += String(localized: ", new record", bundle: L10n.bundle)
    }
    return value
  }

  /// Row percent = change over the range / first e1RM in the range. Nil when there is
  /// nothing to compare.
  static func percent(_ trend: LiftTrend, in range: TrendRange) -> Double? {
    guard
      let change = trend.changeKg(in: range),
      let first = trend.workouts(in: range).first,
      first.e1rmKg > 0
    else { return nil }
    return change / first.e1rmKg * 100
  }

  private func rows(for area: BodyArea, data: ProgressData) -> [LiftTrend] {
    data.liftTrends
      .filter { $0.area == area && !$0.workouts(in: range).isEmpty }
      .sorted { a, b in
        let left = a.changeKg(in: range)
        let right = b.changeKg(in: range)
        switch (left, right) {
        case let (l?, r?):
          return l == r ? a.exercise.localizedName < b.exercise.localizedName : l > r
        case (nil, nil): return a.exercise.localizedName < b.exercise.localizedName
        case (nil, _): return false
        default: return true
        }
      }
  }

  private var footnote: some View {
    Text("Estimated max from your best set each workout.")
      .forge(13, .regular)
      .foregroundStyle(Theme.textSecondary)
      .padding(.horizontal, Theme.margin)
      .padding(.top, 12)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.page)
  }
}
