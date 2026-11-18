import Foundation
#if canImport(Security)
import Security
#endif

/// The API key. Keychain wins. `XAI_API_KEY` is used only when the Keychain item is empty.
/// File Wheel does not read other credential files.
enum XAIAPIKeyResolver {
    static func resolve(keychain: String?, environment: String?) -> String? {
        if let keychain, !keychain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keychain
        }
        if let environment, !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environment
        }
        return nil
    }
}

enum XAIKeychain {
    static let service = "app.filewheel.xai-api"
    static let account = "owner"

    static func currentKey() -> String? {
        let stored = read()
        let environment = ProcessInfo.processInfo.environment["XAI_API_KEY"]
        return XAIAPIKeyResolver.resolve(keychain: stored, environment: environment)
    }

    static func read() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        #if canImport(Security)
        delete()
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    static func delete() -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }
}
