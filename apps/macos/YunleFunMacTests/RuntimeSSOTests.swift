import AppKit
import WebKit
import XCTest
@testable import YunleFunMac

@MainActor
final class RuntimeSSOTests: XCTestCase {
    /// Recovery is opt-in for one explicitly identified failed fixture. Normal
    /// runs neither enumerate website stores nor scan other temporary folders.
    func testRecoverExplicitPendingFixtureIfRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        // xcodebuild removes TEST_RUNNER_ when forwarding an opt-in variable.
        guard let raw = environment["MAC_RUNTIME_SSO_CLEANUP_ID"]
            ?? environment["TEST_RUNNER_MAC_RUNTIME_SSO_CLEANUP_ID"] else { return }
        guard let identity = UUID(uuidString: raw), raw == identity.uuidString,
              Bundle.main.bundleIdentifier == "fun.yunle.macos.tests-host" else {
            throw HostAuthorizationError.invalidRequest
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-runtime-sso-" + raw)
        let manifest = directory.appendingPathComponent("cleanup-pending.json")
        guard var record = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
              record["owner"] as? String == "YunleFunMacTests.RuntimeSSOTests",
              let strings = record["identifiers"] as? [String],
              strings.allSatisfy({ UUID(uuidString: $0)?.uuidString == $0 }),
              Set(strings).count == strings.count else { throw HostAuthorizationError.invalidRequest }
        // Match the persistence/live harness: initialize WebKit's main run loop
        // before class-level removal when this is the only selected test.
        autoreleasepool {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            WKWebView(frame: .zero, configuration: configuration).stopLoading()
        }
        var pending = Set(strings)
        for rawIdentifier in strings {
            let identifier = try XCTUnwrap(UUID(uuidString: rawIdentifier))
            let removalError: Error? = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.remove(forIdentifier: identifier) { continuation.resume(returning: $0) }
            }
            if let removalError {
                XCTFail("Explicit fixture recovery failed for \(identifier): \(removalError). Retained manifest: \(manifest.path)")
            } else {
                pending.remove(rawIdentifier)
                record["identifiers"] = pending.sorted()
                try JSONSerialization.data(withJSONObject: record).write(to: manifest, options: .atomic)
            }
        }
        if pending.isEmpty {
            try FileManager.default.removeItem(at: directory)
            print("[SSO fixture recovery] Removed \(strings.count) recorded stores from \(directory.lastPathComponent)")
        }
    }

    func testFragmentNavigationAllowsANewAuthorizationInTheSameDocument() async throws {
        try await withFixture(account: "a") { fixture in
            let web = try await fixture.load()
            let result = try await WebStoragePageFixture.evaluate(in: web, script: """
            await new Promise(resolve => {
              window.addEventListener('hashchange', resolve, { once: true });
              window.location.hash = 'native-sso-after-fragment';
            });
            return await window.ylf.authorize(parameters);
            """, arguments: ["parameters": macSsoParameters()]) as? [String: Any]
            XCTAssertEqual(result?["code"] as? String, String(repeating: "c", count: 43))
        }
    }

    func testActualWebKitBridgeAuthorizesMainFrameAndRejectsInheritedPopupHandler() async throws {
        try await withFixture(account: "a") { fixture in
            let web = try await fixture.load()
            let result = try await WebStoragePageFixture.evaluate(in: web,
                script: "return await window.ylf.authorize(parameters);", arguments: ["parameters": macSsoParameters()]) as? [String: Any]
            XCTAssertEqual(result?["code"] as? String, String(repeating: "c", count: 43))
            XCTAssertNil(result?["accessToken"])

            // A popup inherits the opener's WKUserContentController. Even with
            // the same trusted URL and scripts, its WKWebView is not the owner.
            var popup: WKWebView? = autoreleasepool { WKWebView(frame: .zero, configuration: web.configuration) }
            try await WebStoragePageFixture.load(in: try XCTUnwrap(popup), origin: fixture.origin, title: "popup")
            let rejected = try await WebStoragePageFixture.evaluate(in: try XCTUnwrap(popup), script: """
            try { await window.ylf.canIUse('authorize'); return false; }
            catch (error) { return String(error).includes('HOST_AUTH_FORBIDDEN'); }
            """) as? Bool
            XCTAssertEqual(rejected, true)
            popup?.stopLoading()
            popup = nil
            let counts = await fixture.service.counts()
            XCTAssertEqual(counts.issues, 1)
        }
    }

    func testGuestLoginContinuationKeepsOnlyItsPageAndRebindsThePersistentProfile() async throws {
        try await withFixture(account: nil) { fixture in
            let web = try await fixture.load()
            let guestID = try XCTUnwrap(web.configuration.websiteDataStore.identifier)
            fixture.presentation.loginShown = expectation(description: "Guest host login")
            fixture.presentation.consentShown = expectation(description: "Explicit post-login consent")
            let authorization = Task { @MainActor in
                try await WebStoragePageFixture.evaluate(in: web,
                    script: "return await window.ylf.authorize(parameters);", arguments: ["parameters": macSsoParameters()])
            }
            await fulfillment(of: [fixture.presentation.loginShown!], timeout: 3)
            fixture.runtime?.accountDidChange("a")
            fixture.accounts.user = AccountUser(id: "a")
            fixture.presentation.loginCompletion?(true)
            await fulfillment(of: [fixture.presentation.consentShown!], timeout: 3)
            XCTAssertTrue(fixture.runtime?.webView === web)
            XCTAssertEqual(try fixture.profiles.snapshot(for: .account("a"), application: fixture.application).active?.identifier, guestID)
            XCTAssertNil(try fixture.profiles.snapshot(for: .guest, application: fixture.application).active)
            fixture.presentation.consentCompletion?(.current)
            let result = try await authorization.value as? [String: Any]
            XCTAssertEqual(result?["code"] as? String, String(repeating: "c", count: 43))
            fixture.runtime?.close()
            XCTAssertTrue(fixture.runtime?.open(fixture.application) == true)
            XCTAssertTrue(fixture.runtime?.webView === web)
            fixture.runtime?.accountDidChange("b")
            fixture.accounts.user = AccountUser(id: "b")
            XCTAssertNil(fixture.runtime?.webView)
            XCTAssertTrue(fixture.runtime?.open(fixture.application) == true)
            XCTAssertNotEqual(fixture.runtime?.webView?.configuration.websiteDataStore.identifier, guestID)
        }
    }

    func testClosingTheNativeWindowRejectsAnInFlightSilentCode() async throws {
        let gate = MacSsoTestGate()
        try await withFixture(account: "a", service: MacSsoTestService(issueGate: gate)) { fixture in
            let web = try await fixture.load()
            let authorization = Task { @MainActor in
                try await WebStoragePageFixture.evaluate(in: web, script: """
                try { return await window.ylf.authorize(parameters); }
                catch (error) { return { rejected: String(error) }; }
                """, arguments: ["parameters": macSsoParameters()]) as? [String: Any]
            }
            await fulfillment(of: [gate.entered], timeout: 3)
            fixture.window?.close()
            await gate.release()
            let result = try await authorization.value
            XCTAssertNil(result?["code"])
            XCTAssertNotNil(result?["rejected"])
        }
    }

    func testHostLogoutAfterOtherAccountHandoffCancelsSystemSessionAndRejectsLateCode() async throws {
        let system = MacSsoTestSystemAuthorization()
        try await withFixture(account: "a", system: system) { fixture in
            var web: WKWebView? = try await fixture.load()
            var authorization: Task<[String: Any]?, Error>?
            defer { authorization?.cancel(); authorization = nil; web = nil }
            // Keep the test's retired document scheduled just long enough to
            // observe its rejected JS promise after the native view detaches.
            autoreleasepool { web?.configuration.preferences.inactiveSchedulingPolicy = .none }
            system.started = expectation(description: "Other-account request handed to the system browser")
            authorization = Task { @MainActor [weak web] in
                guard let web else { throw HostAuthorizationError.expired }
                return try await WebStoragePageFixture.evaluate(in: web, script: """
                try { return await window.ylf.authorize(parameters); }
                catch (error) { return { rejected: String(error) }; }
                """, arguments: ["parameters": macSsoParameters(prompt: "select_account")]) as? [String: Any]
            }
            await fulfillment(of: [system.started!], timeout: 3)
            let callback = try macSsoTestSystemCallback(for: XCTUnwrap(system.url))
            try fixture.profiles.retire("a")
            fixture.runtime?.accountDidChange(nil)
            fixture.accounts.user = nil
            XCTAssertNil(fixture.runtime?.webView)
            XCTAssertTrue(system.cancelled)
            let result = try await authorization?.value
            authorization = nil
            XCTAssertNil(result?["code"])
            XCTAssertTrue((result?["rejected"] as? String)?.contains(HostAuthorizationError.denied.code) == true)
            system.completion?(callback, nil)
            XCTAssertNil(fixture.accounts.user)
            XCTAssertTrue(fixture.accounts.authorizationCalls.isEmpty)
            let counts = await fixture.service.counts()
            XCTAssertEqual(counts.issues, 0, "Other-account selection must never mint a code with the host's token")
            web = nil
        }
    }

    func testAccountRemovalDestroysTheDocumentEvenWhenAnExternalOwnerRetainsItsWebView() async throws {
        try await withFixture(account: "a") { fixture in
            var retainedWeb: WKWebView? = try await fixture.load()
            weak var releasedWeb = retainedWeb
            defer { autoreleasepool { retainedWeb = nil } }
            // An external observer can retain a detached WKWebView. Keep its
            // process scheduled in this test so we can inspect the replacement
            // realm rather than treating background suspension as destruction.
            autoreleasepool { retainedWeb?.configuration.preferences.inactiveSchedulingPolicy = .none }
            _ = try await WebStoragePageFixture.evaluate(in: try XCTUnwrap(retainedWeb), script: """
            window.retiredAccountState = { ticks: 0 };
            window.retiredAccountTimer = setInterval(() => window.retiredAccountState.ticks++, 1);
            return true;
            """)
            try fixture.profiles.retire("a")
            autoreleasepool {
                fixture.runtime?.accountDidChange(nil)
                fixture.accounts.user = nil
                fixture.window?.contentView = nil
            }
            XCTAssertNil(fixture.runtime?.webView)
            XCTAssertNil(fixture.runtime?.application)
            XCTAssertNil(retainedWeb?.navigationDelegate)
            XCTAssertNil(retainedWeb?.uiDelegate)

            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let blank = autoreleasepool {
                    retainedWeb?.url?.absoluteString == "about:blank" && retainedWeb?.isLoading == false
                }
                if blank { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(retainedWeb?.url?.absoluteString, "about:blank")
            let state = try await WebStoragePageFixture.evaluate(in: try XCTUnwrap(retainedWeb), script: """
            return {
              oldRealmGone: typeof window.retiredAccountState === 'undefined' && typeof window.retiredAccountTimer === 'undefined',
              bridgeGone: typeof window.ylf === 'undefined' && typeof window.webkit?.messageHandlers?.ylf === 'undefined',
              documentEmpty: document.title === '' && document.body.childElementCount === 0 && document.body.textContent === ''
            };
            """) as? [String: Bool]
            XCTAssertEqual(state, ["oldRealmGone": true, "bridgeGone": true, "documentEmpty": true])
            XCTAssertNotNil(fixture.runtime, "Named-store ownership outlives the retired document")
            autoreleasepool { retainedWeb = nil }
            let releaseDeadline = Date().addingTimeInterval(5)
            while Date() < releaseDeadline && autoreleasepool(invoking: { releasedWeb != nil }) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertNil(releasedWeb, "Without an external observer, the detached view must still be released")
        }
    }

    func testGuestContinuationIsRetainedBesideAnExistingAccountProfileUntilExplicitlyEnded() async throws {
        try await withFixture(account: "a") { fixture in
            var previous: WKWebView?
            var guest: WKWebView?
            var restored: WKWebView?
            var authorization: Task<Any?, Error>?
            defer {
                authorization?.cancel()
                authorization = nil
                autoreleasepool { previous = nil; guest = nil; restored = nil }
            }
            previous = try await fixture.load()
            let previousID = try autoreleasepool { try XCTUnwrap(previous?.configuration.websiteDataStore.identifier) }
            _ = try await WebStoragePageFixture.evaluate(in: try XCTUnwrap(previous),
                script: "localStorage.setItem('previous-account-draft', 'keep-me'); return true;")
            previous = nil
            fixture.runtime?.accountDidChange(nil)
            fixture.accounts.user = nil
            guest = try await fixture.load()
            let guestID = try autoreleasepool { try XCTUnwrap(guest?.configuration.websiteDataStore.identifier) }
            XCTAssertNotEqual(previousID, guestID)
            fixture.presentation.loginShown = expectation(description: "Guest host login")
            fixture.presentation.consentShown = expectation(description: "Consent after accepted login")
            authorization = Task { @MainActor [weak guest] in
                guard let guest else { throw HostAuthorizationError.expired }
                return try await WebStoragePageFixture.evaluate(in: guest,
                    script: "return await window.ylf.authorize(parameters);", arguments: ["parameters": macSsoParameters()])
            }
            await fulfillment(of: [fixture.presentation.loginShown!], timeout: 3)
            fixture.runtime?.accountDidChange("a")
            fixture.accounts.user = AccountUser(id: "a")
            fixture.presentation.loginCompletion?(true)
            await fulfillment(of: [fixture.presentation.consentShown!], timeout: 3)
            let snapshot = try fixture.profiles.snapshot(for: .account("a"), application: fixture.application)
            XCTAssertEqual(snapshot.active?.identifier, previousID)
            XCTAssertEqual(snapshot.retained.map(\.identifier), [guestID])
            fixture.presentation.consentCompletion?(.current)
            let result = try await authorization?.value as? [String: Any]
            authorization = nil
            XCTAssertNotNil(result?["code"])
            fixture.runtime?.close()
            XCTAssertTrue(fixture.runtime?.open(fixture.application) == true)
            XCTAssertTrue(fixture.runtime?.webView === guest)
            fixture.runtime?.terminate()
            guest = nil
            restored = try await fixture.load()
            let restoredID = autoreleasepool { restored?.configuration.websiteDataStore.identifier }
            XCTAssertEqual(restoredID, previousID)
            let draft = try await WebStoragePageFixture.evaluate(in: try XCTUnwrap(restored),
                script: "return localStorage.getItem('previous-account-draft');") as? String
            XCTAssertEqual(draft, "keep-me")
            restored = nil
        }
    }

    private func withFixture(account: String?, service: MacSsoTestService = MacSsoTestService(),
                             system: MacSsoTestSystemAuthorization? = nil,
                             body: (Fixture) async throws -> Void) async throws {
        let fixture = try Fixture(account: account, service: service, system: system)
        var failure: Error?
        do { try await body(fixture) } catch { failure = error }
        await fixture.cleanUp()
        if let failure { throw failure }
    }

    @MainActor
    private final class Fixture {
        let origin = URL(string: "https://sso.yunle.fun/page")!
        var application: CloudApplication { CloudApplication(id: "runtime-sso-fixture", name: "SSO fixture", websiteUrl: origin.absoluteString) }
        let directory: URL
        let accounts: MacSsoTestAccounts
        let service: MacSsoTestService
        let presentation = MacSsoTestPresentation()
        var runtime: MacWebRuntime?
        var profiles: WebProfileRepository!
        var window: NSWindow?
        private var identifiers = Set<UUID>()

        init(account: String?, service: MacSsoTestService, system: MacSsoTestSystemAuthorization?) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-runtime-sso-\(UUID().uuidString)")
            accounts = MacSsoTestAccounts(account)
            self.service = service
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: "runtime-sso-tests") { [weak self] data, url in
                guard let self else { throw HostAuthorizationError.unavailable }
                if let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let active = (state["active"] as? [String: String])?.values.map { $0 } ?? []
                    let retained = (state["retained"] as? [String: [String]])?.values.flatMap { $0 } ?? []
                    self.identifiers.formUnion((active + retained).compactMap(UUID.init(uuidString:)))
                    try self.persistCleanupRecord()
                }
                try data.write(to: url, options: .atomic)
            }
            autoreleasepool {
                runtime = MacWebRuntime(webProfiles: profiles, loadRequest: { _, _ in })
                var factory: (@MainActor () -> MacSystemAuthorizationLaunching)?
                if let system { factory = { system } }
                runtime?.configureAuthorization(accounts: accounts, service: service, presentation: presentation,
                                                makeSystemAuthorization: factory)
                window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window?.isReleasedWhenClosed = false
            }
        }

        func load() async throws -> WKWebView {
            let web = try autoreleasepool {
                guard runtime?.open(application) == true else { throw HostAuthorizationError.unavailable }
                let web = try XCTUnwrap(runtime?.webView)
                window?.contentView = web
                window?.makeKeyAndOrderFront(nil)
                return web
            }
            try await WebStoragePageFixture.load(in: web, origin: origin, title: "runtime-sso")
            return web
        }

        private func persistCleanupRecord() throws {
            let payload: [String: Any] = ["owner": "YunleFunMacTests.RuntimeSSOTests",
                                         "identifiers": identifiers.map(\.uuidString).sorted()]
            try JSONSerialization.data(withJSONObject: payload).write(to: directory.appendingPathComponent("cleanup-pending.json"), options: .atomic)
        }

        func cleanUp() async {
            autoreleasepool {
                runtime?.terminate()
                window?.contentView = nil
                window?.close()
                window = nil
                runtime = nil
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 100_000_000)
            for identifier in Array(identifiers) {
                var error: Error?
                for attempt in 0..<6 {
                    error = await withCheckedContinuation { continuation in
                        WKWebsiteDataStore.remove(forIdentifier: identifier) { continuation.resume(returning: $0) }
                    }
                    if error == nil { break }
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 100_000_000)
                }
                if let error { XCTFail("SSO fixture store \(identifier) remains: \(error). Manifest: \(directory.path)/cleanup-pending.json") }
                else { identifiers.remove(identifier); try? persistCleanupRecord() }
            }
            if identifiers.isEmpty { try? FileManager.default.removeItem(at: directory) }
        }
    }
}
