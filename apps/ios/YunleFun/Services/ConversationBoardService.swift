import Foundation

protocol ConversationBoardServing: Sendable {
    func load(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot
    func create(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot
    func act(_ action: ConversationBoardAction, id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot
    func events(id: String, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<ConversationBoardSnapshot, Error>
}

struct ConversationBoardService: ConversationBoardServing {
    let session: URLSession
    let origin: URL

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 35
            self.session = URLSession(configuration: configuration, delegate: ConversationCardNoRedirects(), delegateQueue: nil)
        }
    }

    func load(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot {
        try await send(request(id: id, identity: identity), id: id)
    }

    func create(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot {
        var request = try request(id: id, identity: identity)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try await send(request, id: id)
    }

    func act(_ action: ConversationBoardAction, id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot {
        var request = try request(id: id, identity: identity)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(action)
        return try await send(request, id: id)
    }

    func events(id: String, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<ConversationBoardSnapshot, Error> {
        var request = try request(id: id, identity: identity, events: true)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        do { try check(response, request: request, contentType: "text/event-stream") }
        catch { bytes.task.cancel(); throw error }
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let worker = Task {
                defer { bytes.task.cancel() }
                var decoder = AssistantSSEDecoder()
                var byteCount = 0
                do {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        byteCount += 1
                        guard byteCount <= 2 * 1024 * 1024 else { throw ConversationBoardError.unavailable }
                        if let data = try decoder.append(byte) {
                            let snapshot = try Self.decode(data, id: id)
                            continuation.yield(snapshot)
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel(); bytes.task.cancel() }
        }
    }

    private func request(id: String, identity: AuthorizedAccount, events: Bool = false) throws -> URLRequest {
        guard ConversationCard.validInstanceID(id) else { throw ConversationBoardError.invalidCommand }
        let root = origin.appendingPathComponent("api/boards").appendingPathComponent(id)
        let url = events ? root.appendingPathComponent("events") : root
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest, id: String) async throws -> ConversationBoardSnapshot {
        let (data, response) = try await session.data(for: request)
        try check(response, request: request, contentType: "application/json")
        return try Self.decode(data, id: id)
    }

    private func check(_ value: URLResponse, request: URLRequest, contentType: String) throws {
        guard let response = value as? HTTPURLResponse, response.url == request.url else { throw ConversationBoardError.unavailable }
        switch response.statusCode {
        case 401: throw ConversationBoardError.unauthorized
        case 403: throw ConversationBoardError.forbidden
        case 404: throw ConversationBoardError.missing
        case 409: throw ConversationBoardError.conflict
        case 200 where response.mimeType?.lowercased() == contentType: return
        default: throw ConversationBoardError.unavailable
        }
    }

    private static func decode(_ data: Data, id: String) throws -> ConversationBoardSnapshot {
        guard data.count <= 24 * 1024,
              let snapshot = try? JSONDecoder().decode(ConversationBoardSnapshot.self, from: data)
        else { throw ConversationBoardError.unavailable }
        try snapshot.validate(for: id)
        return snapshot
    }
}
