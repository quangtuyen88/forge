import Foundation

enum AppSecret {
static var bundled: String? {
    AppConfig.value("FORGE_APP_SECRET")
  }
  static var value: String? { bundled ?? Keychain.get("forge-app-secret") }
}
