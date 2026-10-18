import Foundation

enum DiagnosticError: Error, Equatable, AccountRequestFailure {
    case invalidInput, invalidRange, emptyLogs, tooLarge, invalidResponse
    case unauthorized, forbidden, throttled, unavailable, outcomeUnknown
    case identityChanged, confirmationExpired, uploadInProgress, cancelled, storage

    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .invalidInput: return "请检查问题描述和日志内容后重新确认。"
        case .invalidRange: return "请选择最近七天内、不超过二十四小时的日志范围。"
        case .emptyLogs: return "所选时间内没有可上传的本 App 日志。"
        case .tooLarge: return "日志内容超过限制，请缩短时间范围后重新确认。"
        case .invalidResponse: return "上传回执未能确认，请先保留当前信息，避免立即重复上传。"
        case .unauthorized: return "登录状态已失效，请重新登录后重新确认。"
        case .forbidden: return "当前账号不能上传诊断日志，请使用正常注册的账号。"
        case .throttled: return "提交较频繁，请一分钟后再试。"
        case .unavailable: return "诊断服务暂时不可用，请稍后重新确认。"
        case .outcomeUnknown: return "上传结果尚未确认，服务器可能已收到。请勿立即重复上传。"
        case .identityChanged: return "账号已变化，请重新选择并确认日志。"
        case .confirmationExpired: return "本次确认已失效，请重新查看将上传的日志。"
        case .uploadInProgress: return "正在上传已确认的日志，请等待本次结果。"
        case .cancelled: return "已取消本次上传；再次提交前需要重新确认。"
        case .storage: return "本机未能保存支持编号，离开应用前请复制或分享。"
        }
    }
    static func safe(_ error: Error) -> DiagnosticError {
        if let error = error as? DiagnosticError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            return error.code == .cancelled ? .cancelled : .outcomeUnknown
        }
        if let error = error as? AccountError {
            switch error {
            case .sessionChanged: return .identityChanged
            case .signedOut, .expiredSession, .invalidCredentials: return .unauthorized
            case .blockedAccount: return .forbidden
            default: return .unavailable
            }
        }
        return .outcomeUnknown
    }
}

protocol DiagnosticServing: Sendable {
    func upload(_ payload: DiagnosticUploadPayload, identity: AuthorizedAccount) async throws -> DiagnosticUploadReceipt
}

struct DiagnosticService: DiagnosticServing {
    let session: URLSession
    let origin: URL
    private let now: @Sendable () -> Date

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.origin = origin; self.now = now
        // Preserve an injected protocol stack while enforcing the same privacy policy.
        let configuration = session?.configuration ?? URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration, delegate: DiagnosticRedirectPolicy(), delegateQueue: nil)
    }

    func upload(_ payload: DiagnosticUploadPayload, identity: AuthorizedAccount) async throws -> DiagnosticUploadReceipt {
        guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil, ["", "/"].contains(origin.path),
              !identity.userID.isEmpty, !identity.accessToken.isEmpty else { throw DiagnosticError.invalidInput }
        let started = now().timeIntervalSince1970 * 1000
        let frozen = try DiagnosticUploadRules.normalize(payload, now: started)
        let body = try DiagnosticUploadRules.encoder().encode(frozen)
        guard body.count <= DiagnosticUploadRules.maximumBodyBytes else { throw DiagnosticError.tooLarge }
        let url = origin.appendingPathComponent("api/diagnostics/logs")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch { throw DiagnosticError.safe(error) }
        let (data, response) = result
        // An HTML login page or oversized response must never trigger token refresh.
        guard let http = response as? HTTPURLResponse, http.url == url,
              http.mimeType?.lowercased() == "application/json",
              http.expectedContentLength <= Int64(DiagnosticUploadRules.maximumResponseBytes),
              data.count <= DiagnosticUploadRules.maximumResponseBytes else { throw DiagnosticError.invalidResponse }
        switch http.statusCode {
        case 401: throw DiagnosticError.unauthorized
        case 403: throw DiagnosticError.forbidden
        case 400: throw DiagnosticError.invalidInput
        case 413: throw DiagnosticError.tooLarge
        case 429: throw DiagnosticError.throttled
        case 200..<300: break
        case 500...599: throw DiagnosticError.unavailable
        default: throw DiagnosticError.invalidResponse
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.code == 0,
              let receipt = envelope.data else { throw DiagnosticError.invalidResponse }
        try DiagnosticUploadRules.validate(receipt, count: frozen.logs.count, now: now().timeIntervalSince1970 * 1000,
                                           started: started)
        return receipt
    }

    private struct Envelope: Decodable { let code: Int; let data: DiagnosticUploadReceipt? }
}

enum DiagnosticUploadRules {
    static let retention: Double = 7 * 24 * 60 * 60 * 1000
    static let clockSkew: Double = 5 * 60 * 1000
    static let maximumBytes = 256 * 1024
    // The API budget counts the description as raw UTF-8, not its JSON escapes.
    // Five hundred one-byte control characters alone add 2500 encoded bytes.
    static let maximumBodyBytes = maximumBytes + 4096
    static let maximumResponseBytes = 16 * 1024

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder
    }
    static func normalize(_ payload: DiagnosticUploadPayload, now: Double) throws -> DiagnosticUploadPayload {
        guard payload.startTime.isFinite, payload.endTime.isFinite else { throw DiagnosticError.invalidRange }
        let start = payload.startTime.rounded(.towardZero), end = payload.endTime.rounded(.towardZero)
        guard start <= end, end - start <= 86_400_999, start >= now - retention,
              end <= now + clockSkew else { throw DiagnosticError.invalidRange }
        guard !payload.logs.isEmpty else { throw DiagnosticError.emptyLogs }
        guard payload.logs.count <= 500 else { throw DiagnosticError.tooLarge }
        let description = payload.issueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard description.utf16.count <= 500 else { throw DiagnosticError.invalidInput }
        let logs = try payload.logs.map { entry -> DiagnosticLogEntry in
            guard entry.message.utf16.count <= 4000 else { throw DiagnosticError.tooLarge }
            guard entry.timestamp.isFinite else { throw DiagnosticError.invalidInput }
            let timestamp = entry.timestamp.rounded(.towardZero)
            guard timestamp >= start, timestamp <= end else { throw DiagnosticError.invalidRange }
            let message = DiagnosticText.redact(entry.message)
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiagnosticError.invalidInput }
            return DiagnosticLogEntry(level: entry.level, message: message, timestamp: timestamp)
        }
        let client = DiagnosticClientContext(
            appVersion: DiagnosticText.redact(payload.client.appVersion, limit: 50),
            buildNumber: DiagnosticText.redact(payload.client.buildNumber, limit: 50),
            platform: DiagnosticText.redact(payload.client.platform, limit: 20),
            route: DiagnosticText.redact(payload.client.route, limit: 200),
            timezone: DiagnosticText.redact(payload.client.timezone, limit: 100),
            userAgent: DiagnosticText.redact(payload.client.userAgent, limit: 500))
        let result = DiagnosticUploadPayload(startTime: start, endTime: end,
            issueDescription: DiagnosticText.redact(description, limit: 500).trimmingCharacters(in: .whitespacesAndNewlines),
            logs: logs, client: client)
        guard try sizeBytes(result) <= maximumBytes else { throw DiagnosticError.tooLarge }
        return result
    }
    static func sizeBytes(_ payload: DiagnosticUploadPayload) throws -> Int {
        try encoder().encode(payload.logs).count + encoder().encode(payload.client).count + payload.issueDescription.utf8.count
    }
    static func validate(_ receipt: DiagnosticUploadReceipt, count: Int? = nil, now: Double, started: Double? = nil) throws {
        guard receipt.supportCode.range(of: "^[A-Z0-9]{12}$", options: .regularExpression) != nil,
              receipt.uploadId.isEmpty || receipt.uploadId.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              (1...500).contains(receipt.logCount), count == nil || receipt.logCount == count,
              receipt.expiresAt.isFinite, receipt.expiresAt.rounded(.towardZero) == receipt.expiresAt,
              receipt.expiresAt > now, receipt.expiresAt <= now + retention + clockSkew,
              started == nil || receipt.expiresAt >= started! + retention - clockSkew else {
            throw DiagnosticError.invalidResponse
        }
    }
}

private final class DiagnosticRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
