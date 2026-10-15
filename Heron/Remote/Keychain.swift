import Foundation
import OSLog
import Security

private let log = Logger(subsystem: "com.voxyfy.heron", category: "keychain")

/// Connection passwords, passphrases and private keys, as generic passwords under Heron's own service.
enum Keychain {
    private static let service = "com.voxyfy.heron"

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound { log.error("Keychain read failed: \(status)") }
            return nil
        }
        // An empty password is never useful; treat it like none so the user is asked again.
        guard let password = String(data: data, encoding: .utf8), !password.isEmpty else { return nil }
        return password
    }

    /// Updates the saved password, or adds one. Returns false if Keychain refused both.
    @discardableResult
    static func setPassword(_ password: String, account: String) -> Bool {
        guard !password.isEmpty else {
            deletePassword(account: account)
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let value = [kSecValueData as String: Data(password.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if updated == errSecSuccess { return true }
        let added = SecItemAdd(query.merging(value) { $1 } as CFDictionary, nil)
        if added != errSecSuccess {
            log.error("Keychain refused password: update \(updated), add \(added)")
        }
        return added == errSecSuccess
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
