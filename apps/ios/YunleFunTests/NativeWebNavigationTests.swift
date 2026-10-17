import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class NativeWebNavigationTests: XCTestCase {
    func testSystemBarReservesViewportAndUpdatesTitle() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let env = try await fixture.environment()
        XCTAssertEqual(env["titleBarVisible"] as? Bool, true)
        XCTAssertFalse(fixture.navigation.isNavigationBarHidden)
        XCTAssertTrue(fixture.browser.view.subviews.first { $0.accessibilityIdentifier == "runtime.floating-controls" }?.accessibilityElementsHidden == true)
        let rect = try XCTUnwrap(env["capsuleRect"] as? [String: Double])
        XCTAssertLessThanOrEqual(try XCTUnwrap(rect["y"]) + XCTUnwrap(rect["height"]), 1)
        XCTAssertEqual(try XCTUnwrap((env["safeAreaInsets"] as? [String: Double])?["top"]), 0, accuracy: 1)
        fixture.browser.customTitle = "已更新的应用名称"
        XCTAssertEqual(fixture.browser.navigationItem.title, "已更新的应用名称")
        capture(fixture, "native-navigation-light")
    }

    func testHideAndShowReplyWithFinalGeometryAndKeepPageTappable() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let hidden = try await fixture.environment(after: "await window.ylf.hideTitleBar();")
        XCTAssertTrue(fixture.navigation.isNavigationBarHidden)
        XCTAssertFalse(try XCTUnwrap(fixture.browser.view.subviews.first { $0.accessibilityIdentifier == "runtime.floating-controls" }).accessibilityElementsHidden)
        XCTAssertEqual(hidden["titleBarVisible"] as? Bool, false)
        XCTAssertEqual(fixture.webView.frame.minY, 0, accuracy: 1)
        let rect = try XCTUnwrap(hidden["capsuleRect"] as? [String: Double])
        XCTAssertEqual(try XCTUnwrap(rect["width"]), 44, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(rect["height"]), 44, accuracy: 1)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(rect["y"]), 0)
        let point = CGPoint(x: fixture.browser.view.bounds.midX, y: try XCTUnwrap(rect["y"]) + 22)
        let hit = try XCTUnwrap(fixture.browser.view.hitTest(point, with: nil))
        XCTAssertTrue(hit === fixture.webView || hit.isDescendant(of: fixture.webView), "The effect container must not block touches between floating controls")
        capture(fixture, "native-navigation-hidden")
        let shown = try await fixture.environment(after: "await window.ylf.showTitleBar();")
        XCTAssertEqual(shown["titleBarVisible"] as? Bool, true)
        XCTAssertFalse(fixture.navigation.isNavigationBarHidden)
        XCTAssertGreaterThan(fixture.webView.frame.minY, 0)
        let shownRect = try XCTUnwrap(shown["capsuleRect"] as? [String: Double])
        XCTAssertLessThanOrEqual(try XCTUnwrap(shownRect["y"]) + XCTUnwrap(shownRect["height"]), 1)
    }

    func testSystemBackTracksRealWebHistory() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        try await fixture.load(title: "second")
        XCTAssertTrue(fixture.webView.canGoBack)
        let back = try XCTUnwrap(fixture.browser.navigationItem.leftBarButtonItems?.first { $0.accessibilityLabel == "返回网页" })
        XCTAssertNotNil(back.action)
        _ = (back.target as? NSObject)?.perform(try XCTUnwrap(back.action))
        try await fixture.waitForTitle("first")
        XCTAssertFalse(fixture.webView.canGoBack)
        XCTAssertFalse(fixture.browser.navigationItem.leftBarButtonItems?.contains { $0.accessibilityLabel == "返回网页" } ?? false)
    }

    func testDarkNavigationWithLongTitleAndAccessibilityTraits() async throws {
        let fixture = try await Fixture(dark: true)
        defer { fixture.close() }
        fixture.browser.customTitle = "一个具有很长中文名称的云应用与辅助功能验证"
        if #available(iOS 17, *) {
            fixture.navigation.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        fixture.navigation.view.layoutIfNeeded()
        XCTAssertNotNil(fixture.browser.navigationItem.titleMenuProvider)
        XCTAssertTrue(fixture.browser.navigationItem.leftBarButtonItems?.contains { $0.accessibilityLabel == "收起应用" } == true)
        XCTAssertEqual(fixture.browser.navigationItem.rightBarButtonItem?.accessibilityLabel, "更多操作")
        capture(fixture, "native-navigation-dark-accessibility")
    }

    func testAuthorizationCannotAppearWhileNavigationContainerDismisses() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let accounts = AccountStore(session: AccountSession(vault: BillingMemoryVault()))
        let page = NativeAuthorizationPage(browser: fixture.browser, accounts: accounts)
        fixture.root.dismiss(animated: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(fixture.navigation.isBeingDismissed)
        XCTAssertNotNil(fixture.browser.viewIfLoaded?.window, "Exercise an in-flight dismissal, before the content leaves the window")
        XCTAssertFalse(page.showLogin(application: "验证应用", completion: { _ in XCTFail("A closing session must not start authentication") }))
        XCTAssertNil(fixture.navigation.presentedViewController)
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    private func capture(_ fixture: Fixture, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: fixture.navigation.view.bounds).image { _ in
            fixture.navigation.view.drawHierarchy(in: fixture.navigation.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    private final class Fixture {
        let window: UIWindow
        let previous: UIWindow?
        let root = UIViewController()
        let browser = WebViewController()
        let navigation: UINavigationController
        let webView: WKWebView

        init(dark: Bool = false) async throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            browser.usesSystemNavigationBar = true
            browser.customTitle = "云应用"
            browser.appInfo = WebAppInfo(id: "fixture", slug: "fixture", name: "云应用", emoji: "", logo: "", themeColor: "#007AFF", description: "", category: "", developer: "", developerName: "")
            navigation = UINavigationController(rootViewController: browser)
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController = root; window.makeKeyAndVisible()
            root.present(navigation, animated: false)
            webView = try XCTUnwrap(Self.findWebView(in: browser.view))
            try await load(title: "first")
        }

        func load(title: String) async throws {
            let html = "<html><head><meta charset='utf-8'><title>\(title)</title><meta name='viewport' content='width=device-width,initial-scale=1'></head><body style='background:#dceeff'><h1>原生导航验证</h1><button>网页仍可交互</button></body></html>"
            let dataURL = "data:text/html;base64," + Data(html.utf8).base64EncodedString()
            webView.load(URLRequest(url: try XCTUnwrap(URL(string: dataURL))))
            try await waitForTitle(title)
        }

        func waitForTitle(_ title: String) async throws {
            for _ in 0..<100 {
                if (try? await webView.evaluateJavaScript("document.title")) as? String == title {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    return
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTFail("The actual WebKit document did not finish loading")
        }

        func environment(after script: String = "") async throws -> [String: Any] {
            let result = try await webView.callAsyncJavaScript(script + "return await window.ylf.getEnv();", arguments: [:], in: nil, contentWorld: .page)
            return try XCTUnwrap(result as? [String: Any])
        }

        func close() { browser.cancelPendingAuthorizations(); root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        private static func findWebView(in view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { findWebView(in: $0) }.first
        }
    }
}
