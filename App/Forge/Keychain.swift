import Foundation
import Security

enum Keychain {
  private static let service = "com.vnbnode.forge"
  private static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]

  static func set(_ value: String, for key: String) {
    delete(key)
    var query = base
    query[kSecAttrAccount as String] = key
    query[kSecValueData as String] = Data(value.utf8)
    SecItemAdd(query as CFDictionary, nil)
  }

  static func get(_ key: String) -> String? {
    var query = base
    query[kSecAttrAccount as String] = key
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(_ key: String) {
    var query = base
    query[kSecAttrAccount as String] = key
    SecItemDelete(query as CFDictionary)
  }
}
