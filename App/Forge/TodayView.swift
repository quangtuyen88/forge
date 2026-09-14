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
  @State private var savedCheckInCount = 0
  @State private var showSettings = false

  private var profile: UserProfile? { profiles.first }

  private var fatigue: (score: Int, action: FatigueAction)? {
    fatigueNow(profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline)
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

  private func heroCard(_ day: PlannedDay) -> some View {
    HStack(alignment: .top, spacing: 12) {
      CoachAvatar(size: 44)
      VStack(alignment: .leading, spacing: 6) {
        Text(weekHeader.uppercased())
          .font(.footnote)
          .foregroundStyle(.secondary)
          .tracking(0.5)
        Text(day.name).font(.title2).bold()
        SpeechBubble {
          Text(coachLine).font(.subheadline)
        }
      }
      Spacer()
      if let f = fatigue {
        Gauge(value: Double(f.score), in: 0...100) {
        } currentValueLabel: {
          Text("\(f.score)").font(.headline).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(scoreColor(f.score))
      } else {
        Image(systemName: "moon.zzz")
          .font(.title)
          .foregroundStyle(.tertiary)
      }
    }
    .card()
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
    return VStack(alignment: .leading, spacing: 16) {
      Text("Today's plan").font(.headline)
      MuscleMapView(intensity: plannedIntensity(day))
        .frame(height: 200)
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
    HStack(spacing: 12) {
      Image(systemName: muscleSymbol(planned.exercise.primary))
        .foregroundStyle(.secondary)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Color(.tertiarySystemFill)))
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
        Text("\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
    }
    .contentShape(Rectangle())
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

  private func muscleSymbol(_ muscle: Muscle) -> String {
    switch muscle {
    case .chest: return "figure.strengthtraining.traditional"
    case .back: return "figure.rower"
    case .quads, .hamstrings, .glutes, .calves: return "figure.walk"
    case .frontDelts, .sideDelts, .rearDelts: return "figure.arms.open"
    case .triceps, .biceps: return "dumbbell"
    case .abs: return "figure.core.training"
    case .forearms: return "hand.raised"
    }
  }

  private func scoreColor(_ score: Int) -> Color {
    if score < 40 { return .green }
    if score < 60 { return .yellow }
    if score < 80 { return .orange }
    return .red
  }
}

extension PlannedDay: Identifiable {
  public var id: String { name }
}

func fatigueNow(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn], healthBaseline: Double? = nil) -> (score: Int, action: FatigueAction)? {
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
    missedRPESessionsLast7d: missed))
  return (score, Fatigue.action(forScore: score))
}
