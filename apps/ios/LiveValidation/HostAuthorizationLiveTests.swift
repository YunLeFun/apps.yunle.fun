import CryptoKit
import Foundation
import Security
import SwiftUI
import WebKit
import XCTest
@testable import YunleFun

/// Drives real page controls and the native consent button in-process. Host
/// credentials never enter JavaScript; no identity or token is injected into JS.
@MainActor
final class HostIdentitySwitchLiveTests: XCTestCase {
    func testRealCloudApplicationDoesNotRestoreAnotherHostAccount() async throws {
        let env = ProcessInfo.processInfo.environment
        let guestFirst = env["YUNLEFUN_LIVE_HOST_GUEST_PROFILE"] == "1"
        guard env["YUNLEFUN_LIVE_HOST_IDENTITY_SWITCH"] == "1" else {
            throw XCTSkip("Requires explicit managed-account SSO identity validation")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an owned isolated simulator may run this validation")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"] else { return XCTFail("Requires the exact owned simulator") }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/sso-identity-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else { return XCTFail("One-use input must be private") }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-zero-balance": "ylf_prod_zero", "production-standard": "ylf_prod_standard"]
        guard pool.accounts.count == 2, Set(pool.accounts.map(\.id)) == Set(expected.keys),
              pool.accounts.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty }),
              let first = pool.accounts.first(where: { $0.id == "production-zero-balance" }),
              let second = pool.accounts.first(where: { $0.id == "production-standard" }) else {
            return XCTFail("Only the two fixed managed synthetic identities are permitted")
        }
        let keychain = "fun.yunle.apps.sso-switch." + UUID().uuidString
        let directory = cache.appendingPathComponent("HostIdentitySwitch-" + UUID().uuidString)
        let library = HomeLibrary(directory: directory)
        let catalog = CatalogStore()
        let runtime = NativeWebRuntime()
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychain)),
                                    accountWillRemove: { id in try runtime.retireAccount(id) }, identityDidChange: { id in
            runtime.resetIdentity(to: id)
            library.activateAccount(id)
            library.setAutoSyncEnabled(false)
        })
        runtime.configureAuthorization(accounts: accounts)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
        runtime.anchor = root
        defer {
            runtime.resetIdentity()
            window.rootViewController = previous
            window.makeKeyAndVisible()
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychain] as CFDictionary)
            try? FileManager.default.removeItem(at: directory)
        }
        var phases: [[String: Any]] = []
        var stage = "catalog"
        var failure = false
        var foreignIdentityObserved = false
        var signedInNames: [String] = []
        var initialID: String?
        let draftKey = "native-sso-isolation-probe-" + UUID().uuidString
        var application: CloudApplication?
        weak var lastBrowser: WebViewController?
        var consentCount = 0
        var guestLoginSucceeded = false
        var guestFormDiagnostics: [String: Bool] = [:]
        do {
            await catalog.load()
            guard let app = catalog.applications.first(where: { $0.marketShortName == "ai-sfc" }) else {
                throw ProbeFailure.observation
            }
            application = app
            for (index, credential) in [first, second, first].enumerated() {
                stage = "host-selection-\(index)"
                var continuedGuest: WebViewController?
                if index == 0 && guestFirst {
                    stage = "guest-page-open"
                    try await wait(seconds: 15) { !runtime.isIdentityCleanupPending && root.presentedViewController == nil }
                    runtime.open(app, catalog: catalog, library: library)
                    try await wait(seconds: 30) {
                        guard let browser = self.browser(in: window), let web = self.webView(in: browser.view),
                              let state = try? await self.pageState(web) else { return false }
                        return !web.isLoading && state["ready"] as? Bool == true && state["name"] as? String == ""
                    }
                    let guestBrowser = try XCTUnwrap(browser(in: window))
                    let guestWeb = try XCTUnwrap(webView(in: guestBrowser.view))
                    _ = try await guestWeb.evaluateJavaScript("localStorage.setItem('\(draftKey)', 'account-a-draft')")
                    _ = try await guestWeb.evaluateJavaScript("document.querySelector('a[aria-label=\"我的春联\"]').click()")
                    try await wait(seconds: 10) {
                        (try? await self.pageState(guestWeb))?["historyLoginGate"] as? Bool == true
                    }
                    _ = try await guestWeb.evaluateJavaScript("document.querySelector('button.account-login').click()")
                    stage = "guest-native-password-form"
                    try await wait(seconds: 15) {
                        guard let sheet = guestBrowser.presentedViewController else { return false }
                        return self.segmentedControl(in: sheet.view) != nil && !sheet.isBeingPresented
                    }
                    let sheet = try XCTUnwrap(guestBrowser.presentedViewController)
                    let picker = try XCTUnwrap(segmentedControl(in: sheet.view))
                    let passwordIndex = try XCTUnwrap((0..<picker.numberOfSegments).first { picker.titleForSegment(at: $0) == "密码" })
                    picker.selectedSegmentIndex = passwordIndex
                    picker.sendActions(for: .valueChanged)
                    try await wait(seconds: 5) { self.textFields(in: sheet.view).contains { $0.isSecureTextEntry } }
                    let fields = textFields(in: sheet.view)
                    let username = try XCTUnwrap(fields.first { !$0.isSecureTextEntry && $0.placeholder == "用户名、邮箱或手机号" })
                    let password = try XCTUnwrap(fields.first { $0.isSecureTextEntry })
                    guard username.becomeFirstResponder() else { throw ProbeFailure.observation }
                    username.insertText(credential.username)
                    username.sendActions(for: .editingChanged)
                    await Task.yield()
                    guard password.becomeFirstResponder() else { throw ProbeFailure.observation }
                    password.insertText(credential.password)
                    password.sendActions(for: .editingChanged)
                    try await Task.sleep(nanoseconds: 300_000_000)
                    guard username.text == credential.username, password.text == credential.password else { throw ProbeFailure.observation }
                    // Dispatch the text field's submit control event, as UIKit
                    // does after Return. Calling its delegate alone omits this.
                    password.sendActions(for: .editingDidEndOnExit)
                    stage = "guest-native-login-submit"
                    do {
                        try await wait(seconds: 35) { accounts.user?.username == credential.username }
                    } catch {
                        // Record only known static UI messages and booleans, never
                        // text-field values, response bodies or arbitrary labels.
                        let labels = self.staticLabels(in: sheet.view)
                        guestFormDiagnostics = [
                            "errorElementPresent": self.hasElement(in: sheet.view, identifier: "login.error"),
                            "processingLabelPresent": labels.contains("正在处理"),
                            "usernameStillMatches": username.text == credential.username,
                            "passwordStillMatches": password.text == credential.password,
                            "sheetStillPresented": sheet.presentingViewController != nil]
                        throw error
                    }
                    guestLoginSucceeded = true
                    guard self.browser(in: window) === guestBrowser else { throw ProbeFailure.observation }
                    continuedGuest = guestBrowser
                } else if index == 2, let initialID { try await accounts.select(initialID) }
                else { try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil) }
                guard let host = accounts.user, host.username == credential.username, host.isUsable else {
                    throw ProbeFailure.observation
                }
                let freshIdentity = try await accounts.authorization(forceRefresh: true)
                guard freshIdentity.userID == host.id else { throw ProbeFailure.observation }
                if index == 0 { initialID = host.id }
                if index == 1, host.id == initialID { throw ProbeFailure.observation }
                if index == 1, signedInNames.first == host.displayName { throw ProbeFailure.ambiguousDisplayName }
                try await wait(seconds: 15) { !runtime.isIdentityCleanupPending && (continuedGuest != nil || root.presentedViewController == nil) }
                let oldSessionRemoved = !runtime.contains(app)
                guard oldSessionRemoved || continuedGuest != nil else { throw ProbeFailure.observation }
                stage = "reopen-\(index)"
                if continuedGuest == nil { runtime.open(app, catalog: catalog, library: library) }
                try await wait(seconds: 30) {
                    guard let browser = self.browser(in: window), let web = self.webView(in: browser.view),
                          let state = try? await self.pageState(web) else { return false }
                    return !web.isLoading && state["ready"] as? Bool == true
                }
                guard let browser = browser(in: window), let web = webView(in: browser.view),
                      web.url?.host == "ai-sfc.yunle.fun" else { throw ProbeFailure.observation }
                let newBrowser = lastBrowser == nil || lastBrowser !== browser
                lastBrowser = browser
                guard newBrowser else { throw ProbeFailure.observation }
                // Observe before cleanup or consent. In the guest-first phase
                // the login request already began; other phases precede SSO.
                // A cached foreign name fails even if the app later replaces it.
                stage = "preauthorization-identity-\(index)"
                var state = try await pageState(web)
                let cachedName = state["name"] as? String ?? ""
                if !cachedName.isEmpty && cachedName != host.displayName {
                    foreignIdentityObserved = true
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let rendered = try await pageState(web)
                    let renderedName = rendered["name"] as? String ?? ""
                    phases.append(["phase": index, "hostAccount": credential.id,
                                   "oldRuntimeSessionRemoved": oldSessionRemoved, "newBrowserCreated": newBrowser,
                                   "freshHostAuthorizationMatches": true, "foreignIdentityBeforeAuthorization": true,
                                   "foreignIdentityAfterRenderDelay": !renderedName.isEmpty && renderedName != host.displayName])
                    attach(window, name: "sso-switch-foreign-identity-phase-\(index)")
                    throw ProbeFailure.foreignIdentity
                }
                // A synthetic non-authentication draft detects both cross-account
                // exposure and a destructive "clear all storage" workaround.
                let draft = try await web.evaluateJavaScript("localStorage.getItem('\(draftKey)')")
                if index == 1, !(draft is NSNull) { throw ProbeFailure.observation }
                if index == 2, draft as? String != "account-a-draft" { throw ProbeFailure.observation }
                if index == 0 {
                    if guestFirst && draft as? String != "account-a-draft" { throw ProbeFailure.observation }
                    _ = try await web.evaluateJavaScript("localStorage.setItem('\(draftKey)', 'account-a-draft')")
                }
                var historyGate = continuedGuest != nil
                var activatedLogin = continuedGuest != nil
                if cachedName.isEmpty {
                    guard state["hasLogin"] as? Bool == true else { throw ProbeFailure.observation }
                    if continuedGuest == nil {
                        let clicked = try await web.evaluateJavaScript("""
                        (() => { const a = document.querySelector('a[aria-label="我的春联"]');
                          if (!a) return false; a.click(); return true; })()
                        """) as? Bool
                        guard clicked == true else { throw ProbeFailure.observation }
                        try await wait(seconds: 10) {
                            guard let state = try? await self.pageState(web) else { return false }
                            return state["historyLoginGate"] as? Bool == true
                        }
                        historyGate = true
                        let login = try await web.evaluateJavaScript("""
                        (() => { const b = document.querySelector('button.account-login');
                          if (!b || b.disabled) return false; b.click(); return true; })()
                        """) as? Bool
                        guard login == true else { throw ProbeFailure.observation }
                        activatedLogin = true
                    }
                    stage = "real-sso-adoption-\(index)"
                    var accepted = Set<ObjectIdentifier>()
                    try await wait(seconds: 35) {
                        if let consent = browser.presentedViewController as? AuthorizationConsentViewController,
                           !consent.isBeingPresented, !consent.isBeingDismissed,
                           !accepted.contains(ObjectIdentifier(consent)),
                           let button = self.button(in: consent.view, identifier: "authorization-current-account"), button.isEnabled {
                            guard button.accessibilityLabel?.contains(host.displayName) == true else { throw ProbeFailure.observation }
                            accepted.insert(ObjectIdentifier(consent))
                            consentCount += 1
                            self.attach(window, name: "sso-switch-native-consent-phase-\(index)")
                            button.sendActions(for: .touchUpInside)
                        }
                        guard let state = try? await self.pageState(web) else { return false }
                        return state["name"] as? String == host.displayName && browser.presentedViewController == nil
                    }
                }
                state = try await pageState(web)
                guard state["name"] as? String == host.displayName else { throw ProbeFailure.observation }
                signedInNames.append(host.displayName)
                attach(window, name: "sso-switch-matching-identity-phase-\(index)")
                phases.append(["phase": index, "hostAccount": credential.id,
                               "oldRuntimeSessionRemoved": oldSessionRemoved, "newBrowserCreated": newBrowser,
                               "freshHostAuthorizationMatches": true,
                               "foreignIdentityBeforeAuthorization": false, "historyLoginGateObserved": historyGate,
                               "realPageLoginActivated": activatedLogin, "displayedIdentityMatchesHost": true,
                               "draftIsolationAndRetentionChecked": index > 0,
                               "guestBrowserKeptThroughNativePasswordLogin": continuedGuest != nil])
            }
        } catch { failure = true }
        // The actual application's logout control is used after observations,
        // including a failing foreign-identity observation. No storage is wiped.
        var webSignedOut = true
        var cleanupVisits = 0
        if cleanupGuestNeeded(accounts), let browser = browser(in: window), let web = webView(in: browser.view) {
            _ = try? await web.evaluateJavaScript("localStorage.removeItem('\(draftKey)')")
        }
        // Visit every signed-in host's partition after the observations so both
        // real consumer sessions are signed out without deleting business data.
        let cleanupIDs = accounts.overview.users.map(\.id)
        for id in cleanupIDs {
            do {
                if accounts.user?.id != id { try await accounts.select(id) }
                try await wait(seconds: 15) { !runtime.isIdentityCleanupPending }
                if browser(in: window) == nil {
                    guard let application else { throw ProbeFailure.observation }
                    runtime.open(application, catalog: catalog, library: library)
                }
                try await wait(seconds: 30) {
                    guard let browser = self.browser(in: window), let web = self.webView(in: browser.view),
                          let state = try? await self.pageState(web) else { return false }
                    return !web.isLoading && state["ready"] as? Bool == true
                }
                guard let browser = browser(in: window), let web = webView(in: browser.view) else { throw ProbeFailure.observation }
                _ = try await web.evaluateJavaScript("localStorage.removeItem('\(draftKey)')")
                cleanupVisits += 1
                let signedOut = await signOutWebUI(web)
                webSignedOut = webSignedOut && signedOut
            } catch { webSignedOut = false }
        }
        var hostSignedOut = true
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id); hostSignedOut = hostSignedOut && accounts.notice == nil }
            catch { hostSignedOut = false }
        }
        let restored = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychain)))
        await restored.restore()
        let emptyKeychain = restored.user == nil && restored.overview.users.isEmpty
        let report: [String: Any] = ["phases": phases, "failureStage": failure ? stage : "none",
            "foreignIdentityObserved": foreignIdentityObserved, "nativeConsentCount": consentCount,
            "nativeGuestPasswordFormDriven": guestFirst, "nativeGuestLoginSucceeded": guestLoginSucceeded,
            "guestFormDiagnostics": guestFormDiagnostics,
            "applicationLogoutUIConfirmed": webSignedOut, "applicationCleanupVisits": cleanupVisits,
            "hostSessionsRemoteSignOut": hostSignedOut,
            "emptyKeychain": emptyKeychain, "oneUseInputDeleted": !FileManager.default.fileExists(atPath: input.path),
            "hostCredentialsInjectedIntoWebView": false, "applicationConsumerRemoteRevocationIndependentlyVerified": false,
            "scope": "Real HTTPS and NativeWebRuntime; in-process DOM clicks and UIKit control events; no OS gesture or system other-account flow"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-host-identity-switch-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertFalse(failure, "Real application identity journey failed at \(stage); response values omitted")
        XCTAssertFalse(foreignIdentityObserved, "The reopened application displayed a different host account before authorization")
        XCTAssertEqual(phases.count, 3)
        XCTAssertTrue(webSignedOut); XCTAssertTrue(hostSignedOut); XCTAssertTrue(emptyKeychain)
    }

    private func cleanupGuestNeeded(_ accounts: AccountStore) -> Bool { accounts.overview.users.isEmpty }

    private func pageState(_ web: WKWebView) async throws -> [String: Any] {
        guard web.url?.host == "ai-sfc.yunle.fun" else { throw ProbeFailure.observation }
        return try await web.evaluateJavaScript("""
        (() => ({ ready: document.readyState === 'complete' && !!document.querySelector('.account-login,.account-trigger'),
          name: document.querySelector('.account-name')?.textContent?.trim() || '',
          hasLogin: !!document.querySelector('button.account-login'),
          historyLoginGate: location.pathname === '/history' && !document.querySelector('.history-list') &&
            document.body.innerText.includes('登录后即可保存与查看你生成过的春联。') }))()
        """) as? [String: Any] ?? [:]
    }

    private func signOutWebUI(_ web: WKWebView) async -> Bool {
        do {
            let state = try await pageState(web)
            if state["name"] as? String == "" { return state["hasLogin"] as? Bool == true }
            _ = try await web.evaluateJavaScript("""
            (() => { const b = document.querySelector('button.account-trigger');
              if (!b) return false;
              b.click();
              return true; })()
            """)
            try await wait(seconds: 5) {
                (try? await web.evaluateJavaScript("!!document.querySelector('.account-action.danger')")) as? Bool == true
            }
            _ = try await web.evaluateJavaScript("document.querySelector('.account-action.danger').click()")
            try await wait(seconds: 15) {
                guard let state = try? await self.pageState(web) else { return false }
                return state["name"] as? String == "" && state["hasLogin"] as? Bool == true
            }
            return true
        } catch { return false }
    }

    private func wait(seconds: TimeInterval, condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProbeFailure.timeout
    }
    private func browser(in window: UIWindow) -> WebViewController? {
        if let navigation = window.rootViewController?.presentedViewController as? UINavigationController {
            return navigation.viewControllers.compactMap { $0 as? WebViewController }.first
        }
        return window.rootViewController?.presentedViewController as? WebViewController
    }
    private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.compactMap { webView(in: $0) }.first
    }
    private func segmentedControl(in view: UIView) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl { return control }
        return view.subviews.compactMap { segmentedControl(in: $0) }.first
    }
    private func textFields(in view: UIView) -> [UITextField] {
        if let field = view as? UITextField { return [field] }
        return view.subviews.flatMap { textFields(in: $0) }
    }
    private func staticLabels(in view: UIView) -> [String] {
        let own = (view as? UILabel)?.text.map { [$0] } ?? []
        return own + view.subviews.flatMap { staticLabels(in: $0) }
    }
    private func hasElement(in view: UIView, identifier: String) -> Bool {
        view.accessibilityIdentifier == identifier || view.subviews.contains { hasElement(in: $0, identifier: identifier) }
    }
    private func button(in view: UIView, identifier: String) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        return view.subviews.compactMap { button(in: $0, identifier: identifier) }.first
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum ProbeFailure: Error { case observation, ambiguousDisplayName, foreignIdentity, timeout }
}

/// Explicit live contract validation with an existing managed synthetic identity.
/// The host token only reaches the fixed CloudBase gateway. The consumer receives
/// the one-time code and its own PKCE verifier, never the host session.
@MainActor
final class HostAuthorizationLiveTests: XCTestCase {
    private var observations: [[String: Any]] = []
    func testRealCloudApplicationLoginConsentAndSignOut() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOST_SSO_UI"] == "1" else {
            throw XCTSkip("Requires explicit live UI driving of the managed native login and consent")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/host-sso-ui-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            return XCTFail("Live credentials require owner-only access")
        }
        let secret = try Data(contentsOf: input); try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: secret)
        guard pool.accounts.count == 1, let credential = pool.accounts.first,
              credential.id == "production-zero-balance", credential.environment == "production",
              credential.username == "ylf_prod_zero" else { return XCTFail("Requires the fixed zero-balance identity") }
        let service = "fun.yunle.apps.host-sso-ui." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let directory = cache.appendingPathComponent("HostSSOUI-" + UUID().uuidString)
        let library = HomeLibrary(directory: directory)
        let catalog = CatalogStore()
        let runtime = NativeWebRuntime()
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: service))) { id in
            runtime.resetIdentity(to: id); library.activateAccount(id); library.setAutoSyncEnabled(false)
        }
        runtime.configureAuthorization(accounts: accounts)
        let wallet = WalletStore(accounts: accounts)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet)
        runtime.configureCommerce(wallet: wallet, purchases: purchases)
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, monitorNetwork: false)
        let assistant = AssistantStore(accounts: accounts)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let page = UIHostingController(rootView: AppRootView().environmentObject(catalog).environmentObject(library)
            .environmentObject(runtime).environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
            .environmentObject(sync).environmentObject(assistant))
        window.rootViewController = page; window.makeKeyAndVisible()
        defer {
            runtime.resetIdentity()
            window.rootViewController = previous; window.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: directory)
        }
        var failure: Error?
        var appSignedIn = false
        var appSignedOut = false
        var consentSeen = false
        var hostSignedOut = false
        do {
            await catalog.load()
            let app = try XCTUnwrap(catalog.applications.first { $0.marketShortName == "ai-sfc" })
            try await Task.sleep(nanoseconds: 500_000_000)
            runtime.open(app, catalog: catalog, library: library)
            print("YLF_UI_HOST_SSO_READY")
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                if let browser = presentedBrowser(in: window) {
                    if browser.presentedViewController is AuthorizationConsentViewController { consentSeen = true }
                    if let web = webView(in: browser.view),
                       let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
                       let user = accounts.user, user.username == credential.username, user.isUsable,
                       body.contains(user.displayName), browser.presentedViewController == nil {
                        appSignedIn = true; break
                    }
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard appSignedIn, consentSeen else { throw LiveFailure.identity }
            attach(window, name: "real-cloud-app-native-sso-signed-in")
            print("YLF_UI_CLOUD_IDENTITY_READY")
            let logoutDeadline = Date().addingTimeInterval(90)
            while Date() < logoutDeadline {
                if let browser = presentedBrowser(in: window),
                   let web = webView(in: browser.view),
                   let user = accounts.user,
                   let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
                   !body.contains(user.displayName), body.contains("登录") {
                    appSignedOut = true; break
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard appSignedOut else { throw LiveFailure.identity }
            attach(window, name: "real-cloud-app-signed-out")
        } catch { failure = error }
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id); hostSignedOut = accounts.notice == nil }
            catch { if failure == nil { failure = error } }
        }
        let report: [String: Any] = ["account": credential.id, "nativeConsentSeen": consentSeen,
            "applicationDisplayedHostIdentity": appSignedIn, "applicationSignedOut": appSignedOut,
            "hostSignedOut": hostSignedOut, "hostCredentialsInjectedIntoWebView": false,
            "scope": "one simulator and AI Spring Festival couplets production application"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-host-sso-ui-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertNil(failure.map { _ in "Live UI authorization journey failed; response contents omitted" })
        XCTAssertTrue(appSignedIn); XCTAssertTrue(appSignedOut); XCTAssertTrue(consentSeen); XCTAssertTrue(hostSignedOut)
    }
    private func presentedBrowser(in window: UIWindow) -> WebViewController? {
        let presented = window.rootViewController?.presentedViewController
        if let navigation = presented as? UINavigationController {
            return navigation.viewControllers.compactMap { $0 as? WebViewController }.first
        }
        return presented as? WebViewController
    }
    private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = webView(in: child) { return web } }
        return nil
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNativeCodeExchangePKCEReplayAndIdentity() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOST_SSO"] == "1" else {
            throw XCTSkip("Requires managed synthetic credentials and explicit live SSO validation")
        }
        let input = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iOSNativeValidation/host-sso-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0 else {
            return XCTFail("Live credentials require owner-only file access")
        }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        guard pool.accounts.count == 1, let credential = pool.accounts.first,
              credential.id == "production-zero-balance", credential.environment == "production",
              credential.username == "ylf_prod_zero", !credential.password.isEmpty else {
            return XCTFail("Only the approved zero-balance synthetic identity may run this test")
        }
        let keychainService = "fun.yunle.apps.host-sso-live." + UUID().uuidString
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychainService)))
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: keychainService] as CFDictionary) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let consumer = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { consumer.invalidateAndCancel() }
        let deviceID = UUID().uuidString
        var temporaryToken: String?
        var stages: [String] = []
        var stage = "host login"
        var failure: Error?
        var temporarySignedOut = false
        var hostSignedOut = false
        do {
            try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
            let identity = try await accounts.authorization(forceRefresh: true)
            let verifier = randomValue()
            let nonce = randomValue()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let origin = "https://ai-sfc.yunle.fun"
            let request = try HostSsoRequest(sourceOrigin: origin, parameters: [
                "clientId": "ai-sfc-web", "redirectUri": origin + "/", "scope": ["identity:bootstrap"],
                "nonce": nonce, "codeChallenge": challenge, "codeChallengeMethod": "S256", "prompt": "consent",
            ])
            let host = HostAuthorizationService()
            stage = "registered policy"
            let policy = try await host.resolve(request)
            guard policy.applicationID == "ai-sfc", policy.applicationOrigin == origin,
                  policy.prompt == "consent" else { throw LiveFailure.protocolResponse }
            stages.append("native resolver validates registered AI Spring Festival couplets policy")
            stage = "native code issuance"
            let issued = try await host.issue(request, identity: identity)
            stages.append("native service issues a real PKCE-bound one-time code")
            let exchangeURL = URL(string: "https://api.yunle.fun/sso-ticket")!
            let exchange: [String: Any] = [
                "action": "exchangeSsoCode", "clientId": request.clientID, "redirectUri": request.redirectURI,
                "scope": "identity:bootstrap", "code": issued.code, "nonce": nonce, "codeVerifier": verifier,
            ]
            stage = "PKCE rejection"
            var invalid = exchange; invalid["codeVerifier"] = randomValue()
            let rejected = try await send(consumer, url: exchangeURL, fields: invalid, origin: origin)
            guard rejected.status == 403, rejected.body["ok"] as? Bool == false,
                  rejected.body["reason"] as? String == "pkce_invalid" else { throw LiveFailure.protocolResponse }
            stages.append("wrong consumer PKCE verifier is rejected without consuming the code")
            stage = "one-time code consumption"
            let consumed = try await send(consumer, url: exchangeURL, fields: exchange, origin: origin)
            guard consumed.status == 200, consumed.body["ok"] as? Bool == true,
                  let ticket = consumed.body["ticket"] as? String, !ticket.isEmpty,
                  let assertion = consumed.body["identityAssertion"] as? String,
                  assertion.split(separator: ".").count == 3 else { throw LiveFailure.protocolResponse }
            stages.append("real HTTPS consumer exchanges code for a ticket and identity assertion")
            stage = "code replay rejection"
            let replay = try await send(consumer, url: exchangeURL, fields: exchange, origin: origin)
            guard replay.status == 409, replay.body["ok"] as? Bool == false,
                  replay.body["reason"] as? String == "code_used" else { throw LiveFailure.protocolResponse }
            stages.append("a second exchange of the same code is rejected")
            stage = "consumer temporary sign-in"
            let signedIn = try await send(consumer, url: CloudbaseAuthService.gateway.appendingPathComponent("auth/v1/signin/custom"),
                                          fields: ["provider_id": "custom", "ticket": ticket], deviceID: deviceID)
            guard signedIn.status == 200, let token = signedIn.body["access_token"] as? String, !token.isEmpty else {
                throw LiveFailure.protocolResponse
            }
            temporaryToken = token
            let profile = try await CloudbaseAuthService().user(accessToken: token, deviceID: deviceID)
            guard profile.id == identity.userID, profile.username == credential.username, profile.isUsable else {
                throw LiveFailure.identity
            }
            stages.append("consumer custom-ticket sign-in resolves the existing host account")
        } catch { failure = error }
        if let temporaryToken {
            do {
                try await CloudbaseAuthService().signOut(accessToken: temporaryToken, deviceID: deviceID)
                temporarySignedOut = true
            } catch { if failure == nil { failure = error; stage = "consumer sign-out" } }
        }
        for user in accounts.overview.users {
            do {
                try await accounts.remove(user.id)
                hostSignedOut = accounts.notice == nil
            } catch { if failure == nil { failure = error; stage = "host sign-out" } }
        }
        let report: [String: Any] = ["account": credential.id, "stages": stages,
            "consumerResponses": observations,
            "consumerSignedOut": temporarySignedOut, "hostSignedOut": hostSignedOut,
            "hostTokenDeliveredToWebView": false, "realApplicationBFFSession": false]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-host-sso-live"; attachment.lifetime = .keepAlways; add(attachment)
        if let failure {
            let category = failure is HostAuthorizationError ? "host protocol" : failure is AccountError ? "account" : "consumer protocol"
            XCTFail("Live SSO failed at \(stage) (\(category)); response contents omitted")
        } else {
            XCTAssertTrue(temporarySignedOut)
            XCTAssertTrue(hostSignedOut)
        }
    }

    private func randomValue() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    private func send(_ session: URLSession, url: URL, fields: [String: Any], origin: String? = nil,
                      deviceID: String? = nil) async throws -> Reply {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let deviceID { request.setValue(deviceID, forHTTPHeaderField: "x-device-id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LiveFailure.protocolResponse }
        var observation: [String: Any] = ["status": http.statusCode, "mime": http.mimeType ?? "missing",
                                          "host": url.host ?? "missing"]
        let body = data.count <= 128 * 1024 ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
        if let reason = body?["reason"] as? String,
           ["pkce_invalid", "code_used", "phone_verification_required", "not_configured", "registry_invalid",
            "registry_unavailable", "identity_unavailable", "error", "origin_not_allowed", "invalid_request",
            "not_authenticated", "code_binding_invalid", "client_binding_invalid"].contains(reason) {
            observation["reason"] = reason
        }
        observations.append(observation)
        guard http.mimeType?.lowercased() == "application/json", let body else { throw LiveFailure.protocolResponse }
        return Reply(status: http.statusCode, body: body)
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private struct Reply { let status: Int; let body: [String: Any] }
    private enum LiveFailure: Error { case protocolResponse, identity }
    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
