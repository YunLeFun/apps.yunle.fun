import WebKit
import XCTest
@testable import YunleFun

final class ApplicationStaticResourcePolicyTests: XCTestCase {
    func testOnlyExactFirstPartyHTTPSOriginsOptInAndAccessChecksRemainSeparate() throws {
        for host in ["admin.yunle.fun", "support.yunle.fun"] {
            var app = CloudApplication(id: host, name: host, websiteUrl: "https://\(host)/tickets/123#access=secret")
            app.accessMode = "login_required"; app.accessWorkshopID = "private-workshop"
            XCTAssertTrue(ApplicationCacheEntry.supports(app))
            XCTAssertFalse(app.canOpenAsGuest)
            var otherPath = app; otherPath.websiteUrl = "https://\(host)/"
            XCTAssertEqual(ApplicationCacheEntry.key(for: app), ApplicationCacheEntry.key(for: otherPath))
            app.isUnavailable = true
            XCTAssertFalse(ApplicationCacheEntry.supports(app))
        }
        for raw in ["http://admin.yunle.fun/", "https://admin.yunle.fun.evil.test/", "https://support.yunle.fun:8443/", "https://user:pass@support.yunle.fun/"] {
            XCTAssertNil(ApplicationStaticResourcePolicy.origin(for: try XCTUnwrap(URL(string: raw))))
        }
    }

    func testDiscoveryIncludesLazyModulesStylesAndFontsButNeverAPIsOrThirdParties() throws {
        let origin = URL(string: "https://support.yunle.fun/")!
        let source = #"["./Route.D8abc.js","./view.ABC.css"]; import("./Lazy.D123.js"); fetch('/api/v1/session'); const x='https://evil.test/_nuxt/x.js'; url(./font.ABC.woff2); '/_nuxt/payload.json'; '/_nuxt/x.js?token=secret'"#
        let references = ApplicationStaticResourcePolicy.references(in: source, relativeTo: origin.appendingPathComponent("_nuxt/entry.js"), origin: origin)
        XCTAssertEqual(Set(references.map(\.lastPathComponent)), ["Route.D8abc.js", "view.ABC.css", "Lazy.D123.js", "font.ABC.woff2"])
        for path in ["api/v1/session", "login", "_nuxt/data.json", "_nuxt/file.js?access=secret"] {
            XCTAssertFalse(ApplicationStaticResourcePolicy.permits(origin.appendingPathComponent(path), from: origin))
        }
        XCTAssertFalse(ApplicationStaticResourcePolicy.permits(URL(string: "https://support.yunle.fun/_nuxt/../api/session.js")!, from: origin))
        XCTAssertFalse(ApplicationStaticResourcePolicy.permits(URL(string: "https://support.yunle.fun/_nuxt/%2e%2e/api/session.js")!, from: origin))
        let request = ApplicationStaticResourcePolicy.navigationRequest(to: origin)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache, no-store")
        XCTAssertEqual(request.cachePolicy, .useProtocolCachePolicy)
    }

    func testPublicCachePolicyRejectsPrivateUserVaryingAndNonCacheableResponses() throws {
        let url = URL(string: "https://admin.yunle.fun/_nuxt/entry.ABC.js")!
        func response(_ value: String, extra: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: extra.merging(["Cache-Control": value]) { _, new in new })!
        }
        XCTAssertTrue(ApplicationStaticResourcePolicy.isPublic(response("public, max-age=31536000, immutable")))
        for policy in ["", "private, max-age=10", "public, no-store, max-age=10", "public, no-cache, max-age=10", "public, max-age=0", "public, private=\"set-cookie\", max-age=10"] {
            XCTAssertFalse(ApplicationStaticResourcePolicy.isPublic(response(policy)))
        }
        for extra in [["Set-Cookie": "session=secret"], ["Vary": "Cookie"], ["Vary": "Authorization, Accept-Encoding"], ["Vary": "*"]] {
            XCTAssertFalse(ApplicationStaticResourcePolicy.isPublic(response("public, max-age=10", extra: extra)))
        }
    }

    func testResourceReceiptCannotBeReplayedAsHTMLAndClearOneKeepsTheOtherSite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let first = CloudApplication(id: "admin", name: "管理后台", websiteUrl: "https://admin.yunle.fun/")
        let second = CloudApplication(id: "support", name: "支持中心", websiteUrl: "https://support.yunle.fun/")
        for app in [first, second] {
            let origin = ApplicationStaticResourcePolicy.origin(for: app.launchURL!)!
            let receipt = ApplicationStaticResourceReceipt(origin: origin, profileIdentifier: UUID(),
                resources: [.init(url: origin.appendingPathComponent("_nuxt/entry.ABC.js"), byteCount: 1234)])
            try await repository.save(JSONEncoder().encode(receipt), for: app)
            let archive = try await repository.archive(for: app)
            XCTAssertNil(archive, "Resource metadata must never be loaded as an archived document")
        }
        let entries = try await repository.entries()
        XCTAssertTrue(entries.allSatisfy(\.isStaticResources))
        XCTAssertEqual(entries.map(\.byteCount), [1234, 1234])
        var moved = first; moved.websiteUrl = "https://admin.yunle.fun/console"
        let snapshot = try await repository.snapshot(for: moved)
        XCTAssertNotNil(snapshot)
        try await repository.remove(id: ApplicationCacheEntry.key(for: first))
        let remaining = try await repository.entries()
        XCTAssertEqual(remaining.map(\.application.id), [second.id])
    }
}

@MainActor
final class ApplicationStaticResourceLiveTests: XCTestCase {
    func testFirstPartySitesWarmActualBrowserCacheAndClearWithoutRemovingLoginOrStorage() async throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_LIVE_TEST"] == "1" else { throw XCTSkip("Opt in to public first-party network validation") }
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent cache stores require iOS 17") }
        let defaultsName = "public-resource-cache-test-\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let service = ApplicationStaticResourceCache(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let store = ApplicationCacheStore(repository: repository, defaults: defaults, staticResources: service)
        for host in ["admin.yunle.fun", "support.yunle.fun"] {
            let identifier = UUID()
            service.profile = { _ in identifier }
            do {
                print("PUBLIC_RESOURCE_TEST_BEGIN \(host) profile=\(identifier)")
                try await exerciseSite(host, identifier: identifier, store: store, repository: repository)
            } catch {
                // Destroy test WebViews and store references before removing
                // their named store; removing an in-use store fails in WebKit.
                try? await Task.sleep(nanoseconds: 100_000_000)
                try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
                throw error
            }
            print("PUBLIC_RESOURCE_TEST_REMOVING_PROFILE \(host) \(identifier)")
            try await Task.sleep(nanoseconds: 100_000_000)
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
            print("PUBLIC_RESOURCE_TEST_PROFILE_REMOVED \(host)")
        }
    }

    @available(iOS 17, *)
    private func exerciseSite(_ host: String, identifier: UUID, store: ApplicationCacheStore, repository: ApplicationCacheRepository) async throws {
        let app = CloudApplication(id: "static-live-\(host)", name: host, websiteUrl: "https://\(host)/")
        let dataStore = WKWebsiteDataStore(forIdentifier: identifier)
        let config = WKWebViewConfiguration(); config.websiteDataStore = dataStore
        let browser = WKWebView(frame: .zero, configuration: config)
        browser.loadSimulatedRequest(URLRequest(url: app.launchURL!), responseHTML: "<title>cache-live</title>")
        try await wait { (try? await browser.evaluateJavaScript("document.title")) as? String == "cache-live" }
        _ = try await browser.evaluateJavaScript("localStorage.setItem('cache-deletion-fixture', 'keep')")
        let cookie = HTTPCookie(properties: [.domain: host, .path: "/", .name: "cache-deletion-fixture", .value: "keep", .secure: "TRUE"])!
        await dataStore.httpCookieStore.setCookie(cookie)
        let started = Date()
        store.download(app)
        try await wait(seconds: 150) { !store.isBusy }
        let entry = try XCTUnwrap(store.entry(for: app), store.message ?? "Missing download")
        let snapshot = try await repository.snapshot(for: app)
        let receipt = try JSONDecoder().decode(ApplicationStaticResourceReceipt.self, from: XCTUnwrap(snapshot).archive)
        XCTAssertGreaterThan(receipt.resources.count, 5)
        let styleResources = receipt.resources.filter { $0.url.pathExtension == "css" }
        XCTAssertFalse(styleResources.isEmpty)
        // only-if-cached cannot hit the network. Use normal credential mode,
        // matching the page's real module and stylesheet requests.
        let cached = try await browser.callAsyncJavaScript("""
            return await Promise.all(urls.map(async url => {
                const r = await fetch(url, {cache: 'only-if-cached', mode: 'same-origin'});
                return r.status;
            }));
            """, arguments: ["urls": styleResources.prefix(6).map { $0.url.absoluteString }], in: nil, contentWorld: .defaultClient) as? [Int]
        XCTAssertEqual(cached, Array(repeating: 200, count: min(6, styleResources.count)))
        // The runtime launches in a new browser. Reusing the simulated
        // document at the same URL would make WebKit treat this as Reload.
        let liveBrowser = WKWebView(frame: .zero, configuration: config)
        liveBrowser.load(ApplicationStaticResourcePolicy.navigationRequest(to: app.launchURL!))
        try await wait(seconds: 60) {
            guard let state = try? await liveBrowser.evaluateJavaScript("document.readyState === 'complete' && location.protocol === 'https:'") as? Bool else { return false }
            return state
        }
        let navigation = try await liveBrowser.evaluateJavaScript("performance.getEntriesByType('navigation')[0].transferSize") as? Int
        XCTAssertGreaterThan(navigation ?? 0, 0, "The main page must be fetched from the network")
        // WebKit reports a revalidated cache hit as 300 header bytes plus
        // zero response-body bytes, including encodedBodySize === 0.
        // See WebCore/page/PerformanceResourceTiming.cpp, transferSize().
        let reused = try await liveBrowser.evaluateJavaScript("performance.getEntriesByType('resource').filter(r => r.name.startsWith(location.origin + '/_nuxt/') && (r.responseStatus === undefined || r.responseStatus === 200 || r.responseStatus === 304) && (r.transferSize === 0 || (r.transferSize === 300 && r.encodedBodySize === 0))).length") as? Int
        XCTAssertGreaterThan(reused ?? 0, 5, "The live site must actually reuse the downloaded scripts and styles")
        print("PUBLIC_RESOURCE_LIVE_PAGE \(host) documentTransfer=\(navigation ?? -1) cachedResources=\(reused ?? -1)")
        liveBrowser.stopLoading()
        liveBrowser.loadHTMLString("<title>done</title>", baseURL: nil)
        browser.loadSimulatedRequest(URLRequest(url: app.launchURL!), responseHTML: "<title>cache-live</title>")
        try await wait { (try? await browser.evaluateJavaScript("document.title")) as? String == "cache-live" }
        print("PUBLIC_RESOURCE_CACHE_LIVE \(host) resources=\(entry.resourceCount) bytes=\(entry.byteCount) seconds=\(Date().timeIntervalSince(started))")
        let attachment = XCTAttachment(string: "\(host): \(entry.resourceCount) resources, \(entry.byteCount) bytes, \(Date().timeIntervalSince(started)) seconds; credentialed browser cache read: \(cached ?? [])")
        attachment.lifetime = .keepAlways; add(attachment)
        print("PUBLIC_RESOURCE_TEST_CLEARING \(host)")
        XCTContext.runActivity(named: "\(host): clear site resources") { _ in }
        await store.clear(id: entry.id)
        print("PUBLIC_RESOURCE_TEST_CLEARED \(host)")
        XCTAssertNil(store.entry(for: app))
        XCTContext.runActivity(named: "\(host): verify cookies") { _ in }
        let cookies = await dataStore.httpCookieStore.allCookies()
        print("PUBLIC_RESOURCE_TEST_COOKIES_READ \(host)")
        XCTAssertTrue(cookies.contains { $0.name == "cache-deletion-fixture" && $0.value == "keep" })
        XCTContext.runActivity(named: "\(host): verify localStorage") { _ in }
        let local = try await browser.evaluateJavaScript("localStorage.getItem('cache-deletion-fixture')") as? String
        XCTAssertEqual(local, "keep")
        XCTContext.runActivity(named: "\(host): verify HTTP cache was deleted") { _ in }
        let removed = try await browser.callAsyncJavaScript("""
            try { const r = await fetch(url, {cache: 'only-if-cached', mode: 'same-origin'}); return r.status; }
            catch { return 0; }
            """, arguments: ["url": styleResources.first!.url.absoluteString], in: nil, contentWorld: .defaultClient) as? Int
        XCTAssertTrue([0, 504].contains(removed ?? -1), "Deleting the site must remove actual HTTP cache data, not only metadata")
        print("PUBLIC_RESOURCE_TEST_DELETION_VERIFIED \(host) status=\(removed ?? -1)")
        browser.stopLoading()
    }

    private func wait(seconds: TimeInterval = 30, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }
}
