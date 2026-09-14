import SwiftUI
import SwiftData
import ForgeCore

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  @State private var trainAnyway = false
  @State private var activeDay: PlannedDay?
  @State private var activeAction: FatigueAction = .proceed
  @State private var sleepQuality = 3
  @State private var soreness = 3
  @State private var energy = 3
  @State private var sleepHours = 7.0
  @State private var sleepPrefilled = false
  @State private var healthBaseline: Double?
  @State private var cardio: (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)?
  @State private var savedCheckInCount = 0
  @State private var showSettings = false

  private var profile: UserProfile? { profiles.first }

  private var fatigue: (score: Int, action: FatigueAction)? {
    fatigueNow(profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline, cardio: cardio)
  }

  private var isForceRest: Bool {
    if case .forceRest = fatigue?.action { return true }
    return false
  }

  private var plannedDay: PlannedDay? {
    guard let profile else { return nil }
    let days = Program.week(profile.currentWeek, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    guard !days.isEmpty else { return nil }
    var day = days[profile.nextDayIndex % days.count]
    switch fatigue?.action {
    case .reduceOptionalSets:
      day = PlannedDay(name: day.name, exercises: day.exercises.map {
        PlannedExercise(exercise: $0.exercise, sets: max(1, $0.sets - 1), repRange: $0.repRange, targetRPE: $0.targetRPE)
      })
    case .lightSession:
      day = PlannedDay(name: day.name, exercises: day.exercises.map {
        PlannedExercise(exercise: $0.exercise, sets: max(1, Int((Double($0.sets) * 0.7).rounded())), repRange: $0.repRange, targetRPE: min($0.targetRPE, 7))
      })
    default:
      break
    }
    return day
  }

  private var rotatedInIDs: Set<String> {
    guard let profile else { return [] }
    let days = Program.week(profile.currentWeek, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    let base = Program.week(profile.currentWeek, profile: profile.profileInput)
    guard !days.isEmpty else { return [] }
    let index = profile.nextDayIndex % days.count
    let baseIDs = Set(base[index].exercises.map(\.exercise.id))
    return Set(days[index].exercises.map(\.exercise.id).filter { !baseIDs.contains($0) })
  }

  private var weekHeader: String {
    guard let profile else { return "" }
    return profile.currentWeek == Mesocycle.deloadWeek ? "Deload week" : "Week \(profile.currentWeek) of \(Mesocycle.weeks)"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          if let day = plannedDay {
            heroCard(day)
            WeekStrip(sessions: sessions, plannedDays: profile?.daysPerWeek ?? 0)
              .card()
            statTiles
            if fatigue == nil {
              checkInCard
            } else {
              planCard(day)
            }
          }
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Today")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .safeAreaInset(edge: .bottom) { bottomBar }
      .sensoryFeedback(.success, trigger: savedCheckInCount)
      .sheet(item: $activeDay) { day in
        WorkoutView(plannedDay: day, action: activeAction)
      }
      .task {
        guard !sleepPrefilled else { return }
        sleepPrefilled = true
        await Health.requestAuthorization()
        if let hours = await Health.lastNightSleepHours() {
          sleepHours = min(12, max(0, (hours * 2).rounded() / 2))
        }
        healthBaseline = await Health.averageSleepHours()
        cardio = await Health.cardioSignals()
      }
    }
  }

  private var coachLine: String {
    guard let fatigue else { return "Check in and I'll set today's plan." }
    switch fatigue.action {
    case .proceed: return "All clear. Let's lift."
    case .reduceOptionalSets: return "Fatigue's up. I dropped your optional sets."
    case .lightSession: return "Light day. Keep RPE under 7."
    case .forceRest: return "Rest today. You've earned it."
    }
  }

  private var cardioLine: String {
    var parts: [String] = []
    if let hrv = cardio?.hrv { parts.append("HRV \(Int(hrv.rounded())) ms") }
    if let rhr = cardio?.rhr { parts.append("Resting HR \(Int(rhr.rounded()))") }
    return parts.joined(separator: " · ")
  }

  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var readiness: Int? {
    fatigue.map { 100 - $0.score }
  }

  private func heroCard(_ day: PlannedDay) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 8) {
        Text(weekHeader.uppercased())
          .font(.caption)
          .foregroundStyle(.white.opacity(0.7))
          .tracking(0.5)
        Text(day.name)
          .font(.largeTitle.bold())
          .foregroundStyle(.white)
          .minimumScaleFactor(0.8)
        SpeechBubble(tint: .white.opacity(0.12)) {
          Text(coachLine).font(.subheadline).foregroundStyle(.white)
        }
        if cardio?.hrv != nil || cardio?.rhr != nil {
          Text(cardioLine)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .monospacedDigit()
        }
      }
      .layoutPriority(1)
      VStack(alignment: .trailing, spacing: 8) {
        readinessRing
        Illustration(name: "coach-point", height: 150)
          .padding(.trailing, -16)
      }
    }
    .padding(16)
    .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  private var readinessRing: some View {
    ZStack {
      Canvas { context, canvas in
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = (min(canvas.width, canvas.height) - 8) / 2
        let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: bounds), with: .color(.white.opacity(0.15)), lineWidth: 6)
        if let fraction = readiness.map({ min(1, max(0, Double($0) / 100)) }), fraction > 0 {
          context.stroke(Path { p in
            p.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                     endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
          }, with: .color(Theme.accent), lineWidth: 6)
        }
      }
      VStack(spacing: 0) {
        Text(readiness.map { "\($0)" } ?? "--")
          .font(.title3.bold())
          .foregroundStyle(.white)
          .monospacedDigit()
        Text("READY")
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .frame(width: 72, height: 72)
  }

  private var statTiles: some View {
    HStack(spacing: 8) {
      StatTile(symbol: "flame.fill", value: "\(streakWeeks) wk", label: "streak")
      StatTile(symbol: "square.stack.3d.up.fill", value: "\(weekSets)", label: "sets this week")
      StatTile(symbol: "trophy.fill", value: bestE1RMText, label: "best e1RM")
    }
  }

  private var streakWeeks: Int {
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

  private var weekSets: Int {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { $0.completed && week.contains($0.date) }.reduce(0) { $0 + $1.sets.count }
  }

  private var bestE1RMText: String {
    let best = sessions.filter(\.completed).flatMap(\.sets)
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    guard let best else { return "—" }
    let value = usesLb ? Plates.kgToLb(best) : best
    return "\(Int(value.rounded())) \(unit)"
  }

  private var checkInCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      pickerRow("Sleep", $sleepQuality)
      pickerRow("Soreness", $soreness)
      pickerRow("Energy", $energy)
      Stepper(value: $sleepHours, in: 0...12, step: 0.5) {
        Text("Slept \(sleepHours, specifier: "%.1f") h").monospacedDigit()
      }
      Button("Save") {
        modelContext.insert(CheckIn(
          date: .now,
          sleep: sleepQuality,
          soreness: soreness,
          energy: energy,
          sleepHours: sleepHours))
        savedCheckInCount += 1
      }
      .buttonStyle(PillButtonStyle())
    }
    .card()
  }

  private func pickerRow(_ label: String, _ value: Binding<Int>) -> some View {
    HStack {
      Text(label)
      Spacer()
      Picker(label, selection: value) {
        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
      }
      .pickerStyle(.segmented)
      .frame(width: 200)
    }
  }

  private func planCard(_ day: PlannedDay) -> some View {
    let rotatedIn = rotatedInIDs
    let minutes = Int((Double(day.exercises.reduce(0) { $0 + $1.sets }) * 2.5 / 5).rounded() * 5)
    return VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Today's plan").font(.headline)
        Spacer()
        Text("≈ \(minutes) min")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      MuscleMapView(intensity: plannedIntensity(day))
        .frame(height: 180)
        .frame(maxWidth: .infinity)
      VStack(spacing: 0) {
        ForEach(Array(day.exercises.enumerated()), id: \.element.exercise.id) { index, planned in
          if index > 0 { Divider() }
          planRow(planned, rotatedIn: rotatedIn.contains(planned.exercise.id))
            .padding(.vertical, 12)
        }
      }
    }
    .card()
  }

  private func plannedIntensity(_ day: PlannedDay) -> [Muscle: Double] {
    var sets: [Muscle: Double] = [:]
    for e in day.exercises { sets[e.exercise.primary, default: 0] += Double(e.sets) }
    guard let max = sets.values.max(), max > 0 else { return [:] }
    return sets.mapValues { $0 / max }
  }

  private func planRow(_ planned: PlannedExercise, rotatedIn: Bool) -> some View {
    let kg = suggestedStartKg(for: planned, last: lastSets(planned.exercise.id), profile: profile)
    let display = usesLb ? Plates.kgToLb(kg) : kg
    return HStack(spacing: 12) {
      EquipmentThumb(equipment: planned.exercise.equipment)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(planned.exercise.name).font(.headline)
          if rotatedIn {
            Text("New variant")
              .font(.caption)
              .foregroundStyle(Theme.accent)
              .padding(.horizontal, 8).padding(.vertical, 2)
              .background(Theme.accent.opacity(0.12), in: Capsule())
          }
        }
        Text("\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · \(Int(display.rounded())) \(unit)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
      Text("RPE \(planned.targetRPE, specifier: "%.0f")")
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
    .contentShape(Rectangle())
  }

  private func lastSets(_ exerciseID: String) -> [LoggedSet] {
    for s in sessions.filter(\.completed).sorted(by: { $0.date > $1.date }) {
      let sets = s.sets.filter { $0.exerciseID == exerciseID }.sorted { $0.setIndex < $1.setIndex }
      if !sets.isEmpty { return sets }
    }
    return []
  }

  @ViewBuilder private var bottomBar: some View {
    if let day = plannedDay, fatigue != nil {
      if isForceRest && !trainAnyway {
        Button("Train anyway") { trainAnyway = true }
          .buttonStyle(PillSecondaryButtonStyle())
          .padding(16)
          .background(.bar)
      } else {
        Button("Start workout") {
          activeAction = fatigue?.action ?? .proceed
          activeDay = day
        }
        .buttonStyle(PillButtonStyle())
        .padding(16)
        .background(.bar)
      }
    }
  }
}

extension PlannedDay: Identifiable {
  public var id: String { name }
}

func fatigueNow(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn], healthBaseline: Double? = nil, cardio: (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)? = nil) -> (score: Int, action: FatigueAction)? {
  guard let ci = checkIns.last(where: { Calendar.current.isDateInToday($0.date) }), let profile = profile else { return nil }
  let now = Date.now
  func volume(_ windowDays: Double) -> Double {
    sessions
      .filter { $0.completed && now.timeIntervalSince($0.date) < windowDays * 86400 }
      .reduce(0) { total, session in
        total + session.sets.reduce(0) { t, set in
          guard let exercise = ExerciseDB.find(set.exerciseID) else { return t }
          let credit = Volume.credit(for: SetLog(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe), exercise: exercise)
          return t + credit.values.reduce(0, +)
        }
      }
  }
  let recentCheckIns = checkIns.filter { now.timeIntervalSince($0.date) < 7 * 86400 }
  let checkinBaseline = recentCheckIns.isEmpty
    ? 7.0
    : recentCheckIns.reduce(0.0) { $0 + $1.sleepHours } / Double(recentCheckIns.count)
  let baseline = healthBaseline ?? checkinBaseline
  let completed7 = sessions.filter { $0.completed && now.timeIntervalSince($0.date) < 7 * 86400 }
  let missed = completed7.filter { session in
    session.sets.contains { $0.rpe > $0.targetRPE + 1 }
  }.count
  // ponytail: <4 weeks of history scales the chronic window; PRD assumes a full 28 days
  let historyWeeks = min(4.0, max(1.0, ceil(now.timeIntervalSince(profile.mesoStart) / (7 * 86400))))
  let score = Fatigue.score(FatigueInputs(
    acuteVolume7d: volume(7),
    avgWeeklyVolume28d: volume(28) / historyWeeks,
    soreness: ci.soreness,
    sleepHoursLastNight: ci.sleepHours,
    sleepBaseline7d: baseline,
    sessionsLast7d: completed7.count,
    missedRPESessionsLast7d: missed,
    hrvLastNight: cardio?.hrv,
    hrvBaseline7d: cardio?.hrvBaseline,
    restingHRLastNight: cardio?.rhr,
    restingHRBaseline7d: cardio?.rhrBaseline))
  return (score, Fatigue.action(forScore: score))
}
