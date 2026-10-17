import SwiftUI
import Vision
import WebKit
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

    func testEmptySignedInHomeShowsAnInFlightSync() async throws {
        let gate = HomeStateLoadGate()
        let fixture = try await HomeStateFixture(service: HomeStateService(gate: gate))
        defer { fixture.close() }
        let loading = Task { await fixture.sync.synchronize() }
        defer { loading.cancel(); Task { await gate.open() } }
        try await gate.waitUntilEntered()
        XCTAssertEqual(fixture.sync.phase, .syncing)
        let screen = try await fixture.readScreen(named: "home-empty-syncing", containing: "正在同步云居", test: self)
        XCTAssertTrue(screen.contains("正在同步云居"), "An empty local home must show that the account's cloud home is still loading")
        XCTAssertTrue(fixture.library.snapshot.applications.isEmpty)
        await gate.open(); await loading.value
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

    init(service: HomeStateService, size: DynamicTypeSize = .large, dark: Bool = false,
         width: CGFloat = 390, height: CGFloat = 844) async throws {
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
        let content = NavigationStack { HomeView {} }
            .environmentObject(catalog).environmentObject(library).environmentObject(runtime)
            .environmentObject(accounts).environmentObject(sync)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(dark ? .dark : .light)
        let controller = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        self.directory = directory; self.authHost = authHost
        self.accounts = accounts; self.catalog = catalog; self.library = library
        self.runtime = runtime; self.sync = sync; self.controller = controller
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
        let deadline = Date().addingTimeInterval(5)
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
            if scrollToFind, !Self.normalized(lines.joined()).contains(Self.normalized(expected)),
               let scroll = scrollView(in: controller.view) {
                let bottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                guard scroll.contentOffset.y < bottom else { break }
                let step = max(100, (scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom) / 2)
                scroll.setContentOffset(CGPoint(x: 0, y: min(scroll.contentOffset.y + step, bottom)), animated: false)
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
        print("[DEBUG-cookie] wait.begin time=\(ProcessInfo.processInfo.systemUptime) applicationState=\(UIApplication.shared.applicationState.rawValue)")
        let preparationDeadline = Date().addingTimeInterval(5)
        while runtime.isIdentityCleanupPending {
            guard Date() < preparationDeadline else {
                recordOpenState(app, stage: "initial-identity-cleanup-timeout", test: test)
                XCTFail("The fixture's initial identity cleanup did not finish before opening")
                print("[DEBUG-cookie] wait.failed time=\(ProcessInfo.processInfo.systemUptime)")
                // Preserve the original failure first; allow external diagnostic samples afterwards.
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if #available(iOS 17.0, *) {
                    let policy = XCTestExpectation(description: "post-failure cookie policy probe")
                    WKWebsiteDataStore.default().httpCookieStore.getCookiePolicy { _ in
                        print("[DEBUG-cookie] policy.callback time=\(ProcessInfo.processInfo.systemUptime)")
                        policy.fulfill()
                    }
                    let result = await XCTWaiter.fulfillment(of: [policy], timeout: 2)
                    print("[DEBUG-cookie] policy.verdict=\(result.rawValue) pending=\(runtime.isIdentityCleanupPending)")
                }
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
