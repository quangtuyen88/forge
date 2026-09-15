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
  @State private var newBadgeToast: Badge?
  @AppStorage("badgesSeen") private var badgesSeen = ""

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

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
          BadgesView(earned: earnedBadges)
          analyticsGrid
          calendarCard
          strengthCard
          weeklySetsCard
          volumeLoadCard
          volumeCard
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
          .padding(.top, 4)
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

  private var streak: Int { streakWeeks(sessions: sessions) }

  private var totalWorkouts: Int { sessions.filter(\.completed).count }

  /// Lifetime tonnage over completed sessions, kg.
  private var lifetimeTonnageKg: Double {
    sessions
      .filter(\.completed)
      .flatMap(\.sets)
      .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  /// Exercises whose per-session best e1RM strictly improved over an earlier session's best.
  private var prCount: Int {
    var bests: [String: Double] = [:]
    var improved: Set<String> = []
    for session in sessions.filter(\.completed).sorted { $0.date < $1.date } {
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
    HStack(spacing: 10) {
      StatTile(symbol: "flame.fill", value: "\(streak)", label: "streak")
      StatTile(symbol: "dumbbell", value: "\(totalWorkouts)", label: "workouts")
      StatTile(symbol: "scalemass", value: weekTonnage, label: "volume 7d")
    }
  }

  private var weekTonnage: String {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    let kg = sessions
      .filter { $0.date > cutoff }
      .flatMap { $0.sets }
      .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    if usesLb {
      return String(format: "%.0fk lb", Plates.kgToLb(kg) / 1000)
    }
    return Fmt.num(kg / 1000) + " t"
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
        HistoryView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "clock.fill", title: "History", subtitle: "\(totalWorkouts) sessions")
      }
      NavigationLink {
        PRBoardView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "trophy.fill", title: "PR board", subtitle: "\(loggedExerciseIDs.count) lifts")
      }
      NavigationLink {
        MeasurementsView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "scalemass", title: "Body stats", subtitle: latestWeight ?? "—")
      }
      NavigationLink {
        ProgressPhotosView()
      } label: {
        AnalyticTile(symbol: "camera.fill", title: "Photos", subtitle: "\(progressPhotos.count)")
      }
      NavigationLink {
        BalanceRadarView()
      } label: {
        AnalyticTile(symbol: "circle.hexagongrid.fill", title: "Balance", subtitle: "Push · Pull · Legs")
      }
      NavigationLink {
        MesoHistoryView(usesLb: usesLb)
      } label: {
        AnalyticTile(symbol: "square.stack.3d.up.fill", title: "Mesocycles", subtitle: "\(mesoBlockCount) blocks")
      }
      NavigationLink {
        RecoveryReportView()
      } label: {
        AnalyticTile(symbol: "bolt.heart.fill", title: "Recovery", subtitle: "Last 7 days")
      }
      ShareLink(item: ReportPDF.url(sessions: sessions, profile: profile), preview: SharePreview("Training report")) {
        AnalyticTile(symbol: "doc.fill", title: "PDF report", subtitle: "One-page summary")
      }
    }
  }

  private var calendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Consistency").forgeSection()
      CalendarHeat(sessions: sessions)
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
              Text(ExerciseDB.find(id)?.name ?? id).tag(id)
            }
          }
          .pickerStyle(.menu)
        }
        if !history.isEmpty {
          HStack(alignment: .firstTextBaseline) {
            Text("\(currentDisplay) \(unit)")
              .forgeNumber()
            if let delta = deltaDisplay {
              Text(delta).foregroundStyle(delta.hasPrefix("+") ? Theme.positive : Theme.negative)
                .forgeCaption()
                .monospacedDigit()
            }
            Spacer()
            if Strength.isPlateaued(history, asOf: .now) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
          }
          Chart(history, id: \.self) { point in
            AreaMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              .foregroundStyle(
                LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
              .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              .foregroundStyle(Theme.accent)
              .interpolationMethod(.catmullRom)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            if point == history.last {
              PointMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                .symbolSize(70)
                .symbol {
                  Circle().fill(Theme.accent)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .frame(width: 10, height: 10)
                }
            }
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
              AxisGridLine().foregroundStyle(Theme.track)
              AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing) {
              AxisGridLine().foregroundStyle(Theme.track)
              AxisValueLabel()
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .frame(height: 180)
        }
        if !topLifts.isEmpty {
          Divider()
          Text("PRs").forgeSection()
          ForEach(topLifts, id: \.exercise.id) { lift in
            HStack(spacing: 12) {
              EquipmentThumb(equipment: lift.exercise.equipment, size: 32)
              Text(lift.exercise.name).forgeBodyStrong()
              Spacer()
              Text("\(formatDisplay(usesLb ? Plates.kgToLb(lift.best) : lift.best)) \(unit)")
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
    return formatDisplay(usesLb ? Plates.kgToLb(best) : best)
  }

  private var deltaDisplay: String? {
    guard let current = history.last else { return nil }
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else { return nil }
    let delta = (usesLb ? Plates.kgToLb(current.e1rm) : current.e1rm) - (usesLb ? Plates.kgToLb(prior.e1rm) : prior.e1rm)
    return "\(delta > 0 ? "+" : "−")\(Fmt.num(abs(delta))) \(unit)"
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
          AxisGridLine().foregroundStyle(Theme.track)
          AxisValueLabel(format: .dateTime.month().day())
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine().foregroundStyle(Theme.track)
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
          AxisGridLine().foregroundStyle(Theme.track)
          AxisValueLabel(format: .dateTime.month().day())
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine().foregroundStyle(Theme.track)
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
      Text(displayName(muscle)).forgeCaption()
    }
  }

  private var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekVolume[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }

  private func displayName(_ muscle: Muscle) -> String {
    let spaced = muscle.rawValue.replacingOccurrences(of: "Delts", with: " delts")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
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
        .background(Circle().fill(Theme.accent.opacity(0.12)))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(subtitle).forgeCaption()
      }
      Spacer()
    }
    .card(padding: 14)
    .contentShape(Rectangle())
  }
}
