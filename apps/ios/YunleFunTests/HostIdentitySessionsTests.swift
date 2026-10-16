import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class HostIdentitySessionsTests: XCTestCase {
    func testClearWaitsForAllowedCookiesAndPreservesUnrelatedSessions() async throws {
        // A separate non-persistent store keeps the test away from the user's
        // real web sessions and the development app's default cookie store.
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
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
            await withCheckedContinuation { continuation in store.setCookie(cookie) { continuation.resume() } }
        }
        let before = await cookies(in: store)
        XCTAssertEqual(before.count, 6)
        await withCheckedContinuation { continuation in
            HostIdentitySessions.clear(in: store) { continuation.resume() }
        }
        let after = await cookies(in: store)
        let remaining = Set(after.map { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "/" + $0.name })
        XCTAssertEqual(remaining, [
            "play.yunle.fun/preferences",
            "elsewhere.example.invalid/__Host-ylf_play_session",
            "play.yunle.fun/h3",
        ])
    }

    private func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.getAllCookies { continuation.resume(returning: $0) } }
    }
}
