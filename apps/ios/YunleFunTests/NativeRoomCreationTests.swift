import CryptoKit
import SwiftUI
import Vision
import XCTest
@testable import YunleFun

final class NativeRoomCreationLiveTests: XCTestCase {
    func testExplicitProductionManagedAccountCanCreateAndRetryOnePublicRoom() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_NATIVE_CREATION_LIVE"] == "production", let path = env["YUNLEFUN_NATIVE_CREATION_ACCOUNT_FILE"] else {
            throw XCTSkip("Explicit production opt-in and one privately handed-off managed account are required")
        }
        struct Input: Decodable { let id: String; let environment: String; let username: String; let password: String }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.posixPermissions] as? Int == 0o600 else { return XCTFail("Account handoff must be private") }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard input.environment == "production", input.id == "production-play-m4-20261029-a" else { return XCTFail("Unexpected managed identity") }
        let auth = CloudbaseAuthService(), device = UUID().uuidString
        let token = try await auth.passwordSignIn(identifier: input.username, password: input.password, deviceID: device, captcha: nil)
        let identity = AuthorizedAccount(userID: token.subject, accessToken: token.accessToken)
        do {
            let key = UUID(), draft = NativeRoomCreationDraft(gameID: "gomoku", isPublic: true), service = NativeRoomCreationService()
            let room = try await service.create(draft, key: key, identity: identity, consent: true)
            let retried = try await service.create(draft, key: key, identity: identity, consent: true)
            XCTAssertEqual(room, retried, "A real retry must return the same room")
            // No WebSocket was opened: the test room must not appear as an online public room.
            let visible = try await NativePublicRoomService().rooms()
            XCTAssertFalse(visible.contains { $0.inviteCode == room.inviteCode })
            let receipt: [String: Any] = ["accountID": input.id, "environment": input.environment,
                "inviteCode": room.inviteCode, "sameRoomOnRetry": room == retried, "onlineConnectionOpened": false]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt), uniformTypeIdentifier: "public.json")
            attachment.name = "native-public-room-live-creation"; attachment.lifetime = .keepAlways; add(attachment)
        } catch {
            try? await auth.signOut(accessToken: token.accessToken, deviceID: device)
            throw error
        }
        try await auth.signOut(accessToken: token.accessToken, deviceID: device)
    }
}

final class NativeRoomCreationServiceTests: XCTestCase {
    override func tearDown() { CreationHTTPProtocol.fixture = nil; super.tearDown() }

    func testSSOAndCreationUseRegisteredAudienceScopedCookieAndPublicPayload() async throws {
        let fixture = CreationHTTPFixture(), host = CreationHost()
        let service = makeService(fixture, host: host), key = UUID()
        let room = try await service.create(.init(gameID: "gomoku", isPublic: true), key: key,
            identity: .init(userID: "create-user", accessToken: "synthetic-access"), consent: false)
        XCTAssertEqual(room.inviteCode, "ABC234")
        let requests = fixture.requests
        XCTAssertEqual(requests.prefix(3).compactMap(\.url?.absoluteString), [
            "https://api.yunle.fun/sso-ticket", "https://api.play.yunle.fun/v1/session/exchange", "https://api.play.yunle.fun/v1/rooms"])
        let exchange = try body(requests[0]), hostRequest = await host.request
        let resolved = try XCTUnwrap(hostRequest)
        let verifier = try XCTUnwrap(exchange["codeVerifier"] as? String)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, resolved.challenge)
        XCTAssertEqual(resolved.clientID, "play-web"); XCTAssertEqual(resolved.redirectURI, "https://play.yunle.fun/")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try body(requests[1])["accessToken"] as? String, "synthetic-access")
        let created = try body(requests[2])
        XCTAssertEqual(created["visibility"] as? String, "public"); XCTAssertEqual(created["roomCapacity"] as? Int, 4)
        XCTAssertEqual((created["game"] as? [String: Any])?["rulesetId"] as? String, "freestyle-15")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString.lowercased())
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Cookie"), "__Host-ylf_play_session=synthetic-session")
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Origin"), "https://play.yunle.fun")
        XCTAssertFalse(String(data: requests[2].httpBody!, encoding: .utf8)!.contains("synthetic-access"))
    }

    func testPrivateDefaultAndChooseLaterPayloadAndUnsupportedGameRejection() throws {
        let data = try NativeRoomCreationDraft(gameID: nil).payload()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["visibility"] as? String, "private"); XCTAssertTrue(body["game"] is NSNull)
        XCTAssertThrowsError(try NativeRoomCreationDraft(gameID: "paper-star").payload())
    }

    func testConsentAndIdentityChangeStopBeforeRoomWrite() async throws {
        let fixture = CreationHTTPFixture(), host = CreationHost(consent: true)
        do {
            _ = try await makeService(fixture, host: host).create(.init(gameID: nil), key: UUID(),
                identity: .init(userID: "create-user", accessToken: "synthetic-access"), consent: false)
            XCTFail("Requires explicit consent")
        } catch { XCTAssertEqual(error as? NativeRoomCreationError, .consentRequired) }
        XCTAssertTrue(fixture.requests.isEmpty)
        do {
            _ = try await makeService(fixture).create(.init(gameID: nil), key: UUID(),
                identity: .init(userID: "create-user", accessToken: "synthetic-access"), consent: false, isCurrent: { false })
            XCTFail("Changed identity cannot create")
        } catch { XCTAssertEqual(error as? NativeRoomCreationError, .identityChanged) }
        XCTAssertFalse(fixture.requests.contains { $0.url?.path == "/v1/rooms" })
    }

    func testWrongIdentityHTMLAndMalformedRoomAreRejected() async throws {
        for mode in ["wrong-user", "html", "bad-code"] {
            let fixture = CreationHTTPFixture(mode: mode)
            do {
                _ = try await makeService(fixture).create(.init(gameID: nil), key: UUID(),
                    identity: .init(userID: "create-user", accessToken: "synthetic-access"), consent: false)
                XCTFail(mode)
            } catch { }
            if mode != "bad-code" { XCTAssertFalse(fixture.requests.contains { $0.url?.path == "/v1/rooms" }) }
        }
    }

    private func makeService(_ fixture: CreationHTTPFixture, host: CreationHost = CreationHost()) -> NativeRoomCreationService {
        CreationHTTPProtocol.fixture = fixture
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CreationHTTPProtocol.self]; config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        return NativeRoomCreationService(session: URLSession(configuration: config), authorization: host)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

@MainActor
final class NativeRoomCreationStoreTests: XCTestCase {
    func testUnconfirmedCreationRestoresOriginalKeyAndVisibilityAcrossReopening() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), accounts = CreationAccounts()
        defer { for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) } }
        let service = CreationStoreService(failFirst: true)
        let first = NativeRoomCreationStore(accounts: accounts, service: service, defaults: defaults)
        let publicDraft = NativeRoomCreationDraft(gameID: "gomoku", isPublic: true)
        let failed = await first.create(publicDraft)
        XCTAssertNil(failed); XCTAssertNotNil(first.error)
        let restored = NativeRoomCreationStore(accounts: accounts, service: service, defaults: defaults)
        let room = await restored.create(.init(gameID: nil, isPublic: false))
        XCTAssertEqual(room?.inviteCode, "ABC234")
        let calls = await service.calls
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertEqual(calls[1].draft, publicDraft)
        let receipt = NativeRoomCreationStore(accounts: accounts, service: service, defaults: defaults)
        let reopened = await receipt.create(publicDraft)
        XCTAssertEqual(reopened?.inviteCode, "ABC234")
        let afterReopen = await service.calls.count
        XCTAssertEqual(afterReopen, 2, "Opening a saved receipt must not POST another room")
        receipt.startAnother()
        XCTAssertNil(receipt.operation)
    }

    func testAccountSwitchAndABARejectLateCreationAndKeepJournalScoped() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name)), accounts = CreationAccounts()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = CreationStoreService(block: true)
        let model = NativeRoomCreationStore(accounts: accounts, service: service, defaults: defaults)
        let pending = Task { await model.create(.init(gameID: nil, isPublic: true)) }
        await service.waitForStart()
        accounts.select("another-user")
        let other = NativeRoomCreationStore(accounts: accounts, service: service, defaults: defaults)
        XCTAssertNil(other.operation)
        accounts.select("create-user")
        await service.release()
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertNil(model.operation?.inviteCode)
        XCTAssertFalse(model.isCreating)
    }

    func testProductionFormRendersPublicSettingWithoutCreatingARoom() async throws {
        let accounts = AccountStore(), service = CreationStoreService()
        let view = NativeRoomCreationView(accounts: accounts, games: [], gameID: nil, service: service, onCreated: { _ in XCTFail() })
        let controller = UIHostingController(rootView: view)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let scene = try XCTUnwrap(previous?.windowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 500_000_000)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "native-room-creation-private-default"; attachment.lifetime = .keepAlways; add(attachment)
        let ocr = VNRecognizeTextRequest(); ocr.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([ocr])
        let text = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("公开房间"), text)
        XCTAssertTrue(text.contains("创建并进入房间"), text)
        let calls = await service.calls.count
        XCTAssertEqual(calls, 0, "Rendering the form must not create a production room")
    }
}

private actor CreationHost: HostAuthorizationServing {
    let consent: Bool
    var request: HostSsoRequest?
    init(consent: Bool = false) { self.consent = consent }
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        self.request = request
        var presentation: [String: Any] = ["appId": "play", "applicationName": "云乐坊间", "applicationOrigin": request.sourceOrigin,
            "permissionDescription": "账号标识、昵称和头像", "consent": consent ? "explicit" : "trusted"]
        if consent { presentation["prompt"] = "consent" }
        return try HostSsoPolicy(response: ["ok": true, "issuer": HostSsoPolicy.issuer, "policyVersion": "fixture",
            "registrationFingerprint": String(repeating: "a", count: 64), "request": request.protocolFields, "presentation": presentation], request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        try HostSsoCode(response: ["ok": true, "code": String(repeating: "c", count: 43)])
    }
}

private final class CreationHTTPFixture: @unchecked Sendable {
    let mode: String
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(mode: String = "valid") { self.mode = mode }
    func receive(_ request: URLRequest) -> ([String: Any], [String: String]) {
        lock.lock(); defer { lock.unlock() }; recorded.append(request)
        var headers = ["Content-Type": mode == "html" ? "text/html" : "application/json"]
        switch request.url!.path {
        case "/sso-ticket": return (["ok": true, "identityAssertion": String(repeating: "a", count: 64)], headers)
        case "/v1/session/exchange":
            headers["Set-Cookie"] = "__Host-ylf_play_session=synthetic-session; Path=/; Secure; HttpOnly; SameSite=Lax"
            return (["ok": true, "user": ["userId": mode == "wrong-user" ? "other" : "create-user"]], headers)
        case "/v1/rooms": return (["ok": true, "room": ["inviteCode": mode == "bad-code" ? "bad" : "ABC234", "roomCapacity": 4]], headers)
        default: return (["ok": true], headers)
        }
    }
}

private final class CreationHTTPProtocol: URLProtocol {
    static var fixture: CreationHTTPFixture?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            stream.open(); defer { stream.close() }; var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
            recorded.httpBody = data
        }
        let (body, headers) = fixture.receive(recorded)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor private final class CreationAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser? = AccountUser(id: "create-user")
    var identityGeneration = UUID()
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount { .init(userID: user!.id, accessToken: "synthetic-access") }
    func select(_ uid: String) { user = AccountUser(id: uid); identityGeneration = UUID() }
}

private actor CreationStoreService: NativeRoomCreating {
    struct Call { let key: UUID; let draft: NativeRoomCreationDraft }
    var calls: [Call] = []
    private var failFirst: Bool
    private var block: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    init(failFirst: Bool = false, block: Bool = false) { self.failFirst = failFirst; self.block = block }
    func create(_ draft: NativeRoomCreationDraft, key: UUID, identity: AuthorizedAccount, consent: Bool,
                isCurrent: @escaping @Sendable () async -> Bool) async throws -> NativeGameRoomIntent {
        calls.append(.init(key: key, draft: draft))
        if block { await withCheckedContinuation { waiter = $0 } }
        guard await isCurrent() else { throw NativeRoomCreationError.identityChanged }
        if failFirst { failFirst = false; throw URLError(.timedOut) }
        return try NativeGameRoomIntent(input: "ABC234")
    }
    func waitForStart() async { while calls.isEmpty { await Task.yield() } }
    func release() { block = false; waiter?.resume(); waiter = nil }
}
