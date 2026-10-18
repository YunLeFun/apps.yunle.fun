import XCTest
@testable import YunleFun

@MainActor
final class CrossAppAuthorizationTests: XCTestCase {
    private let nonce = String(repeating: "n", count: 43)
    private let challenge = String(repeating: "c", count: 43)

    private func entry(_ extra: String = "", replacing: [String: String] = [:], path: String = "/auth/app") -> URL {
        var values = ["client_id": "life-ios", "redirect_uri": "https://life.yunle.fun/auth/callback",
                      "scope": "identity:bootstrap", "nonce": nonce, "code_challenge": challenge,
                      "code_challenge_method": "S256", "prompt": "select_account"]
        values.merge(replacing) { $1 }
        var parts = URLComponents(string: "https://www.yunle.fun\(path)")!
        parts.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return URL(string: parts.string! + extra)!
    }

    func testParsesTheRegisteredEntryIntoProtocolFactsOnly() throws {
        let request = try XCTUnwrap(CrossAppAuthorizationLink.parse(entry()))
        XCTAssertEqual(request.clientID, "life-ios")
        XCTAssertEqual(request.redirectURI.absoluteString, "https://life.yunle.fun/auth/callback")
        XCTAssertEqual(request.sourceOrigin, "https://life.yunle.fun")
        // 跨 App 不转发 prompt，由 broker 总是显式确认
        XCTAssertNil(request.brokerParameters["prompt"])
        let host = try HostSsoRequest(sourceOrigin: request.sourceOrigin, parameters: request.brokerParameters)
        XCTAssertEqual(host.protocolFields["returnUrl"] as? String, "https://life.yunle.fun/auth/callback")
        XCTAssertNotNil(CrossAppAuthorizationLink.parse(entry(replacing: ["prompt": "consent"])))
    }

    func testRejectsMalformedOrUnexpectedEntries() {
        let invalid: [URL] = [
            entry("&nonce=\(String(repeating: "m", count: 43))"),
            entry("&native_callback_uri=yunlefun://auth/sso"),
            entry("&extra=1"),
            entry("#fragment"),
            entry(replacing: ["prompt": "none"]),
            entry(replacing: ["scope": "identity:bootstrap wallet"]),
            entry(replacing: ["code_challenge_method": "plain"]),
            entry(replacing: ["nonce": "short"]),
            entry(replacing: ["redirect_uri": "http://life.yunle.fun/auth/callback"]),
            entry(replacing: ["redirect_uri": "https://life.yunle.fun:8443/auth/callback"]),
            entry(replacing: ["client_id": "Life iOS"]),
            URL(string: entry().absoluteString.replacingOccurrences(of: "https://", with: "https://user@"))!,
            URL(string: entry().absoluteString + "&x=" + String(repeating: "a", count: 4096))!,
        ]
        for url in invalid { XCTAssertNil(CrossAppAuthorizationLink.parse(url), url.absoluteString) }
        XCTAssertFalse(CrossAppAuthorizationLink.isEntry(entry(path: "/auth/sso")))
        XCTAssertFalse(CrossAppAuthorizationLink.isEntry(URL(string: "https://apps.yunle.fun/auth/app")!))
        XCTAssertTrue(CrossAppAuthorizationLink.isEntry(entry("&extra=1")))
    }

    func testCallbackEncodingMatchesTheSharedContractFixture() throws {
        let fixture = try loadFixture()
        let request = CrossAppAuthorizationRequest(clientID: "life-ios", redirectURI: URL(string: fixture.redirectUri)!,
                                                   nonce: fixture.nonce, codeChallenge: challenge)
        let outcomes: [String: CrossAppRedirect] = [
            "approved": .approved(code: fixture.code), "denied": .denied,
            "accountSelectionRequired": .accountSelectionRequired,
        ]
        XCTAssertEqual(Set(outcomes.keys), Set(fixture.cases.map(\.name)))
        for item in fixture.cases {
            let url = try XCTUnwrap(outcomes[item.name]?.callbackURL(for: request))
            XCTAssertEqual(url.absoluteString, "\(fixture.redirectUri)#\(fixture.hashKey)=\(item.encoded)", item.name)
        }
        XCTAssertNil(CrossAppRedirect.approved(code: "not-a-code").callbackURL(for: request))
    }

    func testApprovedCodeReturnsOnlyThroughUniversalLinks() throws {
        var opened: [URL] = []
        var issues: [CrossAppAuthorizationIssue?] = []
        let page = makePage(open: { url, done in opened.append(url); done(true) }, finished: { issues.append($0) })
        page.resolve(page.requestID, result: ["ok": true, "code": String(repeating: "k", count: 43)], error: nil)
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened[0].absoluteString.hasPrefix("https://life.yunle.fun/auth/callback#ylf_sso="))
        XCTAssertEqual(issues, [nil])
        // 只回跳一次
        page.resolve(page.requestID, result: ["ok": true, "code": String(repeating: "k", count: 43)], error: nil)
        XCTAssertEqual(opened.count, 1)
        XCTAssertFalse(page.isPending(page.requestID))
    }

    func testUnopenableCallbackDiscardsTheCode() {
        var issues: [CrossAppAuthorizationIssue?] = []
        let page = makePage(open: { _, done in done(false) }, finished: { issues.append($0) })
        page.resolve(page.requestID, result: ["ok": true, "code": String(repeating: "k", count: 43)], error: nil)
        XCTAssertEqual(issues, [.unableToReturn("原 App")])
    }

    func testDenialAndOtherAccountReturnWithoutCodeAndInvalidRequestsNeverReturn() throws {
        var opened: [URL] = []
        let denied = makePage(open: { url, done in opened.append(url); done(true) })
        denied.resolve(denied.requestID, result: nil, error: HostAuthorizationError.denied.code)
        let other = makePage(open: { url, done in opened.append(url); done(true) })
        XCTAssertTrue(other.useOtherAccount(other.requestID))
        XCTAssertEqual(opened.map { decodedPayload($0)["reason"] as? String }, ["access_denied", "account_selection_required"])
        XCTAssertTrue(opened.allSatisfy { decodedPayload($0)["code"] == nil })

        var issues: [CrossAppAuthorizationIssue?] = []
        let invalid = makePage(open: { url, done in opened.append(url); done(true) }, finished: { issues.append($0) })
        invalid.resolve(invalid.requestID, result: nil, error: HostAuthorizationError.invalidRequest.code)
        XCTAssertEqual(opened.count, 2)
        XCTAssertEqual(issues, [.invalidRequest])
        XCTAssertFalse(invalid.useOtherAccount("another-request"))
    }

    func testCrossAppRequestsAlwaysRequireExplicitConsentEvenForTrustedClients() async throws {
        let accounts = ConsentAccounts(user: AccountUser(id: "a"))
        let broker = NativeAuthorizationBroker(accounts: accounts, service: TrustedService())
        let page = ConsentPage()
        page.consentShown = expectation(description: "Consent")
        let request = try XCTUnwrap(CrossAppAuthorizationLink.parse(entry()))
        broker.begin(requestID: "r", sourceOrigin: request.sourceOrigin, parameters: request.brokerParameters,
                     page: page, requireConsent: true)
        XCTAssertTrue(broker.isBusy)
        await fulfillment(of: [page.consentShown!], timeout: 3)
        XCTAssertTrue(page.results.isEmpty, "No code before an explicit decision")
    }

    // MARK: 辅助

    private func makePage(open: @escaping CrossAppAuthorizationPage.Opener,
                          finished: @escaping (CrossAppAuthorizationIssue?) -> Void = { _ in }) -> CrossAppAuthorizationPage {
        let request = CrossAppAuthorizationRequest(clientID: "life-ios", redirectURI: URL(string: "https://life.yunle.fun/auth/callback")!,
                                                   nonce: nonce, codeChallenge: challenge)
        return CrossAppAuthorizationPage(request: request, accounts: nil, presenter: { nil }, open: open, finished: finished)
    }

    private func decodedPayload(_ url: URL) -> [String: Any] {
        var encoded = String(url.fragment?.dropFirst("ylf_sso=".count) ?? "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private struct Fixture: Decodable {
        struct Case: Decodable { let name: String; let encoded: String }
        let nonce: String, code: String, redirectUri: String, hashKey: String
        let cases: [Case]
    }

    private func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cross-app-redirect", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

@MainActor
private final class ConsentAccounts: AccountAuthorizing {
    var user: AccountUser?
    init(user: AccountUser?) { self.user = user }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        AuthorizedAccount(userID: user?.id ?? "", accessToken: "token")
    }
}

private struct TrustedService: HostAuthorizationServing {
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        try HostSsoPolicy(response: [
            "ok": true, "issuer": HostSsoPolicy.issuer, "policyVersion": "test",
            "registrationFingerprint": String(repeating: "f", count: 64), "request": request.protocolFields,
            "presentation": ["appId": "life", "applicationName": "云生", "applicationOrigin": request.sourceOrigin,
                             "permissionDescription": "账号标识、昵称和头像", "consent": "trusted"],
        ], request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        try HostSsoCode(response: ["ok": true, "code": String(repeating: "c", count: 43)])
    }
}

@MainActor
private final class ConsentPage: HostAuthorizationPage {
    var consentShown: XCTestExpectation?
    var results: [[String: Any]] = []
    func isPending(_ requestID: String) -> Bool { true }
    func pause(_ requestID: String) -> Bool { true }
    func resume(_ requestID: String) -> Bool { true }
    func resolve(_ requestID: String, result: [String: Any]?, error: String?) { if let result { results.append(result) } }
    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool { false }
    func showConsent(policy: HostSsoPolicy, user: AccountUser, completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        consentShown?.fulfill(); return true
    }
    func dismissAuthorizationUI() {}
    func useOtherAccount(_ requestID: String) -> Bool { false }
}
