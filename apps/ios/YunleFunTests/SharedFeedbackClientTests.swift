import Foundation
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

final class SharedFeedbackClientTests: XCTestCase {
    override func tearDown() { SharedFeedbackURLProtocol.fixture = nil; super.tearDown() }

    func testGuestRequestAndReviewedSubmissionUseCSRFAndIdempotencyWithNoAppToken() async throws {
        let receipt = sharedFeedbackTestRecord().receipt
        let fixture = ShareHTTPFixture(replies: [
            .json(["kind": "guest", "csrfToken": "fixture-csrf"], cookie: "__Host-ylf-support-guest=fixture-cookie; Secure; HttpOnly; Path=/"),
            .init(status: 200, data: try JSONEncoder().encode(["receipt": receipt]), contentType: "application/json", cookie: nil),
        ])
        let client = makeClient(fixture)
        let access = try await client.connectGuest()
        let image = try FeedbackScreenshot.prepare(sharedFeedbackTestImage())
        let submission = SupportFeedbackSubmission(product: "www", category: "problem", description: "  Shared screenshot description  ",
            screenshots: [image], context: .init(source: "apps-ios-share", version: "0.2.0 (4)"))
        let result = try await client.submit(submission, key: "stable-share-key", access: access)
        XCTAssertEqual(result, receipt)
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/v1/feedback/guest")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[1].url?.path, "/api/v1/private-feedback")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-csrf-token"), "fixture-csrf")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "idempotency-key"), "stable-share-key")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Origin"), "https://support.yunle.fun")
        XCTAssertTrue(requests[1].value(forHTTPHeaderField: "Cookie")?.contains("fixture-cookie") == true)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.url?.query == nil })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(body["description"] as? String, "Shared screenshot description")
        XCTAssertEqual(body["screenshots"] as? [[String: String]], [["mimeType": "image/jpeg", "data": image.data.base64EncodedString()]])
        XCTAssertEqual(body["context"] as? [String: String], ["source": "apps-ios-share", "version": "0.2.0 (4)"])
        XCTAssertNil(client.session.configuration.httpCookieStorage)
    }

    func testUnrelatedOrInsecureCookiesCannotInitializeTheGuest() async throws {
        for cookie in ["unrelated=fixture; Secure; HttpOnly; Path=/", "__Host-ylf-support-guest=fixture; HttpOnly; Path=/", "__Host-ylf-support-guest=fixture; Secure; Path=/"] {
            let fixture = ShareHTTPFixture(replies: [.json(["kind": "guest", "csrfToken": "fixture"], cookie: cookie)])
            do { _ = try await makeClient(fixture).connectGuest(); XCTFail() }
            catch { XCTAssertEqual(error as? SupportFeedbackError, .invalidResponse) }
        }
    }

    func testHTMLAndServerRejectionAreNeverReportedAsSuccess() async throws {
        let fixture = ShareHTTPFixture(replies: [
            .init(status: 200, data: Data("<html>fallback</html>".utf8), contentType: "text/html", cookie: nil),
            .json(["code": "INVALID_INPUT"], status: 413),
        ])
        let client = makeClient(fixture)
        do { _ = try await client.connectGuest(); XCTFail() }
        catch { XCTAssertEqual(error as? SupportFeedbackError, .invalidResponse) }
        let submission = SupportFeedbackSubmission(product: "www", category: "problem", description: "Valid synthetic description", screenshots: [])
        do { _ = try await client.submit(submission, key: "stable-share-key", access: .init(csrfToken: "fixture", cookies: [])); XCTFail() }
        catch { XCTAssertEqual(error as? SupportFeedbackError, .invalidScreenshot) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testInvalidPayloadAndHeaderAreRejectedBeforeAnyNetworkCall() async throws {
        let fixture = ShareHTTPFixture(replies: [])
        let client = makeClient(fixture)
        let submission = SupportFeedbackSubmission(product: "www", category: "problem", description: "Valid synthetic description", screenshots: [])
        do { _ = try await client.submit(submission, key: "unsafe-key\n", access: .init(csrfToken: "fixture", cookies: [])); XCTFail() }
        catch { XCTAssertEqual(error as? SupportFeedbackError, .invalidInput) }
        let shot = try FeedbackScreenshot.prepare(sharedFeedbackTestImage())
        let tooMany = SupportFeedbackSubmission(product: "www", category: "problem", description: "Valid synthetic description", screenshots: Array(repeating: shot, count: 4))
        do { _ = try await client.submit(tooMany, key: "stable-share-key", access: .init(csrfToken: "fixture", cookies: [])); XCTFail() }
        catch { XCTAssertEqual(error as? SupportFeedbackError, .invalidScreenshot) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    private func makeClient(_ fixture: ShareHTTPFixture) -> SupportFeedbackClient {
        SharedFeedbackURLProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.protocolClasses = [SharedFeedbackURLProtocol.self]
        return SupportFeedbackClient(session: URLSession(configuration: configuration))
    }
}

struct ShareHTTPReply {
    let status: Int
    let data: Data
    let contentType: String
    let cookie: String?
    static func json(_ value: [String: Any], status: Int = 200, cookie: String? = nil) -> Self {
        .init(status: status, data: try! JSONSerialization.data(withJSONObject: value), contentType: "application/json", cookie: cookie)
    }
}
final class ShareHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [URLRequest] = []
    private var replies: [ShareHTTPReply]
    init(replies: [ShareHTTPReply]) { self.replies = replies }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
    func take(_ request: URLRequest) -> ShareHTTPReply {
        lock.lock(); defer { lock.unlock() }; received.append(request)
        return replies.isEmpty ? .json([:], status: 500) : replies.removeFirst()
    }
}
final class SharedFeedbackURLProtocol: URLProtocol {
    static var fixture: ShareHTTPFixture?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
            recorded.httpBody = bytes
        }
        let reply = fixture.take(recorded)
        var headers = ["Content-Type": reply.contentType]
        if let cookie = reply.cookie { headers["Set-Cookie"] = cookie }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
