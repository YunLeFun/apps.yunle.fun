import SwiftUI
import Vision
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class HomeLayoutVisualTests: XCTestCase {
    func testUnavailableStatusExplainsDelistingWithoutRemovingTheInstallation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory)
        try library.adopt(RemoteHomeScreen(revision: String(repeating: "a", count: 64),
            configuration: HomeConfiguration(installedApps: [.init(appId: "removed")])))
        let before = library.snapshot
        let application = try XCTUnwrap(library.snapshot.applications.first)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for dark in [false, true] {
            let content = ApplicationUnavailableView(application: application, service: UnavailableStatusFixture())
                .environmentObject(library).preferredColorScheme(dark ? .dark : .light)
            let controller = UIHostingController(rootView: content)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 350_000_000)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
                .replacingOccurrences(of: " ", with: "")
            XCTAssertTrue(text.contains("应用已下架"), text)
            XCTAssertTrue(text.contains("安装记录已保留"), text)
            XCTAssertTrue(text.contains("刷新状态"), text)
            let attachment = XCTAttachment(image: image); attachment.name = "unavailable-status-" + (dark ? "dark" : "light")
            attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(library.snapshot, before)
        }
    }

    func testWorkshopHomeShowsPrivateAppsWithoutInstallingThem() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), workshopService: HomeWorkspaceServiceFixture(), workspaceID: "ABC234")
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-private-light", containing: "支持中心", test: self)
        XCTAssertTrue(text.contains("云乐坊私有工坊")); XCTAssertTrue(text.contains("管理后台")); XCTAssertTrue(text.contains("支持中心"))
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
        XCTAssertTrue(fixture.runtime.applications.isEmpty)
    }

    func testWorkspacePickerShowsPersonalAndAuthorizedWorkshops() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), workshopService: HomeWorkspaceServiceFixture(),
            workspaceID: "ABC234", workspacePicker: true)
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-picker", containing: "灵感工坊", test: self)
        XCTAssertTrue(text.contains("我的云居")); XCTAssertTrue(text.contains("云乐坊私有工坊")); XCTAssertTrue(text.contains("灵感工坊"))
    }

    func testWorkspaceSwitcherKeepsPersonalHomeReachableAtLargestText() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), size: .accessibility5, width: 320, height: 800,
            workshopService: HomeWorkspaceServiceFixture())
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-personal-largest-text", containing: "去工坊看看", scrollToFind: true, test: self)
        XCTAssertTrue(text.contains("去工坊看看"))
    }

    func testWorkshopHomeInDark() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), dark: true,
            workshopService: HomeWorkspaceServiceFixture(), workspaceID: "ABC234")
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-private-dark", containing: "支持中心", test: self)
        XCTAssertTrue(text.contains("管理后台")); XCTAssertTrue(text.contains("支持中心"))
    }

    func testWorkshopHomeCanScrollAtLargestText() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), size: .accessibility5, dark: true, width: 320, height: 800,
            workshopService: HomeWorkspaceServiceFixture(), workspaceID: "ABC234")
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-largest-text", containing: "support.yunle.fun", scrollToFind: true, test: self)
        XCTAssertTrue(text.contains("supportyunlefun"))
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
    }

    func testSwitchingWorkshopsAndReturningToPersonalHomeKeepsLibrarySeparate() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), workshopService: HomeWorkspaceServiceFixture(), workspaceID: "ABC234")
        defer { fixture.close() }
        _ = try await fixture.readScreen(named: "home-workspace-before-switch", containing: "支持中心", test: self)
        fixture.workspaceDefaults.set("DEF567", forKey: HomeWorkspaceView.selectionKey(userID: "home-state-user"))
        let other = try await fixture.readScreen(named: "home-workspace-after-switch", containing: "灵感笔记", test: self)
        XCTAssertTrue(other.contains("灵感笔记")); XCTAssertFalse(other.contains("管理后台")); XCTAssertFalse(other.contains("支持中心"))
        fixture.workspaceDefaults.set("", forKey: HomeWorkspaceView.selectionKey(userID: "home-state-user"))
        // Vision may omit the narrow “的” in this bold heading on the CI renderer.
        // Verify the distinguishing visible phrase and selected workspace independently.
        let personal = try await fixture.readScreen(named: "home-workspace-personal", containing: "带回云居", test: self)
        XCTAssertTrue(personal.contains("我的云居")); XCTAssertTrue(personal.contains("带回云居"))
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
        XCTAssertTrue(fixture.runtime.applications.isEmpty)
    }

    func testRestoredMissingWorkshopReturnsToPersonalHome() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(), workshopService: HomeWorkspaceServiceFixture(), workspaceID: "XYZ234")
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-removed", containing: "把喜欢的应用带回云居", test: self)
        XCTAssertTrue(text.contains("我的云居"))
        XCTAssertEqual(fixture.workspaceDefaults.string(forKey: HomeWorkspaceView.selectionKey(userID: "home-state-user")), "")
    }

    func testWorkshopHomeDoesNotShowPrivateAppsWhenAccessIsRevoked() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(),
            workshopService: HomeWorkspaceServiceFixture(access: .none), workspaceID: "ABC234")
        defer { fixture.close() }
        let text = try await fixture.readScreen(named: "home-workspace-revoked", containing: "暂不能访问这个工坊", test: self)
        XCTAssertTrue(text.contains("暂不能访问这个工坊"))
        XCTAssertFalse(text.contains("管理后台")); XCTAssertFalse(text.contains("支持中心"))
    }

    func testLateWorkshopResponseCannotReplaceTheNewSelection() async throws {
        let gate = HomeStateLoadGate()
        let fixture = try await HomeStateFixture(service: HomeStateService(),
            workshopService: HomeWorkspaceServiceFixture(firstPageGate: gate), workspaceID: "ABC234")
        defer { fixture.close(); Task { await gate.open() } }
        try await gate.waitUntilEntered()
        fixture.workspaceDefaults.set("DEF567", forKey: HomeWorkspaceView.selectionKey(userID: "home-state-user"))
        let text = try await fixture.readScreen(named: "home-workspace-switch-while-loading", containing: "灵感笔记", test: self)
        XCTAssertTrue(text.contains("灵感笔记"))
        await gate.open()
        let after = try await fixture.readScreen(named: "home-workspace-late-response", containing: "灵感笔记", test: self)
        XCTAssertTrue(after.contains("灵感笔记")); XCTAssertFalse(after.contains("管理后台")); XCTAssertFalse(after.contains("支持中心"))
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
    }

    func testCompactHomeWithStandardText() async throws {
        try await render(size: .large, dark: false)
    }

    func testCompactHomeWithLargestAccessibilityText() async throws {
        try await render(size: .accessibility5, dark: true)
    }

    func testEmptyHomeCanScrollAtLargestAccessibilityText() async throws {
        try await render(size: .accessibility5, dark: false, empty: true)
    }

    func testEmptySignedInHomeShowsAnInFlightSync() async throws {
        let gate = HomeStateLoadGate()
        let fixture = try await HomeStateFixture(service: HomeStateService(gate: gate))
        defer { fixture.close() }
        let loading = Task { await fixture.sync.synchronize() }
        defer { loading.cancel(); Task { await gate.open() } }
        try await gate.waitUntilEntered()
        XCTAssertEqual(fixture.sync.phase, .syncing)
        let screen = try await fixture.readScreen(named: "home-empty-syncing", containing: "把喜欢的应用带回云居", test: self)
        XCTAssertFalse(screen.contains("正在同步云居"), "Background sync must not insert a loading row into the home content")
        let activity = try XCTUnwrap(fixture.toolbarActivityFrame, "The navigation bar must indicate that the cloud home is still loading")
        XCTAssertLessThan(activity.maxY, 150, "Sync activity belongs in the navigation bar")
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
        await gate.open(); await loading.value
    }

    func testBackgroundSyncKeepsApplicationPositionsStable() async throws {
        try await assertStableHomeDuringSync(size: .large, dark: false)
    }

    func testBackgroundSyncKeepsApplicationPositionsStableAtLargestText() async throws {
        try await assertStableHomeDuringSync(size: .accessibility5, dark: true)
    }

    private func assertStableHomeDuringSync(size: DynamicTypeSize, dark: Bool) async throws {
        let gate = HomeStateLoadGate()
        let remote = RemoteHomeScreen(revision: String(repeating: "c", count: 64),
            configuration: HomeConfiguration(installedApps: [HomeAppReference(appId: "offline-reading")]))
        let fixture = try await HomeStateFixture(service: HomeStateService(remote: remote, gate: gate), size: size, dark: dark)
        defer { fixture.close() }
        fixture.library.add(CloudApplication(id: "offline-reading", name: "离线阅读", emoji: "📖"))
        try fixture.library.adopt(remote)
        let before = fixture.library.snapshot
        let suffix = dark ? "largest-text-dark" : "standard-light"
        _ = try await fixture.readScreen(named: "home-before-sync-" + suffix, containing: "离线阅读", test: self)
        let idleBounds = try XCTUnwrap(fixture.visibleTextBounds["离线阅读"])
        XCTAssertNil(fixture.toolbarActivityFrame)

        let loading = Task { await fixture.sync.synchronize() }
        defer { loading.cancel(); Task { await gate.open() } }
        try await gate.waitUntilEntered()
        _ = try await fixture.readScreen(named: "home-background-sync-" + suffix, containing: "离线阅读", test: self)
        let syncingBounds = try XCTUnwrap(fixture.visibleTextBounds["离线阅读"])
        XCTAssertNotNil(fixture.toolbarActivityFrame)
        XCTAssertEqual(syncingBounds.minY, idleBounds.minY, accuracy: 0.002, "Starting sync must not move applications")

        await gate.open(); await loading.value
        XCTAssertEqual(fixture.sync.phase, .idle)
        _ = try await fixture.readScreen(named: "home-after-sync-" + suffix, containing: "离线阅读", test: self)
        let finishedBounds = try XCTUnwrap(fixture.visibleTextBounds["离线阅读"])
        XCTAssertNil(fixture.toolbarActivityFrame)
        XCTAssertEqual(finishedBounds.minY, idleBounds.minY, accuracy: 0.002, "Finishing sync must not move applications")
        XCTAssertEqual(fixture.library.snapshot, before)
    }

    func testEmptySignedInHomeShowsSyncFailureAndRetry() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(failure: URLError(.notConnectedToInternet)))
        defer { fixture.close() }
        await fixture.sync.synchronize()
        guard case .failed = fixture.sync.phase else { return XCTFail("The fixture must reach a real coordinator failure") }
        let screen = try await fixture.readScreen(named: "home-empty-sync-failed", containing: "网络暂时无法连接", test: self)
        XCTAssertTrue(screen.contains("网络暂时无法连接"), "An unsuccessful account restore must not look like an ordinary new home")
        XCTAssertTrue(screen.contains("重试同步"), "The empty home must expose a retry without requiring the options menu")
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
    }

    func testEmptySignedInHomeShowsConflictWithoutAdoptingEitherVersion() async throws {
        let remote = RemoteHomeScreen(revision: String(repeating: "b", count: 64),
            configuration: HomeConfiguration(installedApps: [HomeAppReference(appId: "cloud-only")], updatedAt: 100))
        let fixture = try await HomeStateFixture(service: HomeStateService(remote: remote))
        defer { fixture.close() }
        // Removing the last local application is still a pending change. It must
        // not silently replace a different cloud home or conceal the choice.
        let removed = CloudApplication(id: "removed-local", name: "已移除的本地应用")
        fixture.library.add(removed); fixture.library.remove(removed)
        let before = fixture.library.snapshot
        await fixture.sync.synchronize()
        guard case .conflict = fixture.sync.phase else { return XCTFail("The fixture must require a version choice") }
        let screen = try await fixture.readScreen(named: "home-empty-sync-conflict", containing: "另一台设备更新了云居", test: self)
        XCTAssertTrue(screen.contains("另一台设备更新了云居"), "The last-app removal must not hide the cloud conflict")
        XCTAssertEqual(fixture.library.snapshot, before, "Displaying a conflict must not choose a version")
    }

    func testSyncFailureKeepsExistingLocalApplicationsVisible() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(failure: URLError(.notConnectedToInternet)))
        defer { fixture.close() }
        let app = CloudApplication(id: "offline-reading", name: "离线阅读", emoji: "📖")
        fixture.library.add(app)
        let before = fixture.library.snapshot
        await fixture.sync.synchronize()
        guard case .failed = fixture.sync.phase else { return XCTFail("The fixture must reach a real coordinator failure") }
        let screen = try await fixture.readScreen(named: "home-local-content-sync-failed", containing: "离线阅读", test: self)
        XCTAssertTrue(screen.contains("离线阅读"), "Sync errors must retain the local application's launch entry")
        XCTAssertEqual(fixture.library.snapshot, before)
    }

    func testEmptyHomeWithAutomaticSyncDisabledDistinguishesAnUnreadCloudHome() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService())
        defer { fixture.close() }
        let before = fixture.library.snapshot
        XCTAssertFalse(before.autoSyncEnabled)
        XCTAssertNil(before.base)
        let screen = try await fixture.readScreen(named: "home-empty-cloud-not-read-auto-sync-disabled", containing: "尚未同步", test: self)
        XCTAssertTrue(screen.contains("尚未同步"), "A local empty home does not prove that the cloud home is empty")
        XCTAssertTrue(screen.contains("立即同步"), "Manual sync must remain available when automatic sync is disabled")
        XCTAssertEqual(fixture.sync.phase, .idle)
        XCTAssertEqual(fixture.library.snapshot, before, "Rendering must not enable synchronization or choose cloud data")
    }

    func testEmptySyncFailureKeepsRetryReachableAtLargestTextInDark() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService(failure: URLError(.notConnectedToInternet)),
            size: .accessibility5, dark: true, width: 320, height: 800)
        defer { fixture.close() }
        await fixture.sync.synchronize()
        guard case .failed = fixture.sync.phase else { return XCTFail("The fixture must reach a real coordinator failure") }
        let before = fixture.library.snapshot
        let failure = try await fixture.readScreen(named: "home-empty-sync-failed-dark-accessibility5", containing: "网络暂时无法连接", test: self)
        XCTAssertTrue(failure.contains("网络暂时无法连接"))
        let retry = try await fixture.readScreen(named: "home-empty-sync-retry-dark-accessibility5", containing: "重试同步", scrollToFind: true, test: self)
        XCTAssertTrue(retry.contains("重试同步"), "Native scrolling must expose retry without reducing the requested text size")
        XCTAssertEqual(fixture.library.snapshot, before)
    }

    func testEmptyHomeDoesNotOverrideDisabledSync() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService())
        defer { fixture.close() }
        fixture.library.setSyncEnabled(false)
        let before = fixture.library.snapshot
        let screen = try await fixture.readScreen(named: "home-empty-sync-disabled", containing: "去工坊看看", test: self)
        XCTAssertTrue(screen.contains("去工坊看看"))
        XCTAssertFalse(screen.contains("立即同步"), "A disabled sync preference must not become an invitation to start synchronization")
        XCTAssertFalse(screen.contains("尚未同步"))
        XCTAssertEqual(fixture.library.snapshot, before)
        XCTAssertEqual(fixture.sync.phase, .idle)
    }

    func testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable() async throws {
        let fixture = try await HomeStateFixture(service: HomeStateService())
        defer { fixture.close() }
        let app = CloudApplication(id: "home-running", name: "继续阅读", websiteUrl: "https://127.0.0.1:1/", emoji: "📖")
        fixture.library.add(app)
        let initial = try await fixture.readScreen(named: "home-running-before-open", containing: "继续阅读", test: self)
        XCTAssertTrue(initial.contains("继续阅读"), "Wait for the actual home launch entry before opening its session")
        let browser = try await fixture.open(app, test: self)
        _ = browser.perform(NSSelectorFromString("minimizeTapped"))
        try await fixture.waitForDismissal(of: browser)
        fixture.library.remove(app)
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
        XCTAssertTrue(fixture.runtime.contains(app), "Removing an installation does not end its paused session")
        let screen = try await fixture.readScreen(named: "home-last-installation-removed-session-retained", containing: "正在运行", test: self)
        XCTAssertTrue(screen.contains("正在运行"), "A retained session must have a visible home entry instead of an empty content area")
        XCTAssertTrue(screen.contains("去工坊看看"), "A home with no installed applications must keep its add-app guidance")
        XCTAssertTrue(fixture.runtime.contains(app), "Displaying the home must not evict the paused browser")
        let restored = try await fixture.open(app, test: self)
        XCTAssertTrue(restored === browser, "The existing session must remain resumable after its installation is removed")
        fixture.runtime.end(app)
        try await fixture.waitForDismissal(of: restored)
        XCTAssertTrue(fixture.runtime.applications.isEmpty)
        let ended = try await fixture.readScreen(named: "home-final-session-ended", containing: "去工坊看看", test: self)
        XCTAssertTrue(ended.contains("去工坊看看"))
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
            .environmentObject(WalletStore(accounts: accounts, service: AssistantWalletFixture(member: false))).environmentObject(AssistantRolloutStore())
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

private struct UnavailableStatusFixture: ApplicationAvailabilityServing {
    func application(reference: String) async throws -> CloudApplication { throw ApplicationUnavailableReason.delisted }
}

/// Hosts the production HomeView, its real coordinator and the actual native
/// session container. Only authentication and remote home responses are local
/// fixtures; the tests never contact a user account or external cloud service.
@MainActor
private final class HomeStateFixture {
    private let directory: URL
    private let authHost: String
    private let window: UIWindow
    private let previous: UIWindow?
    private let animationsWereEnabled: Bool
    private let controller: UIViewController
    let accounts: AccountStore
    let catalog: CatalogStore
    let library: HomeLibrary
    let runtime: NativeWebRuntime
    let sync: HomeSyncCoordinator
    let workspaceDefaults: UserDefaults
    private let defaultsSuite: String
    private let iconFixtureHosts: Set<String>
    private(set) var visibleTextBounds: [String: CGRect] = [:]

    var toolbarActivityFrame: CGRect? {
        func activity(in view: UIView, withinNavigationBar: Bool = false) -> UIActivityIndicatorView? {
            let inBar = withinNavigationBar || view is UINavigationBar
            if inBar, let indicator = view as? UIActivityIndicatorView, indicator.isAnimating { return indicator }
            return view.subviews.lazy.compactMap { activity(in: $0, withinNavigationBar: inBar) }.first
        }
        guard let indicator = activity(in: controller.view) else { return nil }
        return indicator.convert(indicator.bounds, to: controller.view)
    }

    init(service: HomeStateService, size: DynamicTypeSize = .large, dark: Bool = false,
         width: CGFloat = 390, height: CGFloat = 844,
         workshopService: WorkshopServing? = nil, workspaceID: String = "", workspacePicker: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authHost = UUID().uuidString.lowercased() + ".home-state.test"
        let auth = AuthHTTPFixture(replies: [(200, #"{"sub":"home-state-user","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(authHost, fixture: auth)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState(); state.activeID = "home-state-user"
        state.accounts = [SavedAccount(user: AccountUser(id: "home-state-user"), credential: AccountCredential(
            accessToken: "home-state-fixture-only", refreshToken: "not-used", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: configuration),
            origin: URL(string: "https://\(authHost)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        XCTAssertEqual(accounts.user?.id, "home-state-user")
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"), accountID: "home-state-user")
        library.setAutoSyncEnabled(false)
        let runtime = NativeWebRuntime()
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, service: service, monitorNetwork: false)
        let defaultsSuite = "HomeWorkspaceTests." + UUID().uuidString
        let workspaceDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        workspaceDefaults.set(workspaceID, forKey: HomeWorkspaceView.selectionKey(userID: "home-state-user"))
        var iconPipeline = ApplicationImagePipeline.shared
        var iconHosts = Set<String>()
        if workshopService != nil {
            let assets = CatalogIconAssets.byOrigin.values
            let urls = assets.compactMap { URL(string: $0.url) }
            let fixture = IconHTTPFixture(replies: Dictionary(urls.map { ($0.path, (200, iconTestSVG, nil as Int?)) }, uniquingKeysWith: { first, _ in first }))
            iconHosts = Set(urls.compactMap(\.host))
            for host in iconHosts { IconHTTPProtocol.register(host, fixture) }
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [IconHTTPProtocol.self]
            iconPipeline = ApplicationImagePipeline(session: URLSession(configuration: config))
            for asset in assets {
                let candidate = ApplicationIconCandidate(url: URL(string: asset.url)!, role: asset.role, revision: asset.revision)
                _ = try await iconPipeline.load([candidate], pixelSize: Int(HomeGridMetrics.iconSize * UIScreen.main.scale))
            }
        }
        let content = Group {
            if workspacePicker, let workshopService {
                HomeWorkspacePicker(accounts: accounts, workshops: MyWorkshopsStore(accounts: accounts, service: workshopService),
                    selectedID: Binding(get: { workspaceDefaults.string(forKey: HomeWorkspaceView.selectionKey(userID: accounts.user?.id)) ?? "" },
                                        set: { workspaceDefaults.set($0, forKey: HomeWorkspaceView.selectionKey(userID: accounts.user?.id)) }))
            } else {
                NavigationStack {
                    if let workshopService {
                        HomeWorkspaceView(accounts: accounts, service: workshopService, defaults: workspaceDefaults, iconPipeline: iconPipeline, browse: {})
                    } else { HomeView {} }
                }
            }
        }
            .environmentObject(catalog).environmentObject(library).environmentObject(runtime)
            .environmentObject(accounts).environmentObject(sync)
            .environmentObject(WalletStore(accounts: accounts, service: AssistantWalletFixture(member: false))).environmentObject(AssistantRolloutStore())
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(dark ? .dark : .light)
        let controller = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        self.directory = directory; self.authHost = authHost
        self.accounts = accounts; self.catalog = catalog; self.library = library
        self.runtime = runtime; self.sync = sync; self.controller = controller
        self.workspaceDefaults = workspaceDefaults; self.defaultsSuite = defaultsSuite
        self.iconFixtureHosts = iconHosts
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        window.rootViewController = controller; window.makeKeyAndVisible()
        runtime.configureAuthorization(accounts: accounts)
        runtime.anchor = controller
    }

    func readScreen(named name: String, containing expected: String, scrollToFind: Bool = false, test: XCTestCase) async throws -> String {
        // A large-text scan needs several OCR passes before the target reaches
        // the viewport. On CI, Vision can take seconds per pass.
        let deadline = Date().addingTimeInterval(scrollToFind ? 30 : 5)
        var image: UIImage?, lines: [String] = []
        repeat {
            try await Task.sleep(nanoseconds: 100_000_000)
            controller.view.layoutIfNeeded()
            let rendered = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            image = rendered
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(rendered.cgImage)).perform([request])
            lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            visibleTextBounds = Dictionary((request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { (Self.normalized($0.string), observation.boundingBox) }
            }, uniquingKeysWith: { first, _ in first })
            if scrollToFind, !Self.normalized(lines.joined()).contains(Self.normalized(expected)),
               let scroll = scrollView(in: controller.view) {
                let bottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                // A loading row can initially be the bottom of a short list.
                // Keep waiting for the requested content until the deadline.
                if scroll.contentOffset.y < bottom {
                    let step = max(100, (scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom) / 2)
                    scroll.setContentOffset(CGPoint(x: 0, y: min(scroll.contentOffset.y + step, bottom)), animated: false)
                }
            }
        } while !Self.normalized(lines.joined()).contains(Self.normalized(expected)) && Date() < deadline
        if let image {
            let screenshot = XCTAttachment(image: image); screenshot.name = name; screenshot.lifetime = .keepAlways; test.add(screenshot)
        }
        let transcript = XCTAttachment(string: lines.joined(separator: "\n"))
        transcript.name = name + "-recognized-visible-text"; transcript.lifetime = .keepAlways; test.add(transcript)
        return Self.normalized(lines.joined())
    }

    func open(_ app: CloudApplication, test: XCTestCase) async throws -> WebViewController {
        let preparationDeadline = Date().addingTimeInterval(5)
        while runtime.isIdentityCleanupPending {
            guard Date() < preparationDeadline else {
                recordOpenState(app, stage: "initial-identity-cleanup-timeout", test: test)
                XCTFail("The fixture's initial identity cleanup did not finish before opening")
                throw NSError(domain: "HomeLayoutVisualTests", code: 5)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let deadline = Date().addingTimeInterval(5)
        recordOpenState(app, stage: "before-request", test: test)
        runtime.open(app, catalog: catalog, library: library)
        recordOpenState(app, stage: "after-one-request", test: test)
        if let issue = runtime.issue {
            XCTFail("The runtime rejected the fixture's single open request: \(issue.title) — \(issue.message)")
            throw NSError(domain: "HomeLayoutVisualTests", code: 4)
        }
        repeat {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let navigation = controller.presentedViewController as? UINavigationController,
               let browser = navigation.topViewController as? WebViewController,
               browser.appInfo?.id == app.id, browser.viewIfLoaded?.window != nil,
               !navigation.isBeingPresented, !navigation.isBeingDismissed {
                browser.view.subviews.compactMap { $0 as? WKWebView }.first?.stopLoading()
                return browser
            }
        } while Date() < deadline
        recordOpenState(app, stage: "presentation-timeout", test: test)
        XCTFail("The fixture's native session did not finish opening")
        throw NSError(domain: "HomeLayoutVisualTests", code: 1)
    }

    private func recordOpenState(_ app: CloudApplication, stage: String, test: XCTestCase) {
        var ancestor = controller
        while let parent = ancestor.parent { ancestor = parent }
        let navigation = controller.presentedViewController as? UINavigationController
        let browser = navigation?.topViewController as? WebViewController
        let text = """
        stage=\(stage)
        launchURL=\(app.launchURL?.absoluteString ?? "nil")
        canOpenAsGuest=\(app.canOpenAsGuest)
        issueTitle=\(runtime.issue?.title ?? "nil")
        issueMessage=\(runtime.issue?.message ?? "nil")
        anchorIsController=\(runtime.anchor === controller)
        anchorHasFixtureWindow=\(runtime.anchor?.viewIfLoaded?.window === window)
        controllerHasFixtureWindow=\(controller.viewIfLoaded?.window === window)
        ancestorIsWindowRoot=\(ancestor === window.rootViewController)
        windowIsKey=\(window.isKeyWindow)
        windowIsHidden=\(window.isHidden)
        presentedController=\(controller.presentedViewController.map { String(reflecting: type(of: $0)) } ?? "nil")
        presenting=\(navigation?.isBeingPresented ?? false)
        dismissing=\(navigation?.isBeingDismissed ?? false)
        visibleBrowserID=\(browser?.appInfo?.id ?? "nil")
        browserHasWindow=\(browser?.viewIfLoaded?.window != nil)
        runtimeContainsApplication=\(runtime.contains(app))
        runtimeApplicationCount=\(runtime.applications.count)
        """
        let attachment = XCTAttachment(string: text)
        attachment.name = "home-state-open-" + stage; attachment.lifetime = .keepAlways; test.add(attachment)
    }

    func waitForDismissal(of browser: WebViewController) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if controller.presentedViewController == nil && browser.viewIfLoaded?.window == nil { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        XCTFail("The native browser did not return to the production HomeView")
        throw NSError(domain: "HomeLayoutVisualTests", code: 2)
    }

    func close() {
        // Automatic sync is disabled for every fixture. Cancel the real
        // coordinator task before releasing a held response or removing files.
        sync.identityChanged()
        for app in Array(runtime.applications) { runtime.end(app) }
        XCTAssertTrue(runtime.applications.isEmpty)
        controller.dismiss(animated: false)
        window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
        UIView.setAnimationsEnabled(animationsWereEnabled)
        AuthHTTPProtocol.unregister(authHost)
        workspaceDefaults.removePersistentDomain(forName: defaultsSuite)
        iconFixtureHosts.forEach(IconHTTPProtocol.unregister)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func normalized(_ value: String) -> String {
        value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }
            .map(String.init).joined()
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}

private struct HomeWorkspaceServiceFixture: WorkshopServing {
    var access: WorkshopAccess = .active
    var firstPageGate: HomeStateLoadGate?
    private func workshop(_ id: String) -> PersonalWorkshop {
        PersonalWorkshop(id: id, ownerName: "云乐坊", ownerAvatar: nil,
            name: id == "ABC234" ? "云乐坊私有工坊" : "灵感工坊", description: nil, joinPolicy: .closed, status: .active, ownerUid: "home-state-user")
    }
    func mine(identity: AuthorizedAccount) async throws -> WorkshopManagement? {
        WorkshopManagement(workshop: workshop("ABC234"), pending: [], guests: [], blocked: [])
    }
    func joined(identity: AuthorizedAccount) async throws -> [PersonalWorkshop] { [workshop("ABC234"), workshop("DEF567")] }
    func page(id: String, identity: AuthorizedAccount?) async throws -> WorkshopPage {
        guard identity?.userID == "home-state-user" else { throw WorkshopError.unauthorized }
        if id == "ABC234" { await firstPageGate?.wait() }
        let apps: [CloudApplication]
        if id == "ABC234" {
            apps = [CloudApplication(id: "workspace-admin", name: "管理后台", websiteUrl: "https://admin.yunle.fun", emoji: "🛠️",
                        accessMode: "login_required", audience: "workshop", accessWorkshopID: id),
                    CloudApplication(id: "workspace-support", name: "支持中心", websiteUrl: "https://support.yunle.fun", emoji: "💬",
                        accessMode: "login_required", audience: "workshop", accessWorkshopID: id)]
        } else {
            apps = [CloudApplication(id: "workspace-notes", name: "灵感笔记", websiteUrl: "https://example.invalid", emoji: "📝",
                        accessMode: "public", audience: "workshop", accessWorkshopID: id)]
        }
        return WorkshopPage(surface: "workshop", access: access, workshop: workshop(id), apps: access == .active ? apps : [])
    }
    func create(draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop { throw WorkshopError.forbidden }
    func update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop { throw WorkshopError.forbidden }
    func join(id: String, identity: AuthorizedAccount) async throws -> WorkshopJoinResult { throw WorkshopError.forbidden }
    func leave(id: String, identity: AuthorizedAccount) async throws -> WorkshopMembership { throw WorkshopError.forbidden }
    func decide(id: String, member: WorkshopMembership, action: WorkshopDecision, identity: AuthorizedAccount) async throws -> WorkshopMembership { throw WorkshopError.forbidden }
}

private actor HomeStateService: HomeSyncServing {
    private let remote: RemoteHomeScreen
    private let failure: Error?
    private let gate: HomeStateLoadGate?
    init(remote: RemoteHomeScreen = RemoteHomeScreen(revision: nil, configuration: HomeConfiguration()),
         failure: Error? = nil, gate: HomeStateLoadGate? = nil) {
        self.remote = remote; self.failure = failure; self.gate = gate
    }
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        await gate?.wait()
        if let failure { throw failure }
        return remote
    }
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        XCTFail("Rendering a home state must not publish local configuration")
        throw HomeSyncError.unavailable
    }
}

private actor HomeStateLoadGate {
    private var entered = false
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        if !opened { await withCheckedContinuation { waiting.append($0) } }
    }
    func waitUntilEntered() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !entered {
            guard Date() < deadline else {
                XCTFail("The coordinator did not enter the fixture home service within five seconds")
                throw NSError(domain: "HomeLayoutVisualTests", code: 3)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    func open() { opened = true; waiting.forEach { $0.resume() }; waiting = [] }
}
