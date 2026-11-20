import Foundation

struct TeamSignupSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let signupId: String
    let title: String
    let capacity: Int
    let memberCount: Int
    let joined: Bool
    let revision: Int

    func validate(for id: String) throws {
        guard schemaVersion == 1, signupId == id, TeamSignupCommand.validTitle(title),
              (2...16).contains(capacity), (0...capacity).contains(memberCount),
              !joined || memberCount > 0, (1...9_007_199_254_740_991).contains(revision)
        else { throw TeamSignupError.unavailable }
    }
}

enum TeamSignupCommand: Equatable {
    static let createPrompt = "创建组队报名"
    static let openPrompt = "打开组队报名"
    case create(title: String, capacity: Int)
    case open(String)

    static func parse(_ prompt: String) throws -> Self? {
        if prompt == createPrompt { return .create(title: "组队报名", capacity: 4) }
        if prompt.hasPrefix(createPrompt + " ") {
            let parts = prompt.dropFirst(createPrompt.count).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let capacity = Int(parts[0]), (2...16).contains(capacity),
                  validTitle(String(parts[1])) else { throw TeamSignupError.invalidCommand }
            return .create(title: String(parts[1]), capacity: capacity)
        }
        if prompt == openPrompt || prompt.hasPrefix(openPrompt + " ") {
            let id = prompt.dropFirst(openPrompt.count).trimmingCharacters(in: .whitespaces).lowercased()
            guard validID(id) else { throw TeamSignupError.invalidCommand }
            return .open(id)
        }
        return nil
    }

    static func validID(_ id: String) -> Bool {
        ConversationCard.validInstanceID(id)
    }

    static func validTitle(_ title: String) -> Bool {
        (1...60).contains(title.utf16.count) && title == title.trimmingCharacters(in: .whitespacesAndNewlines)
            && title.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n\t")) == nil
    }
}

enum TeamSignupError: LocalizedError, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, identityChanged, missing, full, unavailable, invalidCommand
    var isUnauthorized: Bool { self == .unauthorized }
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录。"
        case .forbidden: return "当前账号暂时无法参与报名。"
        case .identityChanged: return "账号已切换，请重新打开报名卡。"
        case .missing: return "找不到这张组队报名卡。"
        case .full: return "报名已满，有空位时可再报名。"
        case .unavailable: return "暂时无法连接组队报名，请稍后重试。"
        case .invalidCommand: return "请发送「创建组队报名 4 周末联机」，或复制分享中的完整打开指令。"
        }
    }
}

protocol TeamSignupServing: Sendable {
    func load(id: String, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot
    func create(id: String, title: String, capacity: Int, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot
    func setJoined(_ joined: Bool, id: String, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot
}

struct TeamSignupService: TeamSignupServing {
    let session: URLSession
    let origin: URL

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration, delegate: ConversationCardNoRedirects(), delegateQueue: nil)
        }
    }

    func load(id: String, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot {
        try await request(id: id, method: "GET", identity: identity)
    }
    func create(id: String, title: String, capacity: Int, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot {
        struct Body: Encodable { let title: String; let capacity: Int }
        let body = try JSONEncoder().encode(Body(title: title, capacity: capacity))
        return try await request(id: id, method: "PUT", identity: identity, body: body)
    }
    func setJoined(_ joined: Bool, id: String, identity: AuthorizedAccount) async throws -> TeamSignupSnapshot {
        let body = try JSONEncoder().encode(["joined": joined])
        let snapshot = try await request(id: id, method: "PATCH", identity: identity, body: body)
        guard snapshot.joined == joined else { throw TeamSignupError.unavailable }
        return snapshot
    }

    private func request(id: String, method: String, identity: AuthorizedAccount, body: Data? = nil) async throws -> TeamSignupSnapshot {
        guard TeamSignupCommand.validID(id) else { throw TeamSignupError.invalidCommand }
        let url = origin.appendingPathComponent("api/team-signups").appendingPathComponent(id)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url,
              http.mimeType?.lowercased() == "application/json", data.count <= 8192 else { throw TeamSignupError.unavailable }
        switch http.statusCode {
        case 401: throw TeamSignupError.unauthorized
        case 403: throw TeamSignupError.forbidden
        case 404: throw TeamSignupError.missing
        case 409 where method == "PATCH": throw TeamSignupError.full
        case 200: break
        default: throw TeamSignupError.unavailable
        }
        let snapshot = try JSONDecoder().decode(TeamSignupSnapshot.self, from: data)
        try snapshot.validate(for: id)
        return snapshot
    }
}

final class ConversationCardNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
