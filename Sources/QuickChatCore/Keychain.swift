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
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var q = query(account)
        q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// In-memory store for tests.
public final class MemoryKeyStore: KeyStoring {
    private var keys: [String: String] = [:]
    public init() {}
    public func key(for account: String) -> String? { keys[account] }
    public func setKey(_ value: String?, for account: String) { keys[account] = value }
}
