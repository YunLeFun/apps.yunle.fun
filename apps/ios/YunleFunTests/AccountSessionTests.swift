import Security
import XCTest
@testable import YunleFun

final class AccountSessionTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testAccountStoreChangesItsIdentityGenerationForEveryAccountTransition() async throws {
        let session = AccountSession(api: AccountTestAPI(), vault: try vaultWithAccounts(["a", "b"]), now: { self.fixedNow })
        let store = AccountStore(session: session)
        await store.restore()
        let first = store.identityGeneration
        await store.restore()
        XCTAssertEqual(store.identityGeneration, first, "Refreshing the same identity must not discard drafts")
        try await store.select("b")
        let second = store.identityGeneration
        XCTAssertNotEqual(first, second)
        try await store.select("a")
        XCTAssertNotEqual(store.identityGeneration, first, "A to B to A is still a different session")
        XCTAssertNotEqual(store.identityGeneration, second)
    }

    func testConcurrentAuthorizationRotatesOnceAndPersistsBeforeReturning() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(refreshGate: gate)
        let vault = try vaultWithAccounts(["a"], expired: true)
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let requests = (0..<24).map { _ in Task { try await session.authorization() } }
        await gate.waitUntilEntered()
        await gate.open()
        for request in requests {
            let identity = try await request.value
            XCTAssertEqual(identity.userID, "a")
            XCTAssertEqual(identity.accessToken, "rotated-a")
        }
        let count = await api.refreshCount
        XCTAssertEqual(count, 1)
        let saved = try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
        XCTAssertEqual(saved.accounts.first?.credential.refreshToken, "rotated-refresh-a")
    }

    func testSwitchDuringRefreshSavesRotationButRejectsTheOldRequest() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(refreshGate: gate)
        let vault = try vaultWithAccounts(["a", "b"], expired: true)
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let pending = Task { try await session.authorization() }
        await gate.waitUntilEntered()
        try await session.select("b")
        await gate.open()
        do { _ = try await pending.value; XCTFail("A's pending request must not run as B") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let state = try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
        XCTAssertEqual(state.activeID, "b")
        XCTAssertEqual(state.accounts.first?.credential.accessToken, "rotated-a")
    }

    func testLogoutWinsOverARefreshAlreadyInFlight() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(refreshGate: gate)
        let vault = try vaultWithAccounts(["a"], expired: true)
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let pending = Task { try await session.authorization() }
        await gate.waitUntilEntered()
        _ = try await session.remove("a")
        await gate.open()
        do { _ = try await pending.value; XCTFail("A removed account must not be recreated") }
        catch { XCTAssertEqual(error as? AccountError, .signedOut) }
        let overview = try await session.overview()
        XCTAssertNil(overview.activeID)
        XCTAssertTrue(overview.users.isEmpty)
    }

    func testCancelledLoginCannotReplaceTheCurrentAccount() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(userGate: gate)
        let vault = try vaultWithAccounts(["a"])
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let login = Task { try await session.passwordSignIn(identifier: "c", password: "test-password", captcha: nil) }
        await gate.waitUntilEntered()
        await session.cancelSignIn()
        await gate.open()
        do { try await login.value; XCTFail("Cancelled login must not commit") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let overview = try await session.overview()
        XCTAssertEqual(overview.activeID, "a")
        XCTAssertEqual(overview.users.map(\.id), ["a"])
    }

    func testLateProfileFailureCannotRemoveANewerLoginOfTheSameAccount() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(userGate: gate, rejectedUserToken: "original-a")
        let vault = try vaultWithAccounts(["a"])
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let profile = Task { try await session.refreshProfile() }
        await gate.waitUntilEntered()
        await api.disableUserGate()
        try await session.passwordSignIn(identifier: "a", password: "test-password", captcha: nil)
        await gate.open()
        do { try await profile.value; XCTFail("Stale profile must be ignored") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let identity = try await session.authorization()
        XCTAssertEqual(identity.accessToken, "login-a")
        let count = await api.refreshCount
        XCTAssertEqual(count, 0)
    }

    func testNetworkFailurePreservesTheAccountButRevokedRefreshRemovesIt() async throws {
        let vault = try vaultWithAccounts(["a"], expired: true)
        let api = AccountTestAPI(refreshFailure: .network)
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        let original = try vault.read()
        do { _ = try await session.authorization(); XCTFail("Offline authorization must fail explicitly") }
        catch { XCTAssertTrue(error is URLError) }
        XCTAssertEqual(try vault.read(), original)
        let offline = try await session.overview()
        XCTAssertEqual(offline.activeID, "a")
        await api.setRefreshFailure(.revoked)
        do { _ = try await session.authorization(); XCTFail("Revoked credentials cannot authorize") }
        catch { XCTAssertEqual(error as? AccountError, .expiredSession) }
        let revoked = try await session.overview()
        XCTAssertNil(revoked.activeID)
        XCTAssertTrue(revoked.users.isEmpty)
    }

    func testRotatedCredentialSurvivesATemporaryKeychainWriteFailureInMemory() async throws {
        let vault = try vaultWithAccounts(["a"], expired: true)
        let api = AccountTestAPI()
        let session = AccountSession(api: api, vault: vault, now: { self.fixedNow })
        _ = try await session.overview()
        vault.failNextWrite()
        do { _ = try await session.authorization(); XCTFail("Persistence must succeed before authorization returns") }
        catch { XCTAssertEqual(error as? AccountError, .storage) }
        let identity = try await session.authorization()
        XCTAssertEqual(identity.accessToken, "rotated-a")
        let count = await api.refreshCount
        XCTAssertEqual(count, 1, "The consumed refresh token must never be reused")
        let saved = try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
        XCTAssertEqual(saved.accounts.first?.credential.refreshToken, "rotated-refresh-a")
    }

    func testUnreadableVaultIsPreservedRatherThanReplacedByLogin() async throws {
        let original = Data("not-a-valid-account-envelope".utf8)
        let vault = MemoryAccountVault(data: original)
        let session = AccountSession(api: AccountTestAPI(), vault: vault)
        do { try await session.passwordSignIn(identifier: "a", password: "test-password", captcha: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .unsupportedVault) }
        XCTAssertEqual(try vault.read(), original)
    }

    func testActualKeychainRoundTripUsesDeviceOnlyProtection() throws {
        let service = "fun.yunle.apps.tests.\(UUID().uuidString)"
        let vault = KeychainAccountVault(service: service)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        defer { SecItemDelete(query as CFDictionary) }
        XCTAssertNil(try vault.read())
        try vault.write(Data("first-test-value".utf8))
        try vault.write(Data("rotated-test-value".utf8))
        XCTAssertEqual(try vault.read(), Data("rotated-test-value".utf8))
        var attributesQuery = query
        attributesQuery[kSecReturnAttributes as String] = true
        var attributes: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(attributesQuery as CFDictionary, &attributes), errSecSuccess)
        XCTAssertEqual((attributes as? [String: Any])?[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @MainActor
    func testAccountProjectionChangesBeforePublishingAndBeforeRemoteLogoutCompletes() async throws {
        let gate = AccountTestGate()
        let api = AccountTestAPI(signOutGate: gate)
        let vault = try vaultWithAccounts(["a", "b"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory)
        library.activateAccount("a")
        library.add(CloudApplication(id: "private-a", name: "A 的应用"))
        library.activateAccount(nil)
        library.add(CloudApplication(id: "guest", name: "访客应用"))
        weak var visibleStore: AccountStore?
        var previousIDs: [String?] = []
        let logoutPublished = expectation(description: "Local account projection cleared")
        let store = AccountStore(session: AccountSession(api: api, vault: vault, now: { self.fixedNow })) { id in
            previousIDs.append(visibleStore?.user?.id)
            library.activateAccount(id)
            if id == nil { logoutPublished.fulfill() }
        }
        visibleStore = store
        await store.restore()
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(previousIDs.count, 1)
        XCTAssertNil(previousIDs[0])
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["private-a"])
        try await store.select("b")
        XCTAssertEqual(previousIDs[1], "a", "Old metadata must remain unpublished until its data is cleared")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        let logout = Task { try await store.remove("b") }
        await gate.waitUntilEntered()
        await fulfillment(of: [logoutPublished], timeout: 2)
        XCTAssertNil(store.user, "Remote signout must not hold the old identity on screen")
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["guest"])
        await gate.open()
        try await logout.value
    }

    private func vaultWithAccounts(_ ids: [String], expired: Bool = false) throws -> MemoryAccountVault {
        var state = AccountVaultState()
        state.activeID = ids.first
        state.accounts = ids.map {
            SavedAccount(user: AccountUser(id: $0, name: "用户 \($0)"), credential: AccountCredential(
                accessToken: "original-\($0)", refreshToken: "refresh-\($0)",
                expiresAt: fixedNow.addingTimeInterval(expired ? -1 : 3600)))
        }
        return MemoryAccountVault(data: try JSONEncoder().encode(state))
    }
}

private final class MemoryAccountVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var fail = false
    init(data: Data? = nil) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if fail { fail = false; throw AccountError.storage }
        data = value
    }
    func failNextWrite() { lock.lock(); defer { lock.unlock() }; fail = true }
}

private actor AccountTestGate {
    private var entered = false
    private var opened = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        entryWaiters.forEach { $0.resume() }; entryWaiters = []
        if !opened { await withCheckedContinuation { held.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func open() { opened = true; held.forEach { $0.resume() }; held = [] }
}

private actor AccountTestAPI: AccountAuthenticating {
    enum RefreshFailure { case network, revoked }
    private(set) var refreshCount = 0
    private let refreshGate: AccountTestGate?
    private var userGate: AccountTestGate?
    private let signOutGate: AccountTestGate?
    private let rejectedUserToken: String?
    private var refreshFailure: RefreshFailure?
    init(refreshGate: AccountTestGate? = nil, userGate: AccountTestGate? = nil,
         rejectedUserToken: String? = nil, refreshFailure: RefreshFailure? = nil, signOutGate: AccountTestGate? = nil) {
        self.refreshGate = refreshGate; self.userGate = userGate
        self.rejectedUserToken = rejectedUserToken; self.refreshFailure = refreshFailure
        self.signOutGate = signOutGate
    }
    func disableUserGate() { userGate = nil }
    func setRefreshFailure(_ value: RefreshFailure) { refreshFailure = value }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        AuthTokenResponse(accessToken: "login-\(identifier)", refreshToken: "login-refresh-\(identifier)", expiresIn: 3600, subject: identifier)
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        refreshCount += 1
        await refreshGate?.wait()
        if refreshFailure == .network { throw URLError(.notConnectedToInternet) }
        if refreshFailure == .revoked { throw AccountError.expiredSession }
        let id = String(refreshToken.dropFirst("refresh-".count))
        return AuthTokenResponse(accessToken: "rotated-\(id)", refreshToken: "rotated-refresh-\(id)", expiresIn: 3600, subject: id)
    }
    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        await userGate?.wait()
        if accessToken == rejectedUserToken { throw AccountError.expiredSession }
        return AccountUser(id: String(accessToken.split(separator: "-").last!))
    }
    func signOut(accessToken: String, deviceID: String) async throws { await signOutGate?.wait() }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.unavailable }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw AccountError.unavailable }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.unavailable }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.unavailable }
}
