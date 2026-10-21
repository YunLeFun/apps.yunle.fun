import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationCacheWebKitTests: XCTestCase {
    func testArchiveReplaysInteractiveContentWithOriginalOrigin() async throws {
        let url = URL(string: "https://cache-fixture.example/index.html")!
        let source = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let html = """
        <html><head><title>cache-fixture</title></head><body>
        <button id="counter" onclick="this.textContent = Number(this.textContent) + 1">0</button>
        <script>window.cacheScriptRan = true;</script>
        </body></html>
        """
        source.loadSimulatedRequest(URLRequest(url: url), responseHTML: html)
        try await wait(source, script: "window.cacheScriptRan === true")
        let archive: Data = try await withCheckedThrowingContinuation { continuation in
            source.createWebArchiveData { continuation.resume(with: $0) }
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let replay = WKWebView(frame: .zero, configuration: configuration)
        replay.load(archive, mimeType: "application/x-webarchive", characterEncodingName: "UTF-8", baseURL: url)
        try await wait(replay, script: "window.cacheScriptRan === true")
        let origin = try await replay.evaluateJavaScript("location.origin") as? String
        XCTAssertEqual(origin, "https://cache-fixture.example")
        _ = try await replay.evaluateJavaScript("document.getElementById('counter').click()")
        let count = try await replay.evaluateJavaScript("document.getElementById('counter').textContent") as? String
        XCTAssertEqual(count, "1")
    }

    func testArchiveLoadsExternalScriptStylesAndImageWithoutNetworkSource() async throws {
        let origin = "https://offline-cache.invalid/"
        let html = """
        <html><head><link rel="stylesheet" href="style.css"></head><body>
        <div id="result"></div><img id="icon" src="icon.svg">
        <script src="app.js"></script><script type="module" src="module.js"></script></body></html>
        """
        func resource(_ path: String, _ mime: String, _ text: String) -> [String: Any] {
            ["WebResourceURL": origin + path, "WebResourceMIMEType": mime,
             "WebResourceTextEncodingName": "UTF-8", "WebResourceData": Data(text.utf8)]
        }
        let archive = try PropertyListSerialization.data(fromPropertyList: [
            "WebMainResource": resource("", "text/html", html),
            "WebSubresources": [
                resource("module.js", "application/javascript", "import { value } from './dependency.js'; window.moduleReady = value;"),
                resource("dependency.js", "application/javascript", "export const value = 42;"),
                resource("style.css", "text/css", "#result { color: rgb(1, 2, 3); }"),
                resource("app.js", "application/javascript", "document.getElementById('result').textContent = 'offline-ready';"),
                resource("icon.svg", "image/svg+xml", "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16'/></svg>")
            ]
        ], format: .binary, options: 0)
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let replay = WKWebView(frame: .zero, configuration: configuration)
        replay.load(archive, mimeType: "application/x-webarchive", characterEncodingName: "UTF-8", baseURL: URL(string: origin)!)
        try await wait(replay, script: "document.getElementById('result')?.textContent === 'offline-ready' && document.getElementById('icon')?.naturalWidth === 16 && window.moduleReady === 42")
        let color = try await replay.evaluateJavaScript("getComputedStyle(document.getElementById('result')).color") as? String
        XCTAssertEqual(color, "rgb(1, 2, 3)")
    }

    private func wait(_ web: WKWebView, script: String) async throws {
        // Up to 30 seconds of polling: a cold WebContent launch on a shared CI runner is slow.
        for _ in 0..<600 {
            if (try? await web.evaluateJavaScript(script)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Cached WebKit content did not become interactive")
        throw URLError(.timedOut)
    }
}
