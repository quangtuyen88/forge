import Foundation

enum AppSecret {
  static var bundled: String? {
    let v = (Bundle.main.object(forInfoDictionaryKey: "FORGE_APP_SECRET") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (v?.isEmpty ?? true) ? nil : v
  }
  static var value: String? { bundled ?? Keychain.get("forge-app-secret") }
}
