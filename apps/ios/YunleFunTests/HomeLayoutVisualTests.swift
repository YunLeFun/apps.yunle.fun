import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class HomeLayoutVisualTests: XCTestCase {
    func testCompactHomeWithStandardText() async throws {
        try await render(size: .large, dark: false)
    }

    func testCompactHomeWithLargestAccessibilityText() async throws {
        try await render(size: .accessibility5, dark: true)
    }

    func testEmptyHomeCanScrollAtLargestAccessibilityText() async throws {
        try await render(size: .accessibility5, dark: false, empty: true)
    }

    private func render(size: DynamicTypeSize, dark: Bool, empty: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let applications = [
            CloudApplication(id: "reading", name: "给自己留一段安静阅读的时间", description: "收藏文章，随时继续阅读。", emoji: "📖", requiresMembership: true),
            CloudApplication(id: "weather", name: "天气", description: "出门前看看天气。", emoji: "☀️"),
            CloudApplication(id: "journal", name: "每日手记", description: "记下值得留住的小事。", emoji: "✏️"),
        ]
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        if !empty {
            applications.forEach(library.add)
            library.setPinned(applications[0], true)
        }
        let before = library.snapshot
        let accounts = AccountStore(session: AccountSession(vault: BillingMemoryVault()))
        let runtime = NativeWebRuntime()
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, monitorNetwork: false)
        let content = NavigationStack { HomeView {} }
            .environmentObject(catalog).environmentObject(library).environmentObject(runtime)
            .environmentObject(accounts).environmentObject(sync)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(dark ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000)
        controller.view.layoutIfNeeded()
        if empty {
            let scroll = try XCTUnwrap(scrollView(in: controller.view), "The empty home must scroll so its browse button remains reachable")
            let visibleHeight = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
            XCTAssertGreaterThan(scroll.contentSize.height, visibleHeight)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
            controller.view.layoutIfNeeded()
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = empty ? "home-empty-accessibility5-scrolled" : dark ? "home-compact-dark-accessibility5" : "home-compact-light-large"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(library.snapshot, before, "Changing the layout must preserve installations, pins and order")
        XCTAssertTrue(runtime.applications.isEmpty, "Displaying the home must not launch an application")
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}
