import AppKit
import AuthenticationServices
import XCTest
@testable import YunleFunMac

@MainActor
final class MacAuthorizationPageTests: XCTestCase {
    func testFragmentNavigationNeverClassifiesReloadOrDifferentPathQueryOriginAsTheSameDocument() {
        let current = URL(string: "https://sso.yunle.fun/page?tab=one#old")!
        let fragment = URL(string: "https://sso.yunle.fun/page?tab=one#new")!
        XCTAssertTrue(MacWebNavigationPolicy.isFragmentNavigation(from: current, to: fragment, isReload: false))
        XCTAssertTrue(MacWebNavigationPolicy.isFragmentNavigation(from: fragment, to: fragment, isReload: false))
        XCTAssertFalse(MacWebNavigationPolicy.isFragmentNavigation(from: current, to: fragment, isReload: true))
        XCTAssertFalse(MacWebNavigationPolicy.isFragmentNavigation(from: current, to: current, isReload: true))
        for destination in ["https://sso.yunle.fun/other?tab=one#new", "https://sso.yunle.fun/page?tab=two#new",
                            "https://different.yunle.fun/page?tab=one#new", "https://sso.yunle.fun:444/page?tab=one#new"] {
            XCTAssertFalse(MacWebNavigationPolicy.isFragmentNavigation(from: current, to: URL(string: destination), isReload: false))
        }
    }

    func testCapabilitiesDoNotAdvertiseUnimplementedOrUntrustedMethods() {
        let accounts = MacSsoTestAccounts("a"), service = MacSsoTestService()
        let fixture = Fixture(accounts: accounts, service: service)
        for capability in ["authorize", "canIUse", "getEnv"] {
            var supported: Bool?
            fixture.page.receive(["method": "canIUse", "params": ["method": capability]], source: fixture.source) {
                supported = $0 as? Bool; XCTAssertNil($1)
            }
            XCTAssertEqual(supported, true)
        }
        for capability in ["openAuthSession", "haptic", "close", "setClipboard", "setCapsuleVisible"] {
            fixture.page.receive(["method": "canIUse", "params": ["method": capability]], source: fixture.source) {
                XCTAssertEqual($0 as? Bool, false); XCTAssertNil($1)
            }
        }
        fixture.url = URL(string: "https://untrusted.example/page")!
        fixture.page.receive(["method": "canIUse", "params": ["method": "authorize"]], source: fixture.source) {
            XCTAssertEqual($0 as? Bool, false); XCTAssertNil($1)
        }
    }

    func testSubframesAndForgedOrStaleOriginsCannotStartAuthorization() async {
        let accounts = MacSsoTestAccounts("a"), service = MacSsoTestService()
        let fixture = Fixture(accounts: accounts, service: service)
        let sources: [MacAuthorizationPage.Source] = [
            .init(isMainFrame: false, scheme: "https", host: fixture.url.host!, port: 443, frameURL: fixture.url),
            .init(isMainFrame: true, scheme: "https", host: "evil.example", port: 443, frameURL: fixture.url),
            .init(isMainFrame: true, scheme: "http", host: fixture.url.host!, port: 443, frameURL: fixture.url),
            .init(isMainFrame: true, scheme: "https", host: fixture.url.host!, port: 444, frameURL: fixture.url),
            .init(isMainFrame: true, scheme: "https", host: fixture.url.host!, port: 443,
                  frameURL: URL(string: "https://sso.yunle.fun/previous")),
        ]
        for source in sources {
            fixture.page.receive(["method": "authorize", "params": macSsoParameters()], source: source) {
                XCTAssertNil($0); XCTAssertEqual($1, "HOST_AUTH_FORBIDDEN")
            }
        }
        let counts = await service.counts()
        XCTAssertEqual(counts.resolves, 0)
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testTrustedMainDocumentReceivesOnlyTheOneTimeCode() async {
        let accounts = MacSsoTestAccounts("a"), service = MacSsoTestService()
        let fixture = Fixture(accounts: accounts, service: service)
        let completed = expectation(description: "One-time authorization result")
        fixture.authorize { result, error in
            XCTAssertNil(error)
            let fields = result as? [String: Any]
            XCTAssertEqual(fields?["code"] as? String, String(repeating: "c", count: 43))
            XCTAssertNil(fields?["accessToken"])
            XCTAssertNil(fields?["refreshToken"])
            XCTAssertNil(fields?["session"])
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(accounts.authorizationCalls, [false])
    }

    func testNavigationOrHiddenWindowRevokesTheDocumentBeforeALateCodeArrives() async {
        for navigation in [true, false] {
            let gate = MacSsoTestGate(), accounts = MacSsoTestAccounts("a")
            let fixture = Fixture(accounts: accounts, service: MacSsoTestService(issueGate: gate))
            var replies = [(Any?, String?)]()
            fixture.authorize { replies.append(($0, $1)) }
            await fulfillment(of: [gate.entered], timeout: 3)
            if navigation { fixture.page.navigationStarted(); fixture.page.documentCommitted() }
            else { fixture.visible = false; fixture.page.invalidate(); fixture.visible = true }
            XCTAssertEqual(replies.count, 1)
            XCTAssertNil(replies.first?.0)
            XCTAssertEqual(replies.first?.1, HostAuthorizationError.denied.code)
            await gate.release()
            await Task.yield()
            XCTAssertEqual(replies.count, 1, "Restoring the window or loading the same URL must not revive the old request")
        }
    }

    func testSilentFlowRechecksVisibilityEvenWithoutADeliveredNotification() async {
        let gate = MacSsoTestGate(), accounts = MacSsoTestAccounts("a")
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(issueGate: gate))
        let denied = expectation(description: "Invisible document rejects late result")
        fixture.authorize { result, error in
            XCTAssertNil(result); XCTAssertNotNil(error); denied.fulfill()
        }
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.visible = false
        await gate.release()
        await fulfillment(of: [denied], timeout: 3)
    }

    func testIdentityChangeDuringConsentCannotIssueForEitherIdentity() async {
        let accounts = MacSsoTestAccounts("a"), service = MacSsoTestService(), ui = MacSsoTestPresentation()
        let fixture = Fixture(accounts: accounts, service: service, presentation: ui)
        ui.consentShown = expectation(description: "Native consent")
        var replies = [(Any?, String?)]()
        fixture.authorize(prompt: "consent") { replies.append(($0, $1)) }
        await fulfillment(of: [ui.consentShown!], timeout: 3)
        XCTAssertNil(fixture.broker.identityWillChange(to: "b"))
        accounts.user = AccountUser(id: "b")
        ui.consentCompletion?(.current)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies.first?.0)
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testRemovingApplicationTrustedHostRevokesPendingAndFutureAuthorization() async {
        let gate = MacSsoTestGate(), accounts = MacSsoTestAccounts("a")
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(issueGate: gate),
                              url: URL(string: "https://approved.example/page")!, trustedHosts: ["approved.example"])
        var replies = [(Any?, String?)]()
        fixture.authorize { replies.append(($0, $1)) }
        await fulfillment(of: [gate.entered], timeout: 3)
        fixture.page.updateApplication(CloudApplication(id: "sso-fixture", name: "Fixture",
                                                        websiteUrl: fixture.url.absoluteString, trustedHosts: []))
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies.first?.0)
        XCTAssertEqual(replies.first?.1, HostAuthorizationError.denied.code)
        fixture.page.receive(["method": "canIUse", "params": ["method": "authorize"]], source: fixture.source) {
            XCTAssertEqual($0 as? Bool, false); XCTAssertNil($1)
        }
        await gate.release()
        await Task.yield()
        XCTAssertEqual(replies.count, 1)
    }

    func testOtherAccountUsesValidatedSystemCallbackWithoutSwitchingHostIdentity() async throws {
        let accounts = MacSsoTestAccounts("a"), system = MacSsoTestSystemAuthorization()
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(), system: system)
        system.started = expectation(description: "System authorization")
        let completed = expectation(description: "Validated callback")
        fixture.authorize(prompt: "select_account") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual((result as? [String: Any])?["code"] as? String, String(repeating: "z", count: 43))
            completed.fulfill()
        }
        await fulfillment(of: [system.started!], timeout: 3)
        let url = try XCTUnwrap(system.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let callback = try XCTUnwrap(query.first { $0.name == "native_callback_uri" }?.value).appending("&result=")
        let payload: [String: Any] = ["nonce": String(repeating: "n", count: 43), "iss": HostSsoPolicy.issuer,
                                     "ok": true, "code": String(repeating: "z", count: 43)]
        let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let resultURL = "https://sso.yunle.fun/callback#ylf_sso=" + encoded
        let escaped = try XCTUnwrap(resultURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        system.completion?(URL(string: callback + escaped), nil)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(accounts.user?.id, "a")
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testSystemCancellationAllowsRetryAndOldCallbackCannotTouchTheNewSession() async throws {
        let accounts = MacSsoTestAccounts("a"), system = MacSsoTestSystemAuthorization()
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(), system: system)
        system.started = expectation(description: "First system session")
        var firstReplies = [(Any?, String?)]()
        fixture.authorize(prompt: "select_account") { firstReplies.append(($0, $1)) }
        await fulfillment(of: [system.started!], timeout: 3)
        XCTAssertFalse(fixture.broker.isBusy, "The page owns the system-session lifetime after broker handoff")
        let oldCompletion = try XCTUnwrap(system.completion)
        let oldCallback = try macSsoTestSystemCallback(for: XCTUnwrap(system.url))
        oldCompletion(nil, NSError(domain: ASWebAuthenticationSessionErrorDomain,
                                  code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue))
        XCTAssertEqual(firstReplies.count, 1)
        XCTAssertEqual(firstReplies.first?.1, HostAuthorizationError.denied.code)

        system.started = expectation(description: "Retry starts a fresh system session")
        var nextReplies = [(Any?, String?)]()
        fixture.authorize(prompt: "select_account") { nextReplies.append(($0, $1)) }
        await fulfillment(of: [system.started!], timeout: 3)
        let nextCallback = try macSsoTestSystemCallback(for: XCTUnwrap(system.url))
        XCTAssertNotEqual(oldCallback, nextCallback)
        oldCompletion(oldCallback, nil)
        XCTAssertTrue(nextReplies.isEmpty)
        XCTAssertFalse(system.cancelled, "An obsolete callback must not cancel the newer system session")
        system.completion?(nextCallback, nil)
        XCTAssertEqual(nextReplies.count, 1)
        XCTAssertNotNil((nextReplies.first?.0 as? [String: Any])?["code"])
        XCTAssertEqual(firstReplies.count, 1)
        XCTAssertEqual(accounts.user?.id, "a")
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testWrongStateFailsTheAdapterRequestAndDoesNotBlockRetry() async throws {
        let accounts = MacSsoTestAccounts("a"), system = MacSsoTestSystemAuthorization()
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(), system: system)
        system.started = expectation(description: "System session for wrong-state callback")
        var replies = [(Any?, String?)]()
        fixture.authorize(prompt: "select_account") { replies.append(($0, $1)) }
        await fulfillment(of: [system.started!], timeout: 3)
        let wrong = try macSsoTestSystemCallback(for: XCTUnwrap(system.url), stateOverride: String(repeating: "w", count: 43))
        system.completion?(wrong, nil)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies.first?.0)
        XCTAssertEqual(replies.first?.1, HostAuthorizationError.unavailable.code)
        system.started = expectation(description: "A malformed callback must not leave the page busy")
        fixture.authorize(prompt: "select_account") { replies.append(($0, $1)) }
        await fulfillment(of: [system.started!], timeout: 3)
        system.completion?(try macSsoTestSystemCallback(for: XCTUnwrap(system.url)), nil)
        XCTAssertEqual(replies.count, 2)
        XCTAssertNotNil((replies.last?.0 as? [String: Any])?["code"])
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testSystemTimeoutCancelsTheBrowserAndNeverDeliversALateCallback() async throws {
        let accounts = MacSsoTestAccounts("a"), system = MacSsoTestSystemAuthorization()
        let fixture = Fixture(accounts: accounts, service: MacSsoTestService(), system: system, systemAuthorizationTimeout: 0.03)
        system.started = expectation(description: "System session starts")
        let timedOut = expectation(description: "System session timeout rejects the page")
        var replies = [(Any?, String?)]()
        fixture.authorize(prompt: "select_account") {
            replies.append(($0, $1)); timedOut.fulfill()
        }
        await fulfillment(of: [system.started!, timedOut], timeout: 3)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies.first?.0)
        XCTAssertEqual(replies.first?.1, HostAuthorizationError.denied.code)
        XCTAssertTrue(system.cancelled)
        system.completion?(try macSsoTestSystemCallback(for: XCTUnwrap(system.url)), nil)
        XCTAssertEqual(replies.count, 1)
        XCTAssertFalse(fixture.broker.isBusy)
        XCTAssertTrue(accounts.authorizationCalls.isEmpty)
    }

    func testSystemCallbackImmediatelyRejectsAnInvalidDocumentWithoutAnInvalidationNotification() async throws {
        for changedURL in [false, true] {
            let accounts = MacSsoTestAccounts("a"), system = MacSsoTestSystemAuthorization()
            let fixture = Fixture(accounts: accounts, service: MacSsoTestService(), system: system)
            system.started = expectation(description: "System session starts")
            var replies = [(Any?, String?)]()
            fixture.authorize(prompt: "select_account") { replies.append(($0, $1)) }
            await fulfillment(of: [system.started!], timeout: 3)
            let originalURL = fixture.url
            if changedURL { fixture.url = URL(string: "https://sso.yunle.fun/replaced-route")! }
            else { fixture.visible = false }
            // Model an SPA URL change or a missed window visibility notification.
            // The callback must reject this pending reply, not silently keep it
            // alive until the five-minute browser deadline.
            system.completion?(try macSsoTestSystemCallback(for: XCTUnwrap(system.url)), nil)
            XCTAssertEqual(replies.count, 1)
            XCTAssertNil(replies.first?.0)
            XCTAssertEqual(replies.first?.1, HostAuthorizationError.denied.code)
            XCTAssertTrue(system.cancelled)
            fixture.url = originalURL
            fixture.visible = true
            system.started = expectation(description: "Restored document may start a fresh request")
            fixture.authorize(prompt: "select_account") { replies.append(($0, $1)) }
            await fulfillment(of: [system.started!], timeout: 3)
            system.completion?(try macSsoTestSystemCallback(for: XCTUnwrap(system.url)), nil)
            XCTAssertEqual(replies.count, 2)
            XCTAssertNotNil((replies.last?.0 as? [String: Any])?["code"])
            XCTAssertTrue(accounts.authorizationCalls.isEmpty)
        }
    }

    @MainActor
    private final class Fixture {
        var url = URL(string: "https://sso.yunle.fun/page")!
        var visible = true
        let broker: NativeAuthorizationBroker
        let anchor = NSWindow()
        var page: MacAuthorizationPage!
        var source: MacAuthorizationPage.Source {
            .init(isMainFrame: true, scheme: "https", host: url.host!, port: 443, frameURL: url)
        }

        init(accounts: MacSsoTestAccounts, service: MacSsoTestService,
             presentation: MacAuthorizationPresenting? = nil, system: MacSsoTestSystemAuthorization? = nil,
             url: URL = URL(string: "https://sso.yunle.fun/page")!, trustedHosts: [String] = [],
             systemAuthorizationTimeout: TimeInterval = 300) {
            self.url = url
            broker = NativeAuthorizationBroker(accounts: accounts, service: service)
            let application = CloudApplication(id: "sso-fixture", name: "Fixture", websiteUrl: url.absoluteString, trustedHosts: trustedHosts)
            page = MacAuthorizationPage(application: application, broker: broker, presentation: presentation,
                                        isVisible: { [weak self] in self?.visible == true },
                                        documentURL: { [weak self] in self?.url }, window: { [weak self] in self?.anchor },
                                        makeSystemAuthorization: { system ?? MacSsoTestSystemAuthorization() },
                                        systemAuthorizationTimeout: systemAuthorizationTimeout)
            page.documentCommitted()
        }

        func authorize(prompt: String? = nil, reply: @escaping (Any?, String?) -> Void) {
            var parameters = macSsoParameters(prompt: prompt)
            parameters["redirectUri"] = MacWebNavigationPolicy.origin(of: url)! + "/callback"
            page.receive(["method": "authorize", "params": parameters], source: source, reply: reply)
        }
    }
}

@MainActor
final class MacSsoTestAccounts: AccountAuthorizing {
    var user: AccountUser?
    var authorizationCalls: [Bool] = []
    init(_ id: String?) { user = id.map { AccountUser(id: $0) } }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        authorizationCalls.append(forceRefresh)
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: "test-host-only-token")
    }
}

@MainActor
final class MacSsoTestPresentation: MacAuthorizationPresenting {
    var loginCompletion: ((Bool) -> Void)?
    var consentCompletion: ((AuthorizationSheetChoice) -> Void)?
    var loginShown: XCTestExpectation?
    var consentShown: XCTestExpectation?
    var dismissals = 0
    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        loginCompletion = completion; loginShown?.fulfill(); return true
    }
    func showConsent(policy: HostSsoPolicy, user: AccountUser, completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        consentCompletion = completion; consentShown?.fulfill(); return true
    }
    func dismiss() { dismissals += 1 }
}

@MainActor
final class MacSsoTestSystemAuthorization: MacSystemAuthorizationLaunching {
    var started: XCTestExpectation?
    var url: URL?
    var completion: ((URL?, Error?) -> Void)?
    var cancelled = false
    func start(url: URL, window: NSWindow, completion: @escaping (URL?, Error?) -> Void) -> Bool {
        cancelled = false
        self.url = url; self.completion = completion; started?.fulfill(); return true
    }
    func cancel() { cancelled = true }
}

actor MacSsoTestGate {
    let entered = XCTestExpectation(description: "SSO service entered")
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        entered.fulfill()
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

actor MacSsoTestService: HostAuthorizationServing {
    private let issueGate: MacSsoTestGate?
    private var resolves = 0, issues = 0
    init(issueGate: MacSsoTestGate? = nil) { self.issueGate = issueGate }
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        resolves += 1
        var presentation: [String: Any] = ["appId": "mac-test", "applicationName": "Test app", "applicationOrigin": request.sourceOrigin,
                                           "permissionDescription": "账号标识、昵称和头像", "consent": "trusted"]
        if let prompt = request.prompt { presentation["prompt"] = prompt }
        return try HostSsoPolicy(response: ["ok": true, "issuer": HostSsoPolicy.issuer, "policyVersion": "test-v1",
                                            "registrationFingerprint": String(repeating: "a", count: 64),
                                            "request": request.protocolFields, "presentation": presentation], request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        issues += 1
        await issueGate?.wait()
        return try HostSsoCode(response: ["ok": true, "code": String(repeating: "c", count: 43)])
    }
    func counts() -> (resolves: Int, issues: Int) { (resolves, issues) }
}

func macSsoParameters(prompt: String? = nil) -> [String: Any] {
    var fields: [String: Any] = ["clientId": "mac-test", "redirectUri": "https://sso.yunle.fun/callback",
                                 "nonce": String(repeating: "n", count: 43), "codeChallenge": String(repeating: "k", count: 43),
                                 "codeChallengeMethod": "S256", "scope": ["identity:bootstrap"]]
    if let prompt { fields["prompt"] = prompt }
    return fields
}

func macSsoTestSystemCallback(for authorizationURL: URL, stateOverride: String? = nil) throws -> URL {
    let query = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
    let callback = try XCTUnwrap(query.first { $0.name == "native_callback_uri" }?.value)
    var components = try XCTUnwrap(URLComponents(string: callback))
    if let stateOverride { components.queryItems = [URLQueryItem(name: "state", value: stateOverride)] }
    let nonce = try XCTUnwrap(query.first { $0.name == "nonce" }?.value)
    let redirect = try XCTUnwrap(query.first { $0.name == "redirect_uri" }?.value)
    let payload: [String: Any] = ["ok": true, "nonce": nonce, "iss": HostSsoPolicy.issuer,
                                 "code": String(repeating: "z", count: 43)]
    let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    components.queryItems?.append(URLQueryItem(name: "result", value: redirect + "#ylf_sso=" + encoded))
    return try XCTUnwrap(components.url)
}
