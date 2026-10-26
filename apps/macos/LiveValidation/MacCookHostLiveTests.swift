import AppKit
import Foundation
import Security
import WebKit
import XCTest
@testable import YunleFunMac

/// Explicit production Cook validation in the isolated Testing app. No host
/// token or password is evaluated in the consumer's JavaScript context.
/// A native UI driver submits login and consent at progress.json checkpoints.
@MainActor
final class MacCookHostLiveTests: XCTestCase {
    private enum Failure: Error { case observation, timeout, cleanup }
    private struct Input: Decodable {
        struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
        let runID: String
        let accounts: [Credential]
    }
    private var runtime: MacWebRuntime?
    private var accounts: AccountStore?
    private var window: NSWindow?
    private var consumer: WKWebView?
    private var runDirectory: URL?
    private var phase = "setup"
    private var checks: [String: Bool] = [:]

    func testCookSSOAndUnsupportedCapabilities() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YLF_MAC_COOK_HOST"] == "1" else { throw XCTSkip("Explicit isolated Cook validation only") }
        guard Bundle.main.bundleIdentifier == "fun.yunle.macos.tests-host",
              let rawRun = env["YLF_MAC_COOK_RUN_ID"], let run = UUID(uuidString: rawRun) else { return XCTFail("Wrong validation host or run") }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cache.appendingPathComponent("MacCookHost-" + run.uuidString)
        runDirectory = directory
        let inputURL = directory.appendingPathComponent("input.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: inputURL.path)[.posixPermissions] as? NSNumber
        guard let permissions, permissions.intValue & 0o077 == 0 else { return XCTFail("One-use input must be private") }
        let data = try Data(contentsOf: inputURL)
        try FileManager.default.removeItem(at: inputURL)
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard UUID(uuidString: input.runID) == run, input.accounts.count == 1,
              let credential = input.accounts.first, credential.id == "production-zero-balance",
              credential.environment == "production", credential.username == "ylf_prod_zero", !credential.password.isEmpty else { return XCTFail("Wrong managed account") }
        let service = "fun.yunle.macos.cook-host." + run.uuidString
        let vault = KeychainAccountVault(service: service)
        let journal = KeychainAccountVault(service: service + ".revocations")
        guard try vault.read() == nil, try journal.read() == nil else { return XCTFail("Run already has pending cleanup") }
        let api = try ManagedHostAuth(journal: journal)
        var profileIDs: [UUID] = []
        var failure = ""
        do {
            try await journey(credential, directory: directory, service: service, api: api, vault: vault, profileIDs: &profileIDs)
        } catch {
            failure = phase + ": " + String(reflecting: type(of: error))
            if let window { attach(window, "mac-cook-failure-" + phase) }
        }
        mark("cleanup")
        if checks["consumerSignedOut"] != true, let web = consumer {
            do { try await signOut(web); checks["consumerSignedOut"] = true } catch { checks["consumerSignedOut"] = false }
        }
        if let accounts {
            for user in accounts.overview.users { try? await accounts.remove(user.id) }
        }
        do {
            if let saved = try vault.read() { try await api.includeSavedAccounts(JSONDecoder().decode(AccountVaultState.self, from: saved)) }
            try await api.revokeOutstanding()
            checks["hostRemoteSignOutAcknowledged"] = accounts?.overview.users.isEmpty == true
            for name in [vault.service, journal.service] {
                let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: name] as CFDictionary)
                guard result == errSecSuccess || result == errSecItemNotFound else { throw Failure.cleanup }
            }
            checks["isolatedKeychainCleared"] = try vault.read() == nil && journal.read() == nil
        } catch { checks["hostRemoteSignOutAcknowledged"] = false }
        weak var releasedRuntime = runtime
        weak var releasedWeb = consumer
        runtime?.terminate(); window?.contentView = nil; consumer = nil; accounts = nil; runtime = nil
        window?.close(); window = nil
        let runtimeReleased = releasedRuntime == nil && releasedWeb == nil
        var removed = true
        for id in profileIDs where runtimeReleased {
            let completion = CallbackResult<Void>()
            WKWebsiteDataStore.remove(forIdentifier: id) { error in completion.finish(error.map { .failure($0) } ?? .success(())) }
            if await XCTWaiter.fulfillment(of: [completion.completed], timeout: 12) != .completed { removed = false }
            else { do { try completion.get() } catch { removed = false } }
        }
        removed = removed && runtimeReleased
        if removed && checks["isolatedKeychainCleared"] == true { try? FileManager.default.removeItem(at: directory) }
        let report: [String: Any] = ["runID": run.uuidString, "source": "production Cook in real macOS WKWebView", "checks": checks, "failure": failure, "hostCredentialsInjectedIntoConsumer": false, "profileCleanupComplete": removed]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: cache.appendingPathComponent("MacCookHost-" + run.uuidString + ".report.json"), options: .atomic)
        let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        attachment.name = "mac-cook-host-report"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(failure.isEmpty, "Safe failing phase: " + failure)
        XCTAssertEqual(checks.count, 14)
        XCTAssertTrue(checks.values.allSatisfy { $0 })
    }

    private func journey(_ credential: Input.Credential, directory: URL, service: String, api: ManagedHostAuth, vault: KeychainAccountVault, profileIDs: inout [UUID]) async throws {
        mark("catalog")
        let profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: service)
        let host = MacWebRuntime(webProfiles: profiles)
        runtime = host
        let store = AccountStore(session: AccountSession(api: api, vault: vault),
                                 accountWillRemove: { try profiles.retire($0) },
                                 identityDidChange: { [weak host] in host?.accountDidChange($0) })
        accounts = store
        host.configureAuthorization(accounts: store)
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        await catalog.load()
        guard !catalog.isCached, catalog.error == nil,
              let app = catalog.applications.first(where: { $0.marketShortName == "cook" }),
              app.websiteUrl == "https://cook.yunle.fun/home" else { throw Failure.observation }
        profileIDs = [try profiles.select(.guest, application: app).identifier]
        try JSONEncoder().encode(profileIDs).write(to: directory.appendingPathComponent("owned-profiles.json"), options: .atomic)
        checks["productionCatalogEntry"] = true
        guard host.open(app), let web = host.webView else { throw Failure.observation }
        consumer = web
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.window = window
        window.title = "Cook host validation"
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait(40) { (try? await self.js(web, "return document.title==='食用手册' && !!document.querySelector('ion-tab-button') && document.documentElement.classList.contains('in-yunle-app');")) as? Bool == true }
        _ = try await js(web, "window.__cookHostErrors=0;addEventListener('error',()=>window.__cookHostErrors++);addEventListener('unhandledrejection',()=>window.__cookHostErrors++);return true;")
        mark("desktop-capabilities")
        let capabilities = try await js(web, "const r={};for(const k of ['authorize','haptic','setClipboard'])r[k]=await window.ylf.canIUse(k);return r;") as? [String: Bool]
        guard capabilities == ["authorize": true, "haptic": false, "setClipboard": false] else { throw Failure.observation }
        checks["desktopCapabilitiesMatch"] = true
        let environment = try await js(web, "return await window.ylf.getEnv();") as? [String: Any]
        guard environment?["platform"] as? String == "macos", environment?["trusted"] as? Bool == true,
              environment?["capsuleVisible"] as? Bool == false, environment?["capsuleRect"] == nil,
              environment?["displayMode"] as? String == "titlebar",
              try await js(web, "return getComputedStyle(document.documentElement).getPropertyValue('--cook-host-capsule-inset').trim()==='0px' && window.__cookHostErrors===0;") as? Bool == true else { throw Failure.observation }
        checks["desktopLayoutWithoutCapsule"] = true
        let clipboardVersion = NSPasteboard.general.changeCount
        let rejected = try await js(web, "const r={};for(const k of ['haptic','setClipboard']){try{await window.ylf[k](k==='haptic'?'light':'Cook capability validation');r[k]=false;}catch(e){r[k]=String(e).includes('HOST_API_UNSUPPORTED');}}return r;") as? [String: Bool]
        guard rejected == ["haptic": true, "setClipboard": true], clipboardVersion == NSPasteboard.general.changeCount else { throw Failure.observation }
        checks["unsupportedCallsRejectWithoutClipboardWrite"] = true
        guard try await js(web, "const e=document.querySelector('.choose-food button.ingredient-chip,.wb-food');if(!e)return false;window.__cookChip=e;window.__cookChipBefore=e.getAttribute('aria-pressed');e.click();return true;") as? Bool == true else { throw Failure.observation }
        try await wait(8) { (try? await self.js(web, "return window.__cookChip.getAttribute('aria-pressed')!==window.__cookChipBefore && window.__cookHostErrors===0;")) as? Bool == true }
        _ = try await js(web, "window.__cookChip.click();delete window.__cookChip;delete window.__cookChipBefore;return true;")
        checks["ingredientSelectionDegradesWithoutHaptic"] = true
        mark("native-login")
        _ = try await js(web, "const t=[...document.querySelectorAll('ion-tab-button')].find(x=>x.textContent.trim()==='我的');if(!t)return false;t.click();return true;")
        try await wait(15) { (try? await self.state(web))?["hasLogin"] as? Bool == true }
        try await clickItem(web, "使用云乐坊账号登录")
        try await wait(25) { window.attachedSheet != nil }
        checks["nativeLoginSheetPresented"] = true
        mark("native-login-controls")
        let login = try XCTUnwrap(window.attachedSheet)
        attach(login, "mac-cook-native-login")
        mark("native-password-method")
        try await wait(8) {
            if let control = self.views(login).compactMap({ $0 as? NSSegmentedControl }).first,
               let index = (0..<control.segmentCount).first(where: { control.label(forSegment: $0) == "密码" }) {
                control.selectedSegment = index
                return control.sendAction(control.action, to: control.target)
            }
            return false
        }
        try await wait(8) { self.views(login).contains { $0 is NSSecureTextField } }
        mark("native-password-fields")
        let username = try XCTUnwrap(views(login).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "用户名、邮箱或手机号" })
        let password = try XCTUnwrap(views(login).compactMap { $0 as? NSSecureTextField }.first)
        try enter(credential.username, into: username)
        try enter(credential.password, into: password)
        login.makeFirstResponder(nil)
        try signal("await-native-submit")
        try await wait(90) { store.user?.username == credential.username }
        checks["nativePasswordFormAuthenticated"] = true
        mark("native-consent")
        try await accept(window)
        try await wait(35) { (try? await self.state(web))?["name"] as? String == store.user?.displayName }
        guard runtime?.webView === web, web.url?.host == "cook.yunle.fun" else { throw Failure.observation }
        checks["realCookSsoAdoptionInSameWebView"] = true
        attach(window, "mac-cook-signed-in")
        try await signOut(web)
        checks["cookSignOutKeepsHostSignedIn"] = store.user?.username == credential.username
        mark("cancel-and-retry")
        try await clickItem(web, "使用云乐坊账号登录")
        try await wait(25) { window.attachedSheet?.title == "云乐坊账号授权" }
        let cancelSheet = try XCTUnwrap(window.attachedSheet)
        attach(cancelSheet, "mac-cook-cancel-consent")
        try signal("await-cancel")
        try await wait(90) {
            let state = try? await self.state(web)
            return window.attachedSheet == nil && state?["hasLogin"] as? Bool == true
        }
        guard runtime?.webView === web, web.url?.host == "cook.yunle.fun" else { throw Failure.observation }
        checks["cancelPreservesConsumerWithoutRedirect"] = true
        try await clickItem(web, "使用云乐坊账号登录")
        try await accept(window)
        try await wait(30) { (try? await self.state(web))?["name"] as? String == store.user?.displayName }
        checks["retryAfterCancelSucceeds"] = true
        try await signOut(web)
        checks["consumerSignedOut"] = true
    }

    func testRemoveRecordedCookProfiles() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YLF_MAC_COOK_CLEANUP"] == "1" else { throw XCTSkip("Explicit fixture cleanup only") }
        guard Bundle.main.bundleIdentifier == "fun.yunle.macos.tests-host",
              let raw = env["YLF_MAC_COOK_RUN_ID"], let run = UUID(uuidString: raw) else { throw Failure.cleanup }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cache.appendingPathComponent("MacCookHost-" + run.uuidString)
        let service = "fun.yunle.macos.cook-host." + run.uuidString
        guard try KeychainAccountVault(service: service).read() == nil,
              try KeychainAccountVault(service: service + ".revocations").read() == nil else { throw Failure.cleanup }
        let ids = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: directory.appendingPathComponent("owned-profiles.json")))
        guard ids.count <= 2, Set(ids).count == ids.count else { throw Failure.cleanup }
        autoreleasepool { let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); WKWebView(frame: .zero, configuration: config).stopLoading() }
        for id in ids {
            let completion = CallbackResult<Void>()
            WKWebsiteDataStore.remove(forIdentifier: id) { error in completion.finish(error.map { .failure($0) } ?? .success(())) }
            guard await XCTWaiter.fulfillment(of: [completion.completed], timeout: 12) == .completed else { throw Failure.timeout }
            try completion.get()
        }
        try FileManager.default.removeItem(at: directory)
        let reportURL = cache.appendingPathComponent("MacCookHost-" + run.uuidString + ".report.json")
        if let data = try? Data(contentsOf: reportURL), var report = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            report["profileCleanupComplete"] = true
            report["profilesRemovedAfterValidationProcessExit"] = true
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        }
        print("COOK_MAC_RECORDED_PROFILES_REMOVED " + run.uuidString)
    }

    private func mark(_ name: String) { phase = name; print("COOK_MAC_STAGE " + name) }
    private func js(_ web: WKWebView, _ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await web.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }
    private func state(_ web: WKWebView) async throws -> [String: Any] {
        try await js(web, "return {name:document.querySelector('.my-account h2')?.textContent.trim()||'',hasLogin:[...document.querySelectorAll('ion-item')].some(x=>x.textContent.includes('使用云乐坊账号登录'))};") as? [String: Any] ?? [:]
    }
    private func clickItem(_ web: WKWebView, _ text: String) async throws {
        guard try await js(web, "const e=[...document.querySelectorAll('ion-item')].find(x=>x.textContent.includes(text));if(!e)return false;e.click();return true;", arguments: ["text": text]) as? Bool == true else { throw Failure.observation }
    }
    private func signOut(_ web: WKWebView) async throws {
        if (try? await state(web))?["hasLogin"] as? Bool == true { return }
        try await clickItem(web, "退出登录")
        try await wait(25) { (try? await self.state(web))?["hasLogin"] as? Bool == true }
    }
    private func accept(_ window: NSWindow) async throws {
        try await wait(25) { window.attachedSheet?.title == "云乐坊账号授权" }
        let sheet = try XCTUnwrap(window.attachedSheet)
        attach(sheet, "mac-cook-native-consent")
        try signal("await-consent")
        try await wait(90) { window.attachedSheet == nil }
    }
    private func signal(_ name: String) throws {
        mark(name)
        guard let runDirectory else { throw Failure.observation }
        try JSONSerialization.data(withJSONObject: ["phase": name], options: [.sortedKeys]).write(to: runDirectory.appendingPathComponent("progress.json"), options: .atomic)
    }
    private func views(_ root: Any) -> [NSView] {
        let view = (root as? NSWindow)?.contentView ?? (root as? NSView)
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { views($0) }
    }
    private func enter(_ value: String, into field: NSTextField) throws {
        guard field.window?.makeFirstResponder(field) == true,
              let editor = field.currentEditor() else { throw Failure.observation }
        editor.insertText(value)
    }
    private func wait(_ seconds: TimeInterval, until condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure.timeout
    }
    private func attach(_ window: NSWindow, _ name: String) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
