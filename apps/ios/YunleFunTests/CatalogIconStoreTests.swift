import Combine
import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class CatalogIconManifestTests: XCTestCase {
    func testWebsiteRegistryUsesExactOriginsAndUpdatesPrivateAppsWithoutPublicSlugInheritance() throws {
        let entry = websiteEntry()
        let manifest = try CatalogIconManifest(data: manifestData([manifestEntry()], websites: [entry]))
        var app = CloudApplication(id: "private", name: "私有应用", slug: "cook", websiteUrl: "https://new.yunle.fun/path?q=1", audience: "workshop", accessWorkshopID: "ABC234")
        let candidates = app.iconCandidates(dark: false, downloaded: manifest.assets, websites: manifest.websiteIcons)
        XCTAssertEqual(candidates.map { $0.url.absoluteString }, ["https://icons.yunle.fun/products/brand/app-icon.svg"])
        XCTAssertEqual(candidates.first?.revision, String(repeating: "c", count: 64))
        app.websiteUrl = "https://new.yunle.fun.attacker.test"
        XCTAssertTrue(app.iconCandidates(dark: false, websites: manifest.websiteIcons).isEmpty)
        XCTAssertTrue(try CatalogIconManifest(data: manifestData([manifestEntry()])).websiteIcons.isEmpty, "Old cached manifests remain readable")
        for patch in [["origin": "https://new.yunle.fun/path"], ["url": "https://example.com/icon.svg"], ["icon": "invalid"], ["sha256": "bad"]] {
            var invalid = entry; patch.forEach { invalid[$0.key] = $0.value }
            XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([manifestEntry()], websites: [invalid])))
        }
        XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([manifestEntry()], websites: [entry, entry])))
    }
    func testOnlySelectedAssetsBecomeRuntimeEntries() throws {
        var entry = manifestEntry()
        entry["candidates"] = [["url": "https://example.test/not-selected.svg"]]
        let manifest = try CatalogIconManifest(data: manifestData([entry]))
        XCTAssertEqual(manifest.assets["cook"]?.official, "https://example.test/official.svg")
        XCTAssertEqual(manifest.assets["cook"]?.thumbnail, thumbnail("cook", "v3"))
        XCTAssertNotNil(manifest.assets["cook"]?.revision)
        let generated = try CatalogIconManifest(data: manifestData([manifestEntry(slug: "new-app", official: false)]))
        XCTAssertNil(generated.assets["new-app"]?.official)
        let newApp = CloudApplication(id: "new-record", name: "新应用", marketShortName: "new-app")
        XCTAssertEqual(newApp.iconCandidates(dark: false, downloaded: generated.assets).first?.url.absoluteString,
                       thumbnail("new-app", "v3"), "New catalog entries do not require a bundled snapshot update")
    }

    func testInvalidOrUnselectedManifestsAreRejectedAsAWhole() throws {
        XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([], schema: 1)))
        XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([manifestEntry()], schema: 2)))
        XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([manifestEntry(), manifestEntry()])))
        XCTAssertThrowsError(try CatalogIconManifest(data: Data(repeating: 32, count: CatalogIconManifest.maximumBytes + 1)))
        for (key, value) in [("status", "candidate"), ("usage", "comparison-only"), ("kind", "unknown"), ("version", "../v3")] {
            var entry = manifestEntry(), selected = entry["desktopAsset"] as! [String: Any]
            selected[key] = value; entry["desktopAsset"] = selected
            XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([entry])), key)
        }
        for url in ["http://example.test/a.svg", "https://user:secret@example.test/a.svg", "https://example.test/a.svg?token=x", "https://example.test/page.html"] {
            var entry = manifestEntry(), selected = entry["desktopAsset"] as! [String: Any]
            selected["source"] = ["kind": "official-source", "url": url, "sha256": String(repeating: "b", count: 64)]
            entry["desktopAsset"] = selected
            XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([entry])), url)
        }
        for (key, value) in [("url", "https://example.test/wrong.webp"), ("sha256", "not-a-hash"), ("mime", "image/png")] {
            var entry = manifestEntry(), selected = entry["desktopAsset"] as! [String: Any]
            var image = selected["thumbnail"] as! [String: Any]
            image[key] = value; selected["thumbnail"] = image; entry["desktopAsset"] = selected
            XCTAssertThrowsError(try CatalogIconManifest(data: manifestData([entry])), key)
        }
    }

    func testDownloadedOfficialArtworkUpdatesStaleMetadataAndKeepsBundledFallbacks() throws {
        let manifest = try CatalogIconManifest(data: manifestData([manifestEntry()]))
        let app = CloudApplication(id: "a", name: "做菜", marketShortName: "cook",
                                   iconAssets: .init(appIcon: .init(src: "https://example.test/old.svg", darkSrc: "https://example.test/dark.svg")))
        let light = app.iconCandidates(dark: false, downloaded: manifest.assets)
        XCTAssertEqual(light.first?.url.absoluteString, "https://example.test/official.svg")
        XCTAssertEqual(light.first?.revision, manifest.assets["cook"]?.revision)
        XCTAssertTrue(light.contains { $0.url.absoluteString == "https://example.test/old.svg" })
        XCTAssertEqual(light.last?.url.absoluteString, CatalogIconAssets.bySlug["cook"]?.thumbnail)
        XCTAssertEqual(app.iconCandidates(dark: true, downloaded: manifest.assets).first?.url.absoluteString, "https://example.test/dark.svg")
        let other = CloudApplication(id: "a", name: "风扇", marketShortName: "electric-fan")
        XCTAssertEqual(other.iconCandidates(dark: false, downloaded: manifest.assets).first?.url.absoluteString,
                       CatalogIconAssets.bySlug["electric-fan"]?.thumbnail)
        var privateApp = app; privateApp.accessWorkshopID = "private"
        XCTAssertFalse(privateApp.iconCandidates(dark: false, downloaded: manifest.assets).contains { $0.revision != nil })
    }
}

@MainActor
final class CatalogIconStoreTests: XCTestCase {
    private var directory: URL!
    private var cacheURL: URL { directory.appendingPathComponent("nested/manifest.json") }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-icons-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testWebsiteBindingsRefreshAndReopenFromCacheIndependentlyOfCatalogArtwork() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()], websites: [websiteEntry()]))
        let store = CatalogIconStore(service: service, cacheURL: cacheURL)
        await store.refresh()
        let first = try XCTUnwrap(store.websiteIcons["https://new.yunle.fun"])
        var next = websiteEntry(); next["sha256"] = String(repeating: "d", count: 64)
        await service.setData(try manifestData([manifestEntry()], websites: [next]))
        await store.refresh(force: true)
        XCTAssertNotEqual(first.revision, store.websiteIcons["https://new.yunle.fun"]?.revision)
        let restored = CatalogIconStore(service: service, cacheURL: cacheURL)
        XCTAssertEqual(restored.websiteIcons, store.websiteIcons)
        await service.setFailure(true)
        await store.refresh(force: true)
        XCTAssertEqual(store.websiteIcons, restored.websiteIcons)
    }

    func testColdStartPublishesUpdateAndReopensFromDiskWithoutNetworking() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]))
        let store = CatalogIconStore(service: service, cacheURL: cacheURL)
        XCTAssertEqual(store.source, .bundled)
        XCTAssertTrue(store.assets.isEmpty)
        var updates = 0
        let observation = store.$assets.dropFirst().sink { _ in updates += 1 }
        await store.refresh()
        XCTAssertEqual(store.source, .network)
        XCTAssertEqual(store.assets["cook"]?.thumbnail, thumbnail("cook", "v3"))
        XCTAssertEqual(updates, 1)
        let restored = CatalogIconStore(service: service, cacheURL: cacheURL)
        XCTAssertEqual(restored.source, .cache)
        XCTAssertEqual(restored.assets, store.assets)
        await expectCalls(service, 1)
        observation.cancel()
    }

    func testNetworkAndInvalidManifestFailuresNeverOverwriteLastGoodCache() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]))
        let store = CatalogIconStore(service: service, cacheURL: cacheURL)
        await store.refresh()
        let saved = try Data(contentsOf: cacheURL), assets = store.assets
        await service.setFailure(true)
        await store.refresh(force: true)
        XCTAssertEqual(store.assets, assets)
        XCTAssertEqual(try Data(contentsOf: cacheURL), saved)
        await service.setFailure(false)
        await service.setData(Data("invalid json".utf8))
        await store.refresh(force: true)
        XCTAssertEqual(store.assets, assets)
        XCTAssertEqual(try Data(contentsOf: cacheURL), saved)
    }

    func testCorruptCacheFallsBackToSnapshotAndCanRecover() async throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: cacheURL)
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]))
        let store = CatalogIconStore(service: service, cacheURL: cacheURL)
        XCTAssertEqual(store.source, .bundled)
        XCTAssertFalse(CloudApplication(id: "cook", name: "做菜").iconCandidates(dark: false, downloaded: store.assets).isEmpty)
        await store.refresh()
        XCTAssertEqual(store.source, .network)
        XCTAssertNoThrow(try CatalogIconManifest(data: Data(contentsOf: cacheURL)))
    }

    func testConcurrentRefreshesCoalesceAndRespectHourlyTTLAndManualRefresh() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]), delay: true)
        var now = Date(timeIntervalSince1970: 1_000)
        let store = CatalogIconStore(service: service, cacheURL: cacheURL, now: { now })
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await store.refresh(force: true) } }
        }
        await expectCalls(service, 1)
        await store.refresh()
        await expectCalls(service, 1)
        now += CatalogIconStore.refreshInterval
        await store.refresh()
        await expectCalls(service, 2)
        await store.refresh(force: true)
        await expectCalls(service, 3)
    }

    func testFailureBackoffStillAllowsManualRetry() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]))
        await service.setFailure(true)
        var now = Date(timeIntervalSince1970: 1_000)
        let store = CatalogIconStore(service: service, cacheURL: cacheURL, now: { now })
        await store.refresh(); await store.refresh()
        await expectCalls(service, 1)
        now += CatalogIconStore.retryInterval
        await store.refresh()
        await expectCalls(service, 2)
        await service.setFailure(false)
        await store.refresh(force: true)
        XCTAssertEqual(store.source, .network)
    }

    func testSameURLWithNewHashPublishesNewCandidatesAndUnchangedManifestDoesNotReload() async throws {
        let service = ManifestFixtureService(data: try manifestData([manifestEntry()]))
        let store = CatalogIconStore(service: service, cacheURL: cacheURL)
        await store.refresh()
        let app = CloudApplication(id: "cook", name: "做菜")
        let before = app.iconCandidates(dark: false, downloaded: store.assets)
        var updates = 0
        let observation = store.$assets.dropFirst().sink { _ in updates += 1 }
        await store.refresh(force: true)
        XCTAssertEqual(updates, 0)
        await service.setData(try manifestData([manifestEntry(hash: "c")]))
        await store.refresh(force: true)
        let after = app.iconCandidates(dark: false, downloaded: store.assets)
        XCTAssertEqual(before.first?.url, after.first?.url)
        XCTAssertNotEqual(before.first?.revision, after.first?.revision)
        XCTAssertEqual(updates, 1)
        observation.cancel()
    }
}

private actor ManifestFixtureService: CatalogIconFetching {
    var data: Data
    var calls = 0
    var failing = false
    let delay: Bool
    init(data: Data, delay: Bool = false) { self.data = data; self.delay = delay }
    func setFailure(_ value: Bool) { failing = value }
    func setData(_ value: Data) { data = value }
    func count() -> Int { calls }
    func manifest() async throws -> CatalogIconManifest {
        calls += 1
        if delay { try await Task.sleep(nanoseconds: 30_000_000) }
        if failing { throw URLError(.notConnectedToInternet) }
        return try CatalogIconManifest(data: data)
    }
}

private func thumbnail(_ slug: String, _ version: String) -> String {
    "https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/app-icons/\(version)/\(slug).webp"
}
private func manifestEntry(slug: String = "cook", official: Bool = true, hash: String = "a") -> [String: Any] {
    ["slug": slug, "desktopAsset": ["kind": official ? "official" : "generated", "version": "v3", "usage": "desktop-selected",
        "thumbnail": ["url": thumbnail(slug, "v3"), "width": 256, "height": 256, "mime": "image/webp", "bytes": 100, "sha256": String(repeating: hash, count: 64)],
        "source": ["kind": official ? "official-source" : "generated-artwork", "url": "https://example.test/official.svg", "sha256": String(repeating: "b", count: 64)]]]
}
private func websiteEntry() -> [String: Any] {
    ["origin": "https://new.yunle.fun", "icon": "brand-app-icon", "url": "https://icons.yunle.fun/products/brand/app-icon.svg", "sha256": String(repeating: "c", count: 64)]
}
private func manifestData(_ entries: [[String: Any]], schema: Int = 1, websites: [[String: Any]]? = nil) throws -> Data {
    var document: [String: Any] = ["schemaVersion": schema, "assets": entries]
    if let websites { document["websiteIcons"] = websites }
    return try JSONSerialization.data(withJSONObject: document)
}

private func expectCalls(_ service: ManifestFixtureService, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) async {
    let count = await service.count()
    XCTAssertEqual(count, expected, file: file, line: line)
}

final class CatalogIconServiceTests: XCTestCase {
    func testMalformedOrOversizedPrimaryFallsBackToTheSourceMirror() async throws {
        let valid = try manifestData([manifestEntry()])
        let urls = CatalogIconService.endpoints.map(\.absoluteString)
        for primary in [(200, Data("not json".utf8), Optional<Int>.none),
                        (200, Data(), Optional(CatalogIconManifest.maximumBytes + 1))] {
            ManifestHTTPProtocol.configure([urls[0]: primary, urls[1]: (200, valid, nil)])
            let result = try await service().manifest()
            XCTAssertEqual(result.assets["cook"]?.thumbnail, thumbnail("cook", "v3"))
            let requests = ManifestHTTPProtocol.capturedRequests()
            XCTAssertEqual(requests.map { $0.url!.absoluteString }, urls)
            XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        }
    }

    func testUnavailableSourcesRemainAnExplicitFailure() async throws {
        ManifestHTTPProtocol.configure([:])
        do { _ = try await service().manifest(); XCTFail("Do not replace last-good artwork with an empty successful response") }
        catch { XCTAssertEqual(ManifestHTTPProtocol.capturedRequests().count, 2) }
    }

    private func service() -> CatalogIconService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManifestHTTPProtocol.self]
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        return CatalogIconService(session: URLSession(configuration: config))
    }
}

private final class ManifestHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var replies: [String: (Int, Data, Int?)] = [:]
    private static var requests: [URLRequest] = []
    static func configure(_ values: [String: (Int, Data, Int?)]) {
        lock.lock(); defer { lock.unlock() }; replies = values; requests = []
    }
    static func capturedRequests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let (status, data, length) = Self.replies[request.url!.absoluteString] ?? (503, Data(), nil)
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Length": String(length ?? data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
