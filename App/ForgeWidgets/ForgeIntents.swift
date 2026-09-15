import AppIntents
import Foundation

struct SkipRestIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Skip rest"

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: Notification.Name("forge.skipRest"), object: nil)
    return .result()
  }
}
