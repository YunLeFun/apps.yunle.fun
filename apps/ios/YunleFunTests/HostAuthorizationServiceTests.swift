import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class HostAuthorizationServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }

    func testRequestUsesTheActualOriginAndOnlyProtocolFacts() throws {
        var input = ssoParameters()
        input["applicationName"] = "页面伪造名称"
        input["uid"] = "page-selected-user"
        input["access_token"] = "page-token"
        input["acquisition"] = ["version": 9]
        let request = try HostSsoRequest(sourceOrigin: ssoOrigin, parameters: input)
        XCTAssertEqual(request.protocolFields["targetOrigin"] as? String, ssoOrigin)
        XCTAssertNil(request.protocolFields["uid"])
        XCTAssertNil(request.protocolFields["applicationName"])
        XCTAssertNil(request.protocolFields["access_token"])
        XCTAssertNil(request.protocolFields["acquisition"])
        for source in [ssoOrigin + "/", "http://dayun-kicker.yunle.fun", "https://evil.example", ssoOrigin + ":443"] {
            XCTAssertThrowsError(try HostSsoRequest(sourceOrigin: source, parameters: input))
        }
        for (key, value) in [
            ("nonce", "too-short"), ("codeChallenge", String(repeating: "c", count: 42)),
            ("nonce", String(repeating: "n", count: 43) + "\n"),
            ("codeChallenge", String(repeating: "c", count: 43) + "\n"),
            ("codeChallengeMethod", "plain"), ("redirectUri", "https://evil.example/"),
            ("redirectUri", ssoOrigin + "/a/../"), ("prompt", "none"),
        ] {
            var invalid = input; invalid[key] = value
            XCTAssertThrowsError(try HostSsoRequest(sourceOrigin: ssoOrigin, parameters: invalid))
        }
        input["scope"] = ["identity:bootstrap", "admin"]
        XCTAssertThrowsError(try HostSsoRequest(sourceOrigin: ssoOrigin, parameters: input))
    }

    func testRegistryEchoAndPresentationAreValidatedIndependently() throws {
        let request = try ssoRequest()
        let response = ssoPolicyBody(request)
        let policy = try HostSsoPolicy(response: response, request: request)
        XCTAssertEqual(policy.applicationName, "暴力电驴")
        for key in ["mode", "clientId", "targetOrigin", "returnUrl", "scope", "nonce", "codeChallenge", "codeChallengeMethod"] {
            var changed = response
            var echo = try XCTUnwrap(changed["request"] as? [String: Any])
            echo[key] = "substituted"
            changed["request"] = echo
            XCTAssertThrowsError(try HostSsoPolicy(response: changed, request: request), key)
        }
        for (key, value) in [("issuer", "https://evil.example"), ("registrationFingerprint", "missing"), ("policyVersion", "")] {
            var changed = response; changed[key] = value
            XCTAssertThrowsError(try HostSsoPolicy(response: changed, request: request))
        }
        for (key, value) in [
            ("applicationOrigin", "https://evil.example"), ("applicationIconUrl", "http://example.com/icon.png"),
            ("permissionDescription", "读取密码"), ("consent", "implicit"), ("prompt", "select_account"),
        ] {
            var changed = response
            var presentation = try XCTUnwrap(changed["presentation"] as? [String: Any])
            presentation[key] = value; changed["presentation"] = presentation
            XCTAssertThrowsError(try HostSsoPolicy(response: changed, request: request))
        }
    }

    func testExplicitConsentAndAccountSelectionCannotBeSilentlyDowngraded() throws {
        let request = try ssoRequest(prompt: "consent")
        var body = ssoPolicyBody(request)
        var presentation = try XCTUnwrap(body["presentation"] as? [String: Any])
        presentation["prompt"] = nil
        body["presentation"] = presentation
        XCTAssertThrowsError(try HostSsoPolicy(response: body, request: request))
        let trusted = try ssoRequest()
        presentation["consent"] = "explicit"
        body = ssoPolicyBody(trusted); body["presentation"] = presentation
        XCTAssertThrowsError(try HostSsoPolicy(response: body, request: trusted))
        let select = try ssoRequest(prompt: "select_account")
        XCTAssertEqual(try HostSsoPolicy(response: ssoPolicyBody(select), request: select).prompt, "select_account")
    }

    func testIssueResultOnlyDeliversASingleUseCodeAndStrictBoolean() throws {
        let code = try HostSsoCode(response: ["result": [
            "ok": true, "code": String(repeating: "c", count: 43), "expiresAt": 1_800_000_000_000,
            "access_token": "must-not-leave-host", "refresh_token": "must-not-leave-host",
        ]])
        XCTAssertEqual(Set(code.pageResult.keys), ["ok", "code", "issuer", "expiresAt"])
        for body: [String: Any] in [
            ["ok": 1, "code": String(repeating: "c", count: 43)],
            ["ok": true, "code": "invalid"], ["ok": true, "code": String(repeating: "c", count: 43), "expiresAt": true],
        ] { XCTAssertThrowsError(try HostSsoCode(response: body)) }
        var numericOK = ssoPolicyBody(try ssoRequest()); numericOK["ok"] = 1
        XCTAssertThrowsError(try HostSsoPolicy(response: numericOK, request: ssoRequest()))
    }

    func testResolverNeverReceivesHostCredentialsAndOnlyGatewayIssuesForCurrentIdentity() async throws {
        let pending = try ssoRequest(prompt: "consent")
        let fixture = AuthHTTPFixture(replies: [
            (200, try json(ssoPolicyBody(pending))),
            (200, try json(["ok": true, "code": String(repeating: "c", count: 43)])),
        ])
        let service = service(fixture)
        _ = try await service.resolve(pending)
        let issued = try await service.issue(pending, identity: AuthorizedAccount(userID: "host-a", accessToken: "test-token-a"))
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/auth/sso/resolve")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].url?.path, "/v1/functions/sso-ticket")
        XCTAssertNotEqual(requests[0].url?.host, requests[1].url?.host)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer test-token-a")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil && $0.url?.query == nil })
        let resolution = try fields(requests[0]), issue = try fields(requests[1])
        XCTAssertEqual(resolution["prompt"] as? String, "consent")
        XCTAssertNil(issue["prompt"])
        XCTAssertNil(issue["uid"])
        XCTAssertNil(issue["userId"])
        XCTAssertEqual(issue["action"] as? String, "issueSsoCode")
        XCTAssertEqual(issued.code, String(repeating: "c", count: 43))
    }

    func testHTTPFailuresAndHTMLCannotBecomeASuccessfulPolicy() async throws {
        let fixture = AuthHTTPFixture(replies: [(401, "{}"), (503, "{}"), (200, "<html>not an API</html>")])
        let service = service(fixture), request = try ssoRequest()
        for expected in [HostAuthorizationError.unauthorized, .unavailable, .invalidResponse] {
            do { _ = try await service.resolve(request); XCTFail("Invalid transport result must fail") }
            catch { XCTAssertEqual(error as? HostAuthorizationError, expected) }
        }
        let production = HostAuthorizationService().session.configuration
        XCTAssertNil(production.httpCookieStorage)
        XCTAssertNil(production.urlCredentialStorage)
        XCTAssertFalse(production.httpShouldSetCookies)
        XCTAssertNil(production.urlCache)
    }

    private func service(_ fixture: AuthHTTPFixture) -> HostAuthorizationService {
        let resolverHost = "resolve-" + UUID().uuidString.lowercased() + ".invalid"
        let gatewayHost = "gateway-" + UUID().uuidString.lowercased() + ".invalid"
        hosts += [resolverHost, gatewayHost]
        hosts.forEach { AuthHTTPProtocol.register($0, fixture: fixture) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return HostAuthorizationService(session: URLSession(configuration: config),
                                        resolver: URL(string: "https://\(resolverHost)/api/auth/sso/resolve")!,
                                        gateway: URL(string: "https://\(gatewayHost)")!)
    }
    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private func fields(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }; data.append(buffer, count: count)
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

let ssoOrigin = "https://dayun-kicker.yunle.fun"
func ssoParameters(prompt: String? = nil) -> [String: Any] {
    var values: [String: Any] = ["clientId": "dayun-kicker-web", "redirectUri": ssoOrigin + "/",
                                "scope": ["identity:bootstrap"], "nonce": String(repeating: "n", count: 43),
                                "codeChallenge": String(repeating: "c", count: 43), "codeChallengeMethod": "S256"]
    if let prompt { values["prompt"] = prompt }
    return values
}
func ssoRequest(prompt: String? = nil) throws -> HostSsoRequest {
    try HostSsoRequest(sourceOrigin: ssoOrigin, parameters: ssoParameters(prompt: prompt))
}
func ssoPolicyBody(_ request: HostSsoRequest) -> [String: Any] {
    var presentation: [String: Any] = [
        "appId": "dayun-kicker", "applicationName": "暴力电驴", "applicationOrigin": request.sourceOrigin,
        "permissionDescription": "账号标识、昵称和头像", "consent": "trusted",
    ]
    if let prompt = request.prompt { presentation["prompt"] = prompt }
    return ["ok": true, "issuer": HostSsoPolicy.issuer, "policyVersion": "test-policy",
            "registrationFingerprint": String(repeating: "f", count: 64),
            "request": request.protocolFields, "presentation": presentation]
}
