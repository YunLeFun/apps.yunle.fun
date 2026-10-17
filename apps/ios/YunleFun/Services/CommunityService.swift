import Foundation

protocol CommunityServing: Sendable {
    func reviews(appKey: String, identity: AuthorizedAccount?) async throws -> ReviewList
    func submit(appKey: String, draft: ReviewDraft, identity: AuthorizedAccount) async throws -> ReviewSubmission
    func delete(reviewID: String, identity: AuthorizedAccount) async throws
    func report(target: ReportTarget, reason: ReportReason, detail: String, identity: AuthorizedAccount) async throws
    func reports(identity: AuthorizedAccount) async throws -> [MyReport]
}
struct CommunityService: CommunityServing {
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
            self.session = URLSession(configuration: config, delegate: CommunityRedirectPolicy(), delegateQueue: nil)
        }
    }
    func reviews(appKey: String, identity: AuthorizedAccount?) async throws -> ReviewList {
        var parts = URLComponents(url: origin.appendingPathComponent("api/reviews"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "appKey", value: appKey)]
        let result: Envelope<ReviewList> = try await request(parts.url!, identity: identity)
        guard let list = result.data else { throw CommunityError.invalidResponse }
        try list.validate(appKey: appKey, owner: identity?.userID)
        return list
    }
    func submit(appKey: String, draft: ReviewDraft, identity: AuthorizedAccount) async throws -> ReviewSubmission {
        guard draft.isValid else { throw CommunityError.invalidInput }
        let result: Envelope<ReviewSubmission> = try await request(origin.appendingPathComponent("api/reviews"), method: "POST",
            fields: ["appKey": appKey, "rating": draft.rating,
                     "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                     "content": draft.content.trimmingCharacters(in: .whitespacesAndNewlines)], identity: identity)
        guard let submitted = result.data, submitted.review.status == submitted.status else { throw CommunityError.invalidResponse }
        try submitted.review.validate(appKey: appKey, owner: identity.userID)
        return submitted
    }
    func delete(reviewID: String, identity: AuthorizedAccount) async throws {
        guard CommunityValue.identifier(reviewID) else { throw CommunityError.invalidInput }
        let _: Envelope<Empty> = try await request(origin.appendingPathComponent("api/reviews").appendingPathComponent(reviewID),
                                                   method: "DELETE", identity: identity)
    }
    func report(target: ReportTarget, reason: ReportReason, detail: String, identity: AuthorizedAccount) async throws {
        guard !target.id.isEmpty, detail.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 500 else {
            throw CommunityError.invalidInput
        }
        let result: Envelope<ReportReceipt> = try await request(origin.appendingPathComponent("api/reports"), method: "POST",
            fields: ["targetType": target.type.rawValue, "targetId": target.id, "appKey": target.appKey,
                     "reason": reason.rawValue, "detail": detail.trimmingCharacters(in: .whitespacesAndNewlines)], identity: identity)
        guard let receipt = result.data, CommunityValue.identifier(receipt.id) else { throw CommunityError.invalidResponse }
    }
    func reports(identity: AuthorizedAccount) async throws -> [MyReport] {
        let result: Envelope<ReportList> = try await request(origin.appendingPathComponent("api/reports"), identity: identity)
        guard let reports = result.data?.reports, reports.count <= 50,
              Set(reports.map(\.id)).count == reports.count else { throw CommunityError.invalidResponse }
        for report in reports { try report.validate() }
        return reports
    }
    private func request<Value: Decodable>(_ url: URL, method: String = "GET", fields: [String: Any]? = nil,
                                           identity: AuthorizedAccount?) async throws -> Envelope<Value> {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let identity { request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization") }
        if let fields {
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunityError.invalidResponse }
        switch http.statusCode {
        case 401: throw CommunityError.unauthorized
        case 403: throw CommunityError.forbidden
        case 404: throw CommunityError.notFound
        case 409: throw CommunityError.duplicate
        case 429: throw CommunityError.throttled
        case 200..<300: break
        default: throw CommunityError.unavailable
        }
        guard data.count <= 2 * 1024 * 1024,
              let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: data),
              envelope.code == 0 else { throw CommunityError.invalidResponse }
        return envelope
    }
    private struct Empty: Decodable {}
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct ReportReceipt: Decodable { let id: String }
    private struct ReportList: Decodable { let reports: [MyReport] }
}
private final class CommunityRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
