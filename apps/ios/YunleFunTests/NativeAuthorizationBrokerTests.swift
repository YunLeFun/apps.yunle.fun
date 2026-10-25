import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

@MainActor
final class NativeAuthorizationBrokerTests: XCTestCase {
    func testGuestLoginKeepsOnlyItsRequestAndWaitsForCookiesThenRequiresConsent() async throws {
        let accounts = SsoAccounts(nil), service = SsoService(), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        page.loginShown = expectation(description: "Native login")
        begin(broker, page)
        await fulfillment(of: [page.loginShown!], timeout: 3)
        XCTAssertTrue(broker.identityWillChange(to: "a") === page)
        accounts.user = AccountUser(id: "a")
        page.loginCompletion?(true)
        XCTAssertEqual(page.consentCount, 0)
        var counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
        page.consentShown = expectation(description: "Explicit confirmation after login")
        broker.identityCookiesCleared()
        await fulfillment(of: [page.consentShown!], timeout: 3)
        counts = await service.counts()
        XCTAssertEqual(counts.resolves, 2)
        XCTAssertEqual(counts.issues, 0, "Login must never silently authorize")
        page.resolved = expectation(description: "One-time code")
        page.consentCompletion?(.current)
        await fulfillment(of: [page.resolved!], timeout: 3)
        XCTAssertNil(page.responses.first?.error)
        XCTAssertEqual(page.responses.first?.result?["code"] as? String, String(repeating: "c", count: 43))
        XCTAssertEqual(accounts.refreshRequests, [false])
    }

    func testCancellingLoginOrConsentNeverRequestsAnAccessTokenOrCode() async throws {
        for signedIn in [false, true] {
            let accounts = SsoAccounts(signedIn ? "a" : nil), service = SsoService(), page = SsoPage()
            let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
            let shown = expectation(description: "Decision")
            if signedIn { page.consentShown = shown } else { page.loginShown = shown }
            begin(broker, page, prompt: signedIn ? "consent" : nil)
            await fulfillment(of: [shown], timeout: 3)
            if signedIn { page.consentCompletion?(.cancel) } else { page.loginCompletion?(false) }
            XCTAssertEqual(page.responses.first?.error, "HOST_AUTH_DENIED")
            let counts = await service.counts()
            XCTAssertEqual(counts.issues, 0)
            XCTAssertTrue(accounts.refreshRequests.isEmpty)
        }
    }

    func testAccountSwitchDuringIssueDiscardsTheLateCodeAndClosesItsUI() async throws {
        let gate = SsoGate(), accounts = SsoAccounts("a"), service = SsoService(issueGate: gate), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        begin(broker, page)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertNil(broker.identityWillChange(to: "b"))
        accounts.user = AccountUser(id: "b")
        XCTAssertEqual(page.responses.first?.error, "HOST_AUTH_DENIED")
        XCTAssertEqual(page.dismissals, 1)
        let late = expectation(description: "No late code"); late.isInverted = true
        page.resolved = late
        await gate.open()
        await fulfillment(of: [late], timeout: 0.2)
        XCTAssertEqual(page.responses.count, 1)
    }

    func testNavigationDuringPolicyResolutionNeverIssuesForTheNewDocument() async throws {
        let gate = SsoGate(), accounts = SsoAccounts("a"), service = SsoService(resolveGate: gate), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        page.resolved = expectation(description: "Expired original request")
        begin(broker, page)
        await fulfillment(of: [gate.entered], timeout: 3)
        page.pending = false
        await gate.open()
        await fulfillment(of: [page.resolved!], timeout: 3)
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
        XCTAssertTrue(accounts.refreshRequests.isEmpty)
    }

    func testGateway401RefreshesOnceForTheSameAccount() async throws {
        let accounts = SsoAccounts("a"), service = SsoService(unauthorizedOnce: true), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        page.resolved = expectation(description: "Retried code")
        begin(broker, page)
        await fulfillment(of: [page.resolved!], timeout: 3)
        XCTAssertEqual(accounts.refreshRequests, [false, true])
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 2)
        XCTAssertNil(page.responses.first?.error)
    }

    func testOtherAccountUsesSystemAuthenticationWithoutReadingHostCredentials() async throws {
        let accounts = SsoAccounts("a"), service = SsoService(), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        page.otherStarted = expectation(description: "System account selection")
        begin(broker, page, prompt: "select_account")
        await fulfillment(of: [page.otherStarted!], timeout: 3)
        XCTAssertTrue(accounts.refreshRequests.isEmpty)
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
        XCTAssertTrue(page.responses.isEmpty)
        XCTAssertEqual(accounts.user?.id, "a")
    }

    func testExpiredConsentCannotBeAcceptedLater() async throws {
        let accounts = SsoAccounts("a"), service = SsoService(), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service, decisionTimeout: 0.02)
        page.resolved = expectation(description: "Decision expires")
        begin(broker, page, prompt: "consent")
        await fulfillment(of: [page.resolved!], timeout: 3)
        page.consentCompletion?(.current)
        XCTAssertEqual(page.responses.count, 1)
        XCTAssertEqual(page.dismissals, 1)
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
        XCTAssertTrue(accounts.refreshRequests.isEmpty)
    }

    func testAuthenticatedAccountCannotPreserveARequestByStartingLoginAgain() async throws {
        let accounts = SsoAccounts("a"), service = SsoService(), page = SsoPage()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        page.consentShown = expectation(description: "Consent")
        begin(broker, page, prompt: "consent")
        await fulfillment(of: [page.consentShown!], timeout: 3)
        XCTAssertNil(broker.identityWillChange(to: nil))
        accounts.user = nil
        page.consentCompletion?(.current)
        XCTAssertEqual(page.responses.first?.error, "HOST_AUTH_DENIED")
        let counts = await service.counts()
        XCTAssertEqual(counts.issues, 0)
    }

    func testACompletedRequestDoesNotRetainThePageUntilItsDeadline() async throws {
        let accounts = SsoAccounts("a"), service = SsoService()
        let broker = NativeAuthorizationBroker(accounts: accounts, service: service)
        weak var released: SsoPage?
        do {
            let page = SsoPage()
            released = page
            let done = expectation(description: "Delivery")
            page.resolved = done
            begin(broker, page)
            await fulfillment(of: [done], timeout: 3)
        }
        await Task.yield()
        XCTAssertNil(released, "A completed request must not keep its page through a cancelled deadline")
    }

    private func begin(_ broker: NativeAuthorizationBroker, _ page: SsoPage, prompt: String? = nil) {
        broker.begin(requestID: "test-request", sourceOrigin: ssoOrigin, parameters: ssoParameters(prompt: prompt), page: page)
    }
}

@MainActor
private final class SsoAccounts: AccountAuthorizing {
    var user: AccountUser?
    var refreshRequests: [Bool] = []
    init(_ id: String?) { user = id.map { AccountUser(id: $0) } }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        refreshRequests.append(forceRefresh)
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: "test-token-\(user.id)")
    }
}
private actor SsoGate {
    let entered = XCTestExpectation(description: "Service entered")
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        entered.fulfill()
        if !isOpen { await withCheckedContinuation { continuation = $0 } }
    }
    func open() { isOpen = true; continuation?.resume(); continuation = nil }
}
private actor SsoService: HostAuthorizationServing {
    private let resolveGate: SsoGate?
    private let issueGate: SsoGate?
    private var unauthorizedOnce: Bool
    private var resolves = 0, issues = 0
    init(resolveGate: SsoGate? = nil, issueGate: SsoGate? = nil, unauthorizedOnce: Bool = false) {
        self.resolveGate = resolveGate; self.issueGate = issueGate; self.unauthorizedOnce = unauthorizedOnce
    }
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        resolves += 1
        await resolveGate?.wait()
        return try HostSsoPolicy(response: ssoPolicyBody(request), request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        issues += 1
        await issueGate?.wait()
        if unauthorizedOnce { unauthorizedOnce = false; throw HostAuthorizationError.unauthorized }
        return try HostSsoCode(response: ["ok": true, "code": String(repeating: "c", count: 43)])
    }
    func counts() -> (resolves: Int, issues: Int) { (resolves, issues) }
}
@MainActor
private final class SsoPage: HostAuthorizationPage {
    struct Response { let result: [String: Any]?; let error: String? }
    var pending = true
    var responses: [Response] = []
    var dismissals = 0, consentCount = 0
    var loginShown: XCTestExpectation?, consentShown: XCTestExpectation?, resolved: XCTestExpectation?, otherStarted: XCTestExpectation?
    var loginCompletion: ((Bool) -> Void)?
    var consentCompletion: ((AuthorizationSheetChoice) -> Void)?
    func isPending(_ requestID: String) -> Bool { pending }
    func pause(_ requestID: String) -> Bool { pending }
    func resume(_ requestID: String) -> Bool { pending }
    func resolve(_ requestID: String, result: [String: Any]?, error: String?) {
        pending = false
        responses.append(Response(result: result, error: error)); resolved?.fulfill()
    }
    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        loginCompletion = completion; loginShown?.fulfill(); return true
    }
    func showConsent(policy: HostSsoPolicy, user: AccountUser, completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        consentCount += 1; consentCompletion = completion; consentShown?.fulfill(); return true
    }
    func dismissAuthorizationUI() { dismissals += 1 }
    func useOtherAccount(_ requestID: String) -> Bool { otherStarted?.fulfill(); return true }
}
