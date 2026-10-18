import XCTest
@testable import YunleFun

final class CloudbaseAuthServiceTests: XCTestCase {
    private var fixtures: [String] = []
    private let token = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600,"sub":"test-user"}"#

    func testMalformedProfileCredentialIsExpiredButOtherPreconditionsAreNot() async throws {
        let failure = #"{"error":"failed_precondition","error_code":9}"#
        let (api, _) = service([(400, failure), (400, failure), (400, #"{"error":"invalid_argument","error_code":3}"#)])
        do { _ = try await api.user(accessToken: "malformed-test", deviceID: "test-device"); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .expiredSession) }
        do { _ = try await api.passwordSignIn(identifier: "user", password: "test", deviceID: "test-device", captcha: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .unavailable) }
        do { _ = try await api.user(accessToken: "test-token", deviceID: "test-device"); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .unavailable) }
    }

    override func tearDown() {
        fixtures.forEach { AuthHTTPProtocol.unregister($0) }
        fixtures = []
        super.tearDown()
    }

    func testPasswordLoginAndUserInfoMatchTheOfficialWireContract() async throws {
        let (api, fixture) = service([
            (200, token),
            (200, #"{"sub":"test-user","name":"测试用户","phone_number":"+86 13800000000","user_desc":"个人简介","status":"ACTIVE"}"#),
        ])
        let response = try await api.passwordSignIn(identifier: "13800000000", password: "test-password", deviceID: "test-device", captcha: nil)
        let user = try await api.user(accessToken: response.accessToken, deviceID: "test-device")
        let requests = fixture.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/auth/v1/signin", "/auth/v1/user/me"])
        XCTAssertEqual(try fields(requests[0]), ["username": "+86 13800000000", "password": "test-password"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertNil(requests[1].httpBody)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-device-id"), "test-device")
        XCTAssertEqual(user.id, response.subject)
        XCTAssertEqual(user.description, "个人简介")
    }

    func testPhoneVerificationForAnExistingUserSignsInWithoutSendingTheAddressAgain() async throws {
        let (api, fixture) = service([
            (200, #"{"verification_id":"test-verification","expires_in":300,"is_user":true}"#),
            (200, #"{"verification_token":"test-verification-token"}"#),
            (200, token),
        ])
        let challenge = try await api.sendVerification(address: VerificationAddress.phoneInput("+86 13800000000"),
                                                       deviceID: "test-device", captcha: "test-captcha")
        _ = try await api.verify(challenge, code: "123456", deviceID: "test-device", captcha: nil)
        let requests = fixture.requests
        XCTAssertEqual(try fields(requests[0]), ["phone_number": "+86 13800000000", "target": "ANY"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-captcha-token"), "test-captcha")
        XCTAssertEqual(try fields(requests[1]), ["verification_id": "test-verification", "verification_code": "123456"])
        XCTAssertEqual(requests[2].url?.path, "/auth/v1/signin")
        XCTAssertEqual(try fields(requests[2]), ["verification_token": "test-verification-token"])
    }

    func testNewEmailUserSignsUpUsingTheVerifiedEmail() async throws {
        let (api, fixture) = service([
            (200, #"{"verification_id":"test-verification","expires_in":300,"is_user":false}"#),
            (200, #"{"verification_token":"test-verification-token"}"#),
            (200, token),
        ])
        let challenge = try await api.sendVerification(address: VerificationAddress.emailInput("native@example.invalid"),
                                                       deviceID: "test-device", captcha: nil)
        _ = try await api.verify(challenge, code: "123456", deviceID: "test-device", captcha: nil)
        let requests = fixture.requests
        XCTAssertEqual(try fields(requests[0]), ["email": "native@example.invalid", "target": "ANY"])
        XCTAssertEqual(requests[2].url?.path, "/auth/v1/signup")
        XCTAssertEqual(try fields(requests[2]), ["email": "native@example.invalid", "verification_token": "test-verification-token"])
    }

    func testRefreshProfileAndSignoutNeverPutCredentialsInURLs() async throws {
        let (api, fixture) = service([(200, token), (200, "{}"), (200, "{}")])
        _ = try await api.refresh("test-refresh", deviceID: "test-device")
        try await api.updateProfile(userID: "test-user", name: "昵称", description: "简介",
                                    accessToken: "test-access", deviceID: "test-device")
        try await api.signOut(accessToken: "test-access", deviceID: "test-device")
        let requests = fixture.requests
        XCTAssertEqual(try fields(requests[0]), ["grant_type": "refresh_token", "refresh_token": "test-refresh"])
        XCTAssertEqual(requests[0].url?.path, "/auth/v1/token")
        XCTAssertEqual(try fields(requests[1]), ["user_id": "test-user", "nickname": "昵称", "description": "简介"])
        XCTAssertEqual(requests[1].url?.path, "/auth/v1/user/basic/edit")
        XCTAssertEqual(requests[2].url?.path, "/auth/v1/user/signout")
        XCTAssertEqual(try fields(requests[2]), [:], "The signout endpoint does not accept a refresh_token field")
        XCTAssertTrue(requests.allSatisfy { $0.url?.query == nil })
    }

    func testCaptchaChallengeAndVerificationUseDedicatedEndpoints() async throws {
        let (api, fixture) = service([
            (200, #"{"data":"data:image/gif;base64,R0lG","type":"image","token":"test-image-token","expires_in":60}"#),
            (200, #"{"captcha_token":"test-captcha-token","expires_in":60}"#),
        ])
        let challenge = try await api.captcha(deviceID: "test-device")
        let verified = try await api.verifyCaptcha(token: challenge.token, text: "abc", deviceID: "test-device")
        XCTAssertEqual(verified, "test-captcha-token")
        XCTAssertEqual(fixture.requests.map { $0.url!.path }, ["/auth/v1/captcha/data", "/auth/v1/captcha/data/verify"])
        XCTAssertEqual(try fields(fixture.requests[1]), ["token": "test-image-token", "key": "abc"])
    }

    func testCaptchaRequiredAndRateLimitsAreNotMistakenForRevokedSessions() async throws {
        let (api, fixture) = service([
            (401, #"{"error":"captcha_required","error_description":"untrusted server detail"}"#),
            (429, #"{"error":"future_error"}"#),
            (401, #"{"error":"invalid_grant"}"#),
        ])
        for expected in [AccountError.captchaRequired, .rateLimited, .expiredSession] {
            do { _ = try await api.refresh("test-refresh", deviceID: "test-device"); XCTFail() }
            catch { XCTAssertEqual(error as? AccountError, expected) }
        }
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertFalse(AccountError.message(for: AccountError.captchaRequired).contains("untrusted"))
    }

    func testInvalidInputsAndExpiredChallengeDoNotSendARequest() async throws {
        let (api, fixture) = service([])
        do { _ = try await api.passwordSignIn(identifier: "", password: "test", deviceID: "test-device", captcha: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .missingIdentifier) }
        let challenge = VerificationChallenge(address: .email("native@example.invalid"), id: "test-verification",
                                              isExistingUser: true, expiresAt: .distantPast)
        do { _ = try await api.verify(challenge, code: "123456", deviceID: "test-device", captcha: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AccountError, .verificationExpired) }
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertThrowsError(try VerificationAddress.phoneInput("13800000000<script>"))
        XCTAssertThrowsError(try VerificationAddress.emailInput("name@example"))
        XCTAssertEqual(try VerificationAddress.passwordIdentifier("native-user"), "native-user")
    }

    private func fields(_ request: URLRequest) throws -> [String: String] {
        // URLProtocol may expose the body as a stream instead of Data.
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                collected.append(bytes, count: count)
            }
            data = collected
        } else { throw AccountError.invalidResponse }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func service(_ replies: [(Int, String)]) -> (CloudbaseAuthService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        fixtures.append(host)
        let fixture = AuthHTTPFixture(replies: replies)
        AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPProtocol.self]
        return (CloudbaseAuthService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
}

final class AuthHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [URLRequest] = []
    private var replies: [(Int, String)]
    let contentType: String
    init(replies: [(Int, String)], contentType: String = "application/json") { self.replies = replies; self.contentType = contentType }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
    func take(_ request: URLRequest) -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        received.append(request)
        return replies.isEmpty ? (500, "{}") : replies.removeFirst()
    }
}

final class AuthHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: AuthHTTPFixture] = [:]
    static func register(_ host: String, fixture: AuthHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[host] = fixture }
    static func unregister(_ host: String) { lock.lock(); defer { lock.unlock() }; fixtures[host] = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.url?.host ?? ""]
        Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let (status, body) = fixture.take(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                                            headerFields: ["Content-Type": fixture.contentType])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
