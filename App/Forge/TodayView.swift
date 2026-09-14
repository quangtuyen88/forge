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
  @State private var sleepQuality = 3.0
  @State private var soreness = 3.0
  @State private var energy = 3.0
  @State private var sleepHours = 7.0
  @State private var sleepPrefilled = false

  private var profile: UserProfile? { profiles.first }

  private var fatigue: (score: Int, action: FatigueAction)? {
    fatigueNow(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  private var isForceRest: Bool {
    if case .forceRest = fatigue?.action { return true }
    return false
  }

  private var plannedDay: PlannedDay? {
    guard let profile else { return nil }
    let days = Program.week(profile.currentWeek, profile: profile.profileInput)
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

  private var weekHeader: String {
    guard let profile else { return "" }
    return profile.currentWeek == Mesocycle.deloadWeek ? "Deload" : "Week \(profile.currentWeek)"
  }

  var body: some View {
    NavigationStack {
      List {
        if let profile, let day = plannedDay {
          Section("\(weekHeader) · \(day.name)") {
            if let f = fatigue {
              fatigueCard(score: f.score, action: f.action)
            } else {
              checkInCard
            }
            ForEach(day.exercises, id: \.exercise.id) { planned in
              VStack(alignment: .leading, spacing: 2) {
                Text(planned.exercise.name)
                Text("\(planned.sets) sets × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) @ RPE \(planned.targetRPE, specifier: "%.0f")")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            if !isForceRest || trainAnyway {
              Button("Start workout") {
                activeAction = fatigue?.action ?? .proceed
                activeDay = plannedDay
              }
              .frame(maxWidth: .infinity)
              .buttonStyle(.borderedProminent)
            }
          }
        }
      }
      .navigationTitle("Today")
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
      }
    }
  }

  private var checkInCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Daily check-in").font(.headline)
      sliderRow("Sleep quality", $sleepQuality)
      sliderRow("Soreness", $soreness)
      sliderRow("Energy", $energy)
      Stepper(value: $sleepHours, in: 0...12, step: 0.5) {
        Text("Sleep hours: \(sleepHours, specifier: "%.1f")")
      }
      Button("Save check-in") {
        modelContext.insert(CheckIn(
          date: .now,
          sleep: Int(sleepQuality),
          soreness: Int(soreness),
          energy: Int(energy),
          sleepHours: sleepHours))
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.vertical, 4)
  }

  private func sliderRow(_ label: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(label): \(Int(value.wrappedValue))")
      Slider(value: value, in: 1...5, step: 1)
    }
  }

  private func fatigueCard(score: Int, action: FatigueAction) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Fatigue").font(.headline)
        Spacer()
        Text("\(score)")
          .font(.title.bold())
          .foregroundStyle(scoreColor(score))
      }
      Text(actionText(action))
        .font(.subheadline)
      if isForceRest && !trainAnyway {
        Button("Train anyway") { trainAnyway = true }
          .font(.subheadline)
      }
    }
    .padding(.vertical, 4)
  }

  private func scoreColor(_ score: Int) -> Color {
    if score < 40 { return .green }
    if score < 60 { return .yellow }
    if score < 80 { return .orange }
    return .red
  }

  private func actionText(_ action: FatigueAction) -> String {
    switch action {
    case .proceed: return "Proceed as planned"
    case .reduceOptionalSets: return "Fatigue rising: last set of each exercise dropped today"
    case .lightSession: return "Light session: −30% volume, RPE capped at 7"
    case .forceRest: return "Rest day recommended. Your fatigue score is high — train tomorrow."
    }
  }
}

extension PlannedDay: Identifiable {
  public var id: String { name }
}

func fatigueNow(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn]) -> (score: Int, action: FatigueAction)? {
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
  let baseline = recentCheckIns.isEmpty
    ? 7.0
    : recentCheckIns.reduce(0.0) { $0 + $1.sleepHours } / Double(recentCheckIns.count)
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
