import XCTest
@testable import YunleFun

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
