import Foundation
import Security

protocol TokenStore {
    func save(_ value: String, for key: String) throws
    func read(_ key: String) -> String?
    func delete(_ key: String)
}

final class KeychainTokenStore: TokenStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIError.unknown }
    }

    func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class AuthManager {
    private enum Keys {
        static let access = "access.token"
        static let refresh = "refresh.token"
    }

    private let tokenStore: TokenStore
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    var hasTokens: Bool {
        accessToken != nil && refreshToken != nil
    }

    func hasValidTokens() -> Bool {
        hasTokens
    }

    func currentAccessToken() -> String? {
        accessToken
    }

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        self.accessToken = tokenStore.read(Keys.access)
        self.refreshToken = tokenStore.read(Keys.refresh)
    }

    func updateTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        try? tokenStore.save(access, for: Keys.access)
        try? tokenStore.save(refresh, for: Keys.refresh)
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        tokenStore.delete(Keys.access)
        tokenStore.delete(Keys.refresh)
    }
}
