import Charts
import ForgeCore
import SwiftData
import SwiftUI

/// The four trend charts that used to sit on the Progress overview, moved to their own pushed
/// screen so the overview can lead with outcomes instead of diagnostics.
struct ProgressTrendsView: View {
  let usesLb: Bool

  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var selectedLift = ""
  @State private var chartWindowWeeks = 8
  @State private var scrubDate: Date?

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        trendsCard
        strengthCard
        weeklySetsCard
        volumeLoadCard
      }
      .padding(.horizontal, Theme.margin)
    }
    .background(Theme.page)
    .navigationTitle("Trends")
    .onAppear { if selectedLift.isEmpty { selectedLift = loggedExerciseIDs.first ?? "" } }
  }

  private var loggedExerciseIDs: [String] {
    Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).sorted()
  }

  private func lbValue(_ kg: Double, id: String) -> Double {
    (profile?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  private func unit(for id: String) -> String {
    (profile?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }

  private var unit: String { usesLb ? "lb" : "kg" }

  /// Sets of `exerciseID` comparable with the most recent verified equipment context, so two
  /// incompatible verified instances never merge into one baseline. Falls back to all sets
  /// when there is no verified passport context (legacy history stays continuous).
  private func comparableSets(_ sets: [LoggedSet], exerciseID: String) -> [LoggedSet] {
    let pool = sets.filter { $0.exerciseID == exerciseID }
    let reference =
      pool
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return pool }
    return pool.filter { $0.isComparableForBaseline(to: reference) }
  }

  private var history: [E1RMPoint] {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return
      sessions
      .filter { $0.date > cutoff }
      .compactMap { session -> E1RMPoint? in
        let best = comparableSets(session.analysisSets(.trends), exerciseID: selectedLift)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
          .max()
        guard let best else { return nil }
        return E1RMPoint(date: session.date, e1rm: best)
      }
      .sorted { $0.date < $1.date }
  }

  /// Equipment context for the selected lift, when a verified passport instance was recorded.
  /// `nil` for legacy/imported loads, which stay unlabeled rather than guessed.
  private var selectedLiftEquipmentContext: String? {
    guard !selectedLift.isEmpty, let profile else { return nil }
    let sets = sessions.analysisSets(.trends).filter { $0.exerciseID == selectedLift }
    guard
      let reference = sets.first(where: { $0.comparisonContext.normalizationStatus == .verified }),
      let instanceID = reference.equipmentInstanceID
    else { return nil }
    let instance = profile.equipmentPassport.instance(id: instanceID)
    let gymName = instance?.gymProfileID.flatMap { gymID in
      profile.trainingConstraints.gymProfiles.first { $0.id == gymID }?.name
    }
    return [instance?.name ?? instanceID, gymName].compactMap { $0 }.joined(separator: " · ")
  }

  private var trendsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Trends").forgeSection()
        Spacer()
        Text("4 weeks vs the 8 before").forgeCaption()
      }
      if trends.isEmpty {
        Text("Log four sessions to see trends.").forgeLabel()
      } else {
        ForEach(trends) { t in
          TrendRow(
            direction: t.direction, label: t.label, value: t.value, unit: t.unit, detail: t.detail,
            valueColor: t.color, metricSymbol: trendSymbol(t.id))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private struct Trend: Identifiable {
    let id: String
    let label: String
    let value: String
    let unit: String?
    let direction: TrendDirection
    let detail: String?
    let color: Color
  }

  private var trends: [Trend] {
    let now = Date.now
    let recentStart = now.addingTimeInterval(-28 * 86400)
    let priorStart = now.addingTimeInterval(-84 * 86400)
    let completed = sessions.filter(\.completed)
    let recentSessions = completed.filter { $0.date > recentStart }
    guard !recentSessions.isEmpty else { return [] }
    let priorSessions = completed.filter { $0.date > priorStart && $0.date <= recentStart }
    let priorHasData = !priorSessions.isEmpty

    var result: [Trend] = []

    let recentSessionsPerWeek = Double(recentSessions.count) / 4
    let priorSessionsPerWeek = Double(priorSessions.count) / 8
    result.append(
      Trend(
        id: "sessions",
        label: String(localized: "Sessions per week", bundle: L10n.bundle),
        value: Fmt.num(recentSessionsPerWeek),
        unit: "/wk",
        direction: priorHasData ? dir(recentSessionsPerWeek, priorSessionsPerWeek, 0.25) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.num(priorSessionsPerWeek))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricSets))

    let recentSetsPerWeek =
      Double(recentSessions.flatMap { $0.analysisSets(.trends) }.filter { $0.rpe >= 6 }.count) / 4
    let priorSetsPerWeek =
      Double(priorSessions.flatMap { $0.analysisSets(.trends) }.filter { $0.rpe >= 6 }.count) / 8
    result.append(
      Trend(
        id: "sets",
        label: String(localized: "Sets per week", bundle: L10n.bundle),
        value: Fmt.num(recentSetsPerWeek),
        unit: "/wk",
        direction: priorHasData ? dir(recentSetsPerWeek, priorSetsPerWeek, 2) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.num(priorSetsPerWeek))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricSets))

    func tonnage(_ list: [WorkoutSession]) -> Double {
      list.flatMap { $0.analysisSets(.trends) }.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }
    let recentTonnagePerWeek = tonnage(recentSessions) / 4
    let priorTonnagePerWeek = tonnage(priorSessions) / 8
    let recentTonnageDisplay = usesLb ? Plates.kgToLb(recentTonnagePerWeek) : recentTonnagePerWeek
    let priorTonnageDisplay = usesLb ? Plates.kgToLb(priorTonnagePerWeek) : priorTonnagePerWeek
    result.append(
      Trend(
        id: "tonnage",
        label: String(localized: "Tonnage per week", bundle: L10n.bundle),
        value: Fmt.grouped(recentTonnageDisplay),
        unit: "\(unit)/wk",
        direction: priorHasData ? relDir(recentTonnagePerWeek, priorTonnagePerWeek, 0.05) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.grouped(priorTonnageDisplay))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricLoad))

    let recentCounts = Dictionary(
      grouping: recentSessions.flatMap { $0.analysisSets(.trends) }, by: \.exerciseID
    ).mapValues(\.count)
    for (id, _) in recentCounts.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }).prefix(3) {
      let name = ExerciseDB.find(id)?.localizedName ?? id
      let recentBest = recentSessions.flatMap { $0.analysisSets(.trends) }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      let priorBest = priorSessions.flatMap { $0.analysisSets(.trends) }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      guard let recentBest else { continue }
      let bestDisplay = lbValue(recentBest, id: id)
      if let priorBest {
        let priorDisplay = lbValue(priorBest, id: id)
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: unit(for: id),
            direction: relDir(recentBest, priorBest, 0.01),
            detail: "was \(Fmt.num(priorDisplay))",
            color: Theme.metricLoad))
      } else {
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: unit(for: id),
            direction: .flat,
            detail: String(localized: "Log it 8 more weeks to compare", bundle: L10n.bundle),
            color: Theme.metricLoad))
      }
    }
    return result
  }

  private func dir(_ recent: Double, _ prior: Double, _ threshold: Double) -> TrendDirection {
    if recent - prior >= threshold { return .up }
    if recent - prior <= -threshold { return .down }
    return .flat
  }

  private func relDir(_ recent: Double, _ prior: Double, _ fraction: Double) -> TrendDirection {
    guard prior > 0 else { return recent > 0 ? .up : .flat }
    if recent / prior >= 1 + fraction { return .up }
    if recent / prior <= 1 - fraction { return .down }
    return .flat
  }

  private func trendSymbol(_ id: String) -> String {
    switch id {
    case "sessions": return "calendar.badge.checkmark"
    case "sets": return "checkmark.circle.fill"
    case "tonnage": return "scalemass.fill"
    default: return "dumbbell.fill"
    }
  }

  private var strengthCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      if loggedExerciseIDs.isEmpty {
        emptyStrength
      } else {
        HStack {
          Text("Strength").forgeSection()
          Spacer()
          Picker("Lift", selection: $selectedLift) {
            ForEach(loggedExerciseIDs, id: \.self) { id in
              Text(ExerciseDB.find(id)?.localizedName ?? id).tag(id)
            }
          }
          .pickerStyle(.menu)
        }
        if let context = selectedLiftEquipmentContext {
          Label(context, systemImage: "dumbbell.fill")
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        }
        if !history.isEmpty {
          HStack(alignment: .firstTextBaseline) {
            MetricValue(
              value: currentDisplay, unit: unit(for: selectedLift), size: 28,
              color: Theme.metricLoad)
            if let delta = deltaDisplay {
              Text(delta).foregroundStyle(delta.hasPrefix("+") ? Theme.positive : Theme.negative)
                .forgeCaption()
                .monospacedDigit()
            }
            Spacer()
            if Strength.isPlateaued(history, asOf: .now) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.metricEffort)
            }
          }
          Chart {
            ForEach(history, id: \.self) { point in
              LineMark(
                x: .value("Date", point.date),
                y: .value("e1RM", lbValue(point.e1rm, id: selectedLift))
              )
              .foregroundStyle(Theme.metricLoad)
              .interpolationMethod(.catmullRom)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              if point == history.last {
                PointMark(
                  x: .value("Date", point.date),
                  y: .value("e1RM", lbValue(point.e1rm, id: selectedLift))
                )
                .symbolSize(70)
                .symbol {
                  Circle().fill(Theme.accent)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .frame(width: 10, height: 10)
                }
              }
            }
            if let scrubDate, let point = history.first(where: { $0.date == scrubDate }) {
              RuleMark(x: .value("Date", point.date))
                .foregroundStyle(Theme.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center) {
                  ChartCallout(
                    value:
                      "\(formatDisplay(lbValue(point.e1rm, id: selectedLift))) \(unit(for: selectedLift))",
                    caption: point.date.formatted(.dateTime.month().day().locale(L10n.locale)))
                }
            }
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(
                Theme.ring)
              AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(
                Theme.ring)
              AxisValueLabel()
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartOverlay { proxy in
            GeometryReader { geo in
              Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                  LongPressGesture(minimumDuration: 0.15)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                      guard case .second(true, let drag?) = value else { return }
                      guard let plotFrame = proxy.plotFrame else { return }
                      let x = drag.location.x - geo[plotFrame].origin.x
                      if let date: Date = proxy.value(atX: x) {
                        scrubDate =
                          history.min(by: {
                            abs($0.date.timeIntervalSince(date))
                              < abs($1.date.timeIntervalSince(date))
                          })?.date
                      }
                    }
                    .onEnded { _ in scrubDate = nil })
            }
          }
          .frame(height: 180)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "\(liftName) estimated one-rep max \(currentDisplay) \(unit(for: selectedLift))")
          if history.count < 3 {
            Text(
              String(
                localized: "Log \(liftName) \(3 - history.count) more times to see a trend.",
                bundle: L10n.bundle)
            ).forgeCaption()
          }
        } else {
          Text("No \(liftName) in the last 12 weeks.").forgeLabel()
        }
        if !topLifts.isEmpty {
          Divider()
          Text("PRs").forgeSection()
          ForEach(topLifts, id: \.exercise.id) { lift in
            HStack(spacing: 12) {
              EquipmentThumb(equipment: lift.exercise.equipment, size: 32)
                .accessibilityHidden(true)
              Text(lift.exercise.localizedName).forgeBodyStrong()
              Spacer()
              Text(
                "\(formatDisplay(lbValue(lift.best, id: lift.exercise.id))) \(unit(for: lift.exercise.id))"
              )
              .forgeLabel()
              .monospacedDigit()
              .bold()
            }
          }
        }
      }
    }
    .card()
  }

  private var liftName: String {
    ExerciseDB.find(selectedLift)?.localizedName ?? selectedLift
  }

  private var topLifts: [(exercise: Exercise, best: Double)] {
    var bests: [String: Double] = [:]
    for s in sessions where s.completed {
      for set in s.analysisSets(.achievements) {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return
      bests
      .compactMap { id, best in ExerciseDB.find(id).map { (exercise: $0, best: best) } }
      .sorted { $0.best > $1.best }
      .prefix(5).map { $0 }
  }

  private var currentDisplay: String {
    guard let best = history.last?.e1rm else { return "—" }
    return formatDisplay(lbValue(best, id: selectedLift))
  }

  private var deltaDisplay: String? {
    guard let current = history.last else { return nil }
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else {
      return nil
    }
    let delta = lbValue(current.e1rm, id: selectedLift) - lbValue(prior.e1rm, id: selectedLift)
    return "\(delta > 0 ? "+" : "−")\(Fmt.num(abs(delta))) \(unit(for: selectedLift))"
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
    return VStack(alignment: .leading, spacing: 12) {
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
    .card()
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
    return VStack(alignment: .leading, spacing: 12) {
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
    .card()
  }

  private func formatDisplay(_ value: Double) -> String {
    Fmt.num(value)
  }
}
