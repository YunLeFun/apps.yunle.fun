import XCTest
@testable import YunleFun

final class HomeSyncHTTPTests: XCTestCase {
    private var hosts: [String] = []
    private let empty = #"{"schemaVersion":1,"revision":null,"configuration":{"installedApps":[],"dockApps":[],"recentApps":[],"updatedAt":0}}"#
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); hosts = []; super.tearDown() }

    func testWriteSendsExplicitNullBaseWithoutClientUIDOrCookies() async throws {
        let saved = RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: HomeConfiguration(updatedAt: 100))
        let (service, fixture) = service([(200, String(decoding: try JSONEncoder().encode(saved), as: UTF8.self))])
        let write = HomeScreenWrite(baseRevision: nil, mutationId: UUID().uuidString, configuration: HomeConfiguration())
        _ = try await service.save(write, identity: AuthorizedAccount(userID: "test-owner", accessToken: "test-token"))
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/api/home-screen")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body(request)) as? [String: Any])
        XCTAssertTrue(json["baseRevision"] is NSNull)
        XCTAssertNil(json["uid"])
        XCTAssertNil(json["_openid"])
        XCTAssertEqual(json["mutationId"] as? String, write.mutationId)
    }

    func testAConflictCarriesTheRemoteVersionInsteadOfBecomingAnEmptySuccess() async throws {
        let remote = RemoteHomeScreen(revision: String(repeating: "a", count: 64),
                                      configuration: HomeConfiguration(installedApps: [HomeAppReference(appId: "remote")], updatedAt: 100))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(remote))
        let payload = try JSONSerialization.data(withJSONObject: ["data": ["code": "HOME_CONFLICT", "current": object]])
        let (service, _) = service([(409, String(decoding: payload, as: UTF8.self))])
        do { _ = try await service.load(identity: AuthorizedAccount(userID: "test-owner", accessToken: "test-token")); XCTFail() }
        catch HomeSyncError.conflict(let received) { XCTAssertEqual(received, remote) }
    }

    func testFailuresAndMalformedResponsesCannotEraseLocalData() async {
        let (service, _) = service([
            (503, "{}"), (401, "{}"), (200, "{}"),
            (200, #"{"schemaVersion":1,"configuration":{"installedApps":[],"dockApps":[],"recentApps":[],"updatedAt":0}}"#),
        ])
        for _ in 0..<4 {
            do { _ = try await service.load(identity: AuthorizedAccount(userID: "test-owner", accessToken: "test-token")); XCTFail() }
            catch { XCTAssertTrue(error is HomeSyncError) }
        }
    }

    func testSaveRejectsAnAcknowledgementForDifferentContent() async throws {
        let saved = RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: HomeConfiguration(updatedAt: 100))
        let (service, _) = service([(200, String(decoding: try JSONEncoder().encode(saved), as: UTF8.self))])
        let write = HomeScreenWrite(baseRevision: nil, mutationId: UUID().uuidString,
                                    configuration: HomeConfiguration(installedApps: [HomeAppReference(appId: "local")]))
        do { _ = try await service.save(write, identity: AuthorizedAccount(userID: "test-owner", accessToken: "test-token")); XCTFail() }
        catch { guard case HomeSyncError.invalidResponse = error else { return XCTFail("Unexpected error") } }
    }

    private func service(_ replies: [(Int, String)]) -> (HomeSyncService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies)
        AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPProtocol.self]
        return (HomeSyncService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
    private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
