import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class HostIdentitySessionsTests: XCTestCase {
    func testClearWaitsForAllowedCookiesAndPreservesUnrelatedSessions() async throws {
        // A separate non-persistent store keeps the test away from the user's
        // real web sessions and the development app's default cookie store.
        let dataStore = WKWebsiteDataStore.nonPersistent()
        defer { withExtendedLifetime(dataStore) {} }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { withExtendedLifetime(webView) {} }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let entries = [
            ("play.yunle.fun", "__Host-ylf_play_session"),
            ("cms.yunle.fun", "__Host-ylf-cms-session"),
            ("cms.yunle.fun", "h3"),
            ("play.yunle.fun", "preferences"),
            ("elsewhere.example.invalid", "__Host-ylf_play_session"),
            ("play.yunle.fun", "h3"),
        ]
        for (domain, name) in entries {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: domain, .path: "/", .name: name, .value: "test-only", .secure: "TRUE",
            ]))
            try await callback("set fixture cookie " + name) { done in store.setCookie(cookie, completionHandler: done) }
        }
        let before = try await cookies(in: store)
        XCTAssertEqual(before.count, 6)
        try await callback("clear allowed identity cookies") { done in HostIdentitySessions.clear(in: store, completion: done) }
        let after = try await cookies(in: store)
        let remaining = Set(after.map { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "/" + $0.name })
        XCTAssertEqual(remaining, [
            "play.yunle.fun/preferences",
            "elsewhere.example.invalid/__Host-ylf_play_session",
            "play.yunle.fun/h3",
        ])
    }

    private func cookies(in store: WKHTTPCookieStore) async throws -> [HTTPCookie] {
        var values: [HTTPCookie] = []
        try await callback("read fixture cookies") { done in store.getAllCookies { values = $0; done() } }
        return values
    }

    private func callback(_ operation: String, action: (@escaping @Sendable () -> Void) -> Void) async throws {
        let completed = expectation(description: operation)
        action { completed.fulfill() }
        guard await XCTWaiter.fulfillment(of: [completed], timeout: 10) == .completed else {
            XCTFail("WebKit callback timed out: " + operation)
            throw CallbackError.timedOut
        }
    }
    private enum CallbackError: Error { case timedOut }
}
