import Foundation
import ForgeCore
import Observation

/// Decision overrides survive from Today into the logger and clear when the session ends.
/// Observable so a tap on Make easier redraws the row that shows the new load.
@Observable
final class DecisionOverrideStore {
  @MainActor static let shared = DecisionOverrideStore()

  private static let key = "forge.decisionOverrides"
  private var dict: [String: String]

  init() {
    dict = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
  }

  func get(_ exerciseID: String) -> DecisionOverride? {
    dict[exerciseID].flatMap(DecisionOverride.init(rawValue:))
  }

  func set(_ override: DecisionOverride?, for exerciseID: String) {
    if let override {
      dict[exerciseID] = override.rawValue
    } else {
      dict.removeValue(forKey: exerciseID)
    }
    UserDefaults.standard.set(dict, forKey: Self.key)
  }

  func clearAll() {
    dict = [:]
    UserDefaults.standard.removeObject(forKey: Self.key)
  }
}

/// Call-site facade. Reads go through the observable store, so views that read one
/// during body evaluation redraw as soon as it changes.
enum DecisionOverrides {
  @MainActor static func get(_ exerciseID: String) -> DecisionOverride? {
    DecisionOverrideStore.shared.get(exerciseID)
  }

  @MainActor static func set(_ override: DecisionOverride?, for exerciseID: String) {
    DecisionOverrideStore.shared.set(override, for: exerciseID)
  }

  @MainActor static func clearAll() {
    DecisionOverrideStore.shared.clearAll()
  }
}
