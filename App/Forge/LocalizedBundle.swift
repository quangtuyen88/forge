import Foundation
import ForgeCore

/// Resolves the user-chosen language to the matching .lproj bundle so strings switch without relaunch.
enum L10n {
  static let key = "appLanguage"
  nonisolated(unsafe) private static var code: String?
  nonisolated(unsafe) private static var cache: [String: Bundle] = [:]

  static let supported = ["en", "ja", "ko", "vi"]

  /// Follows the language iOS picked for the app (Settings › Regulift › Language); a
  /// `-appLanguage xx` launch argument still overrides it for tests and locale walks.
  static func install() {
    let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
    let system = Bundle.main.preferredLocalizations
      .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
      .first { supported.contains($0) }
    let code = [argument, system].compactMap { $0 }.first { supported.contains($0) } ?? "en"
    if argument == nil { UserDefaults.standard.set(code, forKey: key) }
    apply(code)
  }

  static func apply(_ code: String) {
    Self.code = code
    cache = [:]
    ForgeCoreResources.languageCode = Self.code
  }

  static var locale: Locale {
    Locale(identifier: UserDefaults.standard.string(forKey: key) ?? "en")
  }
  static var languageCode: String {
    UserDefaults.standard.string(forKey: key) ?? "en"
  }

  /// English plural "s" for a counted noun; ja, ko and vi do not inflect, so their entries get "".
  // ponytail: suffix plurals only; move to catalog plural variations if an inflecting language ships.
  static func pluralSuffix(_ count: Int) -> String {
    languageCode == "en" && count != 1 ? "s" : ""
  }

  /// Bundle for `String(localized:bundle:)` and `Text(_:bundle:)` in the app target.
  static var bundle: Bundle {
    resolve(in: .main)
  }

  static func resolve(in base: Bundle) -> Bundle {
    guard let code else { return base }
    let cacheKey = base.bundlePath + "/" + code
    if let hit = cache[cacheKey] { return hit }
    guard let path = base.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return base }
    cache[cacheKey] = bundle
    return bundle
  }
}
