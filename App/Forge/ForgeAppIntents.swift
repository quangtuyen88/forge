import AppIntents
import Foundation
import SwiftData
import ForgeCore

extension Notification.Name {
  static let forgeSkipRest = Notification.Name("forge.skipRest")
  static let forgeLogSet = Notification.Name("forge.logSet")
  static let forgeStartWorkout = Notification.Name("forge.startWorkout")
  static let forgeCheckIn = Notification.Name("forge.checkIn")
}

struct StartTodaysWorkoutIntent: AppIntent {
  static var title: LocalizedStringResource = "Start today's workout"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    UserDefaults(suiteName: WidgetBridge.suite)?.set(true, forKey: "forge.intent.startWorkout")
    return .result()
  }
}

struct LogSetIntent: AppIntent {
  static var title: LocalizedStringResource = "Log a set"
  static var openAppWhenRun = false

  @Parameter(title: "Set", description: "For example: deadlift 132.5x8 @8")
  var text: String?

  func perform() async throws -> some IntentResult {
    if let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      return .result(dialog: await logDialog(from: raw))
    }
    let defaults = UserDefaults(suiteName: WidgetBridge.suite)
    let heartbeat = defaults?.double(forKey: "forge.workout.heartbeat") ?? 0
    guard defaults?.bool(forKey: "forge.workout.active") == true,
          Date.now.timeIntervalSince1970 - heartbeat < 90 else {
      return .result(dialog: "Open Regulift and start a workout first.")
    }
    NotificationCenter.default.post(name: .forgeLogSet, object: nil)
    return .result(dialog: "Set logged.")
  }

  private func logDialog(from text: String) async -> IntentDialog {
    let (candidates, defaultLb, unitOverrides) = await MainActor.run { () -> ([QuickLogCandidate], Bool, [String: Bool]) in
      let context = ForgeApp.sharedContainer.mainContext
      let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
      let profile = profiles.first
      let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
      var candidates: [QuickLogCandidate] = []
      if let profile {
        let week = profile.currentWeek(sessions: sessions)
        let days = Program.week(week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
        if !days.isEmpty {
          let day = days[profile.nextDayIndex % days.count]
          for planned in day.exercises {
            candidates.append(QuickLogCandidate(id: planned.exercise.id, name: planned.exercise.name))
          }
        }
      }
      for exercise in ExerciseDB.everything {
        candidates.append(QuickLogCandidate(id: exercise.id, name: exercise.name))
      }
      return (candidates, profile?.usesLb ?? false, profile?.unitOverrides ?? [:])
    }
    guard let first = QuickLog.parse(text, candidates: candidates, defaultLb: defaultLb) else {
      return IntentDialog(stringLiteral: "Couldn't read that. Say the exercise, weight and reps, like deadlift 132.5 x 8.")
    }
    let exerciseLb = unitOverrides[first.exerciseID] ?? defaultLb
    let parse: QuickLogParse
    if exerciseLb != defaultLb,
       let reparsed = QuickLog.parse(text, candidates: candidates, defaultLb: exerciseLb) {
      parse = reparsed
    } else {
      parse = first
    }
    do {
      try await MainActor.run {
        _ = try SetInserter.insert(exerciseID: parse.exerciseID, weightKg: parse.weightKg, reps: parse.reps, rpe: parse.rpe)
      }
    } catch {
      return IntentDialog(stringLiteral: "Couldn't read that. Say the exercise, weight and reps, like deadlift 132.5 x 8.")
    }
    let name = ExerciseDB.find(parse.exerciseID)?.name ?? parse.exerciseID
    let lb = unitOverrides[parse.exerciseID] ?? defaultLb
    let unit = lb ? "lb" : "kg"
    let display = lb ? Plates.kgToLb(parse.weightKg) : parse.weightKg
    let dialog = "Logged \(name) \(Fmt.num(display)) \(unit) × \(parse.reps)."
    return IntentDialog(stringLiteral: dialog)
  }
}

struct AskCoachIntent: AppIntent {
  static var title: LocalizedStringResource = "Ask coach"
  static var openAppWhenRun = false

  @Parameter(title: "Question", requestValueDialog: "What do you want to ask your coach?")
  var question: String

  func perform() async throws -> some IntentResult {
    guard UserDefaults.standard.bool(forKey: "coachConsent") else {
      return .result(dialog: "Turn on the coach in Regulift first.")
    }
    let (contextText, coachName, notes) = await MainActor.run { () -> (String, String, [String]) in
      let context = ForgeApp.sharedContainer.mainContext
      let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
      let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
      let checkIns = (try? context.fetch(FetchDescriptor<CheckIn>())) ?? []
      let allNotes = (try? context.fetch(FetchDescriptor<CoachNote>())) ?? []
      let notes = Array(allNotes.sorted { $0.date > $1.date }.prefix(20).map(\.text))
      let coachName = Coach.from(UserDefaults.standard.string(forKey: Coach.storageKey) ?? "").name
      let contextText = CoachAPI.dataBlock(profile: profile, sessions: sessions, checkIns: checkIns, usesLb: profile?.usesLb ?? false)
      return (contextText, coachName, notes)
    }
    do {
      let reply = try await CoachAPI.ask(question: question, context: contextText, coach: coachName, history: [], notes: notes)
      return .result(dialog: IntentDialog(stringLiteral: reply.answer))
    } catch {
      return .result(dialog: "Coach is offline right now.")
    }
  }
}

struct CheckInIntent: AppIntent {
  static var title: LocalizedStringResource = "Check in"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    UserDefaults(suiteName: WidgetBridge.suite)?.set(true, forKey: "forge.intent.checkIn")
    return .result()
  }
}

struct ForgeShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartTodaysWorkoutIntent(),
      phrases: ["Start my workout in \(.applicationName)"],
      shortTitle: "Start workout",
      systemImageName: "flame.fill")
    AppShortcut(
      intent: LogSetIntent(),
      phrases: ["Log a set in \(.applicationName)"],
      shortTitle: "Log set",
      systemImageName: "checkmark")
    AppShortcut(
      intent: SkipRestIntent(),
      phrases: ["Skip rest in \(.applicationName)"],
      shortTitle: "Skip rest",
      systemImageName: "forward.fill")
    AppShortcut(
      intent: AskCoachIntent(),
      phrases: ["Ask my coach in \(.applicationName)"],
      shortTitle: "Ask coach",
      systemImageName: "bubble.left.fill")
    AppShortcut(
      intent: CheckInIntent(),
      phrases: ["Check in with \(.applicationName)"],
      shortTitle: "Check in",
      systemImageName: "heart.text.square")
  }
}
