import Foundation

protocol AssistantServing: Sendable {
    func events(input: AssistantRunInput, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<AssistantEvent, Error>
    func search(query: String, identity: AuthorizedAccount) async throws -> [AssistantAppCard]
}
struct AssistantService: AssistantServing {
    static let botID = "agent-yunlefun-1g1ef4a470aefe98"
    let session: URLSession
    let gateway: URL
    let appsOrigin: URL
    init(session: URLSession? = nil, gateway: URL = CloudbaseAuthService.gateway, appsOrigin: URL = CatalogService.productionOrigin) {
        self.gateway = gateway; self.appsOrigin = appsOrigin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never; config.httpCookieStorage = nil
            config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: config, delegate: AssistantRedirectPolicy(), delegateQueue: nil)
        }
    }
    func events(input: AssistantRunInput, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<AssistantEvent, Error> {
        guard input.botId == Self.botID, (1...32).contains(input.messages.count),
              input.messages.allSatisfy({ $0.content.utf16.count <= 8000 }) else { throw AssistantError.tooLong }
        let body = try JSONEncoder().encode(input)
        guard body.count <= 128 * 1024 else { throw AssistantError.tooLong }
        let url = gateway.appendingPathComponent("v1/aibot/bots").appendingPathComponent(Self.botID).appendingPathComponent("send-message")
        var request = authorizedRequest(url: url, identity: identity)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept"); request.httpBody = body
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { bytes.task.cancel(); throw AssistantError.invalidResponse }
        guard http.statusCode == 200 else {
            defer { bytes.task.cancel() }
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 8192 { break }
            }
            let fields = (try? JSONSerialization.jsonObject(with: errorData)) as? [String: Any]
            if http.statusCode == 401 { throw AssistantError.unauthorized }
            if http.statusCode == 429 { throw AssistantError.quota }
            if http.statusCode == 403 {
                throw (fields?["code"] as? String) == "MEMBERSHIP_REQUIRED" ? AssistantError.membershipRequired : .forbidden
            }
            throw AssistantError.unavailable
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) == "text/event-stream" else {
            bytes.task.cancel(); throw AssistantError.invalidResponse
        }
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let worker = Task {
                defer { bytes.task.cancel() }
                do {
                    var decoder = AssistantSSEDecoder(), count = 0
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        count += 1; guard count <= 2 * 1024 * 1024 else { throw AssistantError.tooLong }
                        if let data = try decoder.append(byte) {
                            let event = try AssistantEvent(data: data)
                            if case .dropped = continuation.yield(event) { throw AssistantError.tooLong }
                            if ["RUN_FINISHED", "RUN_ERROR", "_DONE"].contains(event.type ?? "") { continuation.finish(); return }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel(); bytes.task.cancel() }
        }
    }
    func search(query: String, identity: AuthorizedAccount) async throws -> [AssistantAppCard] {
        var request = authorizedRequest(url: appsOrigin.appendingPathComponent("api/agent/search-apps"), identity: identity)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": String(query.prefix(120)), "limit": 6])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        if http.statusCode == 401 { throw AssistantError.unauthorized }
        guard http.statusCode == 200, data.count <= 512 * 1024,
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any], (fields["code"] as? Int) == 0 else { throw AssistantError.unavailable }
        return try AssistantEvent.extractCards(fields["data"])
    }
    private func authorizedRequest(url: URL, identity: AuthorizedAccount) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
private final class AssistantRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
