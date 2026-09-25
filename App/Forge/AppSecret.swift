import Foundation

enum AppSecret {
  static var bundled: String? {
    AppConfig.value("FORGE_APP_SECRET")
  }
  /// DEBUG: `-coachAppSecret <value>` stands in for a missing bundled secret (stubbed Coach E2E only).
  static var value: String? {
    #if DEBUG
    if bundled == nil, let debug = UserDefaults.standard.string(forKey: "coachAppSecret"), !debug.isEmpty { return debug }
    #endif
    return bundled ?? Keychain.get("forge-app-secret")
  }
}
