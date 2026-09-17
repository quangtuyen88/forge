import Foundation
import ForgeCore

/// Resolves the user-chosen language to the matching .lproj bundle so strings switch without relaunch.
enum L10n {
  static let key = "appLanguage"
  nonisolated(unsafe) private static var code: String?
  nonisolated(unsafe) private static var cache: [String: Bundle] = [:]

  static let supported = ["en", "ja", "ko"]

  static func install() {
    var code = UserDefaults.standard.string(forKey: key) ?? ""
    if !supported.contains(code) {
      code = Locale.preferredLanguages
        .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        .first { supported.contains($0) && $0 != "en" } ?? "en"
      UserDefaults.standard.set(code, forKey: key)
    }
    apply(code)
  }

  static func apply(_ code: String) {
    Self.code = code
    cache = [:]
    ForgeCoreResources.languageCode = Self.code
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
