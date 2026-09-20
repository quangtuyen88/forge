import Foundation

enum AppConfig {
  static func value(_ key: String) -> String? {
    guard var value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count >= 2,
       (value.first == "\"" && value.last == "\"" || value.first == "'" && value.last == "'") {
      value.removeFirst()
      value.removeLast()
      value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
    return value
  }
}
