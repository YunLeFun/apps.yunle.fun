import Foundation

enum ApplicationIconRole: String { case appIcon = "app-icon", mark }
protocol PublishingServing: Sendable {
    func access(identity: AuthorizedAccount) async throws -> PublishingAccess
    func applications(identity: AuthorizedAccount) async throws -> [ManagedApplication]
    func save(id: String?, draft: ApplicationDraft, writeVersion: String?, identity: AuthorizedAccount) async throws -> ManagedApplication
    func submit(id: String, makePublic: Bool, shortName: String, writeVersion: String, identity: AuthorizedAccount) async throws -> MarketSubmissionReceipt
    func delist(id: String, writeVersion: String, identity: AuthorizedAccount) async throws
    func upload(png: Data, role: ApplicationIconRole, identity: AuthorizedAccount) async throws -> String
}
struct PublishingService: PublishingServing {
    let session: URLSession
    let origin: URL
    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: config, delegate: PublishingRedirectPolicy(), delegateQueue: nil)
        }
    }
    func access(identity: AuthorizedAccount) async throws -> PublishingAccess {
        try await request(origin.appendingPathComponent("api/apps/access"), identity: identity)
    }
    func applications(identity: AuthorizedAccount) async throws -> [ManagedApplication] {
        let result: OwnedList = try await request(origin.appendingPathComponent("api/apps/mine"), identity: identity)
        guard result.items.count <= 200, Set(result.items.map(\.id)).count == result.items.count else { throw PublishingError.invalidResponse }
        for app in result.items { try app.validate(owner: identity.userID) }
        return result.items.map { record in
            var record = record
            record.application.accessOwnerID = identity.userID; record.application.accessWorkshopID = nil
            return record
        }
    }
    func save(id: String?, draft: ApplicationDraft, writeVersion: String? = nil, identity: AuthorizedAccount) async throws -> ManagedApplication {
        if id != nil { guard let writeVersion, PublishingValue.writeVersion(writeVersion) else { throw PublishingError.unsupportedServer } }
        guard draft.isValid else { throw PublishingError.invalidInput }
        let url = try id.map { try appURL($0).appendingPathComponent("submissions") } ?? origin.appendingPathComponent("api/apps/submissions")
        var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        body["kind"] = "first_party"
        // Projection-only PNG/WebP convenience fields never enter a submission.
        if let icons = draft.iconAssets {
            func variants(_ value: CloudApplication.IconAssets.Variants?) -> [String: String]? {
                guard let src = value?.src?.trimmed, !src.isEmpty else { return nil }
                var result = ["src": src]
                if let dark = value?.darkSrc?.trimmed, !dark.isEmpty { result["darkSrc"] = dark }
                return result
            }
            var compact: [String: Any] = [:]
            if let appIcon = variants(icons.appIcon) { compact["appIcon"] = appIcon }
            if let mark = variants(icons.mark) { compact["mark"] = mark }
            body["iconAssets"] = compact.isEmpty ? nil : compact
        }
        let receipt: ApplicationSaveReceipt = try await request(url, method: "POST", fields: body, writeVersion: writeVersion, identity: identity)
        try receipt.app.validate(owner: identity.userID, id: id)
        guard receipt.submission.appId == receipt.app.id, receipt.submission.submitterUid == identity.userID,
              receipt.app.latestSubmission?.submitterUid == identity.userID,
              PublishingValue.identifier(receipt.submission.id), receipt.submission.id == receipt.app.currentRevisionId,
              receipt.submission.id == receipt.app.latestSubmission?.id,
              receipt.submission.reviewStatus == .draft, receipt.app.latestSubmission?.reviewStatus == .draft,
              receipt.app.writeVersion != nil, receipt.submission.revision > 0, receipt.app.latestSubmission?.revision == receipt.submission.revision,
              receipt.app.publishedSubmissionId == receipt.submission.id, receipt.app.publicationStatus == .published,
              receipt.app.draft.name.trimmed == draft.name.trimmed, receipt.app.draft.slug == draft.slug.trimmed,
              receipt.app.draft.audience == draft.audience else { throw PublishingError.invalidResponse }
        var app = receipt.app
        app.application.accessOwnerID = identity.userID; app.application.accessWorkshopID = nil
        return app
    }
    func submit(id: String, makePublic: Bool, shortName: String, writeVersion: String, identity: AuthorizedAccount) async throws -> MarketSubmissionReceipt {
        guard shortName.isEmpty || PublishingValue.slug(shortName) else { throw PublishingError.invalidInput }
        let receipt: MarketSubmissionReceipt = try await request(appURL(id).appendingPathComponent("public-market"), method: "POST",
            fields: ["makePublic": makePublic, "shortName": shortName], writeVersion: writeVersion, identity: identity)
        guard receipt.appId == id, PublishingValue.identifier(receipt.submissionId), receipt.reviewStatus == .pending else { throw PublishingError.invalidResponse }
        return receipt
    }
    func delist(id: String, writeVersion: String, identity: AuthorizedAccount) async throws {
        let receipt: DelistReceipt = try await request(appURL(id), method: "DELETE", writeVersion: writeVersion, identity: identity)
        guard receipt.success else { throw PublishingError.invalidResponse }
    }
    func upload(png: Data, role: ApplicationIconRole, identity: AuthorizedAccount) async throws -> String {
        guard png.count >= 24, png.count <= 4 * 1024 * 1024,
              png.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]),
              Array(png[16..<24]) == [0, 0, 4, 0, 0, 0, 4, 0] else { throw PublishingError.invalidInput }
        let boundary = "YunleFun-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"assetRole\"\r\n\r\n\(role.rawValue)\r\n".utf8)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(role.rawValue).png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(png); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let receipt: IconReceipt = try await request(origin.appendingPathComponent("api/apps/icon-assets"), method: "POST", rawBody: body,
            contentType: "multipart/form-data; boundary=\(boundary)", identity: identity)
        guard receipt.role == role.rawValue, receipt.width == 1024, receipt.height == 1024,
              receipt.fileID.hasPrefix("cloud://"), PublishingValue.iconSource(receipt.fileID) else { throw PublishingError.invalidResponse }
        return receipt.fileID
    }
    private func appURL(_ id: String) throws -> URL {
        guard PublishingValue.identifier(id) else { throw PublishingError.invalidInput }
        return origin.appendingPathComponent("api/apps").appendingPathComponent(id)
    }
    private func request<Value: Decodable>(_ url: URL, method: String = "GET", fields: [String: Any]? = nil,
        rawBody: Data? = nil, contentType: String? = nil, writeVersion: String? = nil, identity: AuthorizedAccount) async throws -> Value {
        var request = URLRequest(url: url)
        if let writeVersion {
            guard PublishingValue.writeVersion(writeVersion) else { throw PublishingError.unsupportedServer }
            request.setValue("\"\(writeVersion)\"", forHTTPHeaderField: "If-Match")
        }
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        if let fields {
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let rawBody {
            request.httpBody = rawBody; request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PublishingError.invalidResponse }
        switch http.statusCode {
        case 400: throw PublishingError.invalidInput
        case 401: throw PublishingError.unauthorized
        case 403: throw PublishingError.forbidden
        case 404: throw PublishingError.notFound
        case 409, 412: throw PublishingError.conflict
        case 428: throw PublishingError.unsupportedServer
        case 429: throw PublishingError.throttled
        case 200..<300: break
        default: throw PublishingError.unavailable
        }
        guard data.count <= 4 * 1024 * 1024, let result = try? JSONDecoder().decode(Value.self, from: data) else { throw PublishingError.invalidResponse }
        return result
    }
    private struct OwnedList: Decodable { let items: [ManagedApplication] }
    private struct DelistReceipt: Decodable { let success: Bool }
    private struct IconReceipt: Decodable { let fileID: String; let role: String; let width: Int; let height: Int }
}
private final class PublishingRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
struct OwnerPreviewAuthorization {
    let accounts: IdentityScopedAccountAuthorizing
    var service: PublishingServing = PublishingService()
    func resolve(_ app: CloudApplication, boundary: AccountRequestBoundary) async throws -> CloudApplication {
        guard let owner = app.accessOwnerID, owner == boundary.uid, app.accessWorkshopID == nil else { throw PublishingError.forbidden }
        let access = AccountRequestAccess<PublishingError>(accounts: accounts)
        let records = try await access.perform(boundary: boundary) { try await service.applications(identity: $0) }
        guard let record = records.first(where: { $0.id == app.id }), record.hasCurrentMetadata else { throw PublishingError.forbidden }
        var current = record.application
        current.accessOwnerID = owner; current.accessWorkshopID = nil
        guard current.ownerPreviewRestriction == nil, current.launchURL != nil else { throw PublishingError.forbidden }
        return current
    }
}
