import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationCacheRuntimeTests: XCTestCase {
    func testRepeatedCachedSessionsReleaseWebViews() async throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_STARTUP_PROBE"] == "1" else {
            throw XCTSkip("Opt in to the repeated offline startup probe on a dedicated simulator")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory.appendingPathComponent("downloads"))
        let application = CloudApplication(id: "cache-startup-probe", name: "缓存启动回归", websiteUrl: "https://cache-startup.invalid/")
        let archive = try PropertyListSerialization.data(fromPropertyList: [
            "WebMainResource": ["WebResourceURL": application.launchURL!.absoluteString,
                                "WebResourceMIMEType": "text/html", "WebResourceTextEncodingName": "UTF-8",
                                "WebResourceData": Data("<html><title>startup-probe</title><body>cached</body></html>".utf8)]
        ], format: .binary, options: 0)
        try await repository.save(archive, for: application)
        let runtime = NativeWebRuntime(applicationCache: ApplicationCacheStore(repository: repository))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible(); runtime.anchor = root
        defer { runtime.end(application); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for _ in 0..<100 {
            if !runtime.isIdentityCleanupPending { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(runtime.isIdentityCleanupPending)
        for iteration in 1...8 {
            let started = ProcessInfo.processInfo.systemUptime
            print("CACHE_STARTUP_PROBE opening iteration=\(iteration)")
            runtime.open(application, catalog: catalog, library: library)
            let references = try await renderedReferences(in: root)
            print("CACHE_STARTUP_PROBE rendered iteration=\(iteration) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
            runtime.end(application)
            for _ in 0..<100 {
                if references.browser == nil && references.web == nil && root.presentedViewController == nil { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertNil(references.browser, "Ended browser retained after iteration \(iteration)")
            XCTAssertNil(references.web, "Ended WebView retained after iteration \(iteration)")
            XCTAssertNil(root.presentedViewController)
            print("CACHE_STARTUP_PROBE released iteration=\(iteration)")
        }
    }

    private final class RenderedReferences {
        weak var browser: UIViewController?
        weak var web: WKWebView?
    }

    private func renderedReferences(in root: UIViewController) async throws -> RenderedReferences {
        let web = try await renderedWeb(in: root, title: "startup-probe")
        let references = RenderedReferences()
        references.web = web
        references.browser = (root.presentedViewController as? UINavigationController)?.topViewController
        return references
    }

    func testColdRuntimeClearsIdentityWithoutAnExistingWebView() async throws {
        let runtime = NativeWebRuntime()
        for _ in 0..<100 {
            if !runtime.isIdentityCleanupPending { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Cold identity cleanup must complete before the first web session is created")
    }

    func testRuntimeUsesSavedResourcesAndNewSessionSeesUpdatedCache() async throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory.appendingPathComponent("downloads"))
        let application = CloudApplication(id: "runtime-cache", name: "缓存运行时", websiteUrl: "https://runtime-cache.invalid/")
        func archive(_ title: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                "WebMainResource": ["WebResourceURL": application.launchURL!.absoluteString, "WebResourceMIMEType": "text/html", "WebResourceTextEncodingName": "UTF-8",
                                    "WebResourceData": Data("<html><title>\(title)</title><body><button onclick='this.textContent=42'>0</button></body></html>".utf8)]
            ], format: .binary, options: 0)
        }
        try await repository.save(archive("first-cache"), for: application)
        // Keep the default WebKit store's owner alive, as the host does during use.
        let identityWeb = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        defer { withExtendedLifetime(identityWeb) {} }
        identityWeb.loadHTMLString("<title>cache-test-ready</title>", baseURL: nil)
        for _ in 0..<100 {
            if (try? await identityWeb.evaluateJavaScript("document.title")) as? String == "cache-test-ready" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let runtime = NativeWebRuntime(applicationCache: ApplicationCacheStore(repository: repository))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible(); runtime.anchor = root
        defer { runtime.end(application); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for _ in 0..<100 { if !runtime.isIdentityCleanupPending { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        guard !runtime.isIdentityCleanupPending else {
            XCTFail("The existing identity cleanup must finish before testing cache loading")
            throw URLError(.timedOut)
        }
        runtime.open(application, catalog: catalog, library: library)
        XCTAssertNil(runtime.issue?.title)
        let first = try await renderedWeb(in: root, title: "first-cache")
        _ = try await first.evaluateJavaScript("document.querySelector('button').click()")
        let counter = try await first.evaluateJavaScript("document.querySelector('button').textContent") as? String
        XCTAssertEqual(counter, "42")
        try await repository.save(archive("updated-cache"), for: application)
        let previousTitle = try await first.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(previousTitle, "first-cache", "Updating downloads must not interrupt a running session")
        runtime.end(application)
        for _ in 0..<100 { if root.presentedViewController == nil { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        runtime.open(application, catalog: catalog, library: library)
        let updated = try await renderedWeb(in: root, title: "updated-cache")
        XCTAssertFalse(first === updated)
        XCTAssertTrue(library.snapshot.recentIDs.contains(application.id))
    }

    private func renderedWeb(in root: UIViewController, title: String) async throws -> WKWebView {
        // A cold WebContent process took 11.9s in CI. Wait for the actual
        // document within XCTest's existing test allowance, rather than failing
        // a valid archive after an unrelated five-second startup assumption.
        let deadline = Date().addingTimeInterval(TimeInterval(executionTimeAllowance))
        while Date() < deadline {
            if let navigation = root.presentedViewController as? UINavigationController,
               let browser = navigation.topViewController as? WebViewController,
               let web = findWeb(in: browser.view),
               (try? await web.evaluateJavaScript("document.title")) as? String == title { return web }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if let navigation = root.presentedViewController as? UINavigationController,
           let browser = navigation.topViewController as? WebViewController,
           let web = findWeb(in: browser.view) {
            let actualTitle = (try? await web.evaluateJavaScript("document.title")) as? String
            print("CACHE_RUNTIME_STATE", title, actualTitle ?? "no-title", web.url?.absoluteString ?? "no-url", web.isLoading)
        } else { print("CACHE_RUNTIME_STATE", title, "no browser", String(describing: root.presentedViewController)) }
        XCTFail("The native runtime did not load the saved .invalid-origin archive")
        throw URLError(.timedOut)
    }

    private func findWeb(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.findWeb(in: $0) }.first
    }
}
