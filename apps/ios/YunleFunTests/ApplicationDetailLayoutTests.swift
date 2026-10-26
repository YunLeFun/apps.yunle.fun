import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationDetailLayoutTests: XCTestCase {
    func testCompactDetailAtStandardText() async throws { try await render(size: .large, dark: false) }
    func testCompactDetailAtStandardTextInDark() async throws { try await render(size: .large, dark: true) }
    func testCompactDetailAtLargestText() async throws { try await render(size: .accessibility5, dark: false) }
    func testCompactDetailAtLargestTextInDark() async throws { try await render(size: .accessibility5, dark: true) }
    func testLoggedInWorkshopDetailInLight() async throws { try await render(size: .large, dark: false, workshop: true) }
    func testLoggedInWorkshopDetailInDark() async throws { try await render(size: .large, dark: true, workshop: true) }
    func testWorkshopDetailAtLargestTextInDark() async throws { try await render(size: .accessibility5, dark: true, workshop: true) }

    private func render(size: DynamicTypeSize, dark: Bool, workshop: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var application = CloudApplication(id: "detail-layout", name: "给自己留一段安静阅读的时间",
            description: "收藏文章，随时继续阅读。", websiteUrl: "https://example.invalid", emoji: "📖")
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let host = UUID().uuidString.lowercased() + ".detail-auth.test"
        let auth = AuthHTTPFixture(replies: [(200, #"{"sub":"alice","name":"样例账号","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: auth); defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState()
        if workshop {
            application = CloudApplication(id: "detail-workshop", name: "云乐坊 · 管理后台",
                description: "云乐坊一体化管理后台，用于内部运营、应用审核、云币钱包管理、GitHub Secrets 管理与部署触发。",
                websiteUrl: "https://admin.example.invalid", emoji: "🛠️", category: "效率工具", developerName: "云乐坊",
                isOfficial: true, accessMode: "login_required", audience: "workshop", accessWorkshopID: "ABC234")
            state.activeID = "alice"
            state.accounts = [SavedAccount(user: AccountUser(id: "alice"), credential: AccountCredential(accessToken: "fixture-only", refreshToken: "unused", expiresAt: Date().addingTimeInterval(3600)))]
        }
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: config),
            origin: URL(string: "https://\(host)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        if workshop { await accounts.restore(); XCTAssertEqual(accounts.user?.id, "alice") }
        let runtime = NativeWebRuntime()
        let content = NavigationStack { ApplicationDetailView(application: application) }
            .environmentObject(catalog).environmentObject(library).environmentObject(accounts).environmentObject(runtime)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(dark ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: workshop && !size.isAccessibilitySize ? 393 : 320,
                              height: workshop && !size.isAccessibilitySize ? 852 : 800)
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
        screenshot.name = "detail-\(workshop ? "workshop" : "compact")-\(dark ? "dark" : "light")-\(size)"
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
