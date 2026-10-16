import Foundation

protocol CatalogServing {
    func applications() async throws -> [CloudApplication]
}

struct CatalogService: CatalogServing {
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
