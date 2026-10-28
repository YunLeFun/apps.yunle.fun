import Foundation

/// Shared by the host and the extension, with no UIApplication or account-store dependency.
struct SupportFeedbackClient: SupportFeedbackSubmitting {
    #if DEBUG && YUNLE_FEEDBACK_LOCAL_VALIDATION && targetEnvironment(simulator)
    // Explicit local acceptance build only; this flag is absent from every shipped configuration.
    static let origin = URL(string: "https://127.0.0.1:18473")!
    #else
    static let origin = URL(string: "https://support.yunle.fun")!
    #endif
    static let guestCookieName = "__Host-ylf-support-guest"
    static let userCookieName = "__Host-ylf-support-session"
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.httpCookieAcceptPolicy = .never
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration, delegate: FeedbackRedirectPolicy(), delegateQueue: nil)
        }
    }

    func connectGuest() async throws -> SupportFeedbackAccess {
        struct Guest: Decodable { let kind: String; let csrfToken: String }
        let (guest, cookies): (Guest, [HTTPCookie]) = try await request("api/v1/feedback/guest", body: Data("{}".utf8))
        guard guest.kind == "guest", !guest.csrfToken.isEmpty, guest.csrfToken.utf8.count <= 1024,
              cookies.contains(where: { $0.name == Self.guestCookieName }) else { throw SupportFeedbackError.invalidResponse }
        return SupportFeedbackAccess(csrfToken: guest.csrfToken, cookies: cookies.filter { $0.name == Self.guestCookieName })
    }

    func submit(_ submission: SupportFeedbackSubmission, key: String, access: SupportFeedbackAccess) async throws -> SupportFeedbackReceipt {
        try submission.validate()
        guard key.range(of: #"^[A-Za-z0-9_-]{8,128}\z"#, options: .regularExpression) != nil else { throw SupportFeedbackError.invalidInput }
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        struct Result: Decodable { let receipt: SupportFeedbackReceipt }
        let (result, _): (Result, [HTTPCookie]) = try await request("api/v1/private-feedback", body: encoder.encode(submission), access: access, key: key)
        guard Self.identifier(result.receipt.id), result.receipt.productId == submission.productId,
              result.receipt.ticketId.map(Self.identifier) ?? true else { throw SupportFeedbackError.invalidResponse }
        return result.receipt
    }

    static func identifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil
    }

    static func isSupportURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == origin.host && (url.port ?? 443) == (origin.port ?? 443)
            && url.user == nil && url.password == nil
    }

    static func ticketURL(_ receipt: SupportFeedbackReceipt, requiringGuestAccess: Bool = false) -> URL? {
        guard let id = receipt.ticketId, identifier(id), let raw = receipt.ticketUrl, raw.utf8.count <= 8192,
              let url = URL(string: raw), isSupportURL(url), url.path == "/tickets/" + id, url.query == nil else { return nil }
        if requiringGuestAccess {
            guard let fragment = url.fragment, let components = URLComponents(string: "https://local.invalid/?" + fragment),
                  let items = components.queryItems, items.count == 1, items[0].name == "access",
                  let value = items[0].value, !value.isEmpty,
                  value.range(of: #"^[A-Za-z0-9._-]{1,8192}\z"#, options: .regularExpression) != nil else { return nil }
        }
        return url
    }

    private func request<T: Decodable>(_ path: String, body: Data, access: SupportFeedbackAccess? = nil,
                                      key: String? = nil) async throws -> (T, [HTTPCookie]) {
        try Task.checkCancellation()
        let url = Self.origin.appendingPathComponent(path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        if let access {
            request.setValue(HTTPCookie.requestHeaderFields(with: access.cookies)["Cookie"], forHTTPHeaderField: "Cookie")
            request.setValue(access.csrfToken, forHTTPHeaderField: "x-csrf-token")
        }
        if let key { request.setValue(key, forHTTPHeaderField: "idempotency-key") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SupportFeedbackError.invalidResponse }
        switch http.statusCode {
        case 401: throw SupportFeedbackError.unauthorized
        case 403: throw SupportFeedbackError.forbidden
        case 400: throw path == "api/v1/private-feedback" ? SupportFeedbackError.invalidScreenshot : SupportFeedbackError.invalidInput
        case 413: throw SupportFeedbackError.invalidScreenshot
        case 429: throw SupportFeedbackError.throttled
        case 200..<300: break
        default: throw SupportFeedbackError.unavailable
        }
        guard data.count <= 2 * 1024 * 1024, http.mimeType == "application/json",
              let result = try? JSONDecoder().decode(T.self, from: data) else { throw SupportFeedbackError.invalidResponse }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields { if let name = name as? String, let value = value as? String { headers[name] = value } }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter {
            $0.domain == Self.origin.host && $0.path == "/" && $0.isSecure && $0.isHTTPOnly
                && [Self.guestCookieName, Self.userCookieName].contains($0.name)
        }
        return (result, cookies)
    }
}

private final class FeedbackRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
