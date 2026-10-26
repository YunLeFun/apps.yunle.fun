import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class CatalogTests: XCTestCase {
    func testDecodesPublicCatalogContractAndStableIdentity() throws {
        let data = Data("""
        {"items":[{"_id":"record-1","name":"今天来做菜","slug":"cook","marketShortName":"cook","category":"应用","websiteUrl":"https://cook.yunle.fun/","iconAssets":{"appIcon":{"src":"https://cook.yunle.fun/icon.svg"}},"extraFutureField":true}]}
        """.utf8)
        struct Envelope: Decodable { let items: [CloudApplication] }
        let app = try JSONDecoder().decode(Envelope.self, from: data).items[0]
        XCTAssertEqual(app.id, "record-1")
        XCTAssertEqual(app.publicKey, "cook")
        XCTAssertEqual(app.browseCategory, "生活方式")
        XCTAssertEqual(app.iconURL?.absoluteString, "https://cook.yunle.fun/icon.svg")
        XCTAssertTrue(app.canOpenAsGuest)
        XCTAssertEqual(try JSONDecoder().decode(CloudApplication.self, from: JSONEncoder().encode(app)), app)
    }

    func testLaunchPoliciesPreserveAccessAndCanonicalDomains() {
        var app = CloudApplication(id: "record-1", name: "应用", slug: "give-me-money", websiteUrl: "https://old.example")
        XCTAssertEqual(app.launchURL?.host, "gmm.yunle.fun")
        app.accessMode = "invite_only"
        XCTAssertFalse(app.canOpenAsGuest)
        app.accessMode = "future_restricted_mode"
        XCTAssertFalse(app.canOpenAsGuest)
        app.accessMode = "public"
        app.requiresMembership = true
        XCTAssertFalse(app.canOpenAsGuest)
        app.requiresMembership = false
        app.coinCost = 1
        XCTAssertFalse(app.canOpenAsGuest)
        app.coinCost = 0
        app.slug = "custom"
        for url in ["javascript:alert(1)", "http://example.com", "file:///tmp/test", "https://user:password@example.com"] {
            app.websiteUrl = url
            XCTAssertNil(app.launchURL)
        }
    }

    func testPublisherCategoryTakesPrecedenceOverLegacyOverride() {
        let app = CloudApplication(id: "record-1", name: "食谱", slug: "cook", category: "开发")
        XCTAssertEqual(app.browseCategory, "开发")
        XCTAssertTrue(app.matches("食谱"))
        XCTAssertFalse(app.matches("不存在"))
    }

    func testLegacyRatingWithoutPublishedReviewsIsNotDisplayed() {
        var app = CloudApplication(id: "a", name: "应用", rating: 4.8)
        XCTAssertNil(app.displayRating)
        app.ratingCount = 0
        XCTAssertNil(app.displayRating)
        app.ratingCount = 12
        XCTAssertEqual(app.displayRating, 4.8)
        app.rating = 6
        XCTAssertNil(app.displayRating)
    }

    func testCatalogDoesNotTurnAnHTTPFailureIntoAnEmptySuccess() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailureProtocol.self]
        let service = CatalogService(session: URLSession(configuration: config))
        do {
            _ = try await service.applications()
            XCTFail("A failed catalog must remain an explicit error")
        } catch CatalogError.http(let code) {
            XCTAssertEqual(code, 503)
        }
    }

    func testUnavailablePublicAppReadsOnlyWhitelistedReasonsWithoutAuthentication() async throws {
        for reason in ["not_listed", "delisted", "suspended", "unavailable", "future-reason"] {
            let (service, fixture, host) = availabilityService(status: 404,
                body: "{\"data\":{\"code\":\"APP_UNAVAILABLE\",\"reasonCode\":\"\(reason)\",\"reason\":\"private notes\"}}")
            defer { AuthHTTPProtocol.unregister(host) }
            do { _ = try await service.application(reference: "legacy-key"); XCTFail("An unavailable entry must remain unavailable") }
            catch let value as ApplicationUnavailableReason {
                XCTAssertEqual(value, ApplicationUnavailableReason(rawValue: reason) ?? .unavailable)
                XCTAssertFalse(value.message.contains("private notes"))
            }
            let request = try XCTUnwrap(fixture.requests.first)
            XCTAssertEqual(request.url?.path, "/api/apps/public/legacy-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }

    func testAvailabilityRejectsHTMLAndServerFailuresInsteadOfReportingDelisting() async throws {
        for (status, contentType, body) in [(200, "text/html", "<html>fallback</html>"), (503, "application/json", "{}"),
                                         (404, "application/json", "not-json")] {
            let (service, _, host) = availabilityService(status: status, body: body, contentType: contentType)
            defer { AuthHTTPProtocol.unregister(host) }
            do { _ = try await service.application(reference: "legacy-key"); XCTFail("A failed check cannot prove availability") }
            catch is ApplicationUnavailableReason { XCTFail("A malformed response or service failure is not a confirmed removal") }
            catch { }
        }
    }

    func testRelistedAppMustMatchTheRequestedPublicIdentity() async throws {
        let (service, _, host) = availabilityService(status: 200,
            body: #"{"app":{"_id":"canonical-id","name":"恢复的应用","marketShortName":"legacy-key","websiteUrl":"https://example.test/"}}"#)
        defer { AuthHTTPProtocol.unregister(host) }
        let restored = try await service.application(reference: "legacy-key")
        XCTAssertEqual(restored.id, "canonical-id")
        let (other, _, otherHost) = availabilityService(status: 200,
            body: #"{"app":{"_id":"other","name":"其他应用","slug":"legacy-key"}}"#)
        defer { AuthHTTPProtocol.unregister(otherHost) }
        do { _ = try await other.application(reference: "legacy-key"); XCTFail("A private slug cannot select another application") }
        catch CatalogError.invalidResponse { }
    }

    private func availabilityService(status: Int, body: String, contentType: String = "application/json") -> (CatalogService, AuthHTTPFixture, String) {
        let host = UUID().uuidString.lowercased() + ".availability.test"
        let fixture = AuthHTTPFixture(replies: [(status, body)], contentType: contentType)
        AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (CatalogService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture, host)
    }
}

private final class FailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"items\":[]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
