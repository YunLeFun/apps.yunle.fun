import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class NativeRuntimeSessionTests: XCTestCase {
    func testIdentityResetRemovesSessionAndNestedFirstPartySheets() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        try await fixture.presentNestedSheets()
        fixture.runtime.resetIdentity(to: "another-fixture-account")
        XCTAssertFalse(fixture.runtime.contains(fixture.application))
        XCTAssertTrue(fixture.runtime.applications.isEmpty)
        try await fixture.waitForDismissal()
        XCTAssertNil(fixture.root.presentedViewController, "No old account's application may remain behind a dismissed sheet")
        XCTAssertNil(fixture.browser.viewIfLoaded?.window)
    }

    func testEndingApplicationClosesNestedSheetsAndKeepsHomeEntry() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        try await fixture.presentNestedSheets()
        fixture.runtime.end(fixture.application)
        XCTAssertFalse(fixture.runtime.contains(fixture.application))
        try await fixture.waitForDismissal()
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertNil(fixture.browser.viewIfLoaded?.window)
        XCTAssertTrue(fixture.library.contains(fixture.application), "Ending a session must not uninstall the application")
    }

    func testSwitchFromDetailsUsesOneRootAndRestoresSameBrowser() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let first = fixture.browser
        try await fixture.presentNestedSheets()
        let second = fixture.app("second")
        fixture.runtime.open(second, catalog: fixture.catalog, library: fixture.library)
        let secondBrowser = try await fixture.waitForApplication(second)
        XCTAssertTrue(secondBrowser.navigationController?.presentingViewController === fixture.root)
        XCTAssertNil(first?.viewIfLoaded?.window)
        XCTAssertTrue(fixture.runtime.contains(fixture.application))
        fixture.runtime.open(fixture.application, catalog: fixture.catalog, library: fixture.library)
        let restored = try await fixture.waitForApplication(fixture.application)
        XCTAssertTrue(restored === first, "Switching must retain WebKit history and the same cached browser")
        XCTAssertNil(secondBrowser.viewIfLoaded?.window)
    }

    func testLatestOpenWinsDuringAnimatedSwitch() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        UIView.setAnimationsEnabled(true)
        let second = fixture.app("second"), latest = fixture.app("latest")
        fixture.runtime.open(second, catalog: fixture.catalog, library: fixture.library)
        fixture.runtime.open(latest, catalog: fixture.catalog, library: fixture.library)
        let shown = try await fixture.waitForApplication(latest)
        XCTAssertTrue(shown.navigationController?.presentingViewController === fixture.root)
        XCTAssertFalse(fixture.runtime.contains(second))
        XCTAssertEqual(fixture.runtime.applications.first?.id, latest.id)
    }

    func testIdentityResetCancelsQueuedOpenAndLateMinimizeCallback() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let lateMinimize = try XCTUnwrap(fixture.browser.onMinimize)
        UIView.setAnimationsEnabled(true)
        let second = fixture.app("second")
        fixture.runtime.open(second, catalog: fixture.catalog, library: fixture.library)
        fixture.runtime.resetIdentity(to: "another-fixture-account")
        lateMinimize()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(fixture.runtime.applications.isEmpty)
        XCTAssertFalse(fixture.runtime.contains(second))
        try await fixture.waitForDismissal()
        XCTAssertNil(fixture.root.presentedViewController)
        let fresh = fixture.app("fresh")
        fixture.runtime.open(fresh, catalog: fixture.catalog, library: fixture.library)
        _ = try await fixture.waitForApplication(fresh)
    }

    func testCloseCallbackClosesWholeApplicationFromNestedSheet() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        try await fixture.presentNestedSheets()
        _ = fixture.browser.perform(NSSelectorFromString("closeTapped"))
        XCTAssertFalse(fixture.runtime.contains(fixture.application))
        try await fixture.waitForDismissal()
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertTrue(fixture.library.contains(fixture.application))
    }

    func testOldCloseCallbackCannotEndReplacementSession() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let old = fixture.browser
        let lateClose = try XCTUnwrap(old?.onClose)
        fixture.runtime.end(fixture.application)
        try await fixture.waitForDismissal()
        fixture.runtime.open(fixture.application, catalog: fixture.catalog, library: fixture.library)
        let replacement = try await fixture.waitForApplication(fixture.application)
        XCTAssertFalse(replacement === old)
        lateClose()
        XCTAssertTrue(fixture.runtime.contains(fixture.application))
        XCTAssertTrue(replacement.navigationController?.presentingViewController === fixture.root)
    }

    func testMinimizeClosesNestedSheetsAndRestoresSameBrowser() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let original = fixture.browser
        try await fixture.presentNestedSheets()
        _ = fixture.browser.perform(NSSelectorFromString("minimizeTapped"))
        try await fixture.waitForDismissal()
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertNil(original?.viewIfLoaded?.window)
        XCTAssertTrue(fixture.runtime.contains(fixture.application))
        fixture.runtime.open(fixture.application, catalog: fixture.catalog, library: fixture.library)
        let restored = try await fixture.waitForApplication(fixture.application)
        XCTAssertTrue(restored === original)
        XCTAssertNil(restored.presentedViewController, "Dismissed details must not reappear when restoring the application")
    }

    func testChangedLaunchURLReplacesSessionAndClosesDetails() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let original = fixture.browser
        try await fixture.presentNestedSheets()
        var changed = fixture.application
        changed.websiteUrl = "https://runtime.invalid/new-version"
        fixture.runtime.open(changed, catalog: fixture.catalog, library: fixture.library)
        let replacement = try await fixture.waitForApplication(changed)
        XCTAssertFalse(replacement === original)
        XCTAssertEqual(replacement.url, changed.launchURL)
        XCTAssertNil(original?.viewIfLoaded?.window)
        XCTAssertEqual(fixture.runtime.applications.filter { $0.id == changed.id }.count, 1)
    }

    func testDetachedAnchorCannotPresentIntoPreviouslyCachedWindow() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let detached = UIViewController()
        fixture.runtime.anchor = detached
        let second = fixture.app("second")
        fixture.runtime.open(second, catalog: fixture.catalog, library: fixture.library)
        XCTAssertNotNil(fixture.runtime.issue)
        XCTAssertFalse(fixture.runtime.contains(second))
        XCTAssertTrue(fixture.root.presentedViewController === fixture.browser.navigationController)
        fixture.runtime.anchor = fixture.root
        fixture.runtime.open(second, catalog: fixture.catalog, library: fixture.library)
        _ = try await fixture.waitForApplication(second)
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = UIViewController()
        let runtime = NativeWebRuntime()
        let accounts = AccountStore(session: AccountSession(vault: BillingMemoryVault()))
        let application = CloudApplication(id: "session-fixture", name: "会话边界验证", websiteUrl: "https://runtime.invalid/", emoji: "🧪")
        let window: UIWindow
        let previous: UIWindow?
        let library: HomeLibrary
        let catalog: CatalogStore
        let animationsWereEnabled: Bool
        private(set) var browser: WebViewController!

        init() async throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            library = HomeLibrary(directory: directory.appendingPathComponent("home"))
            catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
            library.add(application)
            runtime.configureAuthorization(accounts: accounts)
            window.rootViewController = root; window.makeKeyAndVisible()
            runtime.anchor = root
            for _ in 0..<100 where root.presentedViewController == nil {
                runtime.open(application, catalog: catalog, library: library)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            browser = try await waitForApplication(application)
            browser.view.subviews.compactMap { $0 as? WKWebView }.first?.stopLoading()
            XCTAssertTrue(runtime.contains(application))
        }

        func presentNestedSheets() async throws {
            let detail = try XCTUnwrap(browser.localPageFactory?("/app/session-fixture", "app-detail-sheet", nil))
            detail.modalPresentationStyle = .pageSheet
            try await present(detail, from: browser)
            let child = UIViewController()
            child.modalPresentationStyle = .pageSheet
            try await present(child, from: detail)
            XCTAssertNotNil(detail.presentingViewController)
            XCTAssertNotNil(child.presentingViewController)
        }

        private func present(_ controller: UIViewController, from presenter: UIViewController) async throws {
            let completed = XCTestExpectation(description: "UIKit completed the nested presentation")
            presenter.present(controller, animated: false) { completed.fulfill() }
            guard await XCTWaiter.fulfillment(of: [completed], timeout: 5) == .completed else {
                XCTFail("UIKit did not complete the nested presentation")
                throw NSError(domain: "NativeRuntimeSessionTests", code: 2)
            }
        }

        func waitForDismissal() async throws {
            for _ in 0..<100 {
                if root.presentedViewController == nil && browser.viewIfLoaded?.window == nil { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTFail("The old application and its sheets did not leave the window")
            throw NSError(domain: "NativeRuntimeSessionTests", code: 3)
        }

        func app(_ id: String) -> CloudApplication {
            CloudApplication(id: id, name: id, websiteUrl: "https://runtime.invalid/\(id)", emoji: "🧪")
        }

        func waitForApplication(_ application: CloudApplication) async throws -> WebViewController {
            for _ in 0..<100 {
                if let navigation = root.presentedViewController as? UINavigationController,
                   let browser = navigation.topViewController as? WebViewController,
                   browser.appInfo?.id == application.id, browser.url == application.launchURL,
                   !navigation.isBeingPresented, !navigation.isBeingDismissed, browser.viewIfLoaded?.window != nil {
                    browser.view.subviews.compactMap { $0 as? WKWebView }.first?.stopLoading()
                    return browser
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTFail("The requested application did not become the root presentation")
            throw NSError(domain: "NativeRuntimeSessionTests", code: 1)
        }

        func close() {
            runtime.resetIdentity()
            root.dismiss(animated: false)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
            UIView.setAnimationsEnabled(animationsWereEnabled)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
