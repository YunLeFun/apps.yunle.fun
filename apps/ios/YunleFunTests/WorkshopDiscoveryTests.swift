import XCTest
@testable import YunleFun

final class WorkshopDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_145_600)

    func testEditorialReferencesOnlySelectCurrentPublicApplications() throws {
        let publicApp = CloudApplication(id: "approved", name: "获批名称", websiteUrl: "https://example.invalid/approved")
        let privateApp = CloudApplication(id: "private", name: "坊客作品", audience: "workshop", accessWorkshopID: "ABC234")
        let ownerApp = CloudApplication(id: "owner", name: "作者作品", accessOwnerID: "owner")
        let personalApp = CloudApplication(id: "personal", name: "个人当前修订", personalMarketOwnerLogin: "author")
        let removed = CloudApplication(id: "removed", name: "已下架", isUnavailable: true)
        let references = [publicApp, privateApp, ownerApp, personalApp, removed].map {
            WorkshopDiscoveryPayload.Featured(appId: $0.id, title: "编辑标题", subtitle: nil, startsAt: 0,
                                               expiresAt: now.addingTimeInterval(60).timeIntervalSince1970 * 1_000)
        }
        let payload = WorkshopDiscoveryPayload(schemaVersion: 1, generatedAt: now.timeIntervalSince1970 * 1_000,
                                               featured: references, weeklyChart: nil)
        let result = payload.selection(from: [publicApp, privateApp, ownerApp, personalApp, removed], now: now)
        XCTAssertEqual(result.featured.map(\.application.id), ["approved"])
        XCTAssertEqual(result.featured.first?.application.name, "获批名称")
        XCTAssertEqual(result.featured.first?.application.websiteUrl, "https://example.invalid/approved")
        XCTAssertEqual(result.featured.first?.title, "编辑标题")
    }

    func testExpiredAndFutureRecommendationsDoNotBecomeFallbackRankings() {
        let app = CloudApplication(id: "app", name: "应用")
        let time = now.timeIntervalSince1970 * 1_000
        let payload = WorkshopDiscoveryPayload(schemaVersion: 1, generatedAt: time, featured: [
            .init(appId: app.id, title: nil, subtitle: nil, startsAt: 0, expiresAt: time),
            .init(appId: app.id, title: nil, subtitle: nil, startsAt: time + 1, expiresAt: time + 100),
        ], weeklyChart: nil)
        let result = payload.selection(from: [app], now: now)
        XCTAssertTrue(result.featured.isEmpty)
        XCTAssertTrue(result.weekly.isEmpty)
    }

    func testWeeklyRankKeepsRealRankAndDropsMissingOrDuplicateReferences() {
        let apps = [CloudApplication(id: "first", name: "第一"), CloudApplication(id: "third", name: "第三")]
        let week = WorkshopDiscoveryPayload.weekStart(at: now)
        let payload = WorkshopDiscoveryPayload(schemaVersion: 1, generatedAt: now.timeIntervalSince1970 * 1_000, featured: [],
            weeklyChart: .init(weekStart: week, items: [
                .init(appId: "private", rank: 2), .init(appId: "third", rank: 3),
                .init(appId: "first", rank: 1), .init(appId: "third", rank: 4),
                .init(appId: "first", rank: 11),
            ]))
        let result = payload.selection(from: apps, now: now)
        XCTAssertEqual(result.weekly.map(\.application.id), ["first", "third"])
        XCTAssertEqual(result.weekly.map(\.rank), [1, 3])
        let stale = WorkshopDiscoveryPayload(schemaVersion: 1, generatedAt: 0, featured: [],
            weeklyChart: .init(weekStart: week - 7 * 86_400_000, items: [.init(appId: "first", rank: 1)]))
        XCTAssertTrue(stale.selection(from: apps, now: now).weekly.isEmpty)
    }

    func testWeekUsesShanghaiMondayEvenWhenUTCDayDiffers() throws {
        let formatter = ISO8601DateFormatter()
        let sundayUTC = try XCTUnwrap(formatter.date(from: "2026-10-25T17:00:00Z"))
        let mondayShanghai = try XCTUnwrap(formatter.date(from: "2026-10-25T16:00:00Z"))
        XCTAssertEqual(WorkshopDiscoveryPayload.weekStart(at: sundayUTC), mondayShanghai.timeIntervalSince1970 * 1_000)
    }

    func testServiceRequiresVersionedJSONAndNeverAddsHostCredentials() async throws {
        let host = UUID().uuidString.lowercased() + ".invalid"
        let fixture = AuthHTTPFixture(replies: [(200, "{\"schemaVersion\":1,\"generatedAt\":1793145600000,\"featured\":[],\"weeklyChart\":null}"),
                                               (200, "{\"schemaVersion\":99,\"generatedAt\":1793145600000,\"featured\":[],\"weeklyChart\":null}")])
        AuthHTTPProtocol.register(host, fixture: fixture)
        defer { AuthHTTPProtocol.unregister(host) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthHTTPProtocol.self]
        let service = WorkshopDiscoveryService(session: URLSession(configuration: configuration), origin: URL(string: "https://\(host)")!)
        let payload = try await service.discovery()
        XCTAssertTrue(payload.featured.isEmpty)
        XCTAssertNil(payload.weeklyChart)
        do { _ = try await service.discovery(); XCTFail("Unknown discovery schema must fail closed") }
        catch CatalogError.invalidResponse { }
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/api/catalog/discovery")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
}
