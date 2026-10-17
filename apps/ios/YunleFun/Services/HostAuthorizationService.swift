import Foundation

enum HostAuthorizationError: Error, Equatable {
    case invalidRequest, invalidResponse, unauthorized, denied, unavailable, expired
    var code: String {
        switch self {
        case .invalidRequest: return "HOST_AUTH_INVALID_REQUEST"
        case .denied: return "HOST_AUTH_DENIED"
        default: return "HOST_AUTH_FAILED"
        }
    }
}

/// Contains protocol facts only. Presentation metadata is never taken from a page.
struct HostSsoRequest: Sendable {
    let clientID: String
    let sourceOrigin: String
    let redirectURI: String
    let nonce: String
    let challenge: String
    let prompt: String?
    let acquisitionJSON: String?

    init(sourceOrigin: String, parameters: [String: Any]) throws {
        guard Self.origin(sourceOrigin) == sourceOrigin,
              let client = parameters["clientId"] as? String, Self.matches(client, "^[a-z0-9][a-z0-9-]{1,127}$"),
              let redirect = parameters["redirectUri"] as? String, Self.httpsURL(redirect) != nil,
              Self.originOfURL(redirect) == sourceOrigin,
              let nonce = parameters["nonce"] as? String, Self.matches(nonce, "^[A-Za-z0-9_-]{32,128}$"),
              let challenge = parameters["codeChallenge"] as? String, Self.matches(challenge, "^[A-Za-z0-9_-]{43}$"),
              parameters["codeChallengeMethod"] as? String == "S256",
              parameters["scope"] as? [String] == ["identity:bootstrap"],
              parameters["prompt"] == nil || ["consent", "select_account"].contains(parameters["prompt"] as? String ?? "")
        else { throw HostAuthorizationError.invalidRequest }
        clientID = client
        self.sourceOrigin = sourceOrigin
        redirectURI = redirect
        self.nonce = nonce
        self.challenge = challenge
        prompt = parameters["prompt"] as? String
        acquisitionJSON = NativeSsoProtocol.readAcquisitionJSON(parameters["acquisition"])
    }

    var protocolFields: [String: Any] {
        var fields: [String: Any] = [
            "mode": "redirect", "clientId": clientID, "targetOrigin": sourceOrigin,
            "returnUrl": redirectURI, "scope": "identity:bootstrap", "nonce": nonce,
            "codeChallenge": challenge, "codeChallengeMethod": "S256",
        ]
        if let data = acquisitionJSON?.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) { fields["acquisition"] = value }
        return fields
    }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return false }
        return range.lowerBound == value.startIndex && range.upperBound == value.endIndex
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, String(cString: number.objCType) == "c" else { return nil }
        return number.boolValue
    }
    static func httpsURL(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: { $0.value <= 32 || (127...159).contains($0.value) }),
              let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, host == host.lowercased(), !host.isEmpty, !host.hasSuffix("."),
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.port != 443,
              parts.percentEncodedPath.hasPrefix("/"),
              let url = parts.url, url.absoluteString == value, url.standardized.absoluteString == value
        else { return nil }
        return url
    }
    static func origin(_ value: String) -> String? {
        guard let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, host == host.lowercased(), !host.isEmpty, !host.hasSuffix("."),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty, parts.port != 443,
              parts.url?.absoluteString == value,
              !value.unicodeScalars.contains(where: { $0.value <= 32 || (127...159).contains($0.value) })
        else { return nil }
        return value
    }
    private static func originOfURL(_ value: String) -> String? {
        guard var parts = URLComponents(string: value) else { return nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        return parts.string
    }
}

struct HostSsoPolicy: Sendable {
    static let issuer = "https://www.yunle.fun"
    let applicationID: String
    let applicationName: String
    let applicationOrigin: String
    let applicationIconURL: String?
    let permissionDescription: String
    let prompt: String?
    let version: String
    let registrationFingerprint: String

    init(response: [String: Any], request: HostSsoRequest) throws {
        let body = response["result"] as? [String: Any] ?? response
        if HostSsoRequest.boolean(body["ok"]) == false { throw HostAuthorizationError.invalidRequest }
        guard HostSsoRequest.boolean(body["ok"]) == true, body["issuer"] as? String == Self.issuer,
              let version = body["policyVersion"] as? String, !version.isEmpty, version.utf16.count <= 128,
              let fingerprint = body["registrationFingerprint"] as? String,
              HostSsoRequest.matches(fingerprint, "^[a-f0-9]{64}$"),
              let echo = body["request"] as? [String: Any],
              let presentation = body["presentation"] as? [String: Any],
              let appID = presentation["appId"] as? String,
              HostSsoRequest.matches(appID, "^[a-z0-9][a-z0-9-]{0,127}$"),
              let name = presentation["applicationName"] as? String,
              !name.isEmpty, name.utf16.count <= 80, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              presentation["applicationOrigin"] as? String == request.sourceOrigin,
              presentation["permissionDescription"] as? String == "账号标识、昵称和头像",
              let consent = presentation["consent"] as? String, ["explicit", "trusted"].contains(consent)
        else { throw HostAuthorizationError.invalidResponse }
        for (key, expected) in request.protocolFields where key != "acquisition" {
            guard echo[key] as? String == expected as? String else { throw HostAuthorizationError.invalidResponse }
        }
        let prompt = presentation["prompt"] as? String
        guard presentation["prompt"] == nil || ["consent", "select_account"].contains(prompt ?? ""),
              request.prompt.map({ prompt == $0 }) ?? (prompt == nil || prompt == "consent"),
              consent != "explicit" || prompt == "consent" || prompt == "select_account"
        else { throw HostAuthorizationError.invalidResponse }
        if let icon = presentation["applicationIconUrl"] {
            guard let value = icon as? String, HostSsoRequest.httpsURL(value) != nil else {
                throw HostAuthorizationError.invalidResponse
            }
        }
        applicationID = appID; applicationName = name; applicationOrigin = request.sourceOrigin
        applicationIconURL = presentation["applicationIconUrl"] as? String
        permissionDescription = "账号标识、昵称和头像"
        self.prompt = prompt; self.version = version; registrationFingerprint = fingerprint
    }
}

struct HostSsoCode: Sendable {
    let code: String
    let expiresAt: Double?
    init(response: [String: Any]) throws {
        let body = response["result"] as? [String: Any] ?? response
        guard HostSsoRequest.boolean(body["ok"]) == true, let code = body["code"] as? String,
              HostSsoRequest.matches(code, "^[A-Za-z0-9_-]{43}$") else { throw HostAuthorizationError.invalidResponse }
        var expires: Double?
        if let raw = body["expiresAt"] {
            guard let number = raw as? NSNumber, String(cString: number.objCType) != "c",
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue <= 9_007_199_254_740_991,
                  number.doubleValue.rounded() == number.doubleValue else { throw HostAuthorizationError.invalidResponse }
            expires = number.doubleValue
        }
        self.code = code; expiresAt = expires
    }
    var pageResult: [String: Any] {
        var result: [String: Any] = ["ok": true, "code": code, "issuer": HostSsoPolicy.issuer]
        if let expiresAt { result["expiresAt"] = expiresAt }
        return result
    }
}

protocol HostAuthorizationServing: Sendable {
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode
}

struct HostAuthorizationService: HostAuthorizationServing {
    let session: URLSession
    let resolver: URL
    let gateway: URL
    init(session: URLSession? = nil,
         resolver: URL = URL(string: "https://apps.yunle.fun/api/auth/sso/resolve")!,
         gateway: URL = CloudbaseAuthService.gateway) {
        self.resolver = resolver; self.gateway = gateway
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: config, delegate: HostSsoRedirectPolicy(), delegateQueue: nil)
        }
    }
    func resolve(_ request: HostSsoRequest) async throws -> HostSsoPolicy {
        var fields = request.protocolFields
        if let prompt = request.prompt { fields["prompt"] = prompt }
        let result = try await send(resolver, fields: fields, token: nil)
        return try HostSsoPolicy(response: result, request: request)
    }
    func issue(_ request: HostSsoRequest, identity: AuthorizedAccount) async throws -> HostSsoCode {
        var fields = request.protocolFields
        fields["action"] = "issueSsoCode"
        // Official CloudBase Functions OpenAPI, not a guessed HTTP function URL.
        let result = try await send(gateway.appendingPathComponent("v1/functions/sso-ticket"),
                                    fields: fields, token: identity.accessToken)
        return try HostSsoCode(response: result)
    }
    private func send(_ url: URL, fields: [String: Any], token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HostAuthorizationError.invalidResponse }
        if http.statusCode == 401 { throw HostAuthorizationError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw HostAuthorizationError.unavailable }
        guard data.count <= 128 * 1024,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HostAuthorizationError.invalidResponse
        }
        return result
    }
}

private final class HostSsoRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
