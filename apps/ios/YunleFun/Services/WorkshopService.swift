import Foundation

protocol WorkshopServing: Sendable {
    func mine(identity: AuthorizedAccount) async throws -> WorkshopManagement?
    func joined(identity: AuthorizedAccount) async throws -> [PersonalWorkshop]
    func page(id: String, identity: AuthorizedAccount?) async throws -> WorkshopPage
    func create(draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop
    func update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop
    func join(id: String, identity: AuthorizedAccount) async throws -> WorkshopJoinResult
    func leave(id: String, identity: AuthorizedAccount) async throws -> WorkshopMembership
    func decide(id: String, member: WorkshopMembership, action: WorkshopDecision, identity: AuthorizedAccount) async throws -> WorkshopMembership
}
struct WorkshopService: WorkshopServing {
    let session: URLSession
    let origin: URL
    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: WorkshopRedirectPolicy(), delegateQueue: nil)
        }
    }
    func mine(identity: AuthorizedAccount) async throws -> WorkshopManagement? {
        let result: Mine = try await request(origin.appendingPathComponent("api/workshops/mine"), identity: identity)
        try result.management?.validate(owner: identity.userID)
        return result.management
    }
    func joined(identity: AuthorizedAccount) async throws -> [PersonalWorkshop] {
        let result: Joined = try await request(origin.appendingPathComponent("api/workshops/joined"), identity: identity)
        guard result.items.count <= 100, Set(result.items.map(\.id)).count == result.items.count else { throw WorkshopError.invalidResponse }
        for item in result.items { try item.validate() }
        return result.items
    }
    func page(id: String, identity: AuthorizedAccount?) async throws -> WorkshopPage {
        var result: WorkshopPage = try await request(path(id), identity: identity)
        try result.validate(id: id, identity: identity)
        result.apps = result.apps.map { app in var app = app; app.accessWorkshopID = id; return app }
        return result
    }
    func create(draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop {
        guard draft.isValid else { throw WorkshopError.invalidInput }
        let result: Owned = try await request(origin.appendingPathComponent("api/workshops"), method: "POST",
            fields: ["name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                     "description": draft.description.trimmingCharacters(in: .whitespacesAndNewlines)], identity: identity)
        try result.workshop.validate(owner: identity.userID)
        guard result.workshop.joinPolicy == .approval, result.workshop.status == .active else { throw WorkshopError.invalidResponse }
        return result.workshop
    }
    func update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop {
        guard draft.isValid else { throw WorkshopError.invalidInput }
        let result: Owned = try await request(path(id), method: "PATCH",
            fields: ["name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                     "description": draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                     "joinPolicy": draft.joinPolicy.rawValue, "status": draft.status.rawValue], identity: identity)
        try result.workshop.validate(id: id, owner: identity.userID)
        guard result.workshop.joinPolicy == draft.joinPolicy, result.workshop.status == draft.status else { throw WorkshopError.invalidResponse }
        return result.workshop
    }
    func join(id: String, identity: AuthorizedAccount) async throws -> WorkshopJoinResult {
        let result: WorkshopJoinResult = try await request(path(id).appendingPathComponent("join"), method: "POST", identity: identity)
        try result.validate()
        return result
    }
    func leave(id: String, identity: AuthorizedAccount) async throws -> WorkshopMembership {
        let result: Member = try await request(path(id).appendingPathComponent("leave"), method: "POST", identity: identity)
        try result.membership.validate(workshopID: id, uid: identity.userID, status: .left)
        return result.membership
    }
    func decide(id: String, member: WorkshopMembership, action: WorkshopDecision, identity: AuthorizedAccount) async throws -> WorkshopMembership {
        guard member.workshopId == id, action.allows(member.status), !member.userUid.isEmpty, member.userUid != identity.userID,
              member.userUid.utf16.count <= 256, member.userUid != ".", member.userUid != "..",
              !member.userUid.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw WorkshopError.invalidInput }
        var parts = URLComponents(url: try path(id).appendingPathComponent("members"), resolvingAgainstBaseURL: false)!
        let segment = member.userUid.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
        parts.percentEncodedPath += "/" + segment
        let result: Member = try await request(parts.url!, method: "POST", fields: ["action": action.rawValue], identity: identity)
        try result.membership.validate(workshopID: id, uid: member.userUid, status: action.result)
        return result.membership
    }
    private func path(_ id: String) throws -> URL {
        guard WorkshopLink.normalize(id) == id else { throw WorkshopError.invalidInput }
        return origin.appendingPathComponent("api/workshops").appendingPathComponent(id)
    }
    private func request<Value: Decodable>(_ url: URL, method: String = "GET", fields: [String: Any]? = nil,
                                           identity: AuthorizedAccount?) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let identity { request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization") }
        if let fields {
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WorkshopError.invalidResponse }
        switch http.statusCode {
        case 400: throw WorkshopError.invalidInput
        case 401: throw WorkshopError.unauthorized
        case 403: throw WorkshopError.forbidden
        case 404: throw WorkshopError.notFound
        case 409: throw WorkshopError.conflict
        case 429: throw WorkshopError.throttled
        case 200..<300: break
        default: throw WorkshopError.unavailable
        }
        guard data.count <= 2 * 1024 * 1024, let value = try? JSONDecoder().decode(Value.self, from: data) else { throw WorkshopError.invalidResponse }
        return value
    }
    private struct Owned: Decodable { let workshop: PersonalWorkshop }
    private struct Joined: Decodable { let items: [PersonalWorkshop] }
    private struct Member: Decodable { let membership: WorkshopMembership }
    private struct Mine: Decodable {
        let management: WorkshopManagement?
        enum CodingKeys: String, CodingKey { case management }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.management) else { throw WorkshopError.invalidResponse }
            management = try c.decodeIfPresent(WorkshopManagement.self, forKey: .management)
        }
    }
}
private final class WorkshopRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
struct WorkshopLaunchAuthorization {
    let accounts: IdentityScopedAccountAuthorizing
    var service: WorkshopServing = WorkshopService()
    func resolve(_ app: CloudApplication, boundary: AccountRequestBoundary) async throws -> CloudApplication {
        guard let id = app.accessWorkshopID, app.workshopLaunchRestriction == nil else { throw WorkshopError.forbidden }
        let access = AccountRequestAccess<WorkshopError>(accounts: accounts)
        let page = try await access.perform(boundary: boundary) { try await service.page(id: id, identity: $0) }
        guard page.permitsApps, var current = page.apps.first(where: { $0.id == app.id }), current.workshopLaunchRestriction == nil,
              current.launchURL != nil else { throw WorkshopError.forbidden }
        current.accessWorkshopID = id
        return current
    }
}
