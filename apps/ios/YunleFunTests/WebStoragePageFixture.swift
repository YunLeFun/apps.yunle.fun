import WebKit
import XCTest

/// A document-owned readiness signal avoids evaluating JavaScript in the
/// preceding about:blank document while WebKit is still creating the page.
@MainActor
final class WebStoragePageFixture: NSObject, WKScriptMessageHandler {
    private let ready = XCTestExpectation(description: "The storage fixture document finished loading")
    private let token = UUID().uuidString
    private let origin: URL
    private var received = false

    private init(origin: URL) { self.origin = origin }

    static func load(in web: WKWebView, origin: URL, title: String) async throws {
        let probe = WebStoragePageFixture(origin: origin)
        let content = web.configuration.userContentController
        let handler = "storageFixtureReady"
        content.add(probe, name: handler)
        defer { content.removeScriptMessageHandler(forName: handler) }
        web.loadHTMLString("""
        <html><head><title>\(title)</title></head><body>Storage fixture
        <script>window.addEventListener('load', () => {
          window.webkit.messageHandlers.\(handler).postMessage('\(probe.token)');
        }, { once: true });</script></body></html>
        """, baseURL: origin)
        guard await XCTWaiter.fulfillment(of: [probe.ready], timeout: 5) == .completed else {
            throw Failure.documentNotReady
        }
        XCTAssertEqual(web.title, title)
    }

    static func evaluate(in web: WKWebView, script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        let completed = XCTestExpectation(description: "The storage fixture script returned")
        var result: Result<Any, Error>?
        web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) {
            result = $0
            completed.fulfill()
        }
        // A timer inside JavaScript cannot bound a suspended WebContent process.
        guard await XCTWaiter.fulfillment(of: [completed], timeout: 5) == .completed else {
            throw Failure.scriptDidNotReturn
        }
        return try XCTUnwrap(result).get()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !received, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == origin.scheme,
              message.frameInfo.securityOrigin.host == origin.host,
              message.body as? String == token else { return }
        received = true
        ready.fulfill()
    }

    enum Failure: Error { case documentNotReady, scriptDidNotReturn }
}
