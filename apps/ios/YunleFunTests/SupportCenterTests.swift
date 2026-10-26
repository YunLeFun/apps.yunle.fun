import CryptoKit
import XCTest
@testable import YunleFun

final class SupportCenterServiceTests: XCTestCase {
    override func tearDown() { SupportHTTPProtocol.fixture = nil; super.tearDown() }

    func testTrustedSSOUsesPKCEAndOnlyTransfersTheSupportCookie() async throws {
        let host = SupportTestHost()
        let fixture = SupportHTTPFixture(replies: [
            .json(["ok": true, "identityAssertion": String(repeating: "a", count: 64)]),
            .json(["ok": true, "user": ["userId": "user-a"], "csrfToken": "csrf-a"], cookie: supportCookie),
        ])
        let service = service(fixture, host: host)
        let access = try await service.connect(identity: AuthorizedAccount(userID: "user-a", accessToken: "native-test-token"), consent: false)
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.yunle.fun/sso-ticket")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        let exchange = try body(requests[0]), proof = try body(requests[1])
        let policyRequest = await host.resolved
        let resolved = try XCTUnwrap(policyRequest)
        let verifier = try XCTUnwrap(exchange["codeVerifier"] as? String)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, resolved.challenge)
        XCTAssertEqual(exchange["nonce"] as? String, resolved.nonce)
        XCTAssertEqual(proof["nonce"] as? String, resolved.nonce)
        XCTAssertEqual(proof["accessToken"] as? String, "native-test-token")
        XCTAssertEqual(Set(proof.keys), ["accessToken", "identityAssertion", "nonce"])
        XCTAssertEqual(requests[1].url?.absoluteString, "https://support.yunle.fun/api/v1/session/exchange")
        XCTAssertTrue(requests.allSatisfy { $0.url?.query == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertEqual(access.userID, "user-a")
        XCTAssertEqual(access.cookies.map(\.name), [SupportCenterService.cookieName])
        XCTAssertTrue(access.cookies[0].isHTTPOnly)
        XCTAssertTrue(access.cookies[0].isSecure)
        XCTAssertNil(service.session.configuration.httpCookieStorage)
    }

    func testExplicitConsentDoesNotIssueACodeSilently() async throws {
        let host = SupportTestHost(consent: true)
        let fixture = SupportHTTPFixture(replies: [])
        do {
            _ = try await service(fixture, host: host).connect(identity: .init(userID: "user-a", accessToken: "test"), consent: false)
            XCTFail("Explicit policy requires a native decision")
        } catch { XCTAssertEqual(error as? SupportCenterError, .consentRequired) }
        let issues = await host.issues
        XCTAssertEqual(issues, 0)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testSSORejectsASessionForADifferentUID() async throws {
        let fixture = SupportHTTPFixture(replies: [
            .json(["ok": true, "identityAssertion": String(repeating: "a", count: 64)]),
            .json(["ok": true, "user": ["userId": "user-b"], "csrfToken": "test"], cookie: supportCookie),
        ])
        do {
            _ = try await service(fixture).connect(identity: .init(userID: "user-a", accessToken: "test"), consent: false)
            XCTFail("Must bind to the native account")
        } catch { XCTAssertEqual(error as? SupportCenterError, .invalidResponse) }
    }

    func testGuestSubmissionSendsCSRFAndIdempotencyWithoutAnAccountOrLogs() async throws {
        let fixture = SupportHTTPFixture(replies: [
            .json(["kind": "guest", "csrfToken": "guest-csrf"], cookie: "__Host-ylf-support-guest=fixture-guest; Path=/; Secure; HttpOnly"),
            .json(["receipt": ["id": "fb_test", "productId": "www", "ticketId": "fb_test", "ticketUrl": "https://support.yunle.fun/tickets/fb_test#access=fixture"]]),
        ])
        let service = service(fixture)
        let access = try await service.connect(identity: nil, consent: false)
        let receipt = try await service.submit(product: "www", category: "problem", description: "  A real problem  ", key: "stable-key", access: access)
        XCTAssertEqual(receipt.id, "fb_test")
        let request = fixture.requests[1]
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-csrf-token"), "guest-csrf")
        XCTAssertEqual(request.value(forHTTPHeaderField: "idempotency-key"), "stable-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://support.yunle.fun")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("fixture-guest") == true)
        XCTAssertEqual(try body(request) as? [String: String], ["productId": "www", "category": "problem", "description": "A real problem"])
    }

    func testClosingSupportRevokesOnlyItsOwnSession() async throws {
        let fixture = SupportHTTPFixture(replies: [.json(["ok": true])])
        let cookie = try XCTUnwrap(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": supportCookie],
                                                     for: SupportCenterService.origin).first)
        try await service(fixture).disconnect(.init(userID: "user-a", csrfToken: "csrf-a", cookies: [cookie]))
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "https://support.yunle.fun/api/v1/session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-csrf-token"), "csrf-a")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("fixture-session") == true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testHTMLAndUnauthorizedManagementAreNotEmptySuccesses() async throws {
        let fixture = SupportHTTPFixture(replies: [
            SupportHTTPReply(status: 200, data: Data("<html>fallback</html>".utf8), headers: ["Content-Type": "text/html"]),
            .json(["ok": false], status: 403),
        ])
        let service = service(fixture)
        do { _ = try await service.board(cursor: nil); XCTFail() }
        catch { XCTAssertEqual(error as? SupportCenterError, .invalidResponse) }
        do { _ = try await service.dashboard(product: nil, cursor: nil, access: .init(userID: "user-a", csrfToken: "", cookies: [])); XCTFail() }
        catch { XCTAssertEqual(error as? SupportCenterError, .forbidden) }
    }

    func testGuestBootstrapRejectsCookiesOutsideItsHttpOnlyHostBoundary() async throws {
        for cookie in [
            "__Host-ylf-support-guest=fixture; Path=/; Secure",
            "__Host-ylf-support-guest=fixture; Path=/; HttpOnly",
            "__Host-ylf-support-guest=fixture; Domain=evil.test; Path=/; Secure; HttpOnly",
            "unrelated=fixture; Path=/; Secure; HttpOnly",
        ] {
            let fixture = SupportHTTPFixture(replies: [.json(["kind": "guest", "csrfToken": "fixture"], cookie: cookie)])
            do { _ = try await service(fixture).connect(identity: nil, consent: false); XCTFail("Cookie boundary: \(cookie)") }
            catch { XCTAssertEqual(error as? SupportCenterError, .invalidResponse) }
        }
    }

    func testTicketNavigationRejectsUnrelatedOriginsAndWrongTicketPaths() throws {
        for raw in ["https://support.yunle.fun.evil.test/tickets/fb_test", "http://support.yunle.fun/tickets/fb_test",
                    "https://support.yunle.fun:444/tickets/fb_test", "https://support.yunle.fun/tickets/another",
                    "https://support.yunle.fun/tickets/fb_test?access=secret"] {
            let receipt = SupportFeedbackReceipt(id: "fb_test", productId: "www", ticketId: "fb_test", ticketUrl: raw)
            XCTAssertNil(SupportCenterService.ticketURL(receipt))
        }
        XCTAssertNotNil(SupportCenterService.ticketURL(.init(id: "fb_test", productId: "www", ticketId: "fb_test",
            ticketUrl: "https://support.yunle.fun/tickets/fb_test#access=guest-fixture")))
    }

    func testCookPrivateFeedbackDecodesWebAndIOSWithoutGuessingMissingSources() throws {
        let decoder = JSONDecoder()
        for (source, title) in [("cook-web", "Web"), ("cook-ios", "iOS")] {
            let data = Data("""
                {"id":"fb_fixture","productId":"cook","description":"Private fixture","status":"received",
                 "category":"problem","createdAt":"2026-10-26","context":{"source":"\(source)","version":"1.2.3"}}
                """.utf8)
            let item = try decoder.decode(SupportPrivateItem.self, from: data)
            XCTAssertEqual(item.sourceTitle, title)
            XCTAssertEqual(item.sourceSummary, "\(title) · 1.2.3")
        }
        let historical = Data("""
            {"id":"fb_old","productId":"cook","description":"Old fixture","status":"received",
             "category":"problem","createdAt":"2026-10-26"}
            """.utf8)
        XCTAssertEqual(try decoder.decode(SupportPrivateItem.self, from: historical).sourceSummary, "未记录")
    }

    private var supportCookie: String { "__Host-ylf-support-session=fixture-session; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax" }
    private func service(_ fixture: SupportHTTPFixture, host: SupportTestHost = SupportTestHost()) -> SupportCenterService {
        SupportHTTPProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.protocolClasses = [SupportHTTPProtocol.self]
        return SupportCenterService(session: URLSession(configuration: configuration), authorization: host)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

@MainActor
final class SupportCenterStoreTests: XCTestCase {
    func testLateConnectionCannotCrossAnAccountSwitchOrABA() async {
        let accounts = SupportAccounts("a"), service = SupportStoreFixture(blockConnection: true)
        let model = SupportCenterStore(accounts: accounts, service: service)
        let task = Task { await model.load(.compose) }
        await service.waitForConnection()
        accounts.select("b"); accounts.select("a")
        XCTAssertNil(model.access)
        model.identityChanged()
        await service.releaseConnection()
        await task.value
        XCTAssertNil(model.access)
        XCTAssertNil(model.receipt)
    }

    func testPrivateDashboardDisappearsImmediatelyAtTheIdentityBoundary() async {
        let accounts = SupportAccounts("a"), service = SupportStoreFixture()
        let model = SupportCenterStore(accounts: accounts, service: service)
        await model.load(.manage)
        XCTAssertEqual(model.dashboard?.privateFeedback.items.count, 1)
        accounts.select("b")
        XCTAssertNil(model.dashboard)
        XCTAssertNil(model.access)
    }

    func testUnauthorizedConnectionRefreshesTheHostCredentialOnce() async {
        let accounts = SupportAccounts("a"), service = SupportStoreFixture(unauthorizedOnce: true)
        let model = SupportCenterStore(accounts: accounts, service: service)
        await model.load(.compose)
        XCTAssertEqual(accounts.refreshes, [false, true])
        XCTAssertEqual(model.access?.userID, "a")
    }

    func testFailedSubmissionReusesItsKeyAndDoesNotRetryAutomatically() async {
        let accounts = SupportAccounts(nil), service = SupportStoreFixture()
        let model = SupportCenterStore(accounts: accounts, service: service)
        await model.load(.compose)
        await model.submit(product: "www", category: "problem", description: "same description")
        let first = await service.keys
        XCTAssertEqual(first.count, 1)
        XCTAssertNil(model.receipt)
        await model.submit(product: "www", category: "problem", description: "same description")
        let repeated = await service.keys
        XCTAssertEqual(repeated.count, 2)
        XCTAssertEqual(repeated[0], repeated[1])
        await model.submit(product: "www", category: "suggestion", description: "same description")
        let edited = await service.keys
        XCTAssertNotEqual(edited[1], edited[2])
    }
}

private actor SupportTestHost: HostAuthorizationServing {
    let consent: Bool
    var resolved: HostSsoRequest?
    var issues = 0
    init(consent: Bool = false) { self.consent = consent }
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        resolved = request
        var presentation: [String: Any] = ["appId": "support", "applicationName": "云乐坊支持中心",
            "applicationOrigin": request.sourceOrigin, "permissionDescription": "账号标识、昵称和头像", "consent": consent ? "explicit" : "trusted"]
        if consent { presentation["prompt"] = "consent" }
        return try HostSsoPolicy(response: ["ok": true, "issuer": HostSsoPolicy.issuer,
            "policyVersion": "fixture", "registrationFingerprint": String(repeating: "a", count: 64),
            "request": request.protocolFields, "presentation": presentation], request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        issues += 1
        return try HostSsoCode(response: ["ok": true, "code": String(repeating: "c", count: 43)])
    }
}

private struct SupportHTTPReply {
    let status: Int
    let data: Data
    let headers: [String: String]
    static func json(_ value: [String: Any], status: Int = 200, cookie: String? = nil) -> Self {
        var headers = ["Content-Type": "application/json"]
        headers["Set-Cookie"] = cookie
        return Self(status: status, data: try! JSONSerialization.data(withJSONObject: value), headers: headers)
    }
}
private final class SupportHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [SupportHTTPReply]
    private var received: [URLRequest] = []
    init(replies: [SupportHTTPReply]) { self.replies = replies }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
    func take(_ request: URLRequest) -> SupportHTTPReply {
        lock.lock(); defer { lock.unlock() }
        received.append(request)
        return replies.isEmpty ? .json([:], status: 500) : replies.removeFirst()
    }
}
private final class SupportHTTPProtocol: URLProtocol {
    static var fixture: SupportHTTPFixture?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            recorded.httpBody = data
        }
        let reply = fixture.take(recorded)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class SupportAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser?
    var identityGeneration = UUID()
    var refreshes: [Bool] = []
    init(_ uid: String?) { user = uid.map { AccountUser(id: $0) } }
    func select(_ uid: String?) { user = uid.map { AccountUser(id: $0) }; identityGeneration = UUID() }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        refreshes.append(forceRefresh)
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: "fixture")
    }
}
private actor SupportStoreFixture: SupportCenterServing {
    let blockConnection: Bool
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    var keys: [String] = []
    var unauthorizedOnce: Bool
    init(blockConnection: Bool = false, unauthorizedOnce: Bool = false) {
        self.blockConnection = blockConnection; self.unauthorizedOnce = unauthorizedOnce
    }
    func connect(identity: AuthorizedAccount?, consent: Bool) async throws -> SupportAccess {
        if unauthorizedOnce { unauthorizedOnce = false; throw SupportCenterError.unauthorized }
        entered = true; entryWaiter?.resume(); entryWaiter = nil
        if blockConnection { await withCheckedContinuation { gate = $0 } }
        return SupportAccess(userID: identity?.userID, csrfToken: "fixture", cookies: [])
    }
    func waitForConnection() async { if !entered { await withCheckedContinuation { entryWaiter = $0 } } }
    func releaseConnection() { gate?.resume(); gate = nil }
    func disconnect(_ access: SupportAccess) async throws {}
    func board(cursor: String?) async throws -> SupportPage<SupportBoardItem> { .init(items: [], nextCursor: nil) }
    func dashboard(product: String?, cursor: String?, access: SupportAccess) async throws -> SupportDashboard {
        .init(productId: "www", productIds: ["www"], feedback: .init(items: [], nextCursor: nil),
              privateFeedback: .init(items: [.init(id: "fb_fixture", productId: "www", description: "Private fixture",
                  status: "received", category: "problem", createdAt: "2026-10-26", ticketId: nil, context: nil)], nextCursor: nil))
    }
    func submit(product: String, category: String, description: String, key: String, access: SupportAccess) async throws -> SupportFeedbackReceipt {
        keys.append(key)
        throw URLError(.timedOut)
    }
}
