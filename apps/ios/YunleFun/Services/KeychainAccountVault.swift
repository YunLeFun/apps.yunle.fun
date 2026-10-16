import Foundation
import Security

protocol AccountVault: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

struct KeychainAccountVault: AccountVault {
    let service: String
    private let account = "cloudbase-accounts-v1"

    init(service: String = (Bundle.main.bundleIdentifier ?? "fun.yunle.apps") + ".accounts") {
        self.service = service
    }

    func read() throws -> Data? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AccountError.storage }
        return data
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            attributes.forEach { item[$0.key] = $0.value }
            let inserted = SecItemAdd(item as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw AccountError.storage }
        } else if status != errSecSuccess { throw AccountError.storage }
    }

    // Logout writes an envelope without the removed account. One atomic item
    // keeps the selected account and rotated credentials consistent.
    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
}
