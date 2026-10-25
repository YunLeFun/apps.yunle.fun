import Foundation
import XCTest
@testable import YunleFunMac

final class AccountRestoreTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testStorePublishesRestoredAccountAndIdentityChange() async throws {
        let vault = RestoreMemoryVault()
        let api = RestoreAPI()
        let now = instant
        let original = AccountStore(session: AccountSession(api: api, vault: vault, now: { now }))
        try await original.passwordSignIn(identifier: "restore-user", password: "synthetic-password", captcha: nil)

        var publishedIdentities: [String?] = []
        let restored = AccountStore(session: AccountSession(api: api, vault: vault, now: { now }),
                                    identityDidChange: { publishedIdentities.append($0) })
        let guestGeneration = restored.identityGeneration
        await restored.restore()

        XCTAssertEqual(restored.user?.id, "restore-user")
        XCTAssertEqual(restored.user?.name, "Restored profile")
        XCTAssertEqual(publishedIdentities, ["restore-user"])
        XCTAssertNotEqual(restored.identityGeneration, guestGeneration)
        XCTAssertFalse(restored.isRestoring)
        XCTAssertNil(restored.notice)
    }

    func testNewSessionRestoresPersistedLoginAndDeviceIdentity() async throws {
        let vault = RestoreMemoryVault()
        let api = RestoreAPI()
        let now = instant
        let first = AccountSession(api: api, vault: vault, now: { now })
        try await first.passwordSignIn(identifier: "restore-user", password: "synthetic-password", captcha: nil)
        let before = try savedState(in: vault)

        let restored = AccountSession(api: api, vault: vault, now: { now })
        try await restored.restore()
        let overview = try await restored.overview()
        let authorization = try await restored.authorization()
        let calls = await api.calls()

        XCTAssertEqual(overview.activeID, "restore-user")
        XCTAssertEqual(overview.activeUser?.name, "Restored profile")
        XCTAssertEqual(authorization.accessToken, "original-access")
        XCTAssertEqual(calls.passwordSignIns, 1)
        XCTAssertEqual(calls.profileTokens, ["original-access", "original-access"])
        XCTAssertTrue(calls.refreshTokens.isEmpty)
        XCTAssertEqual(Set(calls.deviceIDs), Set([before.deviceID]))
        XCTAssertEqual(try savedState(in: vault).deviceID, before.deviceID)
    }

    func testExpiredLoginRotatesTokensAndAnotherSessionUsesPersistedRotation() async throws {
        let vault = RestoreMemoryVault()
        let api = RestoreAPI()
        let signedInAt = instant
        let first = AccountSession(api: api, vault: vault, now: { signedInAt })
        try await first.passwordSignIn(identifier: "restore-user", password: "synthetic-password", captcha: nil)

        let restoredAt = instant.addingTimeInterval(3_601)
        let restored = AccountSession(api: api, vault: vault, now: { restoredAt })
        try await restored.restore()
        let saved = try savedState(in: vault)
        let credential = try XCTUnwrap(saved.accounts.first?.credential)
        XCTAssertEqual(credential.accessToken, "rotated-access")
        XCTAssertEqual(credential.refreshToken, "rotated-refresh")
        XCTAssertEqual(credential.expiresAt, restoredAt.addingTimeInterval(3_600))

        let restartedAt = restoredAt.addingTimeInterval(120)
        let restarted = AccountSession(api: api, vault: vault, now: { restartedAt })
        try await restarted.restore()
        let authorization = try await restarted.authorization()
        let calls = await api.calls()
        XCTAssertEqual(authorization.userID, "restore-user")
        XCTAssertEqual(authorization.accessToken, "rotated-access")
        XCTAssertEqual(calls.passwordSignIns, 1)
        XCTAssertEqual(calls.refreshTokens, ["original-refresh"])
        XCTAssertEqual(calls.profileTokens, ["original-access", "rotated-access", "rotated-access"])
    }

    func testLocalSignOutCannotRestoreEvenWhenRemoteRevocationFails() async throws {
        let vault = RestoreMemoryVault()
        let api = RestoreAPI(failSignOut: true)
        let now = instant
        let first = AccountSession(api: api, vault: vault, now: { now })
        try await first.passwordSignIn(identifier: "restore-user", password: "synthetic-password", captcha: nil)

        let revocation = try await first.remove("restore-user")
        let revoked = await revocation.value
        XCTAssertFalse(revoked)
        let saved = try savedState(in: vault)
        XCTAssertNil(saved.activeID)
        XCTAssertTrue(saved.accounts.isEmpty)

        let restored = AccountSession(api: api, vault: vault, now: { now })
        try await restored.restore()
        let overview = try await restored.overview()
        XCTAssertNil(overview.activeUser)
        XCTAssertTrue(overview.users.isEmpty)
        do {
            _ = try await restored.authorization()
            XCTFail("A locally removed account must not regain authorization after restart")
        } catch {
            XCTAssertEqual(error as? AccountError, .signedOut)
        }
        let calls = await api.calls()
        XCTAssertEqual(calls.signOutTokens, ["original-access"])
        XCTAssertEqual(calls.profileTokens, ["original-access"])
        XCTAssertTrue(calls.refreshTokens.isEmpty)
    }

    private func savedState(in vault: RestoreMemoryVault) throws -> AccountVaultState {
        try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
    }
}

// The iOS suite's helpers are private and import its app module. Keep this
// fixture small and exercise the same shared production AccountSession here.
private final class RestoreMemoryVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func read() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    func write(_ value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        data = value
    }
}

actor RestoreAPI: AccountAuthenticating {
    struct Calls: Sendable {
        var passwordSignIns = 0
        var profileTokens: [String] = []
        var refreshTokens: [String] = []
        var signOutTokens: [String] = []
        var deviceIDs: [String] = []
    }

    private var recorded = Calls()
    private let failSignOut: Bool
    init(failSignOut: Bool = false) { self.failSignOut = failSignOut }
    func calls() -> Calls { recorded }

    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        recorded.passwordSignIns += 1
        recorded.deviceIDs.append(deviceID)
        return AuthTokenResponse(accessToken: "original-access", refreshToken: "original-refresh", expiresIn: 3_600, subject: "restore-user")
    }

    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        recorded.profileTokens.append(accessToken)
        recorded.deviceIDs.append(deviceID)
        guard ["original-access", "rotated-access"].contains(accessToken) else { throw AccountError.expiredSession }
        return AccountUser(id: "restore-user", name: recorded.profileTokens.count == 1 ? "Original profile" : "Restored profile")
    }

    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        recorded.refreshTokens.append(refreshToken)
        recorded.deviceIDs.append(deviceID)
        guard refreshToken == "original-refresh", recorded.refreshTokens.count == 1 else { throw AccountError.expiredSession }
        return AuthTokenResponse(accessToken: "rotated-access", refreshToken: "rotated-refresh", expiresIn: 3_600, subject: "restore-user")
    }

    func signOut(accessToken: String, deviceID: String) async throws {
        recorded.signOutTokens.append(accessToken)
        recorded.deviceIDs.append(deviceID)
        if failSignOut { throw URLError(.notConnectedToInternet) }
    }

    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.unavailable }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw AccountError.unavailable }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { throw AccountError.unavailable }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.unavailable }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.unavailable }
}
