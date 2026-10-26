import Foundation
import Security
import UIKit
import WebKit
import XCTest
@testable import YunleFun

/// Runs the production Cook page through the real native host and managed auth.
/// Secrets stay in native controls; the page receives only its normal SSO code.
@MainActor
final class CookHostLiveTests: XCTestCase {
    func testManagedCookLoginClipboardAndHaptics() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["YUNLEFUN_LIVE_COOK_HOST"] == "1" else {
            throw XCTSkip("Requires explicit production Cook host validation")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("CookHostAcceptance/input.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            return XCTFail("One-use input must be private")
        }
        let bytes = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Input.self, from: bytes)
        guard UUID(uuidString: pool.runID) != nil, pool.runID == environment["YUNLEFUN_LIVE_COOK_RUN_ID"],
              pool.simulatorID == environment["SIMULATOR_UDID"], pool.accounts.count == 1,
              let credential = pool.accounts.first, credential.id == "production-zero-balance",
              credential.environment == "production", credential.username == "ylf_prod_zero",
              !credential.password.isEmpty else { return XCTFail("Managed account or simulator binding differs") }

        let directory = cache.appendingPathComponent("CookHostAcceptance/" + pool.runID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keychain = "fun.yunle.apps.cook-host." + pool.runID
        let profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: keychain)
        let runtime = NativeWebRuntime(webProfiles: profiles)
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let catalog = CatalogStore()
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychain)),
                                    accountWillRemove: { id in try runtime.retireAccount(id) },
                                    identityDidChange: { id in
            runtime.resetIdentity(to: id)
            library.activateAccount(id)
            library.setAutoSyncEnabled(false)
        })
        runtime.configureAuthorization(accounts: accounts)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previousRoot = window.rootViewController
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
        runtime.anchor = root
        let previousClipboard = UIPasteboard.general.items
        defer {
            UIPasteboard.general.items = previousClipboard
            runtime.resetIdentity()
            window.rootViewController = previousRoot
            window.makeKeyAndVisible()
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychain] as CFDictionary)
        }

        var phase = "catalog"
        var checks: [String: Bool] = [:]
        var failure: String?
        var application: CloudApplication?
        var consumer: WKWebView?
        func mark(_ next: String) { phase = next; print("COOK_HOST_LIVE_STAGE " + next) }
        do {
            await catalog.load()
            let app = try XCTUnwrap(catalog.applications.first { $0.marketShortName == "cook" })
            application = app
            guard app.websiteUrl == "https://cook.yunle.fun/home" else { throw Failure.observation }
            try await wait(seconds: 15) { !runtime.isIdentityCleanupPending }
            runtime.open(app, catalog: catalog, library: library)
            try await wait(seconds: 35) {
                guard let browser = self.browser(window), let web = self.webView(browser.view) else { return false }
                let ready = try? await web.evaluateJavaScript("document.title === '食用手册' && !!document.querySelector('ion-tab-button')")
                return !web.isLoading && ready as? Bool == true
            }
            let browser = try XCTUnwrap(self.browser(window))
            let web = try XCTUnwrap(webView(browser.view))
            consumer = web
            mark("capabilities")
            let capabilities = try await javascript(web, """
            const result = {};
            for (const name of ['authorize', 'haptic', 'setClipboard']) result[name] = await window.ylf.canIUse(name);
            return result;
            """) as? [String: Bool]
            guard capabilities == ["authorize": true, "haptic": true, "setClipboard": true] else { throw Failure.observation }
            let host = try await javascript(web, "return await window.ylf.getEnv();") as? [String: Any]
            guard host?["trusted"] as? Bool == true, host?["platform"] as? String == "ios",
                  host?["displayMode"] as? String == "titlebar" else { throw Failure.observation }
            checks["nativeCapabilitiesAndTrustedTitlebar"] = true
            for style in ["light", "success"] {
                _ = try await javascript(web, "await window.ylf.haptic(style); return true;", arguments: ["style": style])
            }
            checks["realNativeHapticCallsAcknowledged"] = true
            let clipboard = "Cook host acceptance " + pool.runID
            _ = try await javascript(web, "await window.ylf.setClipboard(text); return true;", arguments: ["text": clipboard])
            guard UIPasteboard.general.string == clipboard else { throw Failure.observation }
            checks["nativeClipboardReadbackMatches"] = true
            UIPasteboard.general.items = previousClipboard

            mark("cook-my-page")
            let opened = try await web.evaluateJavaScript("""
            (() => { const tab = [...document.querySelectorAll('ion-tab-button')].find(x => x.textContent.trim() === '我的');
              if (!tab) return false; tab.click(); return true; })()
            """) as? Bool
            guard opened == true else { throw Failure.observation }
            try await wait(seconds: 20) { (try? await self.state(web))?["hasLogin"] as? Bool == true }
            mark("native-password-form")
            try await clickItem(web, containing: "使用云乐坊账号登录")
            try await wait(seconds: 20) {
                guard let sheet = browser.presentedViewController else { return false }
                return !sheet.isBeingPresented && self.segmentedControl(sheet.view) != nil
            }
            let sheet = try XCTUnwrap(browser.presentedViewController)
            let segments = try XCTUnwrap(segmentedControl(sheet.view))
            let passwordIndex = try XCTUnwrap((0..<segments.numberOfSegments).first { segments.titleForSegment(at: $0) == "密码" })
            segments.selectedSegmentIndex = passwordIndex
            segments.sendActions(for: .valueChanged)
            try await wait(seconds: 5) { self.fields(sheet.view).contains { $0.isSecureTextEntry } }
            let fields = self.fields(sheet.view)
            let username = try XCTUnwrap(fields.first { !$0.isSecureTextEntry && $0.placeholder == "用户名、邮箱或手机号" })
            let password = try XCTUnwrap(fields.first { $0.isSecureTextEntry })
            guard username.becomeFirstResponder() else { throw Failure.observation }
            username.insertText(credential.username)
            username.sendActions(for: .editingChanged)
            await Task.yield()
            guard password.becomeFirstResponder() else { throw Failure.observation }
            password.insertText(credential.password)
            password.sendActions(for: .editingChanged)
            try await Task.sleep(nanoseconds: 300_000_000)
            guard username.text == credential.username, password.text == credential.password else { throw Failure.observation }
            password.sendActions(for: .editingDidEndOnExit)
            mark("native-login-and-consent")
            try await wait(seconds: 40) { accounts.user?.username == credential.username }
            checks["nativePasswordFormAuthenticatedManagedAccount"] = true
            try await acceptConsent(browser, owner: try XCTUnwrap(accounts.user))
            try await wait(seconds: 35) {
                guard let owner = accounts.user else { return false }
                return (try? await self.state(web))?["name"] as? String == owner.displayName && browser.presentedViewController == nil
            }
            guard browser === self.browser(window), web.url?.host == "cook.yunle.fun" else { throw Failure.observation }
            checks["cookAdoptedHostIdentityWithoutNavigation"] = true
            attach(window, name: "cook-host-signed-in")

            mark("consumer-sign-out")
            try await signOut(web)
            checks["cookSignOutKeepsHostSignedIn"] = accounts.user?.username == credential.username
            mark("native-consent-cancel")
            try await clickItem(web, containing: "使用云乐坊账号登录")
            try await wait(seconds: 20) { browser.presentedViewController is AuthorizationConsentViewController }
            let consent = try XCTUnwrap(browser.presentedViewController as? AuthorizationConsentViewController)
            try await wait(seconds: 5) { !consent.isBeingPresented }
            let cancel = try XCTUnwrap(button(consent.view, identifier: "authorization-cancel"))
            cancel.sendActions(for: .touchUpInside)
            try await wait(seconds: 15) {
                (try? await self.state(web))?["hasLogin"] as? Bool == true && browser.presentedViewController == nil
            }
            guard web.url?.host == "cook.yunle.fun" else { throw Failure.observation }
            checks["denialDidNotFallBackToWebRedirect"] = true
            mark("retry-after-cancel")
            try await clickItem(web, containing: "使用云乐坊账号登录")
            try await acceptConsent(browser, owner: try XCTUnwrap(accounts.user))
            try await wait(seconds: 30) {
                guard let owner = accounts.user else { return false }
                return (try? await self.state(web))?["name"] as? String == owner.displayName
            }
            checks["retryAfterCancellationSucceeded"] = true
            try await signOut(web)
            checks["consumerSignedOutAtCleanup"] = true
        } catch {
            failure = phase + ": " + String(reflecting: type(of: error))
            attach(window, name: "cook-host-failure-" + phase)
        }

        if checks["consumerSignedOutAtCleanup"] != true, let consumer {
            do { try await signOut(consumer); checks["consumerSignedOutAtCleanup"] = true }
            catch { checks["consumerSignedOutAtCleanup"] = false }
        }
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id); checks["hostRemoteSignOutAcknowledged"] = accounts.notice == nil }
            catch { checks["hostRemoteSignOutAcknowledged"] = false }
        }
        if let application { runtime.end(application) }
        let report: [String: Any] = ["runID": pool.runID, "app": "cook", "origin": "https://cook.yunle.fun",
            "checks": checks, "failure": failure ?? "", "scope": "iOS simulator, real WKWebView, production managed synthetic account",
            "physicalHapticFeelingTested": false, "hostCredentialsInjectedIntoWebView": false]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: cache.appendingPathComponent("CookHostAcceptance/report.json"), options: .atomic)
        let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        attachment.name = "cook-host-runtime-report"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertNil(failure)
        XCTAssertEqual(checks.count, 10)
        XCTAssertTrue(checks.values.allSatisfy { $0 })
    }

    private func javascript(_ web: WKWebView, _ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await web.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }
    private func state(_ web: WKWebView) async throws -> [String: Any] {
        try await web.evaluateJavaScript("""
        (() => ({ name: document.querySelector('.my-account h2')?.textContent.trim() || '',
          hasLogin: [...document.querySelectorAll('ion-item')].some(x => x.textContent.includes('使用云乐坊账号登录')),
          hasSignOut: [...document.querySelectorAll('ion-item')].some(x => x.textContent.trim() === '退出登录') }))()
        """) as? [String: Any] ?? [:]
    }
    private func clickItem(_ web: WKWebView, containing text: String) async throws {
        let clicked = try await javascript(web, "const item = [...document.querySelectorAll('ion-item')].find(x => x.textContent.trim().includes(text)); if (!item) return false; item.click(); return true;", arguments: ["text": text]) as? Bool
        guard clicked == true else { throw Failure.observation }
    }
    private func signOut(_ web: WKWebView) async throws {
        if (try? await state(web))?["hasLogin"] as? Bool == true { return }
        try await clickItem(web, containing: "退出登录")
        try await wait(seconds: 25) {
            let state = try? await self.state(web)
            return state?["hasLogin"] as? Bool == true && state?["name"] as? String == ""
        }
    }
    private func acceptConsent(_ browser: WebViewController, owner: AccountUser) async throws {
        try await wait(seconds: 25) {
            guard let consent = browser.presentedViewController as? AuthorizationConsentViewController else { return false }
            return !consent.isBeingPresented && self.button(consent.view, identifier: "authorization-current-account")?.isEnabled == true
        }
        let consent = try XCTUnwrap(browser.presentedViewController as? AuthorizationConsentViewController)
        let current = try XCTUnwrap(button(consent.view, identifier: "authorization-current-account"))
        guard current.accessibilityLabel?.contains(owner.displayName) == true else { throw Failure.observation }
        current.sendActions(for: .touchUpInside)
    }
    private func wait(seconds: TimeInterval, condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure.timeout
    }
    private func browser(_ window: UIWindow) -> WebViewController? {
        let presented = window.rootViewController?.presentedViewController
        return (presented as? UINavigationController)?.viewControllers.compactMap { $0 as? WebViewController }.first ?? presented as? WebViewController
    }
    private func webView(_ view: UIView) -> WKWebView? {
        (view as? WKWebView) ?? view.subviews.compactMap { webView($0) }.first
    }
    private func segmentedControl(_ view: UIView) -> UISegmentedControl? {
        (view as? UISegmentedControl) ?? view.subviews.compactMap { segmentedControl($0) }.first
    }
    private func fields(_ view: UIView) -> [UITextField] {
        if let field = view as? UITextField { return [field] }
        return view.subviews.flatMap { fields($0) }
    }
    private func button(_ view: UIView, identifier: String) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        return view.subviews.compactMap { button($0, identifier: identifier) }.first
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private struct Input: Decodable { let runID: String; let simulatorID: String; let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum Failure: Error { case observation, timeout }
}
