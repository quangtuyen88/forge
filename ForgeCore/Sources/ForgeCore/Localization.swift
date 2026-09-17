import Foundation

public enum ForgeCoreResources {
  nonisolated(unsafe) public static var languageCode: String?

  /// The module bundle, or its .lproj for the chosen language.
  public static var bundle: Bundle {
    guard let code = languageCode,
          let path = Bundle.module.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return .module }
    return bundle
  }
}

public func localizedDayName(_ name: String) -> String {
  String(localized: String.LocalizationValue(name), bundle: ForgeCoreResources.bundle)
}

public extension Exercise {
  /// Display name in the app language; `name` stays the English key used for matching and payloads.
  var localizedName: String {
    String(localized: String.LocalizationValue(name), bundle: ForgeCoreResources.bundle)
  }
}
