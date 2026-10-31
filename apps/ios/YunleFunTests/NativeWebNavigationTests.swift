import Darwin
import Network
import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class NativeWebNavigationTests: XCTestCase {
    func testGameInteractionSwitchesApplyIndependentlyWithoutReloading() async throws {
        let fixture = try await Fixture(gameInteractions: true)
        defer { fixture.close() }
        _ = try await fixture.webView.callAsyncJavaScript("""
            window.gameProgress = 'still-playing';
            const frame = document.createElement('iframe');
            frame.id = 'game-policy-frame';
            frame.srcdoc = '<html><body><p style="user-select:text;-webkit-user-select:text">棋盘</p></body></html>';
            const loaded = new Promise(resolve => frame.onload = resolve);
            document.body.appendChild(frame);
            await loaded;
            """, arguments: [:], in: nil, contentWorld: .page)
        let scriptCount = fixture.webView.configuration.userContentController.userScripts.count
        let cases = [WebGameInteractionSettings(allowsPageBounce: true, allowsLongPress: false),
                     WebGameInteractionSettings(allowsPageBounce: false, allowsLongPress: true),
                     WebGameInteractionSettings(allowsPageBounce: true, allowsLongPress: true),
                     WebGameInteractionSettings()]
        for settings in cases {
            fixture.browser.gameInteractionSettings = settings
            let state = try await fixture.interactionState()
            XCTAssertEqual(fixture.webView.scrollView.bounces, settings.allowsPageBounce)
            XCTAssertEqual(fixture.webView.allowsLinkPreview, settings.allowsLongPress)
            XCTAssertEqual(state["boardSelection"] as? String, settings.allowsLongPress ? "text" : "none")
            XCTAssertEqual(state["boardCallout"] as? String, settings.allowsLongPress ? "default" : "none")
            XCTAssertEqual(state["overscroll"] as? String, settings.allowsPageBounce ? "auto" : "none")
            XCTAssertEqual(state["inputValue"] as? String, "ABC234")
            let frameSelection = try await fixture.webView.callAsyncJavaScript("""
                const frame = document.getElementById('game-policy-frame');
                const expected = allowsLongPress ? 'text' : 'none';
                let selection;
                for (let attempt = 0; attempt < 50; attempt++) {
                  selection = frame.contentWindow.getComputedStyle(frame.contentDocument.querySelector('p')).webkitUserSelect;
                  if (selection === expected) return selection;
                  await new Promise(resolve => setTimeout(resolve, 20));
                }
                return selection;
                """, arguments: ["allowsLongPress": settings.allowsLongPress], in: nil, contentWorld: .page)
            XCTAssertEqual(frameSelection as? String, settings.allowsLongPress ? "text" : "none")
            let progress = try await fixture.webView.evaluateJavaScript("window.gameProgress")
            XCTAssertEqual(progress as? String, "still-playing")
            XCTAssertEqual(fixture.webView.configuration.userContentController.userScripts.count, scriptCount)
            _ = try await fixture.environment()
        }
        fixture.browser.gameInteractionSettings = WebGameInteractionSettings(allowsPageBounce: true, allowsLongPress: true)
        try await fixture.load(title: "enabled")
        let enabled = try await fixture.interactionState()
        XCTAssertEqual(enabled["boardSelection"] as? String, "text")
        XCTAssertEqual(enabled["overscroll"] as? String, "auto")
    }

    func testGameInteractionPolicyPreservesScrollingAndEditingAcrossNavigation() async throws {
        let fixture = try await Fixture(gameInteractions: true)
        defer { fixture.close() }
        XCTAssertFalse(fixture.webView.scrollView.bounces)
        XCTAssertFalse(fixture.webView.scrollView.alwaysBounceVertical)
        XCTAssertFalse(fixture.webView.allowsLinkPreview)
        XCTAssertTrue(fixture.webView.scrollView.isScrollEnabled)
        XCTAssertTrue(fixture.webView.configuration.preferences.isTextInteractionEnabled)

        for title in ["first", "second"] {
            if title != "first" { try await fixture.load(title: title) }
            let state = try await fixture.interactionState()
            XCTAssertEqual(state["boardSelection"] as? String, "none")
            XCTAssertEqual(state["boardCallout"] as? String, "none")
            XCTAssertEqual(state["overscroll"] as? String, "none")
            XCTAssertEqual(state["imageDrag"] as? String, "none")
            XCTAssertEqual(state["editableSelections"] as? [String], ["text", "text", "text", "text"])
            XCTAssertEqual(state["inputCallout"] as? String, "default")
            XCTAssertEqual(state["inputValue"] as? String, "ABC234")
            XCTAssertEqual(state["selectedText"] as? String, "ABC")
            XCTAssertGreaterThan(try XCTUnwrap(state["scrollY"] as? Double), 0, "\(title): \(state)")
        }
    }

    func testOrdinaryWebApplicationKeepsBrowserInteractions() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.webView.scrollView.bounces)
        XCTAssertTrue(fixture.webView.allowsLinkPreview)
        let state = try await fixture.interactionState()
        XCTAssertEqual(state["boardSelection"] as? String, "text")
        XCTAssertEqual(state["boardCallout"] as? String, "default")
        XCTAssertEqual(state["overscroll"] as? String, "auto")
        XCTAssertEqual(state["inputValue"] as? String, "ABC234")
        XCTAssertGreaterThan(try XCTUnwrap(state["scrollY"] as? Double), 0)
    }

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

    func testGameRetryAfterActualWebContentExitRemountsPageAndPreservesStorage() async throws {
        #if targetEnvironment(simulator)
        let server = try RetryHTTPServer()
        try await server.start()
        defer { server.stop() }
        let fixture = try await RetryFixture(url: XCTUnwrap(server.url))
        defer { fixture.close() }
        let original = try await fixture.mountedDocument()
        let store = fixture.webView.configuration.websiteDataStore
        let marker = UUID().uuidString
        try await fixture.seedStorage(marker)
        try await fixture.acceptInput()

        // The PID comes from this test-owned, non-persistent WKWebView only.
        // Never select an unrelated process by name, age or simulator-wide list.
        XCTAssertFalse(store.isPersistent)
        guard fixture.webView.responds(to: NSSelectorFromString("_webProcessIdentifier")),
              let number = fixture.webView.value(forKey: "_webProcessIdentifier") as? NSNumber else {
            throw XCTSkip("This Simulator WebKit does not expose its owned process identifier")
        }
        let terminatedPID = number.int32Value
        guard terminatedPID > 1, terminatedPID != getpid() else { throw RetryFixture.Failure.invalidProcess }
        XCTAssertEqual(kill(terminatedPID, SIGKILL), 0)
        let retry = try await fixture.waitForRetry()
        retry.sendActions(for: .touchUpInside)
        let restored = try await fixture.mountedDocument(differentFrom: original["documentID"] as? String)
        XCTAssertFalse(fixture.failureVisible)
        XCTAssertTrue(fixture.webView.configuration.websiteDataStore === store)
        XCTAssertEqual(restored["context"] as? [String: String], original["context"] as? [String: String])
        XCTAssertEqual(restored["path"] as? String, original["path"] as? String)
        XCTAssertNotEqual((fixture.webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, terminatedPID)
        try await fixture.assertStorage(marker)
        try await fixture.acceptInput()
        let evidence: [String: Any] = [
            "kind": "native-game-retry-loopback-real-webcontent-exit",
            "actualSIGKILL": true, "sameWKWebViewAndStore": true,
            "remountedNonemptyDocument": true, "contextAndStoragePreserved": true,
            "restoredNavigationType": restored["navigationType"] ?? NSNull(),
            "scope": "Owned loopback document and real native retry button; this does not replace the production-game empty-document reproduction and final two-account verification.",
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "native-game-retry-webcontent-exit"; attachment.lifetime = .keepAlways; add(attachment)
        #else
        throw XCTSkip("Only a Simulator-owned WebContent process may be terminated by this test")
        #endif
    }

    func testGameRetryCanLoadOriginalURLAfterFirstNavigationNeverCommits() async throws {
        let server = try RetryHTTPServer(rejectConnections: true)
        try await server.start()
        defer { server.stop() }
        let fixture = try await RetryFixture(url: XCTUnwrap(server.url), expectingNavigationFailure: true)
        defer { fixture.close() }
        let retry = try await fixture.waitForRetry()
        XCTAssertNil(fixture.webView.url, "The failed first provisional navigation must have no committed document to reload")
        XCTAssertNil(fixture.webView.backForwardList.currentItem)
        server.allowRequests()
        retry.sendActions(for: .touchUpInside)
        _ = try await fixture.mountedDocument()
        XCTAssertFalse(fixture.failureVisible)
        try await fixture.acceptInput()
    }

    func testGameRetryAfterWebContentExitRevalidatesCachedNotFoundDocument() async throws {
        #if targetEnvironment(simulator)
        guard #available(iOS 17, *) else { throw XCTSkip("The production game uses a named persistent WebKit store") }
        let profile = UUID()
        do {
            try await exerciseCachedNotFoundRetry(profile: profile)
        } catch {
            try await removeOwnedRetryProfile(profile)
            throw error
        }
        try await removeOwnedRetryProfile(profile)
        #else
        throw XCTSkip("Only a Simulator-owned WebContent process may be terminated")
        #endif
    }

    func testGameRetryAfterWebContentExitKeepsCurrentSPARoomDestination() async throws {
        #if targetEnvironment(simulator)
        let server = try RetryHTTPServer()
        try await server.start()
        defer { server.stop() }
        let fixture = try await RetryFixture(url: XCTUnwrap(server.url))
        defer { fixture.close() }
        _ = try await fixture.webView.evaluateJavaScript("document.getElementById('join-room').click()")
        let original = try await fixture.mountedDocument()
        XCTAssertEqual(original["path"] as? String, "/room/retry-fixture")
        let marker = UUID().uuidString
        try await fixture.seedStorage(marker)
        guard fixture.webView.responds(to: NSSelectorFromString("_webProcessIdentifier")),
              let number = fixture.webView.value(forKey: "_webProcessIdentifier") as? NSNumber,
              number.int32Value > 1, number.int32Value != getpid() else { throw RetryFixture.Failure.invalidProcess }
        XCTAssertEqual(kill(number.int32Value, SIGKILL), 0)
        let retry = try await fixture.waitForRetry()
        retry.sendActions(for: .touchUpInside)
        let restored = try await fixture.mountedDocument(differentFrom: original["documentID"] as? String)
        XCTAssertEqual(restored["path"] as? String, original["path"] as? String,
                       "Recovery must keep the current SPA room rather than reopening the original game entry")
        XCTAssertEqual(restored["context"] as? [String: String], original["context"] as? [String: String])
        try await fixture.assertStorage(marker)
        try await fixture.acceptInput()
        #else
        throw XCTSkip("Only a Simulator-owned WebContent process may be terminated")
        #endif
    }

    @available(iOS 17, *)
    private func removeOwnedRetryProfile(_ profile: UUID) async throws {
        // WebKit releases a dismissed window's store on a later run-loop turn.
        for attempt in 0..<10 {
            do { try await WKWebsiteDataStore.remove(forIdentifier: profile); return }
            catch {
                guard attempt < 9, (error as NSError).domain == "WKWebSiteDataStore",
                      (error as NSError).code == 1 else { throw error }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    @available(iOS 17, *)
    private func exerciseCachedNotFoundRetry(profile: UUID) async throws {
        let server = try RetryHTTPServer(revalidatingNotFound: true)
        try await server.start()
        defer { server.stop() }
        let fixture = try await RetryFixture(url: XCTUnwrap(server.url), store: WKWebsiteDataStore(forIdentifier: profile))
        defer { fixture.close() }
        let original = try await fixture.mountedDocument()
        let marker = UUID().uuidString
        try await fixture.seedStorage(marker)
        guard fixture.webView.responds(to: NSSelectorFromString("_webProcessIdentifier")),
              let number = fixture.webView.value(forKey: "_webProcessIdentifier") as? NSNumber,
              number.int32Value > 1, number.int32Value != getpid() else { throw RetryFixture.Failure.invalidProcess }
        XCTAssertEqual(kill(number.int32Value, SIGKILL), 0)
        let retry = try await fixture.waitForRetry()
        retry.sendActions(for: .touchUpInside)
        defer {
            print("NATIVE_RETRY_CACHED404 conditional-304=\(server.revalidationCount) owned-profile=\(profile)")
            let evidence = XCTAttachment(string: "HTTP 404 entity, public,max-age=0,must-revalidate, ETag; conditional 304 responses: \(server.revalidationCount); test-owned profile: \(profile)")
            evidence.name = "native-retry-cached-404"; evidence.lifetime = .keepAlways; add(evidence)
        }
        let restored = try await fixture.mountedDocument(differentFrom: original["documentID"] as? String)
        XCTAssertEqual(restored["path"] as? String, original["path"] as? String)
        XCTAssertFalse(fixture.failureVisible)
        try await fixture.assertStorage(marker)
        try await fixture.acceptInput()
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

        init(dark: Bool = false, gameInteractions: Bool = false) async throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            browser.usesSystemNavigationBar = true
            browser.usesGameInteractionPolicy = gameInteractions
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

        func interactionState() async throws -> [String: Any] {
            let result = try await webView.callAsyncJavaScript("""
                const host = document.createElement('section');
                document.getElementById('interaction-fixture')?.remove();
                host.id = 'interaction-fixture';
                host.innerHTML = `<div id="board" style="user-select:text;-webkit-user-select:text">棋盘文字</div>
                  <input id="room"><textarea id="chat"></textarea>
                  <div id="editor" contenteditable="true"><span id="editor-child">昵称</span></div>
                  <img id="piece"><div style="height:300vh"></div>`;
                document.body.appendChild(host);
                // Measure scrolling before keyboard focus/blur can restore its own offset.
                await new Promise(resolve => requestAnimationFrame(resolve));
                window.scrollTo(0, 100);
                await new Promise(resolve => requestAnimationFrame(resolve));
                const scrollY = window.scrollY;
                const scrollHeight = document.scrollingElement.scrollHeight;
                const clientHeight = document.scrollingElement.clientHeight;
                window.scrollTo(0, 0);
                const input = document.getElementById('room');
                input.focus();
                document.execCommand('insertText', false, 'ABC234');
                input.setSelectionRange(0, 3);
                const selectedText = input.value.slice(input.selectionStart, input.selectionEnd);
                input.blur();
                const style = id => getComputedStyle(document.getElementById(id));
                return {
                  boardSelection: style('board').webkitUserSelect,
                  boardCallout: style('board').webkitTouchCallout,
                  overscroll: getComputedStyle(document.documentElement).overscrollBehaviorY,
                  imageDrag: style('piece').webkitUserDrag,
                  editableSelections: ['room', 'chat', 'editor', 'editor-child'].map(id => style(id).webkitUserSelect),
                  inputCallout: style('room').webkitTouchCallout,
                  inputValue: input.value, selectedText, scrollY, scrollHeight, clientHeight
                };
                """, arguments: [:], in: nil, contentWorld: .page)
            return try XCTUnwrap(result as? [String: Any])
        }

        func close() { browser.cancelPendingAuthorizations(); root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        private static func findWebView(in view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { findWebView(in: $0) }.first
        }
    }

    @MainActor
    private final class RetryFixture {
        let window: UIWindow
        let previous: UIWindow?
        let root = UIViewController()
        let browser = WebViewController()
        let navigation: UINavigationController
        let webView: WKWebView

        init(url: URL, expectingNavigationFailure: Bool = false, store: WKWebsiteDataStore? = nil) async throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            browser.usesSystemNavigationBar = true
            browser.onGameLifecycleMessage = { _, _ in }
            browser.websiteDataStore = store ?? .nonPersistent()
            browser.url = url
            navigation = UINavigationController(rootViewController: browser)
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController = root; window.makeKeyAndVisible()
            root.present(navigation, animated: false)
            webView = try XCTUnwrap(Self.find(in: browser.view) { $0 as? WKWebView })
            if !expectingNavigationFailure { _ = try await mountedDocument() }
        }

        var failureVisible: Bool { Self.find(in: browser.view) { $0.accessibilityIdentifier == "games.loading-failure" ? $0 : nil } != nil }

        func waitForRetry() async throws -> UIButton {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if let button = Self.find(in: browser.view, match: { view in
                    view.accessibilityIdentifier == "games.loading-retry" ? view as? UIButton : nil
                }) { return button }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw Failure.missingRetry
        }

        func mountedDocument(differentFrom oldID: String? = nil) async throws -> [String: Any] {
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                let state = try? await WebStoragePageFixture.evaluate(in: webView, script: """
                    const root = document.getElementById('retry-game');
                    const query = new URL(location.href).searchParams;
                    return {mounted: root?.dataset.mounted === 'true', documentID: root?.dataset.documentId || '',
                      childCount: root?.childElementCount || 0, path: location.pathname,
                      context: Object.fromEntries(['ylfLaunchId','ylfGameId','ylfMode'].map(key => [key,query.get(key) || ''])),
                      navigationType: performance.getEntriesByType('navigation')[0]?.type || null};
                    """) as? [String: Any]
                if let state, state["mounted"] as? Bool == true, (state["childCount"] as? Int ?? 0) > 0,
                   let id = state["documentID"] as? String, !id.isEmpty, id != oldID { return state }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw Failure.emptyDocument
        }

        func seedStorage(_ marker: String) async throws {
            _ = try await WebStoragePageFixture.evaluate(in: webView, script: """
                localStorage.setItem('native-retry', marker);
                document.cookie = 'native_retry=' + marker + '; Path=/; SameSite=Lax';
                const database = await new Promise((resolve, reject) => {
                  const request = indexedDB.open('native-retry',1);
                  request.onupgradeneeded = () => request.result.createObjectStore('markers');
                  request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
                });
                try { await new Promise((resolve,reject) => {
                  const transaction = database.transaction('markers','readwrite');
                  transaction.objectStore('markers').put(marker,'draft');
                  transaction.oncomplete = () => resolve(); transaction.onerror = transaction.onabort = () => reject(transaction.error);
                }); } finally { database.close(); }
                return true;
                """, arguments: ["marker": marker])
        }

        func assertStorage(_ marker: String) async throws {
            let state = try await WebStoragePageFixture.evaluate(in: webView, script: """
                const database = await new Promise((resolve,reject) => {
                  const request = indexedDB.open('native-retry',1);
                  request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
                });
                try {
                  const value = await new Promise((resolve,reject) => {
                    const transaction = database.transaction('markers','readonly');
                    const request = transaction.objectStore('markers').get('draft');
                    transaction.oncomplete = () => resolve(request.result || '');
                    transaction.onerror = transaction.onabort = () => reject(transaction.error);
                  });
                  return {cookie: document.cookie.includes('native_retry=' + marker),
                    localStorage: localStorage.getItem('native-retry'), indexedDB: value};
                } finally { database.close(); }
                """, arguments: ["marker": marker]) as? [String: Any]
            XCTAssertEqual(state?["cookie"] as? Bool, true)
            XCTAssertEqual(state?["localStorage"] as? String, marker)
            XCTAssertEqual(state?["indexedDB"] as? String, marker)
        }

        func acceptInput() async throws {
            let accepted = try await WebStoragePageFixture.evaluate(in: webView, script: """
                const output = document.getElementById('moves');
                const before = Number(output.textContent);
                document.getElementById('move').click();
                return Number(output.textContent) === before + 1;
                """) as? Bool
            XCTAssertEqual(accepted, true, "The remounted page must process its actual input handler")
        }

        func close() {
            webView.stopLoading(); browser.cancelPendingAuthorizations()
            root.dismiss(animated: false); window.isHidden = true
            window.rootViewController = nil; previous?.makeKey()
        }

        private static func find<T: UIView>(in view: UIView, match: (UIView) -> T?) -> T? {
            if let result = match(view) { return result }
            for child in view.subviews { if let result = find(in: child, match: match) { return result } }
            return nil
        }
        enum Failure: Error { case missingRetry, emptyDocument, invalidProcess }
    }
}

/// Fixed synthetic content only. No credentials, application files or external
/// service is reachable through this loopback-only, system-assigned listener.
private final class RetryHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "native-web-retry-fixture")
    private var connections: [UUID: NWConnection] = [:]
    private var rejectConnections: Bool
    private let revalidatingNotFound: Bool
    private var revalidations = 0
    var revalidationCount: Int { queue.sync { revalidations } }
    var url: URL? { listener.port.flatMap { URL(string: "http://127.0.0.1:\($0.rawValue)/fixture?ylfLaunchId=retry-fixture&ylfGameId=room&ylfMode=online") } }

    init(rejectConnections: Bool = false, revalidatingNotFound: Bool = false) throws {
        self.rejectConnections = rejectConnections
        self.revalidatingNotFound = revalidatingNotFound
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        let readiness = RetryListenerReadiness()
        listener.stateUpdateHandler = { readiness.receive($0) }
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
        guard await XCTWaiter.fulfillment(of: [readiness.ready], timeout: 5) == .completed else { throw Failure.listenerTimedOut }
        try XCTUnwrap(readiness.result).get()
    }

    func allowRequests() { queue.sync { rejectConnections = false } }
    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        if rejectConnections { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, request: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let bytes = request + (data ?? Data())
            guard bytes.count <= 65_536 else { self.finish(connection, id: id); return }
            guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete || error != nil { self.finish(connection, id: id) }
                else { self.receive(connection, id: id, request: bytes) }
                return
            }
            let body = """
                <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>native-retry-fixture</title></head>
                <body><main id="retry-game"><h1>Retry fixture</h1><button id="move">Move</button><output id="moves">0</output><button id="join-room">Join room</button></main>
                <script>
                const root = document.getElementById('retry-game');
                root.dataset.documentId = crypto.randomUUID();
                document.getElementById('move').addEventListener('click', () => {
                  const output = document.getElementById('moves'); output.textContent = String(Number(output.textContent) + 1);
                });
                document.getElementById('join-room').addEventListener('click', () => {
                  const room = new URL(location.href); room.pathname = '/room/retry-fixture';
                  history.pushState({room: 'retry-fixture'}, '', room);
                });
                root.dataset.mounted = 'true';
                </script></body></html>
                """
            let conditional = self.revalidatingNotFound && String(decoding: bytes, as: UTF8.self).lowercased()
                .contains("if-none-match: \"native-retry-fixture-v1\"")
            if conditional { self.revalidations += 1 }
            let status = conditional ? "304 Not Modified" : self.revalidatingNotFound ? "404 Not Found" : "200 OK"
            let cache = self.revalidatingNotFound ? "public,max-age=0,must-revalidate\r\nETag: \"native-retry-fixture-v1\"" : "no-store"
            let entity = conditional ? "" : body
            let length = conditional ? "" : "Content-Length: \(entity.utf8.count)\r\n"
            let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: \(cache)\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; base-uri 'none'\r\n\(length)Connection: close\r\n\r\n"
            connection.send(content: Data((header + entity).utf8), completion: .contentProcessed { [weak self] _ in self?.finish(connection, id: id) })
        }
    }

    private func finish(_ connection: NWConnection, id: UUID) { connection.cancel(); connections.removeValue(forKey: id) }
    enum Failure: Error { case listenerTimedOut }
}

private final class RetryListenerReadiness: @unchecked Sendable {
    let ready = XCTestExpectation(description: "Native retry HTTP fixture is listening")
    private let lock = NSLock()
    private var outcome: Result<Void, NWError>?
    var result: Result<Void, NWError>? { lock.lock(); defer { lock.unlock() }; return outcome }
    func receive(_ state: NWListener.State) {
        let next: Result<Void, NWError>
        switch state {
        case .ready: next = .success(())
        case .failed(let error): next = .failure(error)
        default: return
        }
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = next; lock.unlock(); ready.fulfill()
    }
}
