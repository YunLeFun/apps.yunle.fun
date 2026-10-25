import AppKit
import Foundation
import Security
import WebKit
import XCTest
@testable import YunleFunMac

/// Opt-in production validation using only the two existing managed accounts.
/// Credentials stay in native memory/unique Keychain items; page observations
/// return booleans and status codes, never identity records or session material.
@MainActor
final class MacManagedSSOLiveTests: XCTestCase {
    private var runtime: MacWebRuntime?
    private var accounts: AccountStore?
    private var window: NSWindow?
    private var heldStores: [UUID: WKWebsiteDataStore] = [:]
    private var directory: URL!
    private var checkpoint: Checkpoint!
    private var stage = "setup"
    private var completedStages: [String] = []
    private var draftKey: String { "mac-managed-sso-draft-" + checkpoint.run.uuidString }

    private struct Credential: Decodable {
        let id: String
        let environment: String
        let username: String
        let password: String
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Checkpoint: Codable {
        var version = 1
        let run: UUID
        var profiles: [UUID] = []
    }
    private struct Report: Codable {
        let run: UUID
        let mode: String
        let journeyPassed: Bool
        let cleanupComplete: Bool
        let failureStage: String?
        let completedStages: [String]
        let remainingProfiles: Int
    }
    private enum Failure: Error { case setup, observation, timedOut, cleanup }

    func testManagedPlayAutomaticSSOAndAccountIsolation() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YLF_MAC_MANAGED_SSO_ENABLED"] == "1" else {
            throw XCTSkip("Requires the explicit managed-account validation script")
        }
        guard Bundle.main.bundleIdentifier == "fun.yunle.macos.tests-host",
              let mode = env["YLF_MAC_MANAGED_SSO_MODE"], ["journey", "cleanup"].contains(mode),
              let rawRun = env["YLF_MAC_MANAGED_SSO_RUN_ID"], let run = UUID(uuidString: rawRun) else {
            return XCTFail("Managed SSO requires the isolated Testing host and a valid run UUID")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = cache.appendingPathComponent("MacManagedSSO-" + run.uuidString, isDirectory: true)
        let service = "fun.yunle.macos.managed-sso." + run.uuidString
        let vault = KeychainAccountVault(service: service)
        let journal = KeychainAccountVault(service: service + ".revocations")
        var failureStage: String?
        var journeyPassed = false
        var cleanupComplete = false
        do {
            try validatePrivateDirectory()
            if mode == "journey" {
                guard !FileManager.default.fileExists(atPath: checkpointURL.path),
                      try vault.read() == nil, try journal.read() == nil else { throw Failure.setup }
                checkpoint = Checkpoint(run: run)
                try saveCheckpoint()
            } else {
                checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL))
                guard checkpoint.version == 1, checkpoint.run == run, checkpoint.profiles.count <= 8,
                      Set(checkpoint.profiles).count == checkpoint.profiles.count else { throw Failure.setup }
            }
            // WebKit must initialize its main run loop before its class removal API.
            autoreleasepool {
                let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
                WKWebView(frame: .zero, configuration: config).stopLoading()
            }
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window?.title = "Managed SSO validation"
            window?.isReleasedWhenClosed = false
            window?.makeKeyAndOrderFront(nil)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            let auth = try ManagedHostAuth(journal: journal)
            if mode == "journey" {
                do {
                    let credentials = try consumeInput()
                    try await journey(credentials: credentials, vault: vault, auth: auth)
                    journeyPassed = true
                } catch { failureStage = stage }
            }
            mark("cleanup")
            cleanupComplete = await cleanup(vault: vault, journal: journal, auth: auth)
            if !cleanupComplete, failureStage == nil { failureStage = "cleanup" }
        } catch { failureStage = stage }

        // A setup failure must also destroy an unread one-use input. Recovery
        // metadata and Keychain entries remain until confirmed cleanup succeeds.
        let input = directory.appendingPathComponent("accounts.json")
        if FileManager.default.fileExists(atPath: input.path) {
            do { try FileManager.default.removeItem(at: input) }
            catch { cleanupComplete = false; failureStage = "input-cleanup" }
        }
        if !(await releaseRuntime()) { cleanupComplete = false; failureStage = "runtime-release" }
        window?.contentView = nil; window?.close(); window = nil
        if cleanupComplete {
            do { try FileManager.default.removeItem(at: directory) }
            catch { cleanupComplete = false; failureStage = "directory-cleanup" }
        }
        let report = Report(run: run, mode: mode, journeyPassed: journeyPassed,
                            cleanupComplete: cleanupComplete, failureStage: failureStage,
                            completedStages: completedStages, remainingProfiles: checkpoint?.profiles.count ?? 0)
        do {
            let reportURL = cache.appendingPathComponent("MacManagedSSO-\(run.uuidString)-\(mode).report.json")
            try writePrivate(JSONEncoder().encode(report), to: reportURL)
        } catch { cleanupComplete = false; failureStage = "report-cleanup" }
        print("[ManagedSSO] finished mode=\(mode) journeyPassed=\(journeyPassed) cleanupComplete=\(cleanupComplete)")
        XCTAssertTrue(cleanupComplete, "Managed SSO cleanup incomplete; use the recorded run UUID with --cleanup")
        if mode == "journey" { XCTAssertTrue(journeyPassed, "Managed SSO failed at safe stage: \(failureStage ?? "unknown")") }
    }

    private func journey(credentials: [Credential], vault: KeychainAccountVault, auth: ManagedHostAuth) async throws {
        let profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"),
                                            namespace: checkpoint.run.uuidString)
        let createdRuntime = MacWebRuntime(webProfiles: profiles)
        runtime = createdRuntime
        let store = AccountStore(session: AccountSession(api: auth, vault: vault),
                                 accountWillRemove: { try profiles.retire($0) },
                                 identityDidChange: { [weak createdRuntime] uid in createdRuntime?.accountDidChange(uid) })
        accounts = store
        createdRuntime.configureAuthorization(accounts: store, service: HostAuthorizationService())
        mark("public-play-catalog")
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        await catalog.load()
        guard !catalog.isCached, catalog.error == nil,
              let app = catalog.applications.first(where: { $0.marketShortName == "play" }),
              app.launchURL?.absoluteString == "https://play.yunle.fun/",
              MacWebNavigationPolicy.launchURL(for: app) != nil else { throw Failure.observation }
        completeStage()

        mark("account-a-auto-sso")
        try await store.passwordSignIn(identifier: credentials[0].username, password: credentials[0].password, captcha: nil)
        guard let ownerA = store.user?.id, store.user?.isUsable == true else { throw Failure.observation }
        let profileA = try await open(app, owner: ownerA, profiles: profiles)
        try await verifySignedIn(ownerA)
        try await writeDraft("account-a-draft")
        completeStage()

        mark("account-b-isolation-auto-sso")
        let oldA = WeakWebView(createdRuntime.webView)
        try await store.passwordSignIn(identifier: credentials[1].username, password: credentials[1].password, captcha: nil)
        guard let ownerB = store.user?.id, ownerB != ownerA, store.user?.isUsable == true,
              createdRuntime.webView == nil else { throw Failure.observation }
        window?.contentView = nil
        try await wait(seconds: 5) { oldA.value == nil }
        let profileB = try await open(app, owner: ownerB, profiles: profiles)
        guard profileB != profileA, try await draftMatches(nil) else { throw Failure.observation }
        try await verifySignedIn(ownerB)
        try await writeDraft("account-b-draft")
        completeStage()

        mark("account-a-restored-draft-and-remote-identity")
        try await store.select(ownerA)
        let restoredA = try await open(app, owner: ownerA, profiles: profiles)
        guard restoredA == profileA, try await draftMatches("account-a-draft") else { throw Failure.observation }
        try await verifySignedIn(ownerA)
        completeStage()

        mark("account-a-signout-and-guest-isolation")
        let removedA = WeakWebView(createdRuntime.webView)
        try await store.remove(ownerA)
        guard store.user == nil, store.notice == nil, createdRuntime.webView == nil else { throw Failure.observation }
        window?.contentView = nil
        try await wait(seconds: 5) { removedA.value == nil }
        let retired = try profiles.snapshot(for: .account(ownerA), application: app)
        guard retired.active == nil, retired.retained.contains(where: { $0.identifier == profileA }) else { throw Failure.observation }
        let guest = try await open(app, owner: nil, profiles: profiles)
        guard guest != profileA, guest != profileB, try await draftMatches(nil) else { throw Failure.observation }
        let guestRemote = try await remoteIdentity(in: currentWeb(), expectedOwner: "")
        guard guestRemote.status == 401, !guestRemote.identityMatches else { throw Failure.observation }
        // The real guest bridge may present native login. Returning to the
        // catalogue cancels that request; never complete or authorize it.
        createdRuntime.close()
        createdRuntime.terminate()
        window?.contentView = nil
        completeStage()

        mark("account-a-relogin-uses-new-profile")
        try await store.passwordSignIn(identifier: credentials[0].username, password: credentials[0].password, captcha: nil)
        guard store.user?.id == ownerA else { throw Failure.observation }
        let newA = try await open(app, owner: ownerA, profiles: profiles)
        guard ![profileA, profileB, guest].contains(newA), try await draftMatches(nil) else { throw Failure.observation }
        try await verifySignedIn(ownerA)
        completeStage()
    }

    private func open(_ app: CloudApplication, owner: String?, profiles: WebProfileRepository) async throws -> UUID {
        guard let runtime else { throw Failure.observation }
        let principal: WebProfileRepository.Principal = owner.map { .account($0) } ?? .guest
        let selected = try profiles.select(principal, application: app)
        if !checkpoint.profiles.contains(selected.identifier) {
            checkpoint.profiles.append(selected.identifier)
            try saveCheckpoint() // Record ownership before WebKit can create a store.
        }
        guard runtime.open(app), let web = runtime.webView,
              web.configuration.websiteDataStore.identifier == selected.identifier else { throw Failure.observation }
        heldStores[selected.identifier] = web.configuration.websiteDataStore
        window?.contentView = web
        window?.makeKeyAndOrderFront(nil)
        try await wait(seconds: 25) { (try? await self.pageState(web).ready) == true }
        return selected.identifier
    }

    private func verifySignedIn(_ owner: String) async throws {
        let web = try currentWeb()
        // Observe automatic adoption only. This fixture never clicks a login or
        // consent control and never directly invokes authorize on the page.
        try await wait(seconds: 30) { (try? await self.pageState(web).hasAccount) == true }
        let result = try await remoteIdentity(in: web, expectedOwner: owner)
        guard result.status == 200, result.identityMatches else { throw Failure.observation }
    }

    private struct PageState { let ready: Bool; let hasAccount: Bool; let hasLogin: Bool }
    private func pageState(_ web: WKWebView) async throws -> PageState {
        guard web.url?.scheme == "https", web.url?.host == "play.yunle.fun" else { throw Failure.observation }
        let value = try await evaluate(web, """
        return {
          ready: document.readyState === 'complete' && document.documentElement.dataset.appReady === 'true' && !!document.querySelector('.site-header'),
          hasAccount: !!document.querySelector('.header-session--account'),
          hasLogin: !!document.querySelector('.header-session--login:not(:disabled)')
        };
        """) as? [String: Bool] ?? [:]
        return PageState(ready: value["ready"] == true, hasAccount: value["hasAccount"] == true, hasLogin: value["hasLogin"] == true)
    }

    private struct RemoteIdentity { let status: Int; let identityMatches: Bool }
    private func remoteIdentity(in web: WKWebView, expectedOwner: String) async throws -> RemoteIdentity {
        guard web.url?.scheme == "https", web.url?.host == "play.yunle.fun" else { throw Failure.observation }
        let result = try await evaluate(web, """
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 6000);
        try {
          const response = await fetch('https://api.play.yunle.fun/v1/session', {
            credentials: 'include', cache: 'no-store', redirect: 'error',
            headers: { Accept: 'application/json' }, signal: controller.signal
          });
          const value = await response.json();
          return { status: response.status, identityMatches: response.status === 200 && value.ok === true &&
            expectedOwner.length > 0 && value.user?.userId === expectedOwner };
        } finally { clearTimeout(timer); }
        """, arguments: ["expectedOwner": expectedOwner])
        guard let fields = result as? [String: Any], let status = fields["status"] as? Int,
              let matches = fields["identityMatches"] as? Bool else { throw Failure.observation }
        return RemoteIdentity(status: status, identityMatches: matches)
    }

    private func writeDraft(_ value: String) async throws {
        _ = try await evaluate(currentWeb(), "localStorage.setItem(key, value); return true;",
                               arguments: ["key": draftKey, "value": value])
    }
    private func draftMatches(_ expected: String?) async throws -> Bool {
        try await evaluate(currentWeb(), "return localStorage.getItem(key) === expected;",
                           arguments: ["key": draftKey, "expected": expected as Any? ?? NSNull()]) as? Bool == true
    }
    private func currentWeb() throws -> WKWebView {
        guard let web = runtime?.webView else { throw Failure.observation }
        return web
    }

    private func cleanup(vault: KeychainAccountVault, journal: KeychainAccountVault, auth: ManagedHostAuth) async -> Bool {
        guard await releaseRuntime() else { return false }
        var succeeded = true
        for identifier in checkpoint.profiles {
            do {
                try await cleanConsumer(identifier)
                heldStores.removeValue(forKey: identifier)
                try await removeStore(identifier)
                checkpoint.profiles.removeAll { $0 == identifier }
                try saveCheckpoint()
            } catch { succeeded = false }
        }
        do {
            if let data = try vault.read() {
                try await auth.includeSavedAccounts(JSONDecoder().decode(AccountVaultState.self, from: data))
            }
            try await auth.revokeOutstanding()
            try deleteKeychainItem(service: vault.service)
            try deleteKeychainItem(service: journal.service)
            guard try vault.read() == nil, try journal.read() == nil else { throw Failure.cleanup }
        } catch { succeeded = false }
        heldStores.removeAll()
        return succeeded && checkpoint.profiles.isEmpty
    }

    private func cleanConsumer(_ identifier: UUID) async throws {
        var web: WKWebView?
        autoreleasepool {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = heldStores[identifier] ?? WKWebsiteDataStore(forIdentifier: identifier)
            // No bridge during cleanup: opening this page cannot authorize again.
            web = WKWebView(frame: .zero, configuration: config)
        }
        let released = WeakWebView(web)
        window?.contentView = web
        web?.load(URLRequest(url: URL(string: "https://play.yunle.fun/")!))
        var clean = false
        do {
            guard let page = web else { throw Failure.cleanup }
            try await wait(seconds: 25) {
                guard let state = try? await self.pageState(page) else { return false }
                return state.ready && (state.hasAccount || state.hasLogin)
            }
            _ = try await evaluate(page, "localStorage.removeItem(key); return true;", arguments: ["key": draftKey])
            if try await pageState(page).hasAccount {
                _ = try await evaluate(page, "document.querySelector('.header-session--account').click(); return true;")
                try await wait(seconds: 5) {
                    (try? await self.evaluate(page, "return !!document.querySelector('.header-account-menu__logout:not(:disabled)');")) as? Bool == true
                }
                _ = try await evaluate(page, "document.querySelector('.header-account-menu__logout').click(); return true;")
                try await wait(seconds: 15) { (try? await self.pageState(page).hasLogin) == true }
            }
            let result = try await remoteIdentity(in: page, expectedOwner: "")
            guard result.status == 401,
                  try await evaluate(page, "return localStorage.getItem(key) === null;", arguments: ["key": draftKey]) as? Bool == true else {
                throw Failure.cleanup
            }
            clean = true
        } catch { clean = false }
        web?.stopLoading(); web?.removeFromSuperview()
        window?.contentView = nil; web = nil
        try await wait(seconds: 5) { released.value == nil }
        guard clean else { throw Failure.cleanup }
    }

    private func releaseRuntime() async -> Bool {
        let released = WeakRuntime(runtime)
        runtime?.close(); runtime?.terminate()
        window?.contentView = nil
        accounts = nil; runtime = nil
        // The runtime owns the named store registry. Prove it was released
        // before deleting stores; a retained UI must not silently pass cleanup.
        for _ in 0..<100 {
            if released.value == nil { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func removeStore(_ identifier: UUID) async throws {
        let completion = CallbackResult<Void>()
        WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
            completion.finish(error.map { .failure($0) } ?? .success(()))
        }
        guard await XCTWaiter.fulfillment(of: [completion.completed], timeout: 10) == .completed else { throw Failure.timedOut }
        try completion.get()
    }

    private func evaluate(_ web: WKWebView, _ script: String, arguments: [String: Any] = [:]) async throws -> Any {
        let completion = CallbackResult<Any>()
        web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { completion.finish($0) }
        guard await XCTWaiter.fulfillment(of: [completion.completed], timeout: 8) == .completed else { throw Failure.timedOut }
        return try completion.get()
    }
    private func wait(seconds: TimeInterval, until condition: () async throws -> Bool) async throws {
        let limit = Date().addingTimeInterval(seconds)
        while Date() < limit {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw Failure.timedOut
    }

    private var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }
    private func saveCheckpoint() throws { try writePrivate(JSONEncoder().encode(checkpoint), to: checkpointURL) }
    private func validatePrivateDirectory() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw Failure.setup }
    }
    private func consumeInput() throws -> [Credential] {
        let input = directory.appendingPathComponent("accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { throw Failure.setup }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-zero-balance": "ylf_prod_zero", "production-standard": "ylf_prod_standard"]
        guard pool.accounts.count == 2, Set(pool.accounts.map(\.id)) == Set(expected.keys),
              pool.accounts.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty }),
              let first = pool.accounts.first(where: { $0.id == "production-zero-balance" }),
              let second = pool.accounts.first(where: { $0.id == "production-standard" }) else { throw Failure.setup }
        return [first, second]
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func deleteKeychainItem(service: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: "cloudbase-accounts-v1",
                                   kSecAttrSynchronizable as String: false] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.cleanup }
    }
    private func mark(_ value: String) { stage = value; print("[ManagedSSO] stage=" + value) }
    private func completeStage() { completedStages.append(stage) }
    private final class WeakWebView {
        weak var value: WKWebView?
        init(_ value: WKWebView?) { self.value = value }
    }
    private final class WeakRuntime {
        weak var value: MacWebRuntime?
        init(_ value: MacWebRuntime?) { self.value = value }
    }
}

/// Callbacks may arrive on a framework queue. No mutable state is captured by
/// concurrent closures; both completion and result access are lock protected.
final class CallbackResult<Value>: @unchecked Sendable {
    let completed = XCTestExpectation(description: "Managed validation operation completed")
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value; lock.unlock(); completed.fulfill()
    }
    func get() throws -> Value {
        lock.lock(); defer { lock.unlock() }
        guard let result else { throw AccountError.unavailable }
        return try result.get()
    }
}

/// Persist remote-revocation work before handing a real login to AccountSession.
/// AccountStore removes local credentials before remote sign-out; this separate
/// unique Keychain item makes a failed sign-out retryable after process exit.
actor ManagedHostAuth: AccountAuthenticating {
    private struct Entry: Codable, Equatable { let token: String; let deviceID: String }
    private let api = CloudbaseAuthService()
    private let journal: KeychainAccountVault
    private var entries: [Entry]
    init(journal: KeychainAccountVault) throws {
        self.journal = journal
        entries = try journal.read().map { try JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    private func remember(_ response: AuthTokenResponse, deviceID: String) async throws -> AuthTokenResponse {
        let entry = Entry(token: response.accessToken, deviceID: deviceID)
        do { try include(entry) }
        catch {
            // Keep the in-memory entry for cleanup even if the journal write
            // fails; do not publish an unrecorded host login to the runtime.
            throw AccountError.storage
        }
        return response
    }
    private func include(_ entry: Entry) throws {
        if !entries.contains(entry) { entries.append(entry) }
        try journal.write(JSONEncoder().encode(entries))
    }
    func includeSavedAccounts(_ state: AccountVaultState) throws {
        for account in state.accounts { try include(Entry(token: account.credential.accessToken, deviceID: state.deviceID)) }
    }
    func revokeOutstanding() async throws {
        var failed = false
        for entry in entries {
            do { try await signOut(accessToken: entry.token, deviceID: entry.deviceID) }
            catch { failed = true }
        }
        guard !failed, entries.isEmpty else { throw AccountError.unavailable }
    }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        let response = try await api.passwordSignIn(identifier: identifier, password: password, deviceID: deviceID, captcha: captcha)
        return try await remember(response, deviceID: deviceID)
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        let response = try await api.refresh(refreshToken, deviceID: deviceID)
        return try await remember(response, deviceID: deviceID)
    }
    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        try await api.user(accessToken: accessToken, deviceID: deviceID)
    }
    func signOut(accessToken: String, deviceID: String) async throws {
        do { try await api.signOut(accessToken: accessToken, deviceID: deviceID) }
        catch AccountError.expiredSession {
            // A previous successful revoke or rotation may already invalidate an
            // older journal entry; confirm it cannot read the host profile.
            do { _ = try await api.user(accessToken: accessToken, deviceID: deviceID); throw AccountError.unavailable }
            catch AccountError.expiredSession { }
        }
        entries.removeAll { $0.token == accessToken && $0.deviceID == deviceID }
        try journal.write(JSONEncoder().encode(entries))
    }
    // This fixture performs password login only; business/profile writes and
    // verification sends are never delegated to the production API.
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.unavailable }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw AccountError.unavailable }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { throw AccountError.unavailable }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.unavailable }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.unavailable }
}
