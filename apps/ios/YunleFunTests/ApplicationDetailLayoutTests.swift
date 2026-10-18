import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationDetailLayoutTests: XCTestCase {
    func testCompactDetailAtStandardText() async throws { try await render(size: .large, dark: false) }
    func testCompactDetailAtStandardTextInDark() async throws { try await render(size: .large, dark: true) }
    func testCompactDetailAtLargestText() async throws { try await render(size: .accessibility5, dark: false) }
    func testCompactDetailAtLargestTextInDark() async throws { try await render(size: .accessibility5, dark: true) }

    private func render(size: DynamicTypeSize, dark: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let application = CloudApplication(id: "detail-layout", name: "给自己留一段安静阅读的时间",
            description: "收藏文章，随时继续阅读。", websiteUrl: "https://example.invalid", emoji: "📖")
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let accounts = AccountStore(session: AccountSession(vault: BillingMemoryVault()))
        let runtime = NativeWebRuntime()
        let content = NavigationStack { ApplicationDetailView(application: application) }
            .environmentObject(catalog).environmentObject(library).environmentObject(accounts).environmentObject(runtime)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(dark ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try await Task.sleep(nanoseconds: 50_000_000)
            controller.view.layoutIfNeeded()
        } while list(in: controller.view)?.cellForItem(at: IndexPath(item: 0, section: 0)) == nil && Date() < deadline
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "detail-compact-\(dark ? "dark" : "light")-\(size)"
        screenshot.lifetime = .keepAlways; add(screenshot)
        let list = try XCTUnwrap(list(in: controller.view))
        let header = try XCTUnwrap(list.cellForItem(at: IndexPath(item: 0, section: 0)))
        let visibleHeight = list.bounds.height - list.adjustedContentInset.top - list.adjustedContentInset.bottom
        XCTAssertLessThanOrEqual(header.bounds.height, visibleHeight,
            "The compact long-title fixture must show its identity and primary actions together at the largest text size")
        let geometry = XCTAttachment(string: "headerHeight=\(header.bounds.height)\nvisibleHeight=\(visibleHeight)")
        geometry.name = "detail-layout-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertTrue(runtime.applications.isEmpty, "Rendering must not acquire or open the application")
    }

    private func list(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { self.list(in: $0) }.first
    }
}
