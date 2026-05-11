import Foundation
import Security

/// Pluggable token source for `ClaudeCodeAdapter`. Production uses
/// `KeychainTokenStore`; tests can swap in an in-memory implementation so
/// the adapter doesn't reach into the developer's keychain just to run a
/// hook-routing assertion.
protocol TokenStore {
    func loadOrCreate() throws -> String
}

struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String

    init(service: String = "app.sandfestival.claudecode.token", account: String = "default") {
        self.service = service
        self.account = account
    }

    /// Returns the persisted token, generating and storing a new UUID if none exists.
    func loadOrCreate() throws -> String {
        if let existing = try load() { return existing }
        let token = UUID().uuidString
        try save(token: token)
        return token
    }

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainTokenStoreError.invalidPayload
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.osStatus(status)
        }
    }

    func save(token: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        // Replace any existing value for this (service, account) pair.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainTokenStoreError.osStatus(status) }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.osStatus(status)
        }
    }
}

enum KeychainTokenStoreError: Error {
    case osStatus(OSStatus)
    case invalidPayload
}
