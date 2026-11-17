import Combine
import Foundation
import OSLog

protocol NativeGameCatalogServing {
    func catalog() async throws -> NativeGameCatalog
}

struct NativeGameCatalogService: NativeGameCatalogServing {
    static let endpoint = URL(string: "https://play.yunle.fun/native/catalog-v1.json")!
    let endpoint: URL
    let session: URLSession

    init(session: URLSession? = nil, endpoint: URL = Self.endpoint) {
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration, delegate: NativeGameNoRedirects(), delegateQueue: nil)
        }
    }

    func catalog() async throws -> NativeGameCatalog {
        guard NativeGame.publicHTTPS(endpoint) else { throw NativeGameError.invalidCatalog }
        let transport = NativeGameHostEnvironment.transportURL(endpoint)
        var request = URLRequest(url: transport)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == transport else { throw NativeGameError.invalidCatalog }
        guard http.statusCode == 200 else { throw NativeGameError.http(http.statusCode) }
        guard http.mimeType?.lowercased() == "application/json" else { throw NativeGameError.invalidCatalog }
        return try NativeGameCatalog.decode(data)
    }

    static func bundledData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: "native-game-catalog-v1", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}

private final class NativeGameNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class NativeGameCatalogStore: ObservableObject {
    enum Source: Equatable { case bundled, saved, online }
    @Published private(set) var catalog: NativeGameCatalog?
    @Published private(set) var source: Source?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var storageNotice: String?
    private let service: NativeGameCatalogServing
    private let cacheURL: URL
    private var didAttemptLoad = false
    private let logger = Logger(subsystem: "fun.yunle.apps", category: "game-catalog")

    init(service: NativeGameCatalogServing = NativeGameCatalogService(), cacheURL: URL? = nil,
         bundledData: Data? = NativeGameCatalogService.bundledData()) {
        self.service = service
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(NativeGameHostEnvironment.previewOrigin == nil ? "Games/catalog-v1.json" : "Games/Preview18146/catalog-v1.json")
        if let data = try? Data(contentsOf: self.cacheURL), let saved = try? NativeGameCatalog.decode(data) {
            catalog = saved
            source = .saved
        } else if let bundledData, let bundled = try? NativeGameCatalog.decode(bundledData) {
            catalog = bundled
            source = .bundled
        }
    }

    var games: [NativeGame] { catalog?.games.filter(\.matchesFirstRelease) ?? [] }
    func game(id: String) -> NativeGame? { games.first { $0.gameId == id } }

    func load(force: Bool = false) async {
        guard !isLoading, force || !didAttemptLoad else { return }
        didAttemptLoad = true
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await service.catalog()
            try Task.checkCancellation()
            try next.validate()
            catalog = next
            source = .online
            error = nil
            do {
                let data = try JSONEncoder().encode(next)
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
                storageNotice = nil
            } catch {
                storageNotice = "游戏列表已更新，本机暂时无法保存离线列表。"
                logger.error("Game catalog snapshot could not be saved")
            }
        } catch is CancellationError {
            didAttemptLoad = false
        } catch let issue as URLError where issue.code == .cancelled {
            didAttemptLoad = false
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "游戏列表暂时无法更新，请稍后刷新。"
        }
    }
}
