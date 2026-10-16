import Foundation

struct AccountUser: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String?
    var username: String?
    var email: String?
    var phoneNumber: String?
    var picture: String?
    var description: String?
    var status: String?
    var isAnonymous: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "sub"
        case name, username, email, picture, status
        case phoneNumber = "phone_number"
        case description = "user_desc"
        case isAnonymous = "is_anonymous"
    }

    var displayName: String { name?.nilIfEmpty ?? username?.nilIfEmpty ?? "云乐坊用户" }
    var detail: String {
        if let username = username?.nilIfEmpty { return "@\(username)" }
        if let phone = phoneNumber?.nilIfEmpty {
            let digits = phone.filter(\.isNumber)
            return digits.count >= 7 ? "\(digits.prefix(3))••••\(digits.suffix(4))" : "手机号账号"
        }
        if let email = email?.nilIfEmpty, let at = email.firstIndex(of: "@") {
            return "\(email.prefix(1))•••\(email[at...])"
        }
        return "云乐坊账号"
    }

    var isUsable: Bool { !id.isEmpty && isAnonymous != true && status != "BLOCKED" }
}

struct AuthTokenResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let subject: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token"
        case expiresIn = "expires_in", subject = "sub"
    }

    func credential(at now: Date) throws -> AccountCredential {
        guard !accessToken.isEmpty, !refreshToken.isEmpty, !subject.isEmpty, expiresIn > 0 else {
            throw AccountError.invalidResponse
        }
        return AccountCredential(accessToken: accessToken, refreshToken: refreshToken,
                                 expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)))
    }
}

struct AccountCredential: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

struct SavedAccount: Codable, Equatable, Sendable {
    var user: AccountUser
    var credential: AccountCredential
}

struct AccountVaultState: Codable, Equatable, Sendable {
    var version = 1
    var deviceID = UUID().uuidString
    var accounts: [SavedAccount] = []
    var activeID: String?
}

struct AccountOverview: Equatable, Sendable {
    var revision = 0
    var users: [AccountUser] = []
    var activeID: String?
    var activeUser: AccountUser? { users.first { $0.id == activeID } }
}

struct AuthorizedAccount: Sendable {
    let userID: String
    let accessToken: String
}

enum VerificationAddress: Equatable, Sendable {
    case phone(String)
    case email(String)

    static func phoneInput(_ input: String) throws -> VerificationAddress {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = trimmed.filter(\.isNumber)
        if digits.hasPrefix("86"), digits.count == 13 { digits.removeFirst(2) }
        guard digits.count == 11, digits.first == "1",
              trimmed.allSatisfy({ $0.isNumber || "+ -()".contains($0) }) else {
            throw AccountError.invalidPhone
        }
        return .phone("+86 \(digits)")
    }

    static func emailInput(_ input: String) throws -> VerificationAddress {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !value.contains(where: \.isWhitespace) else { throw AccountError.invalidEmail }
        return .email(value)
    }

    var requestFields: [String: String] {
        switch self { case .phone(let number): return ["phone_number": number]; case .email(let email): return ["email": email] }
    }

    static func passwordIdentifier(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AccountError.missingIdentifier }
        if value.contains("@") {
            guard case .email(let email) = try emailInput(value) else { throw AccountError.invalidEmail }
            return email
        }
        let digits = value.filter(\.isNumber)
        if value.hasPrefix("+86") || (digits.count == 11 && digits.count == value.count) {
            guard case .phone(let number) = try phoneInput(value) else { throw AccountError.invalidPhone }
            return number
        }
        return value
    }
}

struct VerificationChallenge: Sendable {
    let address: VerificationAddress
    let id: String
    let isExistingUser: Bool
    let expiresAt: Date
}

struct CaptchaImage: Decodable, Sendable {
    let data: String
    let type: String
    let token: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey { case data, type, token; case expiresIn = "expires_in" }
}

enum AccountError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse, sessionChanged, signedOut, expiredSession, blockedAccount
    case invalidCredentials, invalidVerification, captchaRequired, invalidCaptcha, rateLimited
    case unavailable, invalidPhone, invalidEmail, missingIdentifier, missingPassword
    case verificationExpired, storage, unsupportedVault

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "账号服务暂时无法使用，请稍后重试。"
        case .sessionChanged: return "账号已发生变化，请重新操作。"
        case .signedOut: return "请先登录云乐坊账号。"
        case .expiredSession: return "登录已过期，请重新登录。"
        case .blockedAccount: return "当前账号暂时无法登录，请联系支持。"
        case .invalidCredentials: return "账号或密码不正确，请检查后重试。"
        case .invalidVerification: return "验证码不正确或已过期，请重新获取。"
        case .captchaRequired: return "请先完成图片验证。"
        case .invalidCaptcha: return "图片验证码不正确，请重试。"
        case .rateLimited: return "操作有些频繁，请稍后再试。"
        case .unavailable: return "暂时无法连接账号服务，请稍后重试。"
        case .invalidPhone: return "请输入正确的中国大陆手机号。"
        case .invalidEmail: return "请输入正确的邮箱地址。"
        case .missingIdentifier: return "请输入用户名、邮箱或手机号。"
        case .missingPassword: return "请输入密码。"
        case .verificationExpired: return "验证码已过期，请重新获取。"
        case .storage: return "无法安全保存账号，请解锁设备后重试。"
        case .unsupportedVault: return "本机账号数据暂时无法读取，原有数据已保留。"
        }
    }

    static func message(for error: Error) -> String {
        if let known = error as? AccountError { return known.errorDescription ?? "操作失败，请重试。" }
        if error is URLError { return "网络暂时无法连接，请检查网络后重试。" }
        return "操作未能完成，请稍后重试。"
    }
}
