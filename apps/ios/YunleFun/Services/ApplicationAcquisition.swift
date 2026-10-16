import Foundation
import Combine

enum ApplicationAcquisitionError: Error, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, unavailable, invalidResponse, identityChanged, conflict, notFound, storage
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .unauthorized: return "登录状态已失效，请重新登录。"
        case .forbidden: return "当前账号暂不能获取这个应用。"
        case .identityChanged: return "账号已变化，请重新确认使用条件。"
        case .conflict: return "应用价格或云币余额已变化，请刷新后重新确认。"
        case .notFound: return "应用暂未上架或已下架。"
        case .storage: return "未能保存到云居，请检查设备存储空间后重试。"
        default: return "暂时无法核对应用权益，请检查网络后重试。"
        }
    }
}
struct ApplicationAcquisitionQuote: Decodable {
    enum State: String, Decodable { case allowed, membershipRequired = "membership_required", purchaseRequired = "purchase_required", invitationRequired = "invitation_required" }
    let userId: String
    let application: CloudApplication
    let state: State
    let reason: String
    let coinCost: Int
    let balance: Int64
    func validate(appID: String, uid: String) throws {
        guard userId == uid, application.id == appID, application.accessOwnerID == nil, application.accessWorkshopID == nil,
              application.isUnavailable != true, application.isPublic != false,
              coinCost >= 0, coinCost <= 9_007_199_254_740_991, coinCost == (application.coinCost ?? 0),
              (0...9_007_199_254_740_991).contains(balance) else { throw ApplicationAcquisitionError.invalidResponse }
        if state == .allowed {
            guard application.launchURL != nil, application.accessMode == nil || ["public", "login_required"].contains(application.accessMode!),
                  ["free", "member", "purchased"].contains(reason),
                  application.requiresMembership != true || reason == "member",
                  coinCost == 0 || ["member", "purchased"].contains(reason) else { throw ApplicationAcquisitionError.invalidResponse }
        }
        if state == .purchaseRequired {
            guard coinCost > 0, application.requiresMembership != true, application.accessMode != "invite_only" else { throw ApplicationAcquisitionError.invalidResponse }
        }
    }
}
protocol ApplicationAcquisitionServing: Sendable {
    func resolve(appID: String, expectedCoinCost: Int?, identity: AuthorizedAccount) async throws -> ApplicationAcquisitionQuote
}
struct ApplicationAcquisitionService: ApplicationAcquisitionServing {
    let session: URLSession
    let origin: URL
    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never; config.httpCookieStorage = nil
            config.urlCredentialStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config, delegate: AcquisitionRedirectPolicy(), delegateQueue: nil)
        }
    }
    func resolve(appID: String, expectedCoinCost: Int?, identity: AuthorizedAccount) async throws -> ApplicationAcquisitionQuote {
        guard appID.range(of: #"^[\w-]{1,128}$"#, options: .regularExpression) != nil,
              expectedCoinCost.map({ $0 > 0 && $0 <= 9_007_199_254_740_991 }) ?? true else { throw ApplicationAcquisitionError.invalidResponse }
        var request = URLRequest(url: origin.appendingPathComponent("api/apps/acquisition"))
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var fields: [String: Any] = ["appId": appID, "action": expectedCoinCost == nil ? "check" : "purchase"]
        if let expectedCoinCost { fields["expectedCoinCost"] = expectedCoinCost }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApplicationAcquisitionError.invalidResponse }
        switch http.statusCode {
        case 401: throw ApplicationAcquisitionError.unauthorized
        case 403: throw ApplicationAcquisitionError.forbidden
        case 404: throw ApplicationAcquisitionError.notFound
        case 409: throw ApplicationAcquisitionError.conflict
        case 200..<300: break
        default: throw ApplicationAcquisitionError.unavailable
        }
        guard data.count <= 2 * 1024 * 1024, let quote = try? JSONDecoder().decode(ApplicationAcquisitionQuote.self, from: data) else { throw ApplicationAcquisitionError.invalidResponse }
        try quote.validate(appID: appID, uid: identity.userID)
        return quote
    }
}
private final class AcquisitionRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct ApplicationCoinConfirmation {
    let boundary: AccountRequestBoundary
    let appID: String
    let coinCost: Int
}
struct ApplicationAccessPermit {
    let boundary: AccountRequestBoundary
    let application: CloudApplication
}
@MainActor
final class ApplicationAcquisitionStore: ObservableObject {
    private let access: AccountRequestAccess<ApplicationAcquisitionError>
    private let service: ApplicationAcquisitionServing
    let application: CloudApplication
    private var stateBoundary: AccountRequestBoundary?
    private var operationID = UUID()
    @Published private var rawQuote: ApplicationAcquisitionQuote?
    @Published private var rawError: String?
    @Published private var rawBusy = false
    var quote: ApplicationAcquisitionQuote? { stateBoundary == access.boundary ? rawQuote : nil }
    var error: String? { stateBoundary == access.boundary ? rawError : nil }
    var isBusy: Bool { stateBoundary == access.boundary && rawBusy }
    var confirmation: ApplicationCoinConfirmation? {
        guard let quote, quote.state == .purchaseRequired, !isBusy, quote.balance >= quote.coinCost else { return nil }
        return ApplicationCoinConfirmation(boundary: access.boundary, appID: application.id, coinCost: quote.coinCost)
    }
    init(application: CloudApplication, accounts: IdentityScopedAccountAuthorizing, service: ApplicationAcquisitionServing = ApplicationAcquisitionService()) {
        self.application = application; self.service = service; access = AccountRequestAccess(accounts: accounts)
    }
    @discardableResult func refresh() async -> ApplicationAccessPermit? { await resolve(confirmation: nil) }
    func purchase(_ confirmation: ApplicationCoinConfirmation) async -> ApplicationAccessPermit? {
        guard access.isCurrent(confirmation.boundary), let current = self.confirmation,
              current.appID == confirmation.appID, current.coinCost == confirmation.coinCost else { return nil }
        return await resolve(confirmation: confirmation)
    }
    func storageFailed() { rawError = ApplicationAcquisitionError.storage.message }
    private func resolve(confirmation: ApplicationCoinConfirmation?) async -> ApplicationAccessPermit? {
        guard !isBusy, access.boundary.uid != nil else { return nil }
        let boundary = access.boundary, operation = UUID()
        operationID = operation; stateBoundary = boundary; rawError = nil; rawQuote = nil; rawBusy = true
        defer { if operationID == operation { rawBusy = false } }
        do {
            let quote = try await access.perform(boundary: boundary) {
                try await service.resolve(appID: application.id, expectedCoinCost: confirmation?.coinCost, identity: $0)
            }
            guard operationID == operation, access.isCurrent(boundary) else { return nil }
            try quote.validate(appID: application.id, uid: boundary.uid!)
            rawQuote = quote
            return quote.state == .allowed ? ApplicationAccessPermit(boundary: boundary, application: quote.application) : nil
        } catch {
            guard operationID == operation, access.isCurrent(boundary) else { return nil }
            rawError = (error as? ApplicationAcquisitionError)?.message ?? ApplicationAcquisitionError.unavailable.message
            return nil
        }
    }
}
