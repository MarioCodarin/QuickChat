import Foundation
import Security

public protocol KeyStoring: AnyObject {
    func key(for account: String) -> String?
    func setKey(_ value: String?, for account: String)
}

/// API keys live in the macOS Keychain, never in the JSON file.
public final class SystemKeychain: KeyStoring {
    private let service = "io.github.mariocodarin.quickchat"

    public init() {}

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func key(for account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setKey(_ value: String?, for account: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            SecItemDelete(query(account) as CFDictionary)
            return
        }
        // Update in place so a failed write never destroys the previous working key.
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}

/// In-memory store for tests.
public final class MemoryKeyStore: KeyStoring {
    private var keys: [String: String] = [:]
    public init() {}
    public func key(for account: String) -> String? { keys[account] }
    public func setKey(_ value: String?, for account: String) { keys[account] = value }
}
