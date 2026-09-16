import AppIntents
import Foundation

struct SkipRestIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Skip rest"

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: Notification.Name("forge.skipRest"), object: nil)
    return .result()
  }
}

struct LogNextSetIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Log set"

  func perform() async throws -> some IntentResult {
    let defaults = UserDefaults(suiteName: WidgetBridge.suite)
    let heartbeat = defaults?.double(forKey: "forge.workout.heartbeat") ?? 0
    guard defaults?.bool(forKey: "forge.workout.active") == true,
          Date.now.timeIntervalSince1970 - heartbeat < 90 else {
      return .result(dialog: "Open Regulift and start a workout first.")
    }
    NotificationCenter.default.post(name: Notification.Name("forge.logSet"), object: nil)
    return .result(dialog: "Set logged.")
  }
}
