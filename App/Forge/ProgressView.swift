import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query private var progressPhotos: [ProgressPhoto]
  @State private var selectedLift = ""
  @State private var scrubDate: Date?
  @State private var selectedBadge: BadgeProgress?
  @State private var newBadgeToast: Badge?
  @AppStorage("badgesSeen") private var badgesSeen = ""

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private func lbValue(_ kg: Double, id: String) -> Double {
    (profile?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  private func unit(for id: String) -> String {
    (profile?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }

  private var loggedExerciseIDs: [String] {
    Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).sorted()
  }

  private var history: [E1RMPoint] {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return sessions
      .filter { $0.date > cutoff }
      .compactMap { session -> E1RMPoint? in
        let best = session.sets
          .filter { $0.exerciseID == selectedLift }
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
          .max()
        guard let best else { return nil }
        return E1RMPoint(date: session.date, e1rm: best)
      }
      .sorted { $0.date < $1.date }
  }

  private var weekVolume: [Muscle: Double] {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    let entries: [(exercise: Exercise, set: SetLog)] = sessions
      .filter { $0.date > cutoff }
      .flatMap { session in
        session.sets.compactMap { set in
          ExerciseDB.find(set.exerciseID).map { exercise in
            (exercise: exercise, set: SetLog(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe))
          }
        }
      }
    return Volume.weeklySets(entries)
  }

  private var csvURL: URL {
    let rows = sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map { "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)" }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          statTiles
          trendsCard
          weeklySetsCard
          strengthCard
          volumeLoadCard
          volumeCard
          calendarCard
          awardsCard
          analyticsGrid
        }
        .padding(.horizontal, Theme.margin)
      }
      .background(Theme.page)
      .navigationTitle("Progress")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: csvURL) { Image(systemName: "square.and.arrow.up") }
        }
      }
      .onAppear {
        if selectedLift.isEmpty { selectedLift = loggedExerciseIDs.first ?? "" }
        celebrateNewBadges()
      }
      .overlay(alignment: .top) {
        if let badge = newBadgeToast {
          HStack(spacing: 8) {
            Image(systemName: badge.symbol)
            Text("New badge · \(badge.title)")
          }
          .forge(13, .semibold)
          .foregroundColor(Theme.onAccent)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Capsule().fill(Theme.accent))
          .shadow(color: Theme.shadow, radius: 12, y: 4)
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
          .task(id: badge) {
            try? await Task.sleep(for: .seconds(3))
            if newBadgeToast == badge { newBadgeToast = nil }
          }
        }
      }
      .animation(.spring(duration: 0.3), value: newBadgeToast)
    }
  }

  private var verifiedSessions: [WorkoutSession] { sessions.filter(\.verified) }

  private var streak: Int { streakWeeks(sessions: verifiedSessions) }

  private var totalWorkouts: Int { verifiedSessions.filter(\.completed).count }

  /// Lifetime tonnage over completed, verified sessions, kg.
  private var lifetimeTonnageKg: Double {
    verifiedSessions
      .filter(\.completed)
      .flatMap(\.sets)
      .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  /// Exercises whose per-session best e1RM strictly improved over an earlier verified session's best.
  private var prCount: Int {
    var bests: [String: Double] = [:]
    var improved: Set<String> = []
    for session in verifiedSessions.filter(\.completed).sorted(by: { $0.date < $1.date }) {
      var sessionBests: [String: Double] = [:]
      for set in session.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        sessionBests[set.exerciseID] = max(sessionBests[set.exerciseID] ?? 0, e)
      }
      for (id, e) in sessionBests {
        if e > (bests[id] ?? 0), bests[id] != nil { improved.insert(id) }
        bests[id] = max(bests[id] ?? 0, e)
      }
    }
    return improved.count
  }

  private var earnedBadges: [Badge] {
    Badges.earned(
      sessions: totalWorkouts,
      streakWeeks: streak,
      tonnageKg: lifetimeTonnageKg,
      prCount: prCount)
  }

  private var badgeProgress: [BadgeProgress] {
    Badges.progress(sessions: totalWorkouts, streakWeeks: streak, tonnageKg: lifetimeTonnageKg, prCount: prCount)
  }

  private var nextBadges: [BadgeProgress] {
    badgeProgress.filter { !earnedBadges.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
  }

  private var awardsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink { AwardsView(earned: earnedBadges, progress: badgeProgress) } label: {
        HStack(spacing: 6) {
          Text("Awards").forgeSection()
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textTertiary)
          Spacer()
          Text("\(earnedBadges.count) of \(Badge.allCases.count)").forgeCaption().monospacedDigit()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      if let next = nextBadges.first {
        NextBadgeRow(symbol: next.badge.symbol, title: next.badge.title, progress: next.progress, target: next.target)
      }
      if !earnedBadges.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 14) {
            ForEach(earnedBadges, id: \.rawValue) { badge in
              Button { selectedBadge = badgeProgress.first { $0.badge == badge } } label: {
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

  /// One-time toast for badges earned since `badgesSeen` was last updated.
  private func celebrateNewBadges() {
    let seen = Set(badgesSeen.split(separator: ",").map(String.init))
    let earnedSet = Set(earnedBadges.map(\.rawValue))
    let fresh = Badge.allCases.filter { earnedSet.contains($0.rawValue) && !seen.contains($0.rawValue) }
    guard !fresh.isEmpty else { return }
    newBadgeToast = fresh.first
    badgesSeen = earnedSet.sorted().joined(separator: ",")
  }

  private var statTiles: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      StatTile(symbol: "flame.fill", value: "\(streak)", unit: "wk", label: String(localized: "streak", bundle: L10n.bundle), tint: Theme.metricTime)
        .accessibilityElement(children: .combine)
      StatTile(symbol: "dumbbell", value: "\(totalWorkouts)", label: String(localized: "workouts", bundle: L10n.bundle), tint: Theme.metricSets)
        .accessibilityElement(children: .combine)
      StatTile(symbol: "scalemass", value: weekTonnageNumber, unit: weekTonnageUnit, label: String(localized: "volume 7d", bundle: L10n.bundle), tint: Theme.metricLoad)
        .accessibilityElement(children: .combine)
      StatTile(symbol: "trophy.fill", value: bestE1RMNumber, unit: unit, label: String(localized: "best e1RM", bundle: L10n.bundle), tint: Theme.metricLoad)
        .accessibilityElement(children: .combine)
    }
  }

  private var weekTonnageKg7d: Double {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    return sessions
      .filter { $0.date > cutoff }
      .flatMap { $0.sets }
      .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
  }

  private var weekTonnageNumber: String {
    usesLb ? String(format: "%.0fk", Plates.kgToLb(weekTonnageKg7d) / 1000) : Fmt.num(weekTonnageKg7d / 1000)
  }

  private var weekTonnageUnit: String { usesLb ? "lb" : "t" }

  private var bestE1RMNumber: String {
    let best = sessions.filter(\.completed).flatMap(\.sets)
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    guard let best else { return "—" }
    let value = usesLb ? Plates.kgToLb(best) : best
    return "\(Int(value.rounded()))"
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
    result.append(Trend(
      id: "sessions",
      label: String(localized: "Sessions per week", bundle: L10n.bundle),
      value: Fmt.num(recentSessionsPerWeek),
      unit: "/wk",
      direction: priorHasData ? dir(recentSessionsPerWeek, priorSessionsPerWeek, 0.25) : .flat,
      detail: priorHasData ? String(localized: "was \(Fmt.num(priorSessionsPerWeek))", bundle: L10n.bundle) : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
      color: Theme.metricSets))

    let recentSetsPerWeek = Double(recentSessions.flatMap { $0.sets }.filter { $0.rpe >= 6 }.count) / 4
    let priorSetsPerWeek = Double(priorSessions.flatMap { $0.sets }.filter { $0.rpe >= 6 }.count) / 8
    result.append(Trend(
      id: "sets",
      label: String(localized: "Sets per week", bundle: L10n.bundle),
      value: Fmt.num(recentSetsPerWeek),
      unit: "/wk",
      direction: priorHasData ? dir(recentSetsPerWeek, priorSetsPerWeek, 2) : .flat,
      detail: priorHasData ? String(localized: "was \(Fmt.num(priorSetsPerWeek))", bundle: L10n.bundle) : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
      color: Theme.metricSets))

    func tonnage(_ list: [WorkoutSession]) -> Double {
      list.flatMap { $0.sets }.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }
    let recentTonnagePerWeek = tonnage(recentSessions) / 4
    let priorTonnagePerWeek = tonnage(priorSessions) / 8
    let recentTonnageDisplay = usesLb ? Plates.kgToLb(recentTonnagePerWeek) : recentTonnagePerWeek
    let priorTonnageDisplay = usesLb ? Plates.kgToLb(priorTonnagePerWeek) : priorTonnagePerWeek
    result.append(Trend(
      id: "tonnage",
      label: String(localized: "Tonnage per week", bundle: L10n.bundle),
      value: Fmt.grouped(recentTonnageDisplay),
      unit: "\(unit)/wk",
      direction: priorHasData ? relDir(recentTonnagePerWeek, priorTonnagePerWeek, 0.05) : .flat,
      detail: priorHasData ? String(localized: "was \(Fmt.grouped(priorTonnageDisplay))", bundle: L10n.bundle) : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
      color: Theme.metricLoad))

    let recentCounts = Dictionary(grouping: recentSessions.flatMap { $0.sets }, by: \.exerciseID).mapValues(\.count)
    for (id, _) in recentCounts.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }).prefix(3) {
      let name = ExerciseDB.find(id)?.localizedName ?? id
      let recentBest = recentSessions.flatMap { $0.sets }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      let priorBest = priorSessions.flatMap { $0.sets }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      guard let recentBest else { continue }
      let bestDisplay = lbValue(recentBest, id: id)
      if let priorBest {
        let priorDisplay = lbValue(priorBest, id: id)
        result.append(Trend(
          id: id,
          label: name,
          value: Fmt.num(bestDisplay),
          unit: unit(for: id),
          direction: relDir(recentBest, priorBest, 0.01),
          detail: "was \(Fmt.num(priorDisplay))",
          color: Theme.metricLoad))
      } else {
        result.append(Trend(
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
          TrendRow(direction: t.direction, label: t.label, value: t.value, unit: t.unit, detail: t.detail, valueColor: t.color)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var mesoBlockCount: Int {
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    guard !completed.isEmpty else { return 0 }
    return 1 + zip(completed, completed.dropFirst()).filter { $0.1.week < $0.0.week }.count
  }

  private var latestWeight: String? {
    measurements.first(where: { ($0.weightKg ?? 0) > 0 })?.weightKg
      .map { UnitFormat.weight($0, usesLb: usesLb) }
  }

  private var analyticsGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      NavigationLink {
        NutritionView()
      } label: {
        AnalyticTile(symbol: "fork.knife", title: String(localized: "Fuel", bundle: L10n.bundle), subtitle: String(localized: "Calories and protein", bundle: L10n.bundle))
      }
      NavigationLink {
        HistoryView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "clock.fill", title: String(localized: "History", bundle: L10n.bundle), subtitle: String(localized: "\(totalWorkouts) sessions", bundle: L10n.bundle))
      }
      NavigationLink {
        PRBoardView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "trophy.fill", title: String(localized: "PR board", bundle: L10n.bundle), subtitle: String(localized: "\(loggedExerciseIDs.count) lifts", bundle: L10n.bundle))
      }
      NavigationLink {
        MeasurementsView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "scalemass", title: String(localized: "Body stats", bundle: L10n.bundle), subtitle: latestWeight ?? "—")
      }
      NavigationLink {
        ProgressPhotosView()
      } label: {
        AnalyticTile(symbol: "camera.fill", title: String(localized: "Photos", bundle: L10n.bundle), subtitle: "\(progressPhotos.count)")
      }
      NavigationLink {
        BalanceRadarView()
      } label: {
        AnalyticTile(symbol: "circle.hexagongrid.fill", title: String(localized: "Balance", bundle: L10n.bundle), subtitle: String(localized: "Push · Pull · Legs", bundle: L10n.bundle))
      }
      NavigationLink {
        MesoHistoryView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "square.stack.3d.up.fill", title: String(localized: "Mesocycles", bundle: L10n.bundle), subtitle: String(localized: "\(mesoBlockCount) blocks", bundle: L10n.bundle))
      }
      NavigationLink {
        RecoveryReportView()
      } label: {
        AnalyticTile(symbol: "bolt.heart.fill", title: String(localized: "Recovery", bundle: L10n.bundle), subtitle: String(localized: "Last 7 days", bundle: L10n.bundle))
      }
      ShareLink(item: ReportPDF.url(sessions: sessions, profile: profile), preview: SharePreview("Training report")) {
        AnalyticTile(symbol: "doc.fill", title: String(localized: "PDF report", bundle: L10n.bundle), subtitle: String(localized: "One-page summary", bundle: L10n.bundle))
      }
    }
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
        if !history.isEmpty {
          HStack(alignment: .firstTextBaseline) {
            MetricValue(value: currentDisplay, unit: unit(for: selectedLift), size: 28, color: Theme.metricLoad)
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
              AreaMark(x: .value("Date", point.date), y: .value("e1RM", lbValue(point.e1rm, id: selectedLift)))
                .foregroundStyle(
                  LinearGradient(colors: [Theme.accentValue.opacity(0.28), Theme.accentValue.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
              LineMark(x: .value("Date", point.date), y: .value("e1RM", lbValue(point.e1rm, id: selectedLift)))
                .foregroundStyle(Theme.accentValue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              if point == history.last {
                PointMark(x: .value("Date", point.date), y: .value("e1RM", lbValue(point.e1rm, id: selectedLift)))
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
                  ChartCallout(value: "\(formatDisplay(lbValue(point.e1rm, id: selectedLift))) \(unit(for: selectedLift))", caption: point.date.formatted(.dateTime.month().day().locale(L10n.locale)))
                }
            }
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
              AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
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
                        scrubDate = history.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })?.date
                      }
                    }
                    .onEnded { _ in scrubDate = nil })
            }
          }
          .frame(height: 180)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(liftName) estimated one-rep max \(currentDisplay) \(unit(for: selectedLift))")
          if history.count < 3 {
            Text(String(localized: "Log \(liftName) \(3 - history.count) more times to see a trend.", bundle: L10n.bundle)).forgeCaption()
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
              Text("\(formatDisplay(lbValue(lift.best, id: lift.exercise.id))) \(unit(for: lift.exercise.id))")
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
      for set in s.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return bests
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
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else { return nil }
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

  private var weeklySetCounts: [WeekSets] {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<8).compactMap { i in
      guard let start = cal.date(byAdding: .weekOfYear, value: i - 7, to: thisWeek) else { return nil }
      let sets = sessions
        .filter { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start == start }
        .flatMap(\.sets)
        .filter { $0.rpe >= 6 }
        .count
      return WeekSets(start: start, sets: sets, isCurrent: i == 7)
    }
  }

  private var weeklySetsCard: some View {
    let data = weeklySetCounts
    let avg = Double(data.map(\.sets).reduce(0, +)) / Double(max(data.count, 1))
    return VStack(alignment: .leading, spacing: 12) {
      Text("Weekly sets").forgeSection()
      Chart {
        ForEach(data) { week in
          BarMark(
            x: .value("Week", week.start, unit: .weekOfYear),
            y: .value("Sets", week.sets))
            .foregroundStyle(week.isCurrent ? Theme.ramp[4] : Theme.ramp[2])
            .cornerRadius(4)
        }
        if avg > 0 {
          RuleMark(y: .value("Average", avg))
            .foregroundStyle(Theme.textTertiary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .trailing) {
              Text("avg").forgeCaption()
            }
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
          AxisValueLabel(format: .dateTime.month().day().locale(L10n.locale))
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
          AxisValueLabel()
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .frame(height: 180)
    }
    .card()
  }

  private struct WeekLoad: Identifiable {
    let start: Date
    let kg: Double
    let isCurrent: Bool
    var id: Date { start }
  }

  private var weeklyLoads: [WeekLoad] {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<12).compactMap { i in
      guard let start = cal.date(byAdding: .weekOfYear, value: i - 11, to: thisWeek) else { return nil }
      let kg = sessions
        .filter { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start == start }
        .flatMap(\.sets)
        .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
      return WeekLoad(start: start, kg: kg, isCurrent: i == 11)
    }
  }

  private var volumeLoadCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Volume load").forgeSection()
        Spacer()
        Text("tonnage per week · \(unit)").forgeCaption()
      }
      Chart(weeklyLoads) { week in
        BarMark(
          x: .value("Week", week.start, unit: .weekOfYear),
          y: .value("Tonnage", usesLb ? Plates.kgToLb(week.kg) : week.kg))
          .foregroundStyle(week.isCurrent ? Theme.ramp[4] : Theme.ramp[2])
          .cornerRadius(4)
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear, count: 3)) {
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
          AxisValueLabel(format: .dateTime.month().day().locale(L10n.locale))
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.ring)
          AxisValueLabel()
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .frame(height: 180)
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
      MuscleMapView(intensity: weekIntensity)
        .frame(height: 220)
        .frame(maxWidth: .infinity)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) { muscle in
          volumeCell(muscle)
        }
      }
    }
    .card()
  }

  private func volumeCell(_ muscle: Muscle) -> some View {
    let l = VolumeLandmarks.base(for: muscle)!
    return VStack(spacing: 4) {
      VolumeRingView(sets: weekVolume[muscle] ?? 0, mev: l.mev, mrv: l.mrv)
      Text(muscle.a11yName).forgeCaption()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(muscle.a11yName), \(Int((weekVolume[muscle] ?? 0).rounded())) sets this week, target \(l.mrv)")
  }

  private var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekVolume[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }

  private func formatDisplay(_ value: Double) -> String {
    Fmt.num(value)
  }

  private func streakWeeks(sessions: [WorkoutSession]) -> Int {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
    let weeks = Set(sessions.filter(\.completed).compactMap { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }
}

struct AnalyticTile: View {
  let symbol: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Theme.accentTint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(subtitle).forgeCaption()
      }
      Spacer()
    }
    .card()
    .contentShape(Rectangle())
  }
}
