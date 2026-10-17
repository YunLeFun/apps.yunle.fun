import Foundation

protocol AccountAuthenticating: Sendable {
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse
    func user(accessToken: String, deviceID: String) async throws -> AccountUser
    func signOut(accessToken: String, deviceID: String) async throws
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws
    func captcha(deviceID: String) async throws -> CaptchaImage
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String
}

struct CloudbaseAuthService: AccountAuthenticating {
    static let gateway = URL(string: "https://yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com")!
    let session: URLSession
    let origin: URL

    init(session: URLSession? = nil, origin: URL = gateway) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: AuthRedirectPolicy(), delegateQueue: nil)
        }
    }

    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        let identifier = try VerificationAddress.passwordIdentifier(identifier)
        guard !password.isEmpty else { throw AccountError.missingPassword }
        return try await request("signin", fields: ["username": identifier, "password": password], deviceID: deviceID, captcha: captcha)
    }

    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge {
        var fields = address.requestFields
        fields["target"] = "ANY"
        let response: VerificationResponse = try await request("verification", fields: fields, deviceID: deviceID, captcha: captcha)
        guard !response.id.isEmpty, response.expiresIn > 0 else { throw AccountError.invalidResponse }
        return VerificationChallenge(address: address, id: response.id, isExistingUser: response.isUser == true,
                                     expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        guard challenge.expiresAt > Date() else { throw AccountError.verificationExpired }
        guard code.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw AccountError.invalidVerification }
        let result: VerificationToken = try await request("verification/verify", fields: [
            "verification_id": challenge.id, "verification_code": code,
        ], deviceID: deviceID, captcha: captcha)
        guard !result.token.isEmpty else { throw AccountError.invalidResponse }
        var fields = challenge.isExistingUser ? [:] : challenge.address.requestFields
        fields["verification_token"] = result.token
        return try await request(challenge.isExistingUser ? "signin" : "signup", fields: fields, deviceID: deviceID, captcha: captcha)
    }

    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        try await request("token", fields: ["grant_type": "refresh_token", "refresh_token": refreshToken], deviceID: deviceID)
    }

    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        try await request("user/me", method: "GET", accessToken: accessToken, deviceID: deviceID)
    }

    func signOut(accessToken: String, deviceID: String) async throws {
        _ = try await data("user/signout", fields: [:], accessToken: accessToken, deviceID: deviceID)
    }

    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws {
        _ = try await data("user/basic/edit", fields: ["user_id": userID, "nickname": name, "description": description],
                           accessToken: accessToken, deviceID: deviceID)
    }

    func captcha(deviceID: String) async throws -> CaptchaImage {
        try await request("captcha/data", fields: [:], deviceID: deviceID)
    }

    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String {
        let result: CaptchaToken = try await request("captcha/data/verify", fields: ["token": token, "key": text], deviceID: deviceID)
        guard !result.token.isEmpty else { throw AccountError.invalidResponse }
        return result.token
    }

    private func request<Response: Decodable>(_ path: String, method: String = "POST", fields: [String: String]? = nil,
                                               accessToken: String? = nil, deviceID: String, captcha: String? = nil) async throws -> Response {
        let data = try await data(path, method: method, fields: fields, accessToken: accessToken, deviceID: deviceID, captcha: captcha)
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountError.invalidResponse }
    }

    private func data(_ path: String, method: String = "POST", fields: [String: String]? = nil,
                      accessToken: String? = nil, deviceID: String, captcha: String? = nil) async throws -> Data {
        var request = URLRequest(url: origin.appendingPathComponent("auth/v1/\(path)"))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceID, forHTTPHeaderField: "x-device-id")
        if let fields {
            request.httpBody = try JSONEncoder().encode(fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let captcha { request.setValue(captcha, forHTTPHeaderField: "x-captcha-token") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(ServiceFailure.self, from: data)
            if path == "user/me", http.statusCode == 400,
               (body?.error == "failed_precondition" && body?.errorCode == 9 || body?.error == "user_not_found") {
                throw AccountError.expiredSession
            }
            throw Self.error(status: http.statusCode, code: body?.error)
        }
        return data
    }

    static func error(status: Int, code: String?) -> AccountError {
        switch code {
        case "invalid_grant", "invalid_token", "unauthenticated", "access_token_expired": return .expiredSession
        case "invalid_username_or_password", "user_not_found", "password_not_set": return .invalidCredentials
        case "captcha_required": return .captchaRequired
        case "invalid_captcha", "invalid_captcha_token": return .invalidCaptcha
        case "invalid_verification_code", "invalid_verification_token", "verification_expired": return .invalidVerification
        case "invalid_status", "user_disabled": return .blockedAccount
        default:
            if status == 429 { return .rateLimited }
            if status == 401 { return .expiredSession }
            return .unavailable
        }
    }

    private struct ServiceFailure: Decodable {
        let error: String?
        let errorCode: Int?
        enum CodingKeys: String, CodingKey { case error; case errorCode = "error_code" }
    }
    private struct VerificationResponse: Decodable {
        let id: String
        let expiresIn: Int
        let isUser: Bool?
        enum CodingKeys: String, CodingKey { case id = "verification_id", expiresIn = "expires_in", isUser = "is_user" }
    }
    private struct VerificationToken: Decodable {
        let token: String
        enum CodingKeys: String, CodingKey { case token = "verification_token" }
    }
    private struct CaptchaToken: Decodable {
        let token: String
        enum CodingKeys: String, CodingKey { case token = "captcha_token" }
    }
}

private final class AuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
