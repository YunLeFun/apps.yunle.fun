import CryptoKit
import WebKit
import XCTest
@testable import YunleFun

final class NativeGameResourceManifestTests: XCTestCase {
    private let bytes = Data("export const fixture = true;".utf8)
    private let endpoint = URL(string: "https://play.yunle.fun/native/resources/paper-star-v1.json")!

    private var resource: NativeGameResourceManifest.Resource {
        .init(url: URL(string: "https://play.yunle.fun/_nuxt/game.Fixture.js")!,
              sha256: digest(bytes), byteCount: bytes.count, contentType: "application/javascript", required: true)
    }

    private func manifest(resources: [NativeGameResourceManifest.Resource]? = nil, bytes: Int? = nil,
                          gameID: String = "paper-star", schema: Int = 1) -> NativeGameResourceManifest {
        let values = resources ?? [resource]
        return .init(schemaVersion: schema, gameId: gameID, version: String(repeating: "a", count: 64),
                     generatedAt: "2026-10-28T12:00:00.000Z", totalBytes: bytes ?? values.reduce(0) { $0 + $1.byteCount }, resources: values)
    }

    private func digest(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }

    func testManifestBindsExactGameAndCanonicalPublicEndpoint() throws {
        let value = manifest()
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try NativeGameResourceManifest.decode(data, manifestURL: endpoint, gameID: "paper-star"), value)
        for raw in [
            "http://play.yunle.fun/native/resources/paper-star-v1.json",
            "https://play.yunle.fun.evil.invalid/native/resources/paper-star-v1.json",
            "https://play.yunle.fun:8443/native/resources/paper-star-v1.json",
            "https://user:password@play.yunle.fun/native/resources/paper-star-v1.json",
            "https://play.yunle.fun/native/resources/paper-star-v1.json?token=secret",
            "https://play.yunle.fun/native/resources/paper-star-v1.json#session",
            "https://play.yunle.fun/native/resources/gomoku-v1.json",
            "https://assets.play.yunle.fun/native/resources/paper-star-v1.json",
        ] {
            XCTAssertThrowsError(try NativeGameResourceManifest.decode(data, manifestURL: XCTUnwrap(URL(string: raw)), gameID: "paper-star"), raw)
        }
        XCTAssertThrowsError(try NativeGameResourceManifest.decode(data, manifestURL: endpoint, gameID: "gomoku"))
    }

    func testResourcesCannotReachDynamicEndpointsOtherGamesOrUnapprovedOrigins() throws {
        for raw in [
            "https://play.yunle.fun/api/session.json", "https://play.yunle.fun/room/ABC234.json",
            "https://play.yunle.fun/_nuxt/../api/session.json", "https://play.yunle.fun/_nuxt/%2e%2e/api/session.json",
            "https://play.yunle.fun/_nuxt/game.js?token=secret", "https://play.yunle.fun/_nuxt/game.js#state",
            "https://play.yunle.fun/_nuxt/game.html", "https://play.yunle.fun/games/gomoku/texture.png",
            "https://assets.play.yunle.fun/games/gomoku/runtime/v2/texture.webp",
            "https://assets.play.yunle.fun.evil.invalid/games/paper-star/runtime/v2/texture.webp",
        ] {
            XCTAssertFalse(NativeGameResourcePolicy.resourceURL(try XCTUnwrap(URL(string: raw)), gameID: "paper-star"), raw)
        }
        XCTAssertTrue(NativeGameResourcePolicy.resourceURL(URL(string: "https://assets.play.yunle.fun/games/paper-star/runtime/v2/texture.webp")!, gameID: "paper-star"))
        XCTAssertTrue(NativeGameResourcePolicy.resourceURL(URL(string: "https://play.yunle.fun/_nuxt/physics.Fixture.wasm")!, gameID: "paper-star"))
    }

    func testManifestRejectsDuplicateResourcesWrongSizesUnknownSchemaAndExcessBudget() {
        XCTAssertThrowsError(try manifest(resources: [resource, resource]).validate(gameID: "paper-star"))
        XCTAssertThrowsError(try manifest(bytes: bytes.count + 1).validate(gameID: "paper-star"))
        XCTAssertThrowsError(try manifest(schema: 2).validate(gameID: "paper-star"))
        XCTAssertThrowsError(try manifest(bytes: NativeGameResourcePolicy.maximumBytes + 1).validate(gameID: "paper-star"))
        let wrongType = NativeGameResourceManifest.Resource(url: resource.url, sha256: resource.sha256, byteCount: resource.byteCount,
                                                            contentType: "text/html", required: true)
        XCTAssertThrowsError(try manifest(resources: [wrongType]).validate(gameID: "paper-star"))
        let noDigest = NativeGameResourceManifest.Resource(url: resource.url, sha256: "fixture", byteCount: resource.byteCount,
                                                           contentType: resource.contentType, required: true)
        XCTAssertThrowsError(try manifest(resources: [noDigest]).validate(gameID: "paper-star"))
    }

    func testNuxtContentHashMayStartWithHyphenWithoutAllowingHiddenOrTraversingPaths() throws {
        // An actual exported Nuxt chunk name can start with the base64url '-'.
        let chunk = NativeGameResourceManifest.Resource(
            url: URL(string: "https://play.yunle.fun/_nuxt/-y8qBI_C.js")!,
            sha256: digest(bytes), byteCount: bytes.count, contentType: "text/javascript", required: true)
        XCTAssertNoThrow(try manifest(resources: [chunk]).validate(gameID: "paper-star"))
        for path in ["/_nuxt/.hidden.js", "/_nuxt/../api/session.json", "/_nuxt/%2e%2e/api/session.json"] {
            XCTAssertFalse(NativeGameResourcePolicy.resourceURL(
                try XCTUnwrap(URL(string: "https://play.yunle.fun" + path)), gameID: "paper-star"), path)
        }
    }

    func testVerificationRejectsPrivateOrCookieSettingResourcesAndChecksRealBytes() throws {
        func response(_ policy: String = "public, max-age=31536000, immutable", extra: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: resource.url, statusCode: 200, httpVersion: nil,
                            headerFields: ["Content-Type": "application/javascript", "Cache-Control": policy].merging(extra) { _, new in new })!
        }
        XCTAssertNoThrow(try NativeGameResourcePolicy.validate(bytes, response: response(), resource: resource))
        XCTAssertThrowsError(try NativeGameResourcePolicy.validate(Data("changed".utf8), response: response(), resource: resource))
        for policy in ["private, max-age=10", "public, no-store, max-age=10", "public, no-cache, max-age=10", "public, max-age=0"] {
            XCTAssertThrowsError(try NativeGameResourcePolicy.validate(bytes, response: response(policy), resource: resource))
        }
        for extra in [["Set-Cookie": "session=secret"], ["Vary": "Cookie"], ["Vary": "Authorization"], ["Vary": "*"]] {
            XCTAssertThrowsError(try NativeGameResourcePolicy.validate(bytes, response: response(extra: extra), resource: resource))
        }
        XCTAssertEqual(NativeGameResourcePolicy.cacheTypes, [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
        XCTAssertFalse(NativeGameResourcePolicy.cacheTypes.contains(WKWebsiteDataTypeCookies))
        XCTAssertFalse(NativeGameResourcePolicy.cacheTypes.contains(WKWebsiteDataTypeLocalStorage))
        XCTAssertFalse(NativeGameResourcePolicy.cacheTypes.contains(WKWebsiteDataTypeIndexedDBDatabases))
    }

    func testTransportCannotBroadenCanonicalManifestOrResourcePolicy() throws {
        let transport = NativeGameHostEnvironment.transportURL(endpoint)
        XCTAssertTrue(NativeGameResourcePolicy.manifestURL(endpoint, gameID: "paper-star"))
        if let preview = NativeGameHostEnvironment.previewOrigin {
            XCTAssertEqual(transport.host, preview.host)
            XCTAssertEqual(transport.port, preview.port)
            XCTAssertEqual(transport.path, endpoint.path)
            XCTAssertFalse(NativeGameResourcePolicy.manifestURL(transport, gameID: "paper-star"))
        } else { XCTAssertEqual(transport, endpoint) }
        let cdn = URL(string: "https://assets.play.yunle.fun/games/paper-star/runtime/v2/texture.webp")!
        XCTAssertEqual(NativeGameHostEnvironment.transportURL(cdn), cdn)
        let unknown = HTTPURLResponse(url: URL(string: "https://evil.invalid/_nuxt/game.js")!, statusCode: 200, httpVersion: nil,
                                      headerFields: ["Content-Type": "application/javascript", "Cache-Control": "public, max-age=10"])!
        XCTAssertThrowsError(try NativeGameResourcePolicy.validate(bytes, response: unknown, resource: resource,
                                                                  expectedResponseURL: unknown.url))
    }
}

@MainActor
final class NativeGameResourceReceiptTests: XCTestCase {
    func testReceiptsStayScopedToExactProfileAndCorruptReceiptsDoNotBecomeReady() throws {
        let name = "native-game-resource-receipt-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let profile = UUID()
        let receipt = NativeGameResourceCacheEntry(gameID: "gomoku", profileID: profile, version: String(repeating: "a", count: 64),
                                                 byteCount: 100, resourceCount: 2, cacheVerifiedResourceCount: 2, preparedAt: Date())
        defaults.set([profile.uuidString], forKey: "nativeGameResourceCache.profiles.v1")
        defaults.set(try JSONEncoder().encode([receipt]), forKey: "nativeGameResourceCache.entries.v1")
        let cache = NativeGameResourceCache(defaults: defaults)
        XCTAssertEqual(cache.entry(gameID: "gomoku", profileID: profile), receipt)
        XCTAssertNil(cache.entry(gameID: "gomoku", profileID: UUID()))
        defaults.set(Data("corrupt receipt".utf8), forKey: "nativeGameResourceCache.entries.v1")
        let corrupt = NativeGameResourceCache(defaults: defaults)
        XCTAssertTrue(corrupt.entries.isEmpty)
        XCTAssertNotNil(corrupt.error)
        XCTAssertEqual(defaults.data(forKey: "nativeGameResourceCache.entries.v1"), Data("corrupt receipt".utf8))
    }
}

/// Explicit opt-in exercises the real built game dependency tree in a unique
/// named store. A skipped test is not evidence of working cache preparation.
@MainActor
final class NativeGameResourceLiveTests: XCTestCase {
    func testPreviewBuildWarmsActualWebKitCacheAndClearPreservesWebsiteData() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              NativeGameHostEnvironment.previewOrigin != nil else {
            throw XCTSkip("Opt in with YUNLEFUN_PLAY_PREVIEW=1 and the fixed local Play preview server")
        }
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent game stores require iOS 17") }
        let profileID = UUID()
        do {
            try await exerciseCache(profileID: profileID)
        } catch {
            do { try await removeProfile(profileID) }
            catch let cleanupError { XCTFail("Could not remove this test's named store \(profileID): \(cleanupError.localizedDescription)") }
            throw error
        }
        try await removeProfile(profileID)
    }

    @available(iOS 17, *)
    private func exerciseCache(profileID: UUID) async throws {
        let defaultsName = "native-game-resource-live-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let cache = NativeGameResourceCache(defaults: defaults)
        let canonical = URL(string: "https://play.yunle.fun/native/resources/gomoku-v1.json")!
        let endpoint = NativeGameHostEnvironment.transportURL(canonical)
        let origin = NativeGameHostEnvironment.transportURL(NativeGameResourcePolicy.origin)
        let network = URLSessionConfiguration.ephemeral
        network.httpCookieStorage = nil; network.httpShouldSetCookies = false; network.urlCredentialStorage = nil; network.urlCache = nil
        let session = URLSession(configuration: network)
        defer { session.invalidateAndCancel() }
        let (data, rawResponse) = try await session.data(from: endpoint)
        let response = try XCTUnwrap(rawResponse as? HTTPURLResponse)
        XCTAssertEqual(response.url, endpoint)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.mimeType, "application/json")
        let manifest = try NativeGameResourceManifest.decode(data, manifestURL: canonical, gameID: "gomoku")
        XCTAssertGreaterThan(manifest.resources.count, 100, "Use the real compiled dependency tree, not a tiny synthetic fixture")
        let dataStore = WKWebsiteDataStore(forIdentifier: profileID)
        var browsers: [WKWebView] = []
        defer {
            cache.cancel()
            for browser in browsers { browser.stopLoading(); browser.loadHTMLString("<title>done</title>", baseURL: nil) }
            browsers.removeAll()
        }
        let owner = try await inertBrowser(store: dataStore, origin: origin, title: "game-cache-owner")
        browsers.append(owner)
        let marker = "native-game-cache-marker"
        _ = try await owner.evaluateJavaScript("localStorage.setItem('\(marker)', 'keep')")
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: try XCTUnwrap(origin.host), .path: "/", .name: marker, .value: "keep"]))
        await dataStore.httpCookieStore.setCookie(cookie)
        let started = Date()
        cache.download(manifestURL: canonical, gameID: "gomoku", profileID: profileID, wifiOnly: false)
        try await wait(seconds: 180) { !cache.isBusy }
        let receipt = try XCTUnwrap(cache.entry(gameID: "gomoku", profileID: profileID), cache.error ?? "Missing actual WebKit preparation receipt")
        XCTAssertNil(cache.error)
        XCTAssertEqual(receipt.byteCount, manifest.totalBytes)
        XCTAssertEqual(receipt.resourceCount, manifest.resources.count)
        XCTAssertEqual(cache.progress, 1)
        let sameOrigin = manifest.resources.filter { $0.url.host == "play.yunle.fun" }
        XCTAssertEqual(receipt.cacheVerifiedResourceCount, sameOrigin.count)

        // A new WKWebView has no fetch response objects or loaded resource list
        // from the preparer. only-if-cached cannot fall back to the network.
        let reader = try await inertBrowser(store: dataStore, origin: origin, title: "game-cache-reader")
        browsers.append(reader)
        let resources: [[String: Any]] = sameOrigin.map {
            ["url": NativeGameHostEnvironment.transportURL($0.url).absoluteString, "bytes": $0.byteCount, "sha256": $0.sha256]
        }
        let reused = try await reader.callAsyncJavaScript("""
            return await Promise.all(resources.map(async resource => {
                const response = await fetch(resource.url, {cache:'only-if-cached', mode:'same-origin', credentials:'same-origin', redirect:'error'});
                if (response.status !== 200) return false;
                const data = await response.arrayBuffer();
                if (data.byteLength !== resource.bytes) return false;
                const hash = await crypto.subtle.digest('SHA-256', data);
                return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, '0')).join('') === resource.sha256;
            }));
            """, arguments: ["resources": resources], in: nil, contentWorld: .defaultClient) as? [Bool]
        XCTAssertEqual(reused, Array(repeating: true, count: sameOrigin.count))
        print("NATIVE_GAME_CACHE_LIVE game=gomoku resources=\(receipt.resourceCount) verified=\(receipt.cacheVerifiedResourceCount) bytes=\(receipt.byteCount) seconds=\(Date().timeIntervalSince(started))")

        await cache.clear(profileID: profileID)
        XCTAssertNil(cache.entry(gameID: "gomoku", profileID: profileID))
        XCTAssertFalse(cache.entries.contains { $0.profileID == profileID })
        let cookies = await dataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == marker && $0.value == "keep" })
        let localMarker = try await reader.evaluateJavaScript("localStorage.getItem('\(marker)')") as? String
        XCTAssertEqual(localMarker, "keep")
        let afterClear = try await inertBrowser(store: dataStore, origin: origin, title: "game-cache-cleared")
        browsers.append(afterClear)
        let sample = try XCTUnwrap(sameOrigin.first)
        let removed = try await afterClear.callAsyncJavaScript("""
            try { return (await fetch(url, {cache:'only-if-cached', mode:'same-origin', credentials:'same-origin'})).status; }
            catch { return 0; }
            """, arguments: ["url": NativeGameHostEnvironment.transportURL(sample.url).absoluteString], in: nil, contentWorld: .defaultClient) as? Int
        XCTAssertTrue([0, 504].contains(removed ?? -1), "Clear must remove the real HTTP cache while keeping website data")
        print("NATIVE_GAME_CACHE_CLEAR game=gomoku status=\(removed ?? -1) cookie=kept localStorage=kept")
        let evidence = XCTAttachment(string: "gomoku: \(receipt.resourceCount) resources, \(receipt.byteCount) bytes, \(sameOrigin.count) fresh-WebView cache-only hash checks; after clear status \(removed ?? -1); Cookie/localStorage preserved")
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @available(iOS 17, *)
    private func inertBrowser(store: WKWebsiteDataStore, origin: URL, title: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.loadSimulatedRequest(URLRequest(url: origin), responseHTML: "<title>\(title)</title>")
        try await wait { (try? await browser.evaluateJavaScript("document.title")) as? String == title }
        return browser
    }

    private func wait(seconds: TimeInterval = 30, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }

    @available(iOS 17, *)
    private func removeProfile(_ identifier: UUID) async throws {
        for attempt in 0..<3 {
            try await Task.sleep(nanoseconds: 150_000_000)
            do { try await WKWebsiteDataStore.remove(forIdentifier: identifier); return }
            catch { if attempt == 2 { throw error } }
        }
    }
}
