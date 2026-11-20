import Foundation

enum WebBuildPalette: String, Decodable, Sendable {
    case indigo, moss, clay, ocean
}

struct WebBuildPage: Decodable, Sendable {
    struct Section: Decodable, Sendable {
        let title: String
        let text: String
        let expandable: Bool
    }

    let title: String
    let description: String
    let palette: WebBuildPalette
    let sections: [Section]

    var isValid: Bool {
        WebBuildValue.text(title, limit: 50) && WebBuildValue.text(description, limit: 220)
            && (1...6).contains(sections.count)
            && sections.allSatisfy { WebBuildValue.text($0.title, limit: 75) && WebBuildValue.text($0.text, limit: 440) }
    }
}

struct WebBuildSummary: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let shareUrl: URL?
    let updatedAt: Double
    let role: WebBuildRole?

    var isValid: Bool {
        WebBuildValue.id(id) && WebBuildValue.text(title, limit: 50) && CommunityValue.timestamp(updatedAt)
            && (shareUrl == nil || shareUrl == WebBuildValue.shareURL(id))
    }
}

enum WebBuildRole: String, Decodable, Sendable {
    case owner, member
}

struct WebBuildRoom: Decodable, Sendable {
    struct Member: Decodable, Identifiable, Sendable {
        let id: String
        let name: String

        var isValid: Bool { (id == "owner" || WebBuildValue.id(id)) && WebBuildValue.text(name, limit: 40) }
    }

    struct Message: Decodable, Identifiable, Sendable {
        enum Kind: String, Decodable, Sendable { case chat, edit }
        let id: String
        let author: Member
        let kind: Kind
        let text: String
        let createdAt: Double

        var isValid: Bool {
            WebBuildValue.id(id) && author.isValid && CommunityValue.timestamp(createdAt)
                && WebBuildValue.text(text, limit: kind == .chat ? 600 : 1000)
        }
    }

    let members: [Member]
    let viewerId: String
    let messages: [Message]
    let inviteExpiresAt: Double?
    let friendInvitesExpireAt: Double?

    var isValid: Bool {
        (1...8).contains(members.count) && members.first?.id == "owner"
            && Set(members.map(\.id)).count == members.count && members.allSatisfy(\.isValid)
            && members.contains { $0.id == viewerId }
            && messages.count <= 50 && Set(messages.map(\.id)).count == messages.count && messages.allSatisfy(\.isValid)
            && (inviteExpiresAt.map(CommunityValue.timestamp) ?? true)
            && (friendInvitesExpireAt.map(CommunityValue.timestamp) ?? true)
    }
}

struct WebBuildProject: Decodable, Sendable {
    let id: String
    let revision: Int
    let page: WebBuildPage
    let prompts: [String]
    let shareUrl: URL?
    let publishedRevision: Int?
    let updatedAt: Double
    let role: WebBuildRole?
    let room: WebBuildRoom?

    var isCurrentPublished: Bool { publishedRevision == revision }
    var canManagePublication: Bool { role != .member }

    var isValid: Bool {
        WebBuildValue.id(id) && (1...1_000_000).contains(revision) && page.isValid && CommunityValue.timestamp(updatedAt)
            && prompts.count <= 8 && (role == .member || !prompts.isEmpty)
            && prompts.allSatisfy { WebBuildValue.text($0, limit: 1000) }
            && (room.map { $0.isValid && ($0.viewerId == "owner") == (role == .owner) } ?? (role != .member))
            && (shareUrl == nil ? publishedRevision == nil : shareUrl == WebBuildValue.shareURL(id)
                && publishedRevision.map { (1...revision).contains($0) } == true)
    }
}

enum WebBuildValue {
    static func id(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func id(forAppSlug slug: String) -> String? {
        guard slug.hasPrefix("web-build-") else { return nil }
        let identifier = String(slug.dropFirst("web-build-".count))
        return id(identifier) ? identifier : nil
    }

    static func text(_ value: String, limit: Int) -> Bool {
        !value.trimmed.isEmpty && value.utf16.count <= limit
    }

    static func shareURL(_ id: String) -> URL? {
        guard self.id(id) else { return nil }
        return URL(string: "https://build.yunle.app/site/\(id)")
    }

    static func inviteProject(_ code: String) -> String? {
        let parts = code.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(id) else { return nil }
        return parts[0]
    }

    static func inviteID(_ value: String) -> Bool {
        value.utf8.count == 24 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

enum WebBuildEdit: Sendable {
    case generate(String), publish, withdraw
}

enum WebBuildRoomAction: Sendable {
    case invite, revoke, join(String), leave, remove(String), chat(String)
    case inviteFriend(String), acceptInvite(String, projectID: String)
}

struct WebBuildRoomReceipt: Decodable, Sendable {
    let project: WebBuildProject?
    let inviteCode: String?
}

protocol WebBuildServing: Sendable {
    func projects(identity: AuthorizedAccount) async throws -> [WebBuildSummary]
    func project(id: String, identity: AuthorizedAccount) async throws -> WebBuildProject
    func update(_ action: WebBuildEdit, project: WebBuildProject?, identity: AuthorizedAccount) async throws -> WebBuildProject
    func submit(project: WebBuildProject, shortName: String, identity: AuthorizedAccount) async throws
    func room(_ action: WebBuildRoomAction, projectID: String?, identity: AuthorizedAccount) async throws -> WebBuildRoomReceipt
}

struct WebBuildService: WebBuildServing {
    private let transport: PublishingService
    private var endpoint: URL { transport.origin.appendingPathComponent("api/web-builds") }

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        transport = PublishingService(session: session, origin: origin)
    }

    func available(identity: AuthorizedAccount) async throws -> Bool {
        let response: Availability = try await transport.request(endpoint.appendingPathComponent("availability"), identity: identity)
        return response.enabled
    }

    @MainActor
    func availableBoundary(for accounts: any IdentityScopedAccountAuthorizing) async -> AccountRequestBoundary? {
        guard accounts.user?.isUsable == true else { return nil }
        let access = AccountRequestAccess<PublishingError>(accounts: accounts)
        let boundary = access.boundary
        let enabled = try? await access.perform(boundary: boundary) { try await available(identity: $0) }
        guard enabled == true, access.isCurrent(boundary), !Task.isCancelled else { return nil }
        return boundary
    }

    func projects(identity: AuthorizedAccount) async throws -> [WebBuildSummary] {
        let url = endpoint.appending(queryItems: [URLQueryItem(name: "includeShared", value: "true")])
        let records: [WebBuildSummary] = try await transport.request(url, identity: identity)
        guard records.count <= 100, Set(records.map(\.id)).count == records.count, records.allSatisfy(\.isValid)
        else { throw PublishingError.invalidResponse }
        return records
    }

    func project(id: String, identity: AuthorizedAccount) async throws -> WebBuildProject {
        guard WebBuildValue.id(id) else { throw PublishingError.invalidInput }
        let project: WebBuildProject = try await transport.request(endpoint.appendingPathComponent(id), identity: identity)
        guard project.id == id, project.isValid else { throw PublishingError.invalidResponse }
        return project
    }

    func update(_ action: WebBuildEdit, project: WebBuildProject?, identity: AuthorizedAccount) async throws -> WebBuildProject {
        var fields: [String: Any] = [:]
        if let project {
            guard project.isValid else { throw PublishingError.invalidInput }
            fields["id"] = project.id
            fields["revision"] = project.revision
        }
        let expectedRevision: Int
        switch action {
        case .generate(let prompt):
            guard WebBuildValue.text(prompt, limit: 1000) else { throw PublishingError.invalidInput }
            fields["action"] = "generate"
            fields["prompt"] = prompt.trimmed
            expectedRevision = (project?.revision ?? 0) + 1
        case .publish:
            guard let project, project.canManagePublication else { throw PublishingError.invalidInput }
            fields["action"] = "publish"
            expectedRevision = project.revision
        case .withdraw:
            guard let project, project.canManagePublication else { throw PublishingError.invalidInput }
            fields["action"] = "withdraw"
            expectedRevision = project.revision + 1
        }
        let result: WebBuildProject = try await transport.request(endpoint, method: "POST", fields: fields, identity: identity)
        guard result.isValid, project == nil || result.id == project?.id, result.revision == expectedRevision
        else { throw PublishingError.invalidResponse }
        switch action {
        case .generate:
            guard (project != nil || result.shareUrl == nil), !result.isCurrentPublished else {
                throw PublishingError.invalidResponse
            }
        case .publish:
            guard result.isCurrentPublished else { throw PublishingError.invalidResponse }
        case .withdraw:
            guard result.shareUrl == nil else { throw PublishingError.invalidResponse }
        }
        return result
    }

    func submit(project: WebBuildProject, shortName: String, identity: AuthorizedAccount) async throws {
        guard project.isValid, project.canManagePublication, project.isCurrentPublished,
              shortName.isEmpty || PublishingValue.slug(shortName) else { throw PublishingError.invalidInput }
        let receipt: Submission = try await transport.request(endpoint, method: "POST", fields: [
            "action": "submit", "id": project.id, "revision": project.revision, "shortName": shortName,
        ], identity: identity)
        guard receipt.slug == "web-build-\(project.id)" else { throw PublishingError.invalidResponse }
    }

    func room(_ action: WebBuildRoomAction, projectID: String?, identity: AuthorizedAccount) async throws -> WebBuildRoomReceipt {
        let expectedID: String
        var fields: [String: Any] = [:]
        switch action {
        case .join(let code):
            let code = code.trimmed
            guard let identifier = WebBuildValue.inviteProject(code) else { throw PublishingError.invalidInput }
            fields["inviteCode"] = code
            expectedID = identifier
        case .acceptInvite(let noticeID, let projectID):
            guard WebBuildValue.inviteID(noticeID), WebBuildValue.id(projectID) else { throw PublishingError.invalidInput }
            fields["inviteId"] = noticeID
            expectedID = projectID
        default:
            guard let projectID, WebBuildValue.id(projectID) else { throw PublishingError.invalidInput }
            fields["id"] = projectID
            expectedID = projectID
        }

        switch action {
        case .invite: fields["action"] = "room.invite"
        case .revoke: fields["action"] = "room.revoke"
        case .join: fields["action"] = "room.join"
        case .acceptInvite: fields["action"] = "room.acceptInvite"
        case .inviteFriend(let target):
            guard !target.isEmpty, target == target.trimmed, target.utf16.count <= 128, target != identity.userID
            else { throw PublishingError.invalidInput }
            fields["action"] = "room.inviteFriend"
            fields["targetId"] = target
        case .leave: fields["action"] = "room.leave"
        case .remove(let member):
            guard WebBuildValue.id(member) else { throw PublishingError.invalidInput }
            fields["action"] = "room.remove"
            fields["memberId"] = member
        case .chat(let text):
            guard WebBuildValue.text(text, limit: 600) else { throw PublishingError.invalidInput }
            fields["action"] = "room.chat"
            fields["text"] = text.trimmed
        }

        let receipt: WebBuildRoomReceipt = try await transport.request(endpoint, method: "POST", fields: fields, identity: identity)
        if case .leave = action {
            guard receipt.project == nil, receipt.inviteCode == nil else { throw PublishingError.invalidResponse }
            return receipt
        }
        guard let project = receipt.project, project.id == expectedID, project.isValid, project.room != nil
        else { throw PublishingError.invalidResponse }
        if case .invite = action {
            guard let code = receipt.inviteCode, WebBuildValue.inviteProject(code) == expectedID,
                  project.role == .owner, project.room?.inviteExpiresAt != nil else { throw PublishingError.invalidResponse }
        } else if receipt.inviteCode != nil {
            throw PublishingError.invalidResponse
        }
        if case .inviteFriend = action {
            guard project.role == .owner, project.room?.friendInvitesExpireAt != nil else { throw PublishingError.invalidResponse }
        }
        return receipt
    }

    private struct Availability: Decodable { let enabled: Bool }
    private struct Submission: Decodable { let slug: String }
}
