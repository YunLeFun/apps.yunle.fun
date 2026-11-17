import Combine
import Foundation

protocol NativePublicRoomServing {
    func rooms() async throws -> [NativePublicRoom]
}

struct NativePublicRoomService: NativePublicRoomServing {
    static let endpoint = URL(string: "https://api.play.yunle.fun/v1/rooms/public")!
    let session: URLSession
    let endpoint: URL

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
            self.session = URLSession(configuration: configuration, delegate: PublicRoomNoRedirects(), delegateQueue: nil)
        }
    }

    func rooms() async throws -> [NativePublicRoom] {
        guard NativeGame.publicHTTPS(endpoint) else { throw NativePublicRoomError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == endpoint else { throw NativePublicRoomError.invalidResponse }
        guard http.statusCode == 200 else { throw NativePublicRoomError.unavailable }
        guard http.mimeType?.lowercased() == "application/json" else { throw NativePublicRoomError.invalidResponse }
        return try NativePublicRoom.decodeList(data)
    }
}

private final class PublicRoomNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class NativePublicRoomStore: ObservableObject {
    @Published private(set) var rooms: [NativePublicRoom] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let service: NativePublicRoomServing

    init(service: NativePublicRoomServing = NativePublicRoomService()) { self.service = service }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        // Live availability must never be represented by a saved room list.
        rooms = []
        defer { isLoading = false }
        do {
            let result = try await service.rooms()
            try Task.checkCancellation()
            rooms = result
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "无法连接公开房间，请检查网络后重试。"
        }
    }
}
