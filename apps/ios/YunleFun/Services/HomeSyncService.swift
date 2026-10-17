import Foundation

protocol HomeSyncServing: Sendable {
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen
}

struct HomeSyncService: HomeSyncServing {
    private let session: URLSession
    private let endpoint: URL
    private var readEndpoint: URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "schema", value: String(HomeScreenWrite.schemaVersion))]
        return components.url!
    }
    init(session: URLSession? = nil, origin: URL = URL(string: "https://apps.yunle.fun")!) {
        endpoint = origin.appendingPathComponent("api/home-screen")
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: HomeRedirectPolicy(), delegateQueue: nil)
        }
    }
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        try await request(identity: identity, write: nil)
    }
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        try write.configuration.validate()
        let saved = try await request(identity: identity, write: write)
        guard saved.revision != nil, write.configuration.matches(saved) else {
            throw HomeSyncError.invalidResponse
        }
        return saved
    }
    private func request(identity: AuthorizedAccount, write: HomeScreenWrite?) async throws -> RemoteHomeScreen {
        // Reads opt in to schema 2 (folders); writes carry the version in the body.
        var request = URLRequest(url: write == nil ? readEndpoint : endpoint)
        request.httpMethod = write == nil ? "GET" : "PUT"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        if let write {
            request.httpBody = try JSONEncoder().encode(write)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.mimeType?.lowercased() == "application/json",
              data.count <= 2 * 1024 * 1024 else { throw HomeSyncError.invalidResponse }
        if http.statusCode == 401 { throw HomeSyncError.unauthorized }
        if http.statusCode == 403 { throw HomeSyncError.forbidden }
        if http.statusCode == 409,
           let failure = try? JSONDecoder().decode(Failure.self, from: data) {
            if failure.data?.code == "HOME_CONFLICT", let remote = failure.data?.current {
                try remote.validate()
                throw HomeSyncError.conflict(remote)
            }
            throw HomeSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else { throw HomeSyncError.unavailable }
        let remote: RemoteHomeScreen
        do { remote = try JSONDecoder().decode(RemoteHomeScreen.self, from: data) }
        catch { throw HomeSyncError.invalidResponse }
        try remote.validate()
        return remote
    }
    private struct Failure: Decodable {
        let data: Details?
        struct Details: Decodable { let code: String?; let current: RemoteHomeScreen? }
    }
}

private final class HomeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
