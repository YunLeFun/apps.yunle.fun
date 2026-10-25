import Foundation
import Security
import XCTest
@testable import YunleFunMac

final class MacKeychainTests: XCTestCase {
    func testRealKeychainPersistsRotationAndSignOutAcrossRebuiltSessions() async throws {
        // A fresh service is never shared with the application or another test.
        let service = "fun.yunle.macos.tests.account-restore." + UUID().uuidString
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "cloudbase-accounts-v1",
            kSecAttrSynchronizable as String: false,
        ]
        defer {
            let status = SecItemDelete(item as CFDictionary)
            XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound,
                          "Could not remove the test's exact Keychain item: \(status)")
        }

        let api = RestoreAPI()
        let signedInAt = Date(timeIntervalSince1970: 1_800_000_000)
        let original = AccountSession(api: api, vault: KeychainAccountVault(service: service), now: { signedInAt })
        try await original.passwordSignIn(identifier: "restore-user", password: "synthetic-password", captcha: nil)

        // Both vault and session are rebuilt so the following result comes from
        // Security.framework storage, not AccountSession's in-memory state.
        let restoredAt = signedInAt.addingTimeInterval(3_601)
        let restoredVault = KeychainAccountVault(service: service)
        let initial = try decode(restoredVault)
        XCTAssertEqual(initial.activeID, "restore-user")
        XCTAssertEqual(initial.accounts.first?.credential.accessToken, "original-access")
        let restored = AccountSession(api: api, vault: restoredVault, now: { restoredAt })
        try await restored.restore()

        let rotated = try decode(KeychainAccountVault(service: service))
        XCTAssertEqual(rotated.deviceID, initial.deviceID)
        XCTAssertEqual(rotated.accounts.first?.credential.accessToken, "rotated-access")
        XCTAssertEqual(rotated.accounts.first?.credential.refreshToken, "rotated-refresh")
        XCTAssertEqual(rotated.accounts.first?.credential.expiresAt, restoredAt.addingTimeInterval(3_600))

        let restarted = AccountSession(api: api, vault: KeychainAccountVault(service: service), now: { restoredAt })
        try await restarted.restore()
        let authorization = try await restarted.authorization()
        XCTAssertEqual(authorization.accessToken, "rotated-access")
        let revocation = try await restarted.remove("restore-user")
        let revoked = await revocation.value
        XCTAssertTrue(revoked)

        // Production logout saves an empty envelope to retain the device ID;
        // it must remove the credential before a subsequent session can load it.
        let signedOut = try decode(KeychainAccountVault(service: service))
        XCTAssertNil(signedOut.activeID)
        XCTAssertTrue(signedOut.accounts.isEmpty)
        XCTAssertEqual(signedOut.deviceID, initial.deviceID)
        let afterLogout = AccountSession(api: api, vault: KeychainAccountVault(service: service), now: { restoredAt })
        try await afterLogout.restore()
        do {
            _ = try await afterLogout.authorization()
            XCTFail("A removed Keychain credential must not restore an account")
        } catch {
            XCTAssertEqual(error as? AccountError, .signedOut)
        }
        let calls = await api.calls()
        XCTAssertEqual(calls.passwordSignIns, 1)
        XCTAssertEqual(calls.refreshTokens, ["original-refresh"])
        XCTAssertEqual(calls.signOutTokens, ["rotated-access"])
    }

    private func decode(_ vault: KeychainAccountVault) throws -> AccountVaultState {
        try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
    }
}
