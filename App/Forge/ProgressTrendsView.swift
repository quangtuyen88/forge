import Charts
import ForgeCore
import SwiftData
import SwiftUI

/// Every lift's trend in one scan: which lifts are moving and which are stuck.
struct ProgressTrendsView: View {
  let usesLb: Bool

  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var area: BodyArea?
  @State private var range: TrendRange = .all
  @AppStorage("trendsSort") private var sort = "change"
  @State private var chartWindowWeeks = 8

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    let data = ProgressData(sessions: sessions, profile: profile)
    return ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if data.liftTrends.isEmpty {
          SkyCard { emptyStrength }
        } else {
          summaryCard(data)
          controls(data)
          ForEach(BodyArea.allCases) { sectionArea in
            if area == nil || area == sectionArea {
              let rows = self.rows(for: sectionArea, data: data)
              if !rows.isEmpty {
                section(sectionArea, rows: rows, data: data)
              }
            }
          }
        }
        weeklySetsCard
        volumeLoadCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationTitle("Trends")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { sortMenu } }
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort", selection: $sort) {
        Text("Biggest change").tag("change")
        Text("Name").tag("name")
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down")
    }
    .accessibilityLabel("Sort")
    .accessibilityIdentifier("trends.sort")
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

  private func summaryCard(_ data: ProgressData) -> some View {
    var stronger = 0
    var holding = 0
    var dipped = 0
    for trend in data.liftTrends {
      switch trend.status(in: range) {
      case .stronger: stronger += 1
      case .holding: holding += 1
      case .dipped: dipped += 1
      case nil: break
      }
    }
    let compared = stronger + holding + dipped
    return SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 12) {
          Text(summaryLabel(data))
            .forge(15, .semibold)
            .foregroundStyle(Theme.textSecondary)
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(stronger)")
              .forge(56, .bold)
              .foregroundStyle(Theme.accent)
              .monospacedDigit()
            Text(String(localized: "of \(compared) stronger", bundle: L10n.bundle))
              .forge(20, .semibold)
              .foregroundStyle(Theme.textSecondary)
          }
          statusBar(stronger: stronger, holding: holding, dipped: dipped)
          HStack(spacing: 16) {
            legendItem(color: Theme.accent, label: String(localized: "\(stronger) stronger", bundle: L10n.bundle))
            legendItem(color: Theme.track, label: String(localized: "\(holding) holding", bundle: L10n.bundle))
            legendItem(color: Theme.textTertiary, label: String(localized: "\(dipped) dipped", bundle: L10n.bundle))
          }
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trends.summary")
        if data.currentBlock >= 2 {
          Picker("Range", selection: $range) {
            Text(String(localized: "Block \(data.currentBlock)", bundle: L10n.bundle))
              .tag(TrendRange.block(data.currentBlock))
            Text("All").tag(TrendRange.all)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("trends.range")
        }
      }
    }
  }

  private func summaryLabel(_ data: ProgressData) -> String {
    if case .block(let n) = range {
      return String(localized: "Estimated max in Block \(n)", bundle: L10n.bundle)
    }
    let month = (data.liftTrends.compactMap { $0.workouts.first?.date }.min() ?? .now)
      .formatted(.dateTime.month(.wide).locale(L10n.locale))
    return String(localized: "Estimated max since \(month)", bundle: L10n.bundle)
  }

  private func statusBar(stronger: Int, holding: Int, dipped: Int) -> some View {
    let compared = stronger + holding + dipped
    return Group {
      if compared <= 24 {
        HStack(spacing: 3) {
          ForEach(0..<compared, id: \.self) { i in
            Capsule()
              .fill(
                i < stronger ? Theme.accent
                  : (i < stronger + holding ? Theme.track : Theme.textTertiary))
              .frame(maxWidth: .infinity)
              .frame(height: 10)
          }
        }
      } else {
        GeometryReader { geo in
          HStack(spacing: 0) {
            Capsule()
              .fill(Theme.accent)
              .frame(width: geo.size.width * Double(stronger) / Double(compared))
            Capsule()
              .fill(Theme.track)
              .frame(width: geo.size.width * Double(holding) / Double(compared))
            Capsule()
              .fill(Theme.textTertiary)
              .frame(width: geo.size.width * Double(dipped) / Double(compared))
          }
        }
        .frame(height: 10)
      }
    }
    .accessibilityHidden(true)
  }

  private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(label)
    }
  }

  private func controls(_ data: ProgressData) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        filterChip(String(localized: "All", bundle: L10n.bundle), value: nil)
        ForEach(
          BodyArea.allCases.filter { listArea in data.liftTrends.contains { $0.area == listArea } }
        ) { listArea in
          filterChip(listArea.shortTitle, value: listArea)
        }
      }
    }
  }

  private func filterChip(_ title: String, value: BodyArea?) -> some View {
    Button {
      area = value
    } label: {
      Text(title)
        .forge(15, .semibold)
        .foregroundStyle(value == area ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(value == area ? Theme.accent : Theme.card))
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .accessibilityAddTraits(value == area ? .isSelected : [])
    .accessibilityIdentifier("trends.filter.\(value?.rawValue ?? "all")")
  }

  private func rows(for area: BodyArea, data: ProgressData) -> [LiftTrend] {
    let scoped = data.liftTrends.filter { $0.area == area && !$0.workouts(in: range).isEmpty }
    switch sort {
    case "name":
      return scoped.sorted { $0.exercise.localizedName < $1.exercise.localizedName }
    default:
      return scoped.sorted { a, b in
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
  }

  private func section(_ area: BodyArea, rows: [LiftTrend], data: ProgressData) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(area.title).forgeSection().accessibilityAddTraits(.isHeader)
      SkyCard(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { i, trend in
            if i > 0 { Divider().padding(.leading, 76) }
            NavigationLink {
              LiftDetailView(exercise: trend.exercise, data: data, usesLb: usesLb)
            } label: {
              row(trend)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("trends.row.\(trend.exercise.id)")
          }
        }
      }
    }
  }

  private func row(_ trend: LiftTrend) -> some View {
    let window = trend.workouts(in: range)
    let isLb = profile?.isLb(for: trend.exercise.id) ?? usesLb
    let latest = Fmt.num(lbValue(trend.latest.e1rmKg, id: trend.exercise.id).rounded())
    return HStack(spacing: 12) {
      LiftToken(exercise: trend.exercise, size: 48, record: window.last?.isRecord ?? false)
      VStack(alignment: .leading, spacing: 2) {
        Text(trend.exercise.localizedName)
          .forge(16, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: "\(latest) \(unit(for: trend.exercise.id))")
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
      }
      Spacer(minLength: 8)
      LiftSparkline(valuesKg: window.map(\.e1rmKg), endIsRecord: window.last?.isRecord ?? false)
        .frame(width: 80, height: 30)
      TrendChangeText(changeKg: trend.changeKg(in: range), isLb: isLb)
        .frame(minWidth: 56, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      Text(verbatim: "\(trend.exercise.localizedName), \(latest) \(unit(for: trend.exercise.id))"))
    .accessibilityValue(TrendChangeText.label(changeKg: trend.changeKg(in: range), isLb: isLb))
  }

  private func lbValue(_ kg: Double, id: String) -> Double {
    (profile?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  private func unit(for id: String) -> String {
    (profile?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }

  private var unit: String { usesLb ? "lb" : "kg" }

  private struct WeekSets: Identifiable {
    let start: Date
    let sets: Int
    let isCurrent: Bool
    var id: Date { start }
  }

  /// The coverage-aware bins behind the Weekly sets chart — missing history never reads as zero.
  private var weeklySetBins: [TrainingMetrics.WeekBin] {
    TrainingMetrics.weeklyBins(
      sessions.metricSets(scopes: [.trends]), weeks: chartWindowWeeks, now: .now,
      calendar: TrainingMetrics.reportingCalendar(), scope: .analysisEligible,
      hardSetsOnly: true, coverageStart: sessions.coverageStart)
  }

  private var weeklySetCounts: [WeekSets] {
    let bins = weeklySetBins
    return bins.enumerated().map { index, bin in
      WeekSets(start: bin.start, sets: bin.count, isCurrent: index == bins.count - 1)
    }
  }

  private var weeklySetsCard: some View {
    let data = weeklySetCounts
    let current = data.last?.sets ?? 0
    let average = TrainingMetrics.averageCount(weeklySetBins)
    return SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 1) {
            Text("Weekly sets").forgeSection()
            MetricValue(value: "\(current)", unit: "sets", size: 32, color: Theme.metricSets)
            Text(weeklySetsCaption(average)).forgeCaption().monospacedDigit()
          }
          Spacer()
        }
        Picker("Range", selection: $chartWindowWeeks) {
          Text("4W").tag(4)
          Text("8W").tag(8)
          Text("12W").tag(12)
        }
        .pickerStyle(.segmented)
        Chart {
          ForEach(data) { week in
            BarMark(
              x: .value("Week", week.start, unit: .weekOfYear),
              y: .value("Sets", week.sets),
              width: .ratio(0.56)
            )
            .foregroundStyle(Theme.metricSets.opacity(week.isCurrent ? 1 : 0.58))
            .cornerRadius(3)
          }
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .weekOfYear, count: max(1, chartWindowWeeks / 4))) {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
              .font(.forge(10, .medium))
              .foregroundStyle(Theme.textTertiary)
          }
        }
        .chartYAxis {
          AxisMarks(position: .trailing) {
            AxisGridLine().foregroundStyle(Theme.ring)
            AxisValueLabel().font(.forge(10, .medium)).foregroundStyle(Theme.textTertiary)
          }
        }
        .chartPlotStyle { plot in
          plot.background(Theme.innerSurface.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        }
        .frame(height: 164)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly sets, \(current) this week, \(chartWindowWeeks) week chart")
      }
    }
  }

  private struct WeekLoad: Identifiable {
    let start: Date
    let kg: Double
    let isCurrent: Bool
    var id: Date { start }
  }

  /// The average counts only weeks with recorded history — "no history" is not "no training".
  private func weeklySetsCaption(_ average: (mean: Double, weeks: Int)?) -> String {
    guard let average else {
      return String(localized: "This week", bundle: L10n.bundle)
    }
    return String(
      localized: "This week · avg \(Fmt.num(average.mean)) over \(average.weeks) recorded weeks",
      bundle: L10n.bundle)
  }

  private var weeklyLoads: [WeekLoad] {
    let bins = TrainingMetrics.weeklyBins(
      sessions.metricSets(scopes: [.trends]), weeks: chartWindowWeeks, now: .now,
      calendar: TrainingMetrics.reportingCalendar(), scope: .analysisEligible,
      hardSetsOnly: false, coverageStart: sessions.coverageStart)
    return bins.enumerated().map { index, bin in
      WeekLoad(start: bin.start, kg: bin.volume, isCurrent: index == bins.count - 1)
    }
  }

  private var volumeLoadCard: some View {
    let currentKg = weeklyLoads.last?.kg ?? 0
    let display = usesLb ? Plates.kgToLb(currentKg) : currentKg
    let compact = display >= 1_000
    let headline = compact ? Fmt.num(display / 1_000) : Fmt.grouped(display)
    let displayUnit = compact ? "k \(unit)" : unit
    return SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Volume load").forgeSection()
          MetricValue(value: headline, unit: displayUnit, size: 32, color: Theme.metricLoad)
          Text("This week · total tonnage").forgeCaption()
        }
        Picker("Range", selection: $chartWindowWeeks) {
          Text("4W").tag(4)
          Text("8W").tag(8)
          Text("12W").tag(12)
        }
        .pickerStyle(.segmented)
        Chart(weeklyLoads) { week in
          BarMark(
            x: .value("Week", week.start, unit: .weekOfYear),
            y: .value("Tonnage", usesLb ? Plates.kgToLb(week.kg) : week.kg),
            width: .ratio(0.56)
          )
          .foregroundStyle(Theme.metricLoad.opacity(week.isCurrent ? 1 : 0.58))
          .cornerRadius(3)
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .weekOfYear, count: max(1, chartWindowWeeks / 4))) {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
              .font(.forge(10, .medium))
              .foregroundStyle(Theme.textTertiary)
          }
        }
        .chartYAxis {
          AxisMarks(position: .trailing) {
            AxisGridLine().foregroundStyle(Theme.ring)
            AxisValueLabel().font(.forge(10, .medium)).foregroundStyle(Theme.textTertiary)
          }
        }
        .chartPlotStyle { plot in
          plot.background(Theme.innerSurface.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        }
        .frame(height: 164)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "Volume load, \(Fmt.grouped(display)) \(unit) this week, \(chartWindowWeeks) week chart")
      }
    }
  }
}

private extension BodyArea {
  var shortTitle: String {
    switch self {
    case .legs: return String(localized: "Legs", bundle: L10n.bundle)
    case .push: return String(localized: "Push", bundle: L10n.bundle)
    case .pull: return String(localized: "Pull", bundle: L10n.bundle)
    case .core: return String(localized: "Core", bundle: L10n.bundle)
    }
  }
}
