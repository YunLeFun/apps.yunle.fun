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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController(), browser = WebViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        var current = true, ended = 0
        var action: ((WebAppMenuAction) -> Void)?
        browser.onClose = { ended += 1 }
        browser.localMenuPageFactory = { _, perform in
            action = perform
            return WebAppMenuPage(controller: UIViewController(), isCurrent: { current })
        }
        browser.modalPresentationStyle = .fullScreen
        root.present(browser, animated: false)
        try await Task.sleep(nanoseconds: 150_000_000)
        browser.perform(NSSelectorFromString("moreTapped"))
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNotNil(browser.presentedViewController)
        let perform = try XCTUnwrap(action)
        perform(.end); perform(.end)
        if invalidateDuringDismissal { current = false }
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertEqual(ended, invalidateDuringDismissal ? 0 : 1)
        perform(.end)
        XCTAssertEqual(ended, invalidateDuringDismissal ? 0 : 1, "A retained callback must not affect another presentation")
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
