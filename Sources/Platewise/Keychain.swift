import Foundation
import Security

/// API keys live in the login Keychain, never in the JSON library file.
enum Keychain {
    private static let service = "local.platewise.Platewise"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves (or, for an empty value, removes) a key. Returns nil on success, else a readable error.
    @discardableResult
    static func set(_ value: String, for account: String) -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let s = SecItemDelete(base as CFDictionary)
            return s == errSecSuccess || s == errSecItemNotFound ? nil : message(s)
        }
        let data = Data(trimmed.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Platewise \(account) API key"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess ? nil : message(status)
    }

    private static func message(_ status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "Couldn't save to the Keychain: \(text)"
    }
}
