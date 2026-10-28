import CryptoKit
import Foundation
import Security

protocol SupportCenterServing: Sendable {
    func connect(identity: AuthorizedAccount?, consent: Bool) async throws -> SupportAccess
    func disconnect(_ access: SupportAccess) async throws
    func board(cursor: String?) async throws -> SupportPage<SupportBoardItem>
    func dashboard(product: String?, cursor: String?, access: SupportAccess) async throws -> SupportDashboard
    func submit(product: String, category: String, description: String, screenshots: [FeedbackScreenshot], key: String,
                access: SupportAccess) async throws -> SupportFeedbackReceipt
}

struct SupportCenterService: SupportCenterServing {
    static let origin = SupportFeedbackClient.origin
    static let cookieName = SupportFeedbackClient.userCookieName
    static let guestCookieName = SupportFeedbackClient.guestCookieName
    let session: URLSession
    let authorization: HostAuthorizationServing

    init(session: URLSession? = nil, authorization: HostAuthorizationServing = HostAuthorizationService()) {
        self.authorization = authorization
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.httpCookieAcceptPolicy = .never
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration, delegate: SupportRedirectPolicy(), delegateQueue: nil)
        }
    }

    func connect(identity: AuthorizedAccount?, consent: Bool = false) async throws -> SupportAccess {
        guard let identity else {
            do {
                let access = try await SupportFeedbackClient(session: session).connectGuest()
                return SupportAccess(userID: nil, csrfToken: access.csrfToken, cookies: access.cookies)
            } catch { throw Self.feedbackError(error) }
        }
        let verifier = try randomValue(), nonce = try randomValue()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).supportBase64URL
        let request = try HostSsoRequest(sourceOrigin: Self.origin.absoluteString, parameters: [
            "clientId": "support-web", "redirectUri": Self.origin.absoluteString + "/",
            "nonce": nonce, "codeChallenge": challenge, "codeChallengeMethod": "S256", "scope": ["identity:bootstrap"],
        ])
        let code: HostSsoCode
        do {
            let policy = try await authorization.resolve(request)
            guard policy.applicationID == "support" else { throw SupportCenterError.invalidResponse }
            if policy.prompt != nil && !consent { throw SupportCenterError.consentRequired }
            try Task.checkCancellation()
            code = try await authorization.issue(request, identity: identity)
        } catch HostAuthorizationError.unauthorized { throw SupportCenterError.unauthorized }
        let (exchange, _): (Exchange, [HTTPCookie]) = try await requestURL(
            URL(string: "https://api.yunle.fun/sso-ticket")!, method: "POST", fields: [
                "action": "exchangeSsoCode", "clientId": "support-web", "redirectUri": request.redirectURI,
                "scope": "identity:bootstrap", "code": code.code, "nonce": nonce, "codeVerifier": verifier,
            ])
        guard exchange.ok, exchange.identityAssertion.count >= 64, exchange.identityAssertion.count <= 8192 else {
            throw SupportCenterError.invalidResponse
        }
        // The existing native credential already proves the same CloudBase UID.
        // Support verifies the signature, audience, nonce, UID, account status and phone admission.
        // Do not adopt the temporary CloudBase ticket or change the App's account session.
        let (connected, cookies): (Connected, [HTTPCookie]) = try await self.request("api/v1/session/exchange", method: "POST", fields: [
            "accessToken": identity.accessToken, "identityAssertion": exchange.identityAssertion, "nonce": nonce,
        ])
        guard connected.ok, connected.user.userId == identity.userID, !connected.csrfToken.isEmpty,
              cookies.contains(where: { $0.name == Self.cookieName && $0.isHTTPOnly }) else { throw SupportCenterError.invalidResponse }
        return SupportAccess(userID: identity.userID, csrfToken: connected.csrfToken, cookies: cookies)
    }

    func board(cursor: String?) async throws -> SupportPage<SupportBoardItem> {
        let (page, _): (SupportPage<SupportBoardItem>, [HTTPCookie]) = try await request("api/v1/feedback", query: ["cursor": cursor])
        guard page.items.count <= 100, Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ Self.identifier($0.id) && $0.voteCount >= 0 }) else { throw SupportCenterError.invalidResponse }
        return page
    }

    func disconnect(_ access: SupportAccess) async throws {
        guard access.userID != nil else { return }
        let (result, _): (Acknowledgement, [HTTPCookie]) = try await request("api/v1/session", method: "DELETE", access: access)
        guard result.ok else { throw SupportCenterError.invalidResponse }
    }

    func dashboard(product: String?, cursor: String?, access: SupportAccess) async throws -> SupportDashboard {
        guard access.userID != nil else { throw SupportCenterError.unauthorized }
        let (dashboard, _): (SupportDashboard, [HTTPCookie]) = try await request("api/internal/v1/dashboard",
            query: ["product": product, "privateCursor": cursor], access: access)
        guard dashboard.productIds.contains(dashboard.productId), dashboard.productIds.count <= 100,
              dashboard.privateFeedback.items.count <= 100, dashboard.feedback.items.count <= 100,
              Set(dashboard.privateFeedback.items.map(\.id)).count == dashboard.privateFeedback.items.count,
              dashboard.privateFeedback.items.allSatisfy({ Self.identifier($0.id) && $0.productId == dashboard.productId }),
              dashboard.privateFeedback.items.allSatisfy({ $0.ticketId.map(Self.identifier) ?? true }),
              dashboard.feedback.items.allSatisfy({ Self.identifier($0.id) && $0.productId == dashboard.productId })
        else { throw SupportCenterError.invalidResponse }
        return dashboard
    }

    func submit(product: String, category: String, description: String, screenshots: [FeedbackScreenshot] = [], key: String,
                access: SupportAccess) async throws -> SupportFeedbackReceipt {
        do {
            return try await SupportFeedbackClient(session: session).submit(
                SupportFeedbackSubmission(product: product, category: category, description: description, screenshots: screenshots),
                key: key, access: SupportFeedbackAccess(csrfToken: access.csrfToken, cookies: access.cookies))
        } catch { throw Self.feedbackError(error) }
    }

    private static func feedbackError(_ error: Error) -> Error {
        guard let failure = error as? SupportFeedbackError else { return error }
        switch failure {
        case .invalidResponse: return SupportCenterError.invalidResponse
        case .invalidInput: return SupportCenterError.invalidInput
        case .invalidScreenshot: return SupportCenterError.invalidScreenshot
        case .unavailable: return SupportCenterError.unavailable
        case .throttled: return SupportCenterError.throttled
        case .unauthorized: return SupportCenterError.unauthorized
        case .forbidden: return SupportCenterError.forbidden
        }
    }

    static func identifier(_ value: String) -> Bool { SupportFeedbackClient.identifier(value) }
    static func isSupportURL(_ url: URL) -> Bool {
        SupportFeedbackClient.isSupportURL(url)
    }
    static func pageURL(path: String) -> URL { origin.appendingPathComponent(path) }
    static func ticketURL(_ receipt: SupportFeedbackReceipt) -> URL? {
        SupportFeedbackClient.ticketURL(receipt)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", query: [String: String?] = [:],
                                      fields: [String: String]? = nil, access: SupportAccess? = nil, key: String? = nil) async throws -> (T, [HTTPCookie]) {
        var components = URLComponents(url: Self.pageURL(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return try await requestURL(components.url!, method: method, fields: fields, access: access, key: key)
    }

    private func requestURL<T: Decodable>(_ url: URL, method: String, fields: [String: String]? = nil,
                                         access: SupportAccess? = nil, key: String? = nil) async throws -> (T, [HTTPCookie]) {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        if let access {
            guard Self.isSupportURL(url) else { throw SupportCenterError.invalidInput }
            request.setValue(HTTPCookie.requestHeaderFields(with: access.cookies)["Cookie"], forHTTPHeaderField: "Cookie")
            if method != "GET" { request.setValue(access.csrfToken, forHTTPHeaderField: "x-csrf-token") }
        }
        if let key { request.setValue(key, forHTTPHeaderField: "idempotency-key") }
        if let fields {
            request.httpBody = try JSONEncoder().encode(fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SupportCenterError.invalidResponse }
        switch http.statusCode {
        case 401: throw SupportCenterError.unauthorized
        case 403: throw SupportCenterError.forbidden
        case 429: throw SupportCenterError.throttled
        case 200..<300: break
        default: throw SupportCenterError.unavailable
        }
        guard data.count <= 2 * 1024 * 1024, http.mimeType == "application/json",
              let value = try? JSONDecoder().decode(T.self, from: data) else { throw SupportCenterError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { if let name = key as? String, let value = value as? String { headers[name] = value } }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter {
            $0.domain == Self.origin.host && $0.path == "/" && $0.isSecure && $0.isHTTPOnly
                && [Self.cookieName, Self.guestCookieName].contains($0.name)
        }
        return (value, cookies)
    }

    private func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SupportCenterError.unavailable }
        return Data(bytes).supportBase64URL
    }
    private struct Exchange: Decodable { let ok: Bool; let identityAssertion: String }
    private struct Connected: Decodable {
        let ok: Bool; let user: User; let csrfToken: String
        struct User: Decodable { let userId: String }
    }
    private struct Acknowledgement: Decodable { let ok: Bool }
}

private extension Data {
    var supportBase64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
private final class SupportRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
