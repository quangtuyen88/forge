import AppIntents
import Foundation

extension Notification.Name {
  static let forgeSkipRest = Notification.Name("forge.skipRest")
  static let forgeLogSet = Notification.Name("forge.logSet")
  static let forgeStartWorkout = Notification.Name("forge.startWorkout")
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

  func perform() async throws -> some IntentResult {
    let defaults = UserDefaults(suiteName: WidgetBridge.suite)
    let heartbeat = defaults?.double(forKey: "forge.workout.heartbeat") ?? 0
    guard defaults?.bool(forKey: "forge.workout.active") == true,
          Date.now.timeIntervalSince1970 - heartbeat < 90 else {
      return .result(dialog: "Open Regulift and start a workout first.")
    }
    NotificationCenter.default.post(name: .forgeLogSet, object: nil)
    return .result(dialog: "Set logged.")
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
  }
}
