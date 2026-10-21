import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class NativeApplicationMenuTests: XCTestCase {
    func testOriginNeverDisplaysCredentialsOrNavigationParameters() {
        XCTAssertEqual(NativeApplicationMenuView.originLabel(URL(string: "https://user:secret@example.test:8443/path?code=secret#token")), "https://example.test:8443")
        XCTAssertNil(NativeApplicationMenuView.originLabel(URL(string: "about:blank")))
        XCTAssertNil(NativeApplicationMenuView.originLabel(nil))
    }

    func testMenuActionEndsExactlyOneSessionAfterDismissal() async throws {
        try await checkAction(invalidateDuringDismissal: false)
    }

    func testIdentityChangeDuringDismissalDropsPendingAction() async throws {
        try await checkAction(invalidateDuringDismissal: true)
    }

    private func checkAction(invalidateDuringDismissal: Bool) async throws {
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController(), browser = WebViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        var current = true, ended = 0
        var action: ((WebAppMenuAction) -> Void)?
        let closed = invalidateDuringDismissal ? nil : XCTestExpectation(description: "The current session ends after menu dismissal")
        closed?.assertForOverFulfill = true
        browser.onClose = { ended += 1; closed?.fulfill() }
        browser.usesSystemNavigationBar = true
        browser.localMenuPageFactory = { _, perform in
            action = perform
            return WebAppMenuPage(controller: UIViewController(), isCurrent: { current })
        }
        let navigation = UINavigationController(rootViewController: browser)
        navigation.modalPresentationStyle = .fullScreen
        let presented = XCTestExpectation(description: "UIKit completed the application presentation")
        root.present(navigation, animated: false) { presented.fulfill() }
        // Returns as soon as UIKit finishes; the long limit only covers a slow shared CI runner.
        let presentationResult = await XCTWaiter.fulfillment(of: [presented], timeout: 30)
        XCTAssertEqual(presentationResult, .completed)
        try await waitForState("The application must be stable in its window") {
            navigation.presentingViewController === root && browser.viewIfLoaded?.window != nil
                && !navigation.isBeingPresented && !navigation.isBeingDismissed
        }
        browser.perform(NSSelectorFromString("moreTapped"))
        try await waitForState("The menu must finish presenting before an action") {
            guard let menu = browser.presentedViewController else { return false }
            return menu.viewIfLoaded?.window != nil && !menu.isBeingPresented && !menu.isBeingDismissed
        }
        let menu = try XCTUnwrap(browser.presentedViewController)
        let perform = try XCTUnwrap(action)
        perform(.end); perform(.end)
        if invalidateDuringDismissal { current = false }
        try await waitForState("The menu must actually leave the window") {
            browser.presentedViewController == nil && menu.presentingViewController == nil
                && menu.viewIfLoaded?.window == nil && !menu.isBeingDismissed
                && menu.transitionCoordinator == nil
        }
        if let closed {
            let closeResult = await XCTWaiter.fulfillment(of: [closed], timeout: 30)
            XCTAssertEqual(closeResult, .completed)
        }
        XCTAssertEqual(ended, invalidateDuringDismissal ? 0 : 1)
        perform(.end)
        XCTAssertEqual(ended, invalidateDuringDismissal ? 0 : 1, "A retained callback must not affect another presentation")
    }

    private func waitForState(_ message: String, condition: () -> Bool) async throws {
        // Polls for up to 30 seconds so a slow CI runner does not fail a state UIKit is still reaching.
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail(message)
        throw NSError(domain: "NativeApplicationMenuTests", code: 1)
    }

    func testLightMenu() async throws { try await render(accessibility: false) }
    func testDarkMenuAtAccessibilitySize() async throws { try await render(accessibility: true) }

    private func render(accessibility: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let application = CloudApplication(id: "fixture", name: "云空调", description: "为你的夏日带来一份清凉。", websiteUrl: "https://example.test/", emoji: "❄️", ownerLogin: "yunyoujun", developerName: "云游君")
        let content = NativeApplicationMenuView(application: application, currentURL: application.launchURL, perform: { _ in })
            .environmentObject(CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json")))
            .environmentObject(HomeLibrary(directory: directory.appendingPathComponent("home")))
            .environmentObject(NativeWebRuntime())
            .environmentObject(AccountStore(session: AccountSession(vault: BillingMemoryVault())))
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .preferredColorScheme(accessibility ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000); controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = accessibility ? "native-menu-dark-accessibility" : "native-menu-light"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
