import AppKit
import Foundation
import Security
import WebKit
import XCTest
@testable import YunleFunMac

/// A human/CUA operates the real consumer, native consent and system browser.
/// Handshakes report visible observations only; they never supply an auth result.
@MainActor
final class MacOtherAccountLiveTests: XCTestCase {
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
        var completedStages: [String] = []
        // Optional fields preserve recovery of checkpoints from the first
        // harness version. Purge requires all of them to be confirmed.
        var signedOutProfiles: [UUID]?
        var hostSessionsRevoked: Bool?
        // Completion of the owned SDK/API logout workflow and anonymous read;
        // this does not assert immediate invalidation of a previously issued JWT.
        var remoteCleanupComplete: Bool?
        var remoteCleanupProcessID: Int32?
        // A system browser login cannot be remotely revoked without its own
        // credentials/device ID. Never report this as a completed remote logout.
        var centralBrowserSessionsMayExist = false
    }
    private struct Handshake: Codable {
        let run: UUID
        let stage: String
        let nonce: UUID
        let instruction: String
    }
    private struct Acknowledgement: Decodable {
        let run: UUID
        let stage: String
        let nonce: UUID
        let observed: String
    }
    private struct Report: Encodable {
        let run: UUID
        let mode: String
        let journeyPassed: Bool
        let phasePassed: Bool
        let completeIncludingStorePurge: Bool
        let pendingStorePurge: Bool
        let currentProcessID: Int32
        let remoteCleanupProcessID: Int32?
        let ownedHostAndConsumerCleanupComplete: Bool
        let consumerSDKSignOutComplete: Bool
        let consumerAnonymousRemoteCheckComplete: Bool
        let hostRemoteSignOutComplete: Bool
        let ownedWebsiteStoresRemoved: Bool
        let failureStage: String?
        let completedStages: [String]
        let remainingProfiles: Int
        let cleanupDiagnostics: [String]
        let centralBrowserSessionsMayExist: Bool
        let centralSessionRemoteRevocation = "not-observed"
        let centralBrowserLifetime = "ephemeral-browser-requested-server-session-expiry-not-observed"
    }
    private struct RemoteIdentity { let status: Int; let matches: Bool }
    private enum Failure: Error { case setup, observation, timedOut, cleanup }
    private var directory: URL!
    private var checkpoint: Checkpoint!
    private var runtime: MacWebRuntime?
    private var accounts: AccountStore?
    private var window: NSWindow?
    private var heldStores: [UUID: WKWebsiteDataStore] = [:]
    private var stage = "setup"
    private var consumerCleanupComplete = false
    private var consumerAnonymousCheckComplete = false
    private var hostCleanupComplete = false
    private var storesCleanupComplete = false
    private var cleanupDiagnostics: [String] = []
    private var remotelyCleanProfiles = Set<UUID>()
    private var sdkCleanProfiles = Set<UUID>()
    private var draftKey: String { "mac-other-account-draft-" + checkpoint.run.uuidString }
    private var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }

    func testRealSystemOtherAccountAndCancellation() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YLF_MAC_OTHER_SSO_ENABLED"] == "1" else {
            throw XCTSkip("Requires the explicit other-account UI validation script")
        }
        guard Bundle.main.bundleIdentifier == "fun.yunle.macos.tests-host",
              let mode = env["YLF_MAC_OTHER_SSO_MODE"], ["journey", "cleanup", "purge"].contains(mode),
              let run = env["YLF_MAC_OTHER_SSO_RUN_ID"].flatMap(UUID.init(uuidString:)) else {
            return XCTFail("Requires isolated Testing host and exact run UUID")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = cache.appendingPathComponent("MacOtherAccountSSO-" + run.uuidString)
        let vault = KeychainAccountVault(service: "fun.yunle.macos.other-sso." + run.uuidString)
        let journal = KeychainAccountVault(service: vault.service + ".revocations")
        var journeyPassed = false
        var cleanupComplete = false
        var failureStage: String?
        do {
            try validatePrivate(directory, permissions: 0o700, directory: true)
            if mode == "journey" {
                guard !FileManager.default.fileExists(atPath: checkpointURL.path),
                      try vault.read() == nil, try journal.read() == nil else { throw Failure.setup }
                checkpoint = Checkpoint(run: run)
                try saveCheckpoint()
            } else {
                try validatePrivate(checkpointURL, permissions: 0o600)
                checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL))
                guard checkpoint.version == 1, checkpoint.run == run, checkpoint.profiles.count <= 4,
                      Set(checkpoint.profiles).count == checkpoint.profiles.count,
                      (checkpoint.signedOutProfiles?.count ?? 0) <= 4 else { throw Failure.setup }
            }
            autoreleasepool {
                let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
                WKWebView(frame: .zero, configuration: config).stopLoading()
            }
            if mode == "purge" {
                mark("purge-confirmed-stores-in-new-process")
                cleanupComplete = await purge(vault: vault, journal: journal)
            } else {
                autoreleasepool {
                    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                    window?.isReleasedWhenClosed = false
                    window?.title = "Other account SSO validation"
                    window?.makeKeyAndOrderFront(nil)
                    NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
                }
                let auth = try ManagedHostAuth(journal: journal)
                if mode == "journey" {
                    do {
                        try await journey(credentials: consumeInput(), vault: vault, auth: auth)
                        journeyPassed = true
                    } catch { failureStage = stage }
                }
                mark("remote-cleanup-before-process-exit")
                cleanupComplete = await cleanup(vault: vault, journal: journal, auth: auth)
            }
            if !cleanupComplete, failureStage == nil { failureStage = stage }
        } catch { failureStage = stage }

        for name in ["accounts.json", "handshake.json", "ack.json"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { cleanupComplete = false; failureStage = "input-cleanup" }
            }
        }
        if !(await releaseRuntime()) { cleanupComplete = false; failureStage = "runtime-release" }
        autoreleasepool {
            window?.makeFirstResponder(nil); window?.contentView = nil
            window?.close(); window = nil
        }
        if cleanupComplete && mode == "purge" {
            do { try FileManager.default.removeItem(at: directory) }
            catch { cleanupComplete = false; failureStage = "directory-cleanup" }
        }
        let report = Report(run: run, mode: mode, journeyPassed: journeyPassed,
                            phasePassed: cleanupComplete && (mode != "journey" || journeyPassed),
                            completeIncludingStorePurge: cleanupComplete && mode == "purge",
                            pendingStorePurge: cleanupComplete && mode != "purge",
                            currentProcessID: ProcessInfo.processInfo.processIdentifier,
                            remoteCleanupProcessID: checkpoint?.remoteCleanupProcessID,
                            ownedHostAndConsumerCleanupComplete: cleanupComplete,
                            consumerSDKSignOutComplete: consumerCleanupComplete,
                            consumerAnonymousRemoteCheckComplete: consumerAnonymousCheckComplete,
                            hostRemoteSignOutComplete: hostCleanupComplete,
                            ownedWebsiteStoresRemoved: storesCleanupComplete, failureStage: failureStage,
                            completedStages: checkpoint?.completedStages ?? [],
                            remainingProfiles: checkpoint?.profiles.count ?? 0,
                            cleanupDiagnostics: cleanupDiagnostics,
                            centralBrowserSessionsMayExist: checkpoint?.centralBrowserSessionsMayExist ?? false)
        do {
            try writePrivate(JSONEncoder().encode(report), to: cache.appendingPathComponent("MacOtherAccountSSO-\(run.uuidString)-\(mode).report.json"))
        } catch { cleanupComplete = false; failureStage = "report-write" }
        print("[OtherAccountSSO] finished mode=\(mode) journeyPassed=\(journeyPassed) phaseCleanupComplete=\(cleanupComplete) storesRemoved=\(storesCleanupComplete)")
        XCTAssertTrue(cleanupComplete, "Owned host/consumer cleanup incomplete; retry exact run --cleanup")
        XCTAssertTrue(consumerCleanupComplete, "Consumer SDK logout must succeed and its local session must be empty")
        XCTAssertTrue(consumerAnonymousCheckComplete, "Consumer anonymous request must freshly return HTTP 401")
        XCTAssertTrue(hostCleanupComplete, "Owned native host sessions must be revoked")
        if mode == "purge" { XCTAssertTrue(storesCleanupComplete, "Every owned WebKit store must be removed") }
        if mode == "journey" { XCTAssertTrue(journeyPassed, "Other-account journey failed at safe stage: \(failureStage ?? "unknown")") }
    }

    private func journey(credentials: [Credential], vault: KeychainAccountVault, auth: ManagedHostAuth) async throws {
        let profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: checkpoint.run.uuidString)
        let created = autoreleasepool { MacWebRuntime(webProfiles: profiles) }
        runtime = created
        let store = AccountStore(session: AccountSession(api: auth, vault: vault),
                                 accountWillRemove: { try profiles.retire($0) },
                                 identityDidChange: { [weak created] owner in
                                     autoreleasepool { created?.accountDidChange(owner) }
                                 })
        accounts = store
        // Actual production UI, bridge, issuer, system browser and callback path.
        autoreleasepool { created.configureAuthorization(accounts: store, service: HostAuthorizationService()) }
        mark("host-a-and-consumer-baseline")
        try await store.passwordSignIn(identifier: credentials[0].username, password: credentials[0].password, captcha: nil)
        guard let ownerA = store.user?.id else { throw Failure.observation }
        let generation = store.identityGeneration
        // Obtain B's comparison identity without selecting it in the host. The
        // short-lived probe is journaled before use and immediately signed out.
        let probeDevice = UUID().uuidString
        let probe = try await auth.passwordSignIn(identifier: credentials[1].username, password: credentials[1].password,
                                                  deviceID: probeDevice, captcha: nil)
        let ownerB = try await auth.user(accessToken: probe.accessToken, deviceID: probeDevice).id
        try await auth.signOut(accessToken: probe.accessToken, deviceID: probeDevice)
        guard ownerA != ownerB else { throw Failure.observation }
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        await catalog.load()
        guard !catalog.isCached, catalog.error == nil,
              let app = catalog.applications.first(where: { $0.marketShortName == "ai-sfc" }),
              app.launchURL?.absoluteString == "https://ai-sfc.yunle.fun/" else { throw Failure.observation }
        let original = try await open(app, owner: ownerA, profiles: profiles)
        try await assertAnonymous()
        try await writeDraft("before-login")
        try completeStage()

        try await handshake("cancel-first-system-session", observation: "system-login-empty-then-cancelled",
                            instruction: "Click consumer Login, native Other account, observe empty system-browser login, cancel that system window, then acknowledge.")
        try assertHost(ownerA, generation: generation, profile: original)
        try await assertAnonymous()
        guard try await draftMatches("before-login") else { throw Failure.observation }
        try completeStage()

        checkpoint.centralBrowserSessionsMayExist = true
        try saveCheckpoint() // Before a UI action can create a remote session.
        try await handshake("login-b-system-session", observation: "system-login-empty-b-completed",
                            instruction: "Click consumer Login, native Other account, verify fresh empty system login, sign in managed B and authorize; acknowledge only after real callback closes the system window.")
        try assertHost(ownerA, generation: generation, profile: original)
        try await assertSignedIn(ownerB)
        guard try await draftMatches("before-login") else { throw Failure.observation }
        try await writeDraft("consumer-b-draft")
        try completeStage()

        try await handshake("website-logout-b-and-cancel-retry", observation: "website-logout-system-login-empty-then-cancelled",
                            instruction: "Use consumer account menu Logout, then Login, native Other account; observe a new empty system login and cancel it. Acknowledge after returning to the consumer.")
        try assertHost(ownerA, generation: generation, profile: original)
        try await assertAnonymous()
        guard try await draftMatches("consumer-b-draft") else { throw Failure.observation }
        try completeStage()

        try await handshake("relogin-b-system-session", observation: "system-login-empty-b-completed",
                            instruction: "Click consumer Login, native Other account; verify empty system login, sign in managed B and authorize, then acknowledge after callback.")
        try assertHost(ownerA, generation: generation, profile: original)
        try await assertSignedIn(ownerB)
        try completeStage()

        mark("host-signout-account-removed")
        let released = autoreleasepool { WeakWebView(created.webView) }
        try await store.remove(ownerA)
        guard store.user == nil, store.notice == nil, created.webView == nil else { throw Failure.observation }
        try completeStage()
        mark("host-signout-old-document-destroyed")
        autoreleasepool {
            window?.makeFirstResponder(nil)
            window?.contentView = nil
        }
        await Task.yield()
        guard runtimeHasNoPages(created) else { throw Failure.observation }
        try await assertTerminatedDocument(released)
        try completeStage()
        mark("host-signout-profile-retired")
        let retired = try profiles.snapshot(for: .account(ownerA), application: app)
        guard retired.active == nil, retired.retained.contains(where: { $0.identifier == original }) else { throw Failure.observation }
        try completeStage()
        mark("host-signout-guest-new-profile")
        let guest = try await open(app, owner: nil, profiles: profiles)
        guard guest != original, try await draftMatches(nil) else { throw Failure.observation }
        try completeStage()
        mark("host-signout-guest-remote-401")
        try await assertAnonymous()
        autoreleasepool {
            created.close(); created.terminate()
            window?.makeFirstResponder(nil); window?.contentView = nil
        }
        try completeStage()

        mark("host-a-relogin-new-consumer-profile")
        try await store.passwordSignIn(identifier: credentials[0].username, password: credentials[0].password, captcha: nil)
        guard store.user?.id == ownerA else { throw Failure.observation }
        let fresh = try await open(app, owner: ownerA, profiles: profiles)
        guard fresh != original, fresh != guest, try await draftMatches(nil) else { throw Failure.observation }
        try await assertAnonymous()
        try completeStage()
        try await handshake("authorize-current-host-a", observation: "native-current-account-authorized",
                            instruction: "Click consumer Login and native Continue with current account A. Do not choose Other account. Acknowledge after the consumer is signed in.")
        try await assertSignedIn(ownerA)
        guard store.user?.id == ownerA, try await draftMatches(nil) else { throw Failure.observation }
        try completeStage()
    }

    private func handshake(_ name: String, observation: String, instruction: String) async throws {
        mark(name)
        let value = Handshake(run: checkpoint.run, stage: name, nonce: UUID(), instruction: instruction)
        let ackURL = directory.appendingPathComponent("ack.json")
        if FileManager.default.fileExists(atPath: ackURL.path) { try FileManager.default.removeItem(at: ackURL) }
        try writePrivate(JSONEncoder().encode(value), to: directory.appendingPathComponent("handshake.json"))
        try await wait(seconds: 600) {
            guard FileManager.default.fileExists(atPath: ackURL.path) else { return false }
            try self.validatePrivate(ackURL, permissions: 0o600)
            let ack = try JSONDecoder().decode(Acknowledgement.self, from: Data(contentsOf: ackURL))
            guard ack.run == value.run, ack.stage == value.stage, ack.nonce == value.nonce,
                  ack.observed == observation else { throw Failure.observation }
            try FileManager.default.removeItem(at: ackURL)
            try FileManager.default.removeItem(at: self.directory.appendingPathComponent("handshake.json"))
            return true
        }
    }

    private func open(_ app: CloudApplication, owner: String?, profiles: WebProfileRepository) async throws -> UUID {
        let selected = try profiles.select(owner.map { .account($0) } ?? .guest, application: app)
        if !checkpoint.profiles.contains(selected.identifier) {
            checkpoint.profiles.append(selected.identifier); try saveCheckpoint()
        }
        let web = try autoreleasepool {
            guard let runtime, runtime.open(app), let web = runtime.webView,
                  web.configuration.websiteDataStore.identifier == selected.identifier else { throw Failure.observation }
            heldStores[selected.identifier] = web.configuration.websiteDataStore
            window?.contentView = web; window?.makeKeyAndOrderFront(nil)
            return web
        }
        try await wait(seconds: 25) { (try? await self.pageReady(web)) == true }
        return selected.identifier
    }
    private func assertHost(_ owner: String, generation: UUID, profile: UUID) throws {
        try autoreleasepool {
            guard accounts?.user?.id == owner, accounts?.identityGeneration == generation,
                  accounts?.overview.activeID == owner, accounts?.overview.users.map(\.id) == [owner],
                  runtime?.webView?.configuration.websiteDataStore.identifier == profile else { throw Failure.observation }
        }
    }
    private func assertAnonymous() async throws {
        let web = try currentWeb()
        try await wait(seconds: 10) {
            (try? await self.evaluate(web, "return !!document.querySelector('button.account-login:not(:disabled)');")) as? Bool == true
        }
        let remote = try await remoteIdentity(web, owner: "")
        guard remote.status == 401, !remote.matches else { throw Failure.observation }
    }
    private func assertSignedIn(_ owner: String) async throws {
        let web = try currentWeb()
        try await wait(seconds: 20) {
            (try? await self.evaluate(web, "return !!document.querySelector('button.account-trigger');")) as? Bool == true
        }
        let remote = try await remoteIdentity(web, owner: owner)
        guard remote.status == 200, remote.matches else { throw Failure.observation }
    }
    private func pageReady(_ web: WKWebView) async throws -> Bool {
        guard web.url?.scheme == "https", web.url?.host == "ai-sfc.yunle.fun" else { return false }
        return try await evaluate(web, "return document.readyState === 'complete' && !!document.querySelector('button.account-login,button.account-trigger');") as? Bool == true
    }
    private func remoteIdentity(_ web: WKWebView, owner: String) async throws -> RemoteIdentity {
        guard web.url?.scheme == "https", web.url?.host == "ai-sfc.yunle.fun" else { throw Failure.observation }
        let result = try await evaluate(web, """
        // This is the inspected production app singleton, shared with its UI.
        // Its credentials remain in this page and never cross the native bridge.
        const module = await import('/_nuxt/X4HmLciw.js');
        const auth = module.a().auth({ persistence: 'local' });
        const sessionResult = await auth.getSession();
        if (sessionResult.error) throw new Error('consumer-session-read-failed');
        const session = sessionResult.data?.session;
        const token = session?.access_token;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 6000);
        try {
          const headers = { Accept: 'application/json' };
          if (token) headers.Authorization = 'Bearer ' + token;
          const response = await fetch('https://yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com/auth/v1/user/me', {
            method: 'GET', headers, credentials: 'omit', cache: 'no-store', redirect: 'error', signal: controller.signal
          });
          const body = await response.json();
          return { status: response.status, matches: !!token && response.status === 200 &&
            owner.length > 0 && body.sub === owner && body.is_anonymous !== true };
        } finally { clearTimeout(timer); }
        """, arguments: ["owner": owner])
        guard let fields = result as? [String: Any], let status = fields["status"] as? Int,
              [200, 401].contains(status), let matches = fields["matches"] as? Bool else { throw Failure.observation }
        return RemoteIdentity(status: status, matches: matches)
    }
    private func currentWeb() throws -> WKWebView {
        guard let web = runtime?.webView else { throw Failure.observation }; return web
    }
    private func writeDraft(_ value: String) async throws {
        _ = try await evaluate(currentWeb(), "window.__ylfOtherAccountRealm = true; localStorage.setItem(key, value); return true;",
                               arguments: ["key": draftKey, "value": value])
    }
    private func draftMatches(_ expected: String?) async throws -> Bool {
        try await evaluate(currentWeb(), "return localStorage.getItem(key) === expected;",
                           arguments: ["key": draftKey, "expected": expected as Any? ?? NSNull()]) as? Bool == true
    }

    private func runtimeHasNoPages(_ value: MacWebRuntime) -> Bool {
        autoreleasepool {
            // Test-only structural observation; never serialize private page,
            // application, URL or account values from the runtime.
            let fields = Mirror(reflecting: value).children
            guard let pages = fields.first(where: { $0.label == "pages" }),
                  let sessions = fields.first(where: { $0.label == "sessions" }) else { return false }
            return Mirror(reflecting: pages.value).children.isEmpty
                && Mirror(reflecting: sessions.value).children.isEmpty
        }
    }

    private func assertTerminatedDocument(_ reference: WeakWebView) async throws {
        // A real AX client can retain the view even after the app removes every
        // page reference. In that case require destruction of the old executable
        // document, not destruction of an object still owned by the observer.
        // Ordinary RuntimeSSOTests separately require weak deallocation once an
        // explicitly held external reference is released, with runtime alive.
        try await wait(seconds: 5) {
            guard let web = autoreleasepool(invoking: { reference.value }) else { return true }
            guard autoreleasepool(invoking: {
                web.window == nil && web.superview == nil
                    && web.navigationDelegate == nil && web.uiDelegate == nil
            }) else { return false }
            return (try? await self.evaluate(web, """
            return document.URL === 'about:blank'
              && document.body?.childElementCount === 0
              && (document.body?.textContent || '') === ''
              && typeof window.ylf === 'undefined'
              && typeof window.webkit?.messageHandlers?.ylf === 'undefined'
              && typeof window.__ylfOtherAccountRealm === 'undefined';
            """)) as? Bool == true
        }
    }

    private func cleanup(vault: KeychainAccountVault, journal: KeychainAccountVault, auth: ManagedHostAuth) async -> Bool {
        // No named store is removed in a process that loaded a consumer page.
        // Persist exact logout proofs, then let a fresh purge process remove it.
        checkpoint.remoteCleanupComplete = false
        do { try saveCheckpoint() } catch { diagnose("cleanup-checkpoint-write-failed"); return false }
        guard await releaseRuntime() else { diagnose("runtime-release-failed"); return false }
        diagnose("runtime-released")
        var complete = true
        consumerCleanupComplete = true
        consumerAnonymousCheckComplete = true
        for identifier in checkpoint.profiles {
            if checkpoint.signedOutProfiles?.contains(identifier) == true { continue }
            do {
                do { try await cleanConsumer(identifier) }
                catch {
                    if !sdkCleanProfiles.contains(identifier) { consumerCleanupComplete = false }
                    if !remotelyCleanProfiles.contains(identifier) { consumerAnonymousCheckComplete = false }
                    throw error
                }
                autoreleasepool { _ = heldStores.removeValue(forKey: identifier) }
                var confirmed = checkpoint.signedOutProfiles ?? []
                confirmed.append(identifier)
                checkpoint.signedOutProfiles = confirmed
                try saveCheckpoint()
            } catch { complete = false }
        }
        do {
            if let saved = try vault.read() { try await auth.includeSavedAccounts(JSONDecoder().decode(AccountVaultState.self, from: saved)) }
            try await auth.revokeOutstanding()
            try deleteKeychain(vault.service); try deleteKeychain(journal.service)
            guard try vault.read() == nil, try journal.read() == nil else { throw Failure.cleanup }
            hostCleanupComplete = true
            checkpoint.hostSessionsRevoked = true
            try saveCheckpoint()
            diagnose("host-signout-api-succeeded")
        } catch { complete = false; diagnose("host-signout-api-failed") }
        storesCleanupComplete = false
        autoreleasepool { heldStores.removeAll() }
        await Task.yield()
        let allConsumersConfirmed = Set(checkpoint.profiles).isSubset(of: Set(checkpoint.signedOutProfiles ?? []))
        guard complete, consumerCleanupComplete, consumerAnonymousCheckComplete,
              hostCleanupComplete, allConsumersConfirmed else { return false }
        do {
            checkpoint.remoteCleanupComplete = true
            checkpoint.remoteCleanupProcessID = ProcessInfo.processInfo.processIdentifier
            try saveCheckpoint()
            diagnose("remote-cleanup-confirmed-purge-requires-new-process")
            return true
        } catch { diagnose("cleanup-checkpoint-write-failed"); return false }
    }
    private func purge(vault: KeychainAccountVault, journal: KeychainAccountVault) async -> Bool {
        // Never create a named WKWebsiteDataStore or load a URL in this mode.
        // The disposable nonpersistent WebView above only initializes WebKit.
        do {
            guard checkpoint.remoteCleanupComplete == true, checkpoint.hostSessionsRevoked == true,
                  let previousPID = checkpoint.remoteCleanupProcessID,
                  previousPID != ProcessInfo.processInfo.processIdentifier,
                  Set(checkpoint.profiles).isSubset(of: Set(checkpoint.signedOutProfiles ?? [])),
                  try vault.read() == nil, try journal.read() == nil,
                  runtime == nil, accounts == nil, window == nil, heldStores.isEmpty else { throw Failure.setup }
            consumerCleanupComplete = true
            consumerAnonymousCheckComplete = true
            hostCleanupComplete = true
            for identifier in checkpoint.profiles {
                try await removeStore(identifier)
                checkpoint.profiles.removeAll { $0 == identifier }
                try saveCheckpoint()
            }
            storesCleanupComplete = checkpoint.profiles.isEmpty
            return storesCleanupComplete
        } catch { diagnose("purge-incomplete-checkpoint-retained"); return false }
    }
    private func cleanConsumer(_ identifier: UUID) async throws {
        var web: WKWebView?
        autoreleasepool {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = heldStores[identifier] ?? WKWebsiteDataStore(forIdentifier: identifier)
            web = WKWebView(frame: .zero, configuration: config)
        }
        let released = WeakWebView(web)
        autoreleasepool {
            window?.contentView = web
            web?.load(URLRequest(url: URL(string: "https://ai-sfc.yunle.fun/")!))
        }
        var clean = false
        var cleanupStage = "consumer-page-ready"
        do {
            guard let page = web else { throw Failure.cleanup }
            try await wait(seconds: 25) { (try? await self.pageReady(page)) == true }
            cleanupStage = "consumer-sdk-signout"
            // No host bridge is installed, so cleanup cannot reauthorize.
            // Use the actual consumer SDK and fail if it reports a logout error.
            guard try await evaluate(page, """
            const module = await import('/_nuxt/X4HmLciw.js');
            const auth = module.a().auth({ persistence: 'local' });
            const before = await auth.getSession();
            if (before.error) throw new Error('consumer-cleanup-read-failed');
            if (before.data?.session) {
              const result = await auth.signOut();
              if (result?.error) throw new Error('consumer-signout-failed');
            }
            const after = await auth.getSession();
            if (after.error || after.data?.session) throw new Error('consumer-signout-unconfirmed');
            localStorage.removeItem(key);
            return localStorage.getItem(key) === null;
            """, arguments: ["key": draftKey]) as? Bool == true else { throw Failure.cleanup }
            sdkCleanProfiles.insert(identifier)
            diagnose("consumer-sdk-signout-and-empty-local-session")
            cleanupStage = "consumer-remote-401"
            let remote = try await remoteIdentity(page, owner: "")
            guard remote.status == 401, !remote.matches else { throw Failure.cleanup }
            remotelyCleanProfiles.insert(identifier)
            diagnose("consumer-anonymous-request-http-401")
            clean = true
        } catch { clean = false; diagnose(cleanupStage + "-failed") }
        autoreleasepool {
            window?.makeFirstResponder(nil)
            web?.stopLoading()
            web?.loadHTMLString("", baseURL: nil)
            web?.removeFromSuperview(); window?.contentView = nil; web = nil
        }
        await Task.yield()
        do { try await assertTerminatedDocument(released) }
        catch { diagnose("consumer-document-destruction-failed"); throw error }
        if autoreleasepool(invoking: { released.value == nil }) {
            diagnose("consumer-webview-released")
        } else {
            diagnose("consumer-document-destroyed-external-view-retained")
        }
        guard clean else { throw Failure.cleanup }
    }
    private func releaseRuntime() async -> Bool {
        let released = autoreleasepool { WeakRuntime(runtime) }
        autoreleasepool {
            window?.makeFirstResponder(nil)
            runtime?.close(); runtime?.terminate(); window?.contentView = nil
            accounts = nil; runtime = nil
        }
        for _ in 0..<100 {
            if released.value == nil { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
    private func evaluate(_ web: WKWebView, _ script: String, arguments: [String: Any] = [:]) async throws -> Any {
        let callback = CallbackResult<Any>()
        autoreleasepool {
            web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { callback.finish($0) }
        }
        guard await XCTWaiter.fulfillment(of: [callback.completed], timeout: 15) == .completed else { throw Failure.timedOut }
        return try callback.get()
    }
    private func wait(seconds: TimeInterval, until condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw Failure.timedOut
    }
    private func consumeInput() throws -> [Credential] {
        let input = directory.appendingPathComponent("accounts.json")
        try validatePrivate(input, permissions: 0o600)
        let data = try Data(contentsOf: input); try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-zero-balance": "ylf_prod_zero", "production-standard": "ylf_prod_standard"]
        guard pool.accounts.count == 2, Set(pool.accounts.map(\.id)) == Set(expected.keys),
              pool.accounts.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty }),
              let a = pool.accounts.first(where: { $0.id == "production-zero-balance" }),
              let b = pool.accounts.first(where: { $0.id == "production-standard" }) else { throw Failure.setup }
        return [a, b]
    }
    private func validatePrivate(_ url: URL, permissions: Int, directory: Bool = false) throws {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)
        guard value[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              (value[.posixPermissions] as? NSNumber)?.intValue == permissions,
              (value[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Failure.setup }
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func saveCheckpoint() throws { try writePrivate(JSONEncoder().encode(checkpoint), to: checkpointURL) }
    private func deleteKeychain(_ service: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "cloudbase-accounts-v1",
                                   kSecAttrSynchronizable as String: false] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.cleanup }
    }
    private func mark(_ name: String) { stage = name; print("[OtherAccountSSO] stage=" + name) }
    private func diagnose(_ value: String) {
        cleanupDiagnostics.append(value)
        print("[OtherAccountSSO] cleanup=" + value)
    }
    private func removeStore(_ identifier: UUID) async throws {
        // WebKit releases its process-side store asynchronously after the last
        // native reference. Retry returned failures, never overlap a timed-out
        // removal with another request or mark a retained UUID as cleaned.
        for attempt in 0..<6 {
            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 100_000_000)
            let callback = CallbackResult<Void>()
            autoreleasepool {
                WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                    callback.finish(error.map { .failure($0) } ?? .success(()))
                }
            }
            guard await XCTWaiter.fulfillment(of: [callback.completed], timeout: 10) == .completed else {
                diagnose("store-removal-timeout"); throw Failure.timedOut
            }
            do {
                try callback.get()
                diagnose("store-removed")
                return
            } catch {
                // Only a numeric code and fixed domain category are safe. An
                // NSError's descriptions/userInfo may include a private URL.
                let value = error as NSError
                let category = value.domain == WKErrorDomain ? "webkit" : "other"
                diagnose("store-removal-\(category)-code-\(value.code)-attempt-\(attempt + 1)")
            }
        }
        throw Failure.cleanup
    }
    private func completeStage() throws { checkpoint.completedStages.append(stage); try saveCheckpoint() }
    private final class WeakWebView {
        weak var value: WKWebView?
        init(_ value: WKWebView?) { self.value = value }
    }
    private final class WeakRuntime {
        weak var value: MacWebRuntime?
        init(_ value: MacWebRuntime?) { self.value = value }
    }
}
