import Foundation

protocol CatalogServing {
    func applications() async throws -> [CloudApplication]
}

protocol ApplicationAvailabilityServing {
    func application(reference: String) async throws -> CloudApplication
}

enum ApplicationUnavailableReason: String, Decodable, Error {
    case notListed = "not_listed", delisted, suspended, unavailable
    var title: String {
        switch self {
        case .notListed: return "应用尚未上架"
        case .delisted: return "应用已下架"
        case .suspended: return "应用已暂停使用"
        case .unavailable: return "应用暂不可用"
        }
    }
    var message: String {
        switch self {
        case .notListed: return "这个应用尚未在公开市场上架，暂时无法从云居打开。安装记录已保留。"
        case .delisted: return "这个应用已从公开市场下架。安装记录已保留，重新上架后可以恢复使用。"
        case .suspended: return "这个应用的公开市场服务已暂停。安装记录已保留，可以稍后刷新状态。"
        case .unavailable: return "当前无法获取这个应用的可用版本，应用资料或访问范围可能已变更。安装记录已保留。"
        }
    }
}

struct CatalogService: CatalogServing, ApplicationAvailabilityServing {
    static let productionOrigin = URL(string: "https://apps.yunle.fun")!
    let session: URLSession
    let origin: URL

    init(session: URLSession? = nil, origin: URL = productionOrigin) {
        self.origin = origin
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: config)
        }
    }

    func applications() async throws -> [CloudApplication] {
        var request = URLRequest(url: origin.appendingPathComponent("api/apps/public"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw CatalogError.http(http.statusCode)
        }
        let result = try JSONDecoder().decode(CatalogResponse.self, from: data)
        var seen = Set<String>()
        return result.items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    private struct CatalogResponse: Decodable { let items: [CloudApplication] }

    func application(reference: String) async throws -> CloudApplication {
        var request = URLRequest(url: origin.appendingPathComponent("api/apps/public").appendingPathComponent(reference))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard http.mimeType?.lowercased() == "application/json" else { throw CatalogError.invalidResponse }
        if http.statusCode == 404 {
            struct Failure: Decodable {
                struct Detail: Decodable { let code: String?; let reasonCode: String? }
                let data: Detail?
            }
            let detail = try JSONDecoder().decode(Failure.self, from: data).data
            guard detail?.code == "APP_UNAVAILABLE" else { throw ApplicationUnavailableReason.unavailable }
            throw ApplicationUnavailableReason(rawValue: detail?.reasonCode ?? "") ?? .unavailable
        }
        guard (200..<300).contains(http.statusCode) else { throw CatalogError.http(http.statusCode) }
        struct Envelope: Decodable { let app: CloudApplication }
        let app = try JSONDecoder().decode(Envelope.self, from: data).app
        guard app.id == reference || app.marketShortName?.lowercased() == reference.lowercased(),
              app.accessWorkshopID == nil, app.accessOwnerID == nil, app.personalMarketOwnerLogin == nil,
              app.isPublic != false, app.audience == nil || app.audience == "public", app.isUnavailable != true
        else { throw CatalogError.invalidResponse }
        return app
    }
}

enum CatalogError: LocalizedError {
    case invalidResponse
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "暂时无法读取工坊，请稍后重试。"
        case .http(429): return "访问有些频繁，请稍后再试。"
        case .http: return "工坊暂时无法连接，请稍后重试。"
        }
    }
}
