import Foundation
import ForgeCore

/// Tiny UserDefaults store so a decision override survives from Today into the
/// logger and disappears when the session is done.
enum DecisionOverrides {
  private static let key = "forge.decisionOverrides"

  static func get(_ exerciseID: String) -> DecisionOverride? {
    guard let raw = dict[exerciseID] else { return nil }
    return DecisionOverride(rawValue: raw)
  }

  static func set(_ override: DecisionOverride?, for exerciseID: String) {
    var d = dict
    if let override {
      d[exerciseID] = override.rawValue
    } else {
      d.removeValue(forKey: exerciseID)
    }
    UserDefaults.standard.set(d, forKey: key)
  }

  static func clearAll() {
    UserDefaults.standard.removeObject(forKey: key)
  }

  private static var dict: [String: String] {
    (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
  }
}
