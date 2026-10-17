import XCTest
@testable import YunleFun

private let diagnosticNow = Date(timeIntervalSince1970: 1_800_000_000)

final class DiagnosticServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(DiagnosticHTTPProtocol.unregister); super.tearDown() }

    func testEndpointHeadersMillisecondsAndClientOwnedFieldsMatchTheRealProtocol() async throws {
        let (service, fixture) = makeService([.json(200, receiptBody())])
        let payload = diagnosticPayload(at: diagnosticNow)
        let receipt = try await service.upload(payload, identity: identity)
        XCTAssertEqual(receipt.supportCode, "ABCDEF012345")
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/api/diagnostics/logs")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["startTime", "endTime", "issueDescription", "logs", "client"]))
        XCTAssertEqual(fields["endTime"] as? Double, diagnosticNow.timeIntervalSince1970 * 1000)
        XCTAssertGreaterThan(try XCTUnwrap(fields["startTime"] as? Double), 1_000_000_000_000)
        XCTAssertNil(fields["ownerUid"])
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticUploadPayload.self, from: requestBody(request)), payload)
    }

    func testInjectedSessionsStillDisableCookiesCredentialsCacheAndRedirects() throws {
        let (service, _) = makeService([])
        let configuration = service.session.configuration
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        let delegate = try XCTUnwrap(service.session.delegate as? URLSessionTaskDelegate)
        let url = URL(string: "https://redirect.invalid/api/diagnostics/logs")!
        let task = service.session.dataTask(with: url)
        defer { task.cancel() }
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://elsewhere.invalid/"])!
        let rejected = expectation(description: "redirect rejected")
        delegate.urlSession?(service.session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: "https://elsewhere.invalid/")!)) { request in
            XCTAssertNil(request); rejected.fulfill()
        }
        wait(for: [rejected], timeout: 1)
    }

    func testMIMEAndResponseBoundsAreCheckedBeforeUnauthorized() async throws {
        let (service, fixture) = makeService([
            .response(401, "text/html", Data("<html>private-secret</html>".utf8)),
            .response(401, "application/json", Data(repeating: 32, count: DiagnosticUploadRules.maximumResponseBytes + 1)),
            .json(401, "{}"), .json(403, "{}")])
        for expected in [DiagnosticError.invalidResponse, .invalidResponse, .unauthorized, .forbidden] {
            do { _ = try await service.upload(diagnosticPayload(at: diagnosticNow), identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? DiagnosticError, expected); XCTAssertFalse(DiagnosticError.safe(error).message.contains("private-secret")) }
        }
        XCTAssertEqual(fixture.requests.count, 4)
    }

    func testRangeUTF16CountAndByteBoundsFailBeforeAnyRequest() async throws {
        let (service, fixture) = makeService([])
        let valid = diagnosticPayload(at: diagnosticNow)
        let values: [(DiagnosticUploadPayload, DiagnosticError)] = [
            (payload(valid, start: valid.endTime + 1), .invalidRange),
            (payload(valid, start: valid.endTime - 86_401_000), .invalidRange),
            (payload(valid, start: valid.endTime - DiagnosticUploadRules.retention - 1), .invalidRange),
            (payload(valid, end: valid.endTime + DiagnosticUploadRules.clockSkew + 1), .invalidRange),
            (payload(valid, start: valid.startTime / 1000, end: valid.endTime / 1000), .invalidRange),
            (payload(valid, start: .nan), .invalidRange),
            (payload(valid, description: String(repeating: "😀", count: 251)), .invalidInput),
            (payload(valid, logs: []), .emptyLogs),
            (payload(valid, logs: Array(repeating: valid.logs[0], count: 501)), .tooLarge),
            (payload(valid, logs: [.init(level: .info, message: String(repeating: "a", count: 4001), timestamp: valid.endTime)]), .tooLarge),
            (payload(valid, logs: [.init(level: .info, message: "outside", timestamp: valid.endTime + 1)]), .invalidRange),
            (payload(valid, logs: Array(repeating: .init(level: .info, message: String(repeating: "中", count: 1500), timestamp: valid.endTime), count: 100)), .tooLarge)
        ]
        for (value, expected) in values {
            do { _ = try await service.upload(value, identity: identity); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? DiagnosticError, expected) }
        }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testRangeAndMessageNormalizationPreserveTheServerBoundary() throws {
        let valid = diagnosticPayload(at: diagnosticNow)
        let start = valid.endTime - 86_400_999
        let input = payload(valid, start: start + 0.9, end: valid.endTime + 0.9,
                            logs: [.init(level: .warn, message: String(repeating: "😀", count: 1000), timestamp: start + 0.9)])
        let normalized = try DiagnosticUploadRules.normalize(input, now: valid.endTime)
        XCTAssertEqual(normalized.startTime, start)
        XCTAssertEqual(normalized.endTime, valid.endTime)
        XCTAssertEqual(normalized.logs[0].timestamp, start)
        XCTAssertLessThanOrEqual(normalized.logs[0].message.utf16.count, 1500)
        XCTAssertEqual(try DiagnosticUploadRules.sizeBytes(normalized),
                       try DiagnosticUploadRules.encoder().encode(normalized.logs).count
                       + DiagnosticUploadRules.encoder().encode(normalized.client).count + normalized.issueDescription.utf8.count)
    }

    func testClientFieldsUseUTF16LimitsAndAreRedactedBeforeEncoding() throws {
        let base = diagnosticPayload(at: diagnosticNow)
        let input = DiagnosticUploadPayload(startTime: base.startTime, endTime: base.endTime,
            issueDescription: "Bearer private-token", logs: base.logs,
            client: .init(appVersion: String(repeating: "😀", count: 100), buildNumber: String(repeating: "b", count: 100),
                platform: String(repeating: "i", count: 100), route: "https://example.com/private?signature=secret",
                timezone: String(repeating: "区", count: 200), userAgent: "user@example.com " + String(repeating: "a", count: 600)))
        let normalized = try DiagnosticUploadRules.normalize(input, now: base.endTime)
        XCTAssertEqual(normalized.client.appVersion.utf16.count, 50)
        XCTAssertEqual(normalized.client.buildNumber.utf16.count, 50)
        XCTAssertEqual(normalized.client.platform.utf16.count, 20)
        XCTAssertEqual(normalized.client.timezone.utf16.count, 100)
        XCTAssertLessThanOrEqual(normalized.client.userAgent.utf16.count, 500)
        let body = String(decoding: try DiagnosticUploadRules.encoder().encode(normalized), as: UTF8.self)
        XCTAssertFalse(body.contains("private-token")); XCTAssertFalse(body.contains("signature=secret"))
        XCTAssertFalse(body.contains("user@example.com"))
    }

    func testDescriptionRemainsCanonicalWhenRedactionExpansionEndsAtWhitespace() throws {
        let base = diagnosticPayload(at: diagnosticNow)
        let raw = String(repeating: "x", count: 482) + " token=a y"
        XCTAssertLessThanOrEqual(raw.utf16.count, 500)
        let normalized = try DiagnosticUploadRules.normalize(payload(base, description: raw), now: base.endTime)
        XCTAssertEqual(normalized.issueDescription, String(repeating: "x", count: 482) + " token=[redacted]")
        XCTAssertEqual(normalized.issueDescription.utf16.count, 499)
        XCTAssertEqual(try DiagnosticUploadRules.normalize(normalized, now: base.endTime), normalized,
                       "A newly frozen payload must survive the same normalization used by confirmation validation and transport")
    }

    func testJSONDescriptionEscapingDoesNotConsumeTheAPILogBudget() async throws {
        let base = diagnosticPayload(at: diagnosticNow)
        let description = String(repeating: "\u{0001}", count: 500)
        let client = diagnosticClient()
        let clientFields = ["appVersion": client.appVersion, "buildNumber": client.buildNumber,
                            "platform": client.platform, "route": client.route, "timezone": client.timezone, "userAgent": client.userAgent]
        let clientBytes = try JSONSerialization.data(withJSONObject: clientFields, options: [.withoutEscapingSlashes]).count
        // Calculate the backend's documented budget independently of the production helper.
        func protocolBytes(_ entries: [DiagnosticLogEntry]) throws -> Int {
            let fields: [[String: Any]] = entries.map {
                ["level": $0.level.rawValue, "message": $0.message, "timestamp": Int64($0.timestamp)]
            }
            return try JSONSerialization.data(withJSONObject: fields, options: [.withoutEscapingSlashes]).count
                + clientBytes + description.utf8.count
        }
        let full = DiagnosticLogEntry(level: .info, message: String(repeating: "x", count: 1500), timestamp: base.endTime)
        var logs = Array(repeating: full, count: 160)
        while try protocolBytes(logs + [full]) <= 256 * 1024 { logs.append(full) }
        let emptyTail = DiagnosticLogEntry(level: .info, message: "", timestamp: base.endTime)
        let remaining = 256 * 1024 - (try protocolBytes(logs + [emptyTail]))
        guard (1...1500).contains(remaining) else { return XCTFail("The near-limit fixture must leave room for one nonempty log") }
        logs.append(DiagnosticLogEntry(level: .info, message: String(repeating: "x", count: remaining), timestamp: base.endTime))
        XCTAssertEqual(try protocolBytes(logs), 256 * 1024)
        let input = DiagnosticUploadPayload(startTime: base.startTime, endTime: base.endTime,
            issueDescription: description, logs: logs, client: client)
        let (service, fixture) = makeService([.json(200, receiptBody(count: logs.count))])
        let receipt = try await service.upload(input, identity: identity)
        XCTAssertEqual(receipt.logCount, logs.count)
        XCTAssertEqual(fixture.requests.count, 1)
        let body = try requestBody(XCTUnwrap(fixture.requests.first))
        XCTAssertGreaterThan(body.count, 256 * 1024 + 1024, "Escaping overhead exceeds the previous extra-body allowance")
        XCTAssertLessThanOrEqual(body.count, DiagnosticUploadRules.maximumBodyBytes)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticUploadPayload.self, from: body), input)
    }

    func testReceiptRequiresCodeIdentifierCountAndPlausibleMillisecondExpiry() async throws {
        let expiry = diagnosticNow.timeIntervalSince1970 * 1000 + DiagnosticUploadRules.retention
        let bodies = [receiptBody(code: 1), receiptBody(supportCode: "bad"), receiptBody(uploadID: "../escape"),
                      receiptBody(count: 2), receiptBody(expires: expiry / 1000), receiptBody(expires: expiry + 0.5),
                      receiptBody(expires: expiry + DiagnosticUploadRules.clockSkew + 1),
                      receiptBody(expires: expiry - DiagnosticUploadRules.clockSkew - 1), "{}"]
        let (service, _) = makeService(bodies.map { .json(200, $0) })
        for _ in bodies {
            do { _ = try await service.upload(diagnosticPayload(at: diagnosticNow), identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? DiagnosticError, .invalidResponse) }
        }
        let (emptyIDService, _) = makeService([.json(200, receiptBody(uploadID: ""))])
        let value = try await emptyIDService.upload(diagnosticPayload(at: diagnosticNow), identity: identity)
        XCTAssertEqual(value.uploadId, "", "The support code remains usable when the backend's optional upload ID is empty")
    }

    func testHTTPFailuresAndTimeoutNeverEchoBodyOrRetryAutomatically() async throws {
        let (service, fixture) = makeService([.json(400, "{\"message\":\"private-token\"}"), .json(413, "{}"),
            .json(429, "{}"), .json(503, "{}"), .failure(URLError(.timedOut))])
        for expected in [DiagnosticError.invalidInput, .tooLarge, .throttled, .unavailable, .outcomeUnknown] {
            do { _ = try await service.upload(diagnosticPayload(at: diagnosticNow), identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? DiagnosticError, expected); XCTAssertFalse(DiagnosticError.safe(error).message.contains("private-token")) }
        }
        XCTAssertEqual(fixture.requests.count, 5)
    }

    private var identity: AuthorizedAccount { .init(userID: "fixture-user", accessToken: "fixture-only") }
    private func makeService(_ replies: [DiagnosticHTTPFixture.Reply]) -> (DiagnosticService, DiagnosticHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".diagnostics.test"; hosts.append(host)
        let fixture = DiagnosticHTTPFixture(replies); DiagnosticHTTPProtocol.register(host, fixture)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [DiagnosticHTTPProtocol.self]
        return (DiagnosticService(session: URLSession(configuration: configuration), origin: URL(string: "https://\(host)")!, now: { diagnosticNow }), fixture)
    }
    private func payload(_ base: DiagnosticUploadPayload, start: Double? = nil, end: Double? = nil,
                         description: String? = nil, logs: [DiagnosticLogEntry]? = nil) -> DiagnosticUploadPayload {
        .init(startTime: start ?? base.startTime, endTime: end ?? base.endTime,
              issueDescription: description ?? base.issueDescription, logs: logs ?? base.logs, client: base.client)
    }
    private func receiptBody(code: Int = 0, uploadID: String = "upload-one", supportCode: String = "ABCDEF012345",
                             count: Int = 1, expires: Double? = nil) -> String {
        let receipt = DiagnosticUploadReceipt(uploadId: uploadID, supportCode: supportCode, logCount: count,
            expiresAt: expires ?? diagnosticNow.timeIntervalSince1970 * 1000 + DiagnosticUploadRules.retention)
        let body = try! JSONSerialization.data(withJSONObject: ["code": code, "data": JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt))])
        return String(decoding: body, as: UTF8.self)
    }
    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }; data.append(buffer, count: count)
        }
        return data
    }
}

func diagnosticClient() -> DiagnosticClientContext {
    .init(appVersion: "0.1.0", buildNumber: "1", platform: "ios", route: "/feedback", timezone: "Asia/Shanghai", userAgent: "YunleFun/iOS")
}
func diagnosticPayload(at date: Date) -> DiagnosticUploadPayload {
    let end = date.timeIntervalSince1970 * 1000
    return .init(startTime: end - 60_000, endTime: end, issueDescription: "界面没有响应",
                 logs: [.init(level: .info, message: "host.screen.ready", timestamp: end)], client: diagnosticClient())
}

private final class DiagnosticHTTPFixture: @unchecked Sendable {
    enum Reply {
        case response(Int, String, Data), failure(URLError)
        static func json(_ status: Int, _ body: String) -> Reply { .response(status, "application/json", Data(body.utf8)) }
    }
    private let lock = NSLock()
    private var replies: [Reply]
    private var captured: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    func take(_ request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }; captured.append(request)
        return replies.isEmpty ? .failure(URLError(.resourceUnavailable)) : replies.removeFirst()
    }
}
private final class DiagnosticHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: DiagnosticHTTPFixture] = [:]
    static func register(_ host: String, _ fixture: DiagnosticHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[host] = fixture }
    static func unregister(_ host: String) { lock.lock(); defer { lock.unlock() }; fixtures.removeValue(forKey: host) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".diagnostics.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixtures[request.url?.host ?? ""]; Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        switch fixture.take(request) {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .response(let status, let mime, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
