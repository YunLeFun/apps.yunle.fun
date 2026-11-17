import CryptoKit
import Foundation
import Security

protocol NativeRoomCreating: Sendable {
    func create(_ draft: NativeRoomCreationDraft, key: UUID, identity: AuthorizedAccount, consent: Bool,
                isCurrent: @escaping @Sendable () async -> Bool) async throws -> NativeGameRoomIntent
}

/// Reuses the registered Play SSO contract. App credentials never enter a URL,
/// browser cookie store, or the room creation journal.
struct NativeRoomCreationService: NativeRoomCreating {
    static let origin = URL(string: "https://play.yunle.fun")!
    static let api = URL(string: "https://api.play.yunle.fun")!
    static let exchange = URL(string: "https://api.yunle.fun/sso-ticket")!
    private let session: URLSession
    private let authorization: HostAuthorizationServing

    init(session: URLSession? = nil, authorization: HostAuthorizationServing = HostAuthorizationService()) {
        self.authorization = authorization
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.httpCookieAcceptPolicy = .never
            config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: RoomCreationNoRedirects(), delegateQueue: nil)
        }
    }

    func create(_ draft: NativeRoomCreationDraft, key: UUID, identity: AuthorizedAccount, consent: Bool,
                isCurrent: @escaping @Sendable () async -> Bool = { true }) async throws -> NativeGameRoomIntent {
        let payload = try draft.payload()
        let verifier = try random(), nonce = try random()
        let challenge = encode(Data(SHA256.hash(data: Data(verifier.utf8))))
        let request = try HostSsoRequest(sourceOrigin: Self.origin.absoluteString, parameters: [
            "clientId": "play-web", "redirectUri": Self.origin.absoluteString + "/", "nonce": nonce,
            "codeChallenge": challenge, "codeChallengeMethod": "S256", "scope": ["identity:bootstrap"],
        ])
        let code: HostSsoCode
        do {
            let policy = try await authorization.resolve(request)
            guard policy.applicationID == "play" else { throw NativeRoomCreationError.invalidResponse }
            if policy.prompt != nil && !consent { throw NativeRoomCreationError.consentRequired }
            try Task.checkCancellation()
            code = try await authorization.issue(request, identity: identity)
        } catch HostAuthorizationError.unauthorized { throw NativeRoomCreationError.unauthorized }
        struct Exchange: Decodable { let ok: Bool; let identityAssertion: String }
        let exchange: (Exchange, HTTPURLResponse) = try await send(Self.exchange, fields: [
            "action": "exchangeSsoCode", "clientId": "play-web", "redirectUri": request.redirectURI,
            "scope": "identity:bootstrap", "code": code.code, "nonce": nonce, "codeVerifier": verifier,
        ])
        guard exchange.0.ok, (64...8192).contains(exchange.0.identityAssertion.count) else { throw NativeRoomCreationError.invalidResponse }
        struct Connected: Decodable { struct User: Decodable { let userId: String }; let ok: Bool; let user: User }
        let connected: (Connected, HTTPURLResponse) = try await send(Self.api.appendingPathComponent("v1/session/exchange"), fields: [
            "accessToken": identity.accessToken, "identityAssertion": exchange.0.identityAssertion, "nonce": nonce,
        ])
        let headers = connected.1.allHeaderFields.reduce(into: [String: String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: Self.api).filter {
            $0.name == "__Host-ylf_play_session" && $0.domain == Self.api.host && $0.path == "/" && $0.isSecure && $0.isHTTPOnly
        }
        guard connected.0.ok, connected.0.user.userId == identity.userID, cookies.count == 1 else {
            throw NativeRoomCreationError.invalidResponse
        }
        let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]!
        // This temporary API session is separate from the App and game WebViews.
        defer { Task { let _: (Acknowledgement, HTTPURLResponse)? = try? await send(Self.api.appendingPathComponent("v1/session"), method: "DELETE", cookie: cookie) } }
        guard !Task.isCancelled, await isCurrent() else { throw NativeRoomCreationError.identityChanged }
        struct Created: Decodable {
            struct Room: Decodable { let inviteCode: String; let roomCapacity: Int }
            let ok: Bool; let room: Room
        }
        let created: (Created, HTTPURLResponse) = try await send(Self.api.appendingPathComponent("v1/rooms"), body: payload, cookie: cookie, key: key)
        guard created.0.ok, created.0.room.roomCapacity == 4 else { throw NativeRoomCreationError.invalidResponse }
        let room = try NativeGameRoomIntent(input: created.0.room.inviteCode)
        guard room.inviteCode == created.0.room.inviteCode else { throw NativeRoomCreationError.invalidResponse }
        return room
    }

    private struct Acknowledgement: Decodable { let ok: Bool }
    private func send<T: Decodable>(_ url: URL, method: String = "POST", fields: [String: String]? = nil,
                                    body: Data? = nil, cookie: String? = nil, key: UUID? = nil) async throws -> (T, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.httpBody = try fields.map { try JSONEncoder().encode($0) } ?? body
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let key { request.setValue(key.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url, data.count <= 1_048_576,
              http.mimeType?.lowercased() == "application/json" else { throw NativeRoomCreationError.invalidResponse }
        switch http.statusCode {
        case 401: throw NativeRoomCreationError.unauthorized
        case 403: throw NativeRoomCreationError.forbidden
        case 200..<300: break
        default: throw NativeRoomCreationError.unavailable
        }
        return (try JSONDecoder().decode(T.self, from: data), http)
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw NativeRoomCreationError.unavailable }
        return encode(Data(bytes))
    }
    private func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private final class RoomCreationNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
