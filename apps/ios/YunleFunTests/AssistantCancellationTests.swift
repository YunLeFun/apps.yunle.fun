import XCTest
@testable import YunleFun

final class AssistantCancellationTests: XCTestCase {
    func testCancellingConsumerCancelsTheActualURLSessionTask() async throws {
        let host = UUID().uuidString.lowercased() + ".assistant.test", fixture = PendingAssistantHTTPFixture()
        PendingAssistantHTTPProtocol.register(host, fixture: fixture)
        defer { PendingAssistantHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PendingAssistantHTTPProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = AssistantService(session: session, gateway: URL(string: "https://\(host)")!)
        let stream = try await service.events(input: assistantInput, identity: .init(userID: "alice", accessToken: "fixture-only"))
        let received = expectation(description: "incremental content received before EOF")
        let consumer = Task {
            for try await event in stream {
                if event.type == "TEXT_MESSAGE_CONTENT" { received.fulfill() }
            }
        }
        await fulfillment(of: [received], timeout: 3)
        consumer.cancel()
        await fulfillment(of: [fixture.cancelled], timeout: 3)
        _ = await consumer.result
    }
}
private final class PendingAssistantHTTPFixture: @unchecked Sendable {
    let cancelled = XCTestExpectation(description: "URLProtocol stopLoading")
    private let lock = NSLock()
    private var stopped = false
    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true; cancelled.fulfill()
    }
}
private final class PendingAssistantHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: PendingAssistantHTTPFixture] = [:]
    private var fixture: PendingAssistantHTTPFixture?
    static func register(_ host: String, fixture: PendingAssistantHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[host] = fixture }
    static func unregister(_ host: String) { lock.lock(); defer { lock.unlock() }; fixtures[host] = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); fixture = Self.fixtures[request.url?.host ?? ""]; Self.lock.unlock()
        guard fixture != nil else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let body = "data: {\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"reply\",\"delta\":\"partial\"}\n\n"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        // Leave the request open so the only way out is consumer cancellation.
    }
    override func stopLoading() { fixture?.stop() }
}
