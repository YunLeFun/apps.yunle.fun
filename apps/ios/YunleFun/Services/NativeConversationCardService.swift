import Foundation

protocol NativeConversationCardServing: Sendable {
    func load(_ reference: ConversationCardReference, identity: AuthorizedAccount) async throws -> NativeConversationCardSnapshot
    func act(_ action: NativeConversationCardAction, on reference: ConversationCardReference,
             identity: AuthorizedAccount) async throws -> NativeConversationCardSnapshot
    func events(_ reference: ConversationCardReference, identity: AuthorizedAccount)
        async throws -> AsyncThrowingStream<NativeConversationCardSnapshot, Error>
}

struct NativeConversationCardService: NativeConversationCardServing {
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

    func load(_ reference: ConversationCardReference, identity: AuthorizedAccount) async throws -> NativeConversationCardSnapshot {
        try await send(request(reference, identity: identity), for: reference)
    }

    func act(_ action: NativeConversationCardAction, on reference: ConversationCardReference,
             identity: AuthorizedAccount) async throws -> NativeConversationCardSnapshot {
        var request = request(reference, identity: identity)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(action)
        return try await send(request, for: reference)
    }

    func events(_ reference: ConversationCardReference, identity: AuthorizedAccount)
        async throws -> AsyncThrowingStream<NativeConversationCardSnapshot, Error> {
        let request = request(reference, identity: identity, streaming: true)
        let (bytes, response) = try await session.bytes(for: request)
        do { try check(response, against: request, contentType: "text/event-stream") }
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
                        guard byteCount <= 2 * 1024 * 1024 else { throw NativeConversationCardError.unavailable }
                        if let data = try decoder.append(byte) {
                            continuation.yield(try Self.decode(data, for: reference))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel(); bytes.task.cancel() }
        }
    }

    private func request(_ reference: ConversationCardReference, identity: AuthorizedAccount, streaming: Bool = false) -> URLRequest {
        let root = origin.appendingPathComponent("api/conversation-cards")
            .appendingPathComponent(reference.type).appendingPathComponent(reference.instanceId)
        let url = streaming ? root.appendingPathComponent("events") : root
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest, for reference: ConversationCardReference) async throws -> NativeConversationCardSnapshot {
        let (data, response) = try await session.data(for: request)
        try check(response, against: request, contentType: "application/json")
        return try Self.decode(data, for: reference)
    }

    private func check(_ value: URLResponse, against request: URLRequest, contentType: String) throws {
        guard let response = value as? HTTPURLResponse, response.url == request.url else { throw NativeConversationCardError.unavailable }
        switch response.statusCode {
        case 401: throw NativeConversationCardError.unauthorized
        case 403: throw NativeConversationCardError.forbidden
        case 404: throw NativeConversationCardError.missing
        case 409: throw NativeConversationCardError.conflict
        case 200 where response.mimeType?.lowercased() == contentType: return
        default: throw NativeConversationCardError.unavailable
        }
    }

    private static func decode(_ data: Data, for reference: ConversationCardReference) throws -> NativeConversationCardSnapshot {
        guard data.count <= 32 * 1024 else { throw NativeConversationCardError.unavailable }
        // Stream failures must be retried. Unknown schema or components fall back to the message summary.
        if let failure = try? JSONDecoder().decode(StreamFailure.self, from: data), failure.error == "CARD_UNAVAILABLE" {
            throw NativeConversationCardError.unavailable
        }
        guard let snapshot = try? JSONDecoder().decode(NativeConversationCardSnapshot.self, from: data)
        else { throw NativeConversationCardError.unsupported }
        try snapshot.validate(for: reference)
        return snapshot
    }

    private struct StreamFailure: Decodable { let error: String }
}
