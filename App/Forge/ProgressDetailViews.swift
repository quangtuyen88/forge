import Charts
import ForgeCore
import SwiftData
import SwiftUI

/// Numbers derived once from the recorded log and profile, shared by the Overview highlights,
/// the badge toast and the detail screens so every surface computes the same thing.
struct ProgressFacts {
  var sessions: [WorkoutSession]
  var profile: UserProfile?

  var usesLb: Bool { profile?.usesLb ?? false }
  var unit: String { usesLb ? "lb" : "kg" }

  func lbValue(_ kg: Double, id: String) -> Double {
    (profile?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  func unit(for id: String) -> String {
    (profile?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }

  var loggedExerciseIDs: [String] {
    Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).sorted()
  }

  /// Sets of `exerciseID` comparable with the most recent verified equipment context, so two
  /// incompatible verified instances never merge into one baseline. Falls back to all sets
  /// when there is no verified passport context (legacy history stays continuous).
  func comparableSets(_ sets: [LoggedSet], exerciseID: String) -> [LoggedSet] {
    let pool = sets.filter { $0.exerciseID == exerciseID }
    let reference =
      pool
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return pool }
    return pool.filter { $0.isComparableForBaseline(to: reference) }
  }

  var verifiedSessions: [WorkoutSession] { sessions.filter(\.verified) }

  var streak: Int { Self.streakWeeks(sessions: verifiedSessions) }

  static func streakWeeks(sessions: [WorkoutSession]) -> Int {
    let cal = TrainingMetrics.reportingCalendar()
    let thisWeek = TrainingMetrics.reportingWeek(containing: .now, calendar: cal).start
    let weeks = Set(
      sessions.filter(\.completed).map {
        TrainingMetrics.reportingWeek(containing: $0.date, calendar: cal).start
      })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }

  /// One definition, shared with Balance and History via `analysisEligibleSessions`.
  var totalWorkouts: Int { sessions.analysisEligibleSessions.count }

  /// Lifetime tonnage over completed, verified sessions, kg.
  var lifetimeTonnageKg: Double {
    verifiedSessions
      .filter(\.completed)
      .flatMap { $0.analysisSets(.achievements) }
      .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  /// Exercises whose per-session best e1RM strictly improved over an earlier verified session's best.
  var prCount: Int {
    var bests: [String: Double] = [:]
    var improved: Set<String> = []
    for session in verifiedSessions.filter(\.completed).sorted(by: { $0.date < $1.date }) {
      var sessionBests: [String: Double] = [:]
      for id in Set(session.analysisSets(.achievements).map(\.exerciseID)) {
        let best = comparableSets(session.analysisSets(.achievements), exerciseID: id)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
        if let best { sessionBests[id] = best }
      }
      for (id, e) in sessionBests {
        if e > (bests[id] ?? 0), bests[id] != nil { improved.insert(id) }
        bests[id] = max(bests[id] ?? 0, e)
      }
    }
    return improved.count
  }

  var earnedBadges: [Badge] {
    Badges.earned(
      sessions: totalWorkouts,
      streakWeeks: streak,
      tonnageKg: lifetimeTonnageKg,
      prCount: prCount)
  }

  var badgeProgress: [BadgeProgress] {
    Badges.progress(
      sessions: totalWorkouts, streakWeeks: streak, tonnageKg: lifetimeTonnageKg, prCount: prCount)
  }

  var nextBadges: [BadgeProgress] {
    badgeProgress.filter { !earnedBadges.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
  }

  var weekVolume: [Muscle: Double] {
    let week = TrainingMetrics.reportingWeek(containing: .now, calendar: TrainingMetrics.reportingCalendar())
    let entries: [(exercise: Exercise, set: SetLog)] =
      sessions
      .filter { $0.completed && TrainingMetrics.contains(week, $0.date) }
      .flatMap { session in
        session.analysisSets(.trends).compactMap { set in
          ExerciseDB.find(set.exerciseID).map { exercise in
            (
          exercise: exercise,
          set: SetLog(
            weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
            effortReported: set.effortReported)
        )
          }
        }
      }
    return Volume.weeklySets(entries)
  }

  var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekVolume[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }
}

/// The Volume detail screen: volume load, weekly sets, and the per-muscle map and rings.
struct ProgressVolumeView: View {
  enum Focus { case totals, muscles }
  let usesLb: Bool
  var focus: Focus = .totals

  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var chartWindowWeeks = 8

  private var facts: ProgressFacts { ProgressFacts(sessions: sessions, profile: nil) }
  private var unit: String { usesLb ? "lb" : "kg" }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          volumeLoadCard
          weeklySetsCard
          volumeCard.id("muscles")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Volume")
      .navigationBarTitleDisplayMode(.large)
      .onAppear {
        if focus == .muscles {
          proxy.scrollTo("muscles", anchor: .top)
        }
      }
    }
  }

  private struct WeekLoad: Identifiable {
    let start: Date
    let kg: Double
    let isCurrent: Bool
    var id: Date { start }
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
    let displayUnit = compact ? (usesLb ? "k lb" : "t") : unit
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

  /// The average counts only weeks with recorded history — "no history" is not "no training".
  private func weeklySetsCaption(_ average: (mean: Double, weeks: Int)?) -> String {
    guard let average else {
      return String(localized: "This week", bundle: L10n.bundle)
    }
    return String(
      localized: "This week · avg \(Fmt.num(average.mean)) over \(average.weeks) recorded weeks",
      bundle: L10n.bundle)
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

  private var volumeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("This week").forgeSection()
        Spacer()
        Text("sets per muscle").forgeCaption()
      }
      MuscleMapView(intensity: facts.weekIntensity)
        .frame(height: 220)
        .frame(maxWidth: .infinity)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) {
          muscle in
          volumeCell(muscle)
        }
      }
    }
    .card()
  }

  private func volumeCell(_ muscle: Muscle) -> some View {
    let l = VolumeLandmarks.base(for: muscle)!
    return VStack(spacing: 4) {
      VolumeRingView(sets: facts.weekVolume[muscle] ?? 0, mev: l.mev, mrv: l.mrv)
      Text(muscle.a11yName).forgeCaption()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(muscle.a11yName), \(Int((facts.weekVolume[muscle] ?? 0).rounded())) sets this week, target \(l.mrv)"
    )
  }
}

/// The Strength detail screen: lift picker, e1RM trend with scrubbing, PRs list, empty state.
struct ProgressStrengthView: View {
  let usesLb: Bool
  var liftID: String? = nil

  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @State private var selectedLift = ""
  @State private var scrubDate: Date?

  private var profile: UserProfile? { profiles.first }
  private var facts: ProgressFacts { ProgressFacts(sessions: sessions, profile: profile) }

  var body: some View {
    ScrollView {
      strengthCard
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Strength")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      if selectedLift.isEmpty {
        if let liftID, facts.loggedExerciseIDs.contains(liftID) {
          selectedLift = liftID
        } else {
          selectedLift = facts.loggedExerciseIDs.first ?? ""
        }
      }
    }
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

  private var history: [E1RMPoint] {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return
      sessions
      .filter { $0.date > cutoff }
      .compactMap { session -> E1RMPoint? in
        let best = facts.comparableSets(session.analysisSets(.trends), exerciseID: selectedLift)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
          .max()
        guard let best else { return nil }
        return E1RMPoint(date: session.date, e1rm: best)
      }
      .sorted { $0.date < $1.date }
  }

  private var strengthCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      if facts.loggedExerciseIDs.isEmpty {
        emptyStrength
      } else {
        HStack {
          Text("Strength").forgeSection()
          Spacer()
          Picker("Lift", selection: $selectedLift) {
            ForEach(facts.loggedExerciseIDs, id: \.self) { id in
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
              value: currentDisplay, unit: facts.unit(for: selectedLift), size: 28,
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
                y: .value("e1RM", facts.lbValue(point.e1rm, id: selectedLift))
              )
              .foregroundStyle(Theme.metricLoad)
              .interpolationMethod(.catmullRom)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              if point == history.last {
                PointMark(
                  x: .value("Date", point.date),
                  y: .value("e1RM", facts.lbValue(point.e1rm, id: selectedLift))
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
                      "\(formatDisplay(facts.lbValue(point.e1rm, id: selectedLift))) \(facts.unit(for: selectedLift))",
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
            "\(liftName) estimated one-rep max \(currentDisplay) \(facts.unit(for: selectedLift))")
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
                "\(formatDisplay(facts.lbValue(lift.best, id: lift.exercise.id))) \(facts.unit(for: lift.exercise.id))"
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
    return formatDisplay(facts.lbValue(best, id: selectedLift))
  }

  private var deltaDisplay: String? {
    guard let current = history.last else { return nil }
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else {
      return nil
    }
    let delta = facts.lbValue(current.e1rm, id: selectedLift)
      - facts.lbValue(prior.e1rm, id: selectedLift)
    return "\(delta > 0 ? "+" : "−")\(Fmt.num(abs(delta))) \(facts.unit(for: selectedLift))"
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

  private func formatDisplay(_ value: Double) -> String {
    Fmt.num(value)
  }
}

/// The Consistency detail screen: the 12-week heat map and the awards card.
struct ProgressConsistencyView: View {
  let usesLb: Bool

  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var selectedBadge: BadgeProgress?

  private var facts: ProgressFacts { ProgressFacts(sessions: sessions, profile: nil) }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        calendarCard
        awardsCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Consistency")
    .navigationBarTitleDisplayMode(.large)
  }

  /// Sessions with a date in the last 12 weeks, for the consistency heat map label.
  private var sessions12Weeks: Int {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return sessions.filter { $0.date > cutoff }.count
  }

  private var calendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Consistency").forgeSection()
      CalendarHeat(sessions: sessions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 12 weeks, \(sessions12Weeks) sessions")
      HStack(spacing: 6) {
        Text("Last 12 weeks").forgeCaption()
        Spacer()
        Text("Less").forgeCaption()
        ForEach(0..<5) {
          RoundedRectangle(cornerRadius: 2).fill(Theme.ramp[$0])
            .frame(width: 10, height: 10)
        }
        Text("More").forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var awardsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink {
        AwardsView(earned: facts.earnedBadges, progress: facts.badgeProgress)
      } label: {
        HStack(spacing: 6) {
          Text("Awards").forgeSection()
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
          Spacer()
          Text("\(facts.earnedBadges.count) of \(Badge.allCases.count)").forgeCaption().monospacedDigit()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      if let next = facts.nextBadges.first {
        NextBadgeRow(
          symbol: next.badge.symbol, title: next.badge.title, progress: next.progress,
          target: next.target)
      }
      if !facts.earnedBadges.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 14) {
            ForEach(facts.earnedBadges, id: \.rawValue) { badge in
              Button {
                selectedBadge = facts.badgeProgress.first { $0.badge == badge }
              } label: {
                VStack(spacing: 6) {
                  Medallion(symbol: badge.symbol, size: 56)
                  Text(badge.title).forgeCaption().lineLimit(1)
                }
                .frame(width: 80)
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel("\(badge.title), earned")
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(item: $selectedBadge) { BadgeDetailView(progress: $0, earned: true) }
  }
}
