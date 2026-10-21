import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class HostIdentitySessionsTests: XCTestCase {
    func testClearWaitsForAllowedCookiesAndPreservesUnrelatedSessions() async throws {
        // About twenty real WebKit round trips; a slow shared CI runner can need more than the
        // two-minute default even when every callback completes.
        executionTimeAllowance = 180
        // A separate non-persistent store keeps the test away from the user's
        // real web sessions and the development app's default cookie store.
        let dataStore = WKWebsiteDataStore.nonPersistent()
        defer { withExtendedLifetime(dataStore) {} }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { withExtendedLifetime(webView) {} }
        // Keep the isolated store backed by a ready, visible page throughout
        // its cookie operations. An unloaded zero-size view can become inactive
        // between callbacks even after the initial cookie-store round trip.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            webView.stopLoading(); webView.removeFromSuperview()
            window.isHidden = true; window.rootViewController = nil
            previousWindow?.makeKey()
        }
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let host = try XCTUnwrap(window.rootViewController?.view)
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
        try await WebStoragePageFixture.load(in: webView,
                                             origin: URL(string: "https://identity-cookies.invalid/")!,
                                             title: "identity-cookie-probe")
        let store = webView.configuration.websiteDataStore.httpCookieStore
        // Complete a round trip before the first write to the cold WebKit store.
        let initial = try await cookies(in: store)
        XCTAssertTrue(initial.isEmpty)
        let entries = [
            ("play.yunle.fun", "__Host-ylf_play_session"),
            ("cms.yunle.fun", "__Host-ylf-cms-session"),
            ("cms.yunle.fun", "h3"),
            ("play.yunle.fun", "preferences"),
            ("elsewhere.example.invalid", "__Host-ylf_play_session"),
            ("play.yunle.fun", "h3"),
        ]
        var expected: Set<String> = []
        for (domain, name) in entries {
            let url = try XCTUnwrap(URL(string: "https://\(domain)/"))
            let parsed = HTTPCookie.cookies(withResponseHeaderFields: [
                "Set-Cookie": "\(name)=test-only; Path=/; Secure",
            ], for: url)
            XCTAssertEqual(parsed.count, 1)
            let cookie = try XCTUnwrap(parsed.first)
            XCTAssertTrue(cookie.isSecure)
            XCTAssertEqual(cookie.path, "/")
            try await callback("set fixture cookie " + name) { done in store.setCookie(cookie, completionHandler: done) }
            expected.insert(domain + "/" + name)
            let recorded = try await cookies(in: store)
            let keys = Set(recorded.map(identity))
            guard keys == expected, recorded.count == expected.count else {
                XCTFail("Cookie fixture was not retained before cleanup: expected \(expected.sorted()), found \(keys.sorted())")
                throw FixtureError.notRetained
            }
        }
        let before = try await cookies(in: store)
        XCTAssertEqual(before.count, 6)
        XCTAssertEqual(Set(before.map(identity)), expected)
        try await callback("clear allowed identity cookies") { done in HostIdentitySessions.clear(in: dataStore, completion: done) }
        let after = try await cookies(in: store)
        let remaining = Set(after.map(identity))
        XCTAssertEqual(remaining, [
            "play.yunle.fun/preferences",
            "elsewhere.example.invalid/__Host-ylf_play_session",
            "play.yunle.fun/h3",
        ])
    }

    private func identity(_ cookie: HTTPCookie) -> String {
        cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "/" + cookie.name
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
    private enum FixtureError: Error { case notRetained }
}
