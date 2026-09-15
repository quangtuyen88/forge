import Foundation
import WidgetKit

struct WidgetSnapshot: Codable {
  var dayName: String
  var minutes: Int
  var exercises: Int
  var streakWeeks: Int
  var weekSets: Int
  var weekTarget: Int
  var checkedIn: Bool
  var updated: Date
}

enum WidgetBridge {
  static let suite = "group.com.vnbnode.forge"
  private static let key = "forge.widget.snapshot"

  static func load() -> WidgetSnapshot? {
    guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }

  static func save(_ s: WidgetSnapshot) {
    if let defaults = UserDefaults(suiteName: suite), let data = try? JSONEncoder().encode(s) {
      defaults.set(data, forKey: key)
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
}
