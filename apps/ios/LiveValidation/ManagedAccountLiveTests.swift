import CryptoKit
import Darwin
import Foundation
import Security
import SwiftUI
import UIKit
import XCTest
@testable import YunleFun

@MainActor
final class HomeScrollMotionLiveTests: XCTestCase {
    func testStandardMotionAnimatesAutomaticScroll() async throws { try await sample(reduceMotion: false) }
    func testReducedMotionRevealsWithoutIntermediateScrollPositions() async throws { try await sample(reduceMotion: true) }

    private func sample(reduceMotion: Bool) async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_LIVE_HOME_MOTION"] == "1" else {
            throw XCTSkip("Requires a controlled Reduce Motion setting on an owned simulator")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("This validation is restricted to an owned simulator")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"] else { return XCTFail("Requires the exact owned simulator") }
        XCTAssertEqual(UIAccessibility.isReduceMotionEnabled, reduceMotion, "Verify the real system setting before sampling")
        let signal = HomeScrollSignal()
        let controller = UIHostingController(rootView: HomeScrollMotionFixture(signal: signal))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        XCTAssertTrue(UIView.areAnimationsEnabled, "The ordinary-motion control must retain UIKit animations")
        let deadline = Date().addingTimeInterval(5)
        var scroll: UIScrollView?
        repeat {
            controller.view.layoutIfNeeded()
            scroll = findScroll(in: controller.view)
            if (scroll?.contentSize.height ?? 0) > 2000 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        XCTAssertEqual(signal.observedReduceMotion, reduceMotion, "SwiftUI must observe the same system preference")
        let view = try XCTUnwrap(scroll)
        XCTAssertGreaterThan(view.contentSize.height, 2000)
        let start = view.contentOffset.y
        let end = view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
        XCTAssertGreaterThan(end - start, 1000, "Use a meaningful automatic scroll distance")
        var positions: [CGFloat] = [start]
        signal.reveal = true
        let samplingEnd = Date().addingTimeInterval(0.8)
        repeat {
            try await Task.sleep(nanoseconds: 8_000_000)
            positions.append(view.contentOffset.y)
        } while Date() < samplingEnd
        let intermediate = positions.filter { abs($0 - start) > 1 && abs($0 - end) > 1 }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "reduceMotion": reduceMotion, "start": start, "destination": end,
            "positions": positions, "intermediateSamples": intermediate.count,
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "home-scroll-\(reduceMotion ? "reduced" : "standard")"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(view.contentOffset.y, end, accuracy: 1, "Both settings must reveal the requested last row")
        if reduceMotion { XCTAssertTrue(intermediate.isEmpty, "Reduce Motion must not travel through intermediate scroll positions") }
        else { XCTAssertGreaterThan(intermediate.count, 2, "The normal setting must retain its visible scroll animation") }
    }
    private func findScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }
}

@MainActor
private final class HomeScrollSignal: ObservableObject { @Published var reveal = false; var observedReduceMotion: Bool? }
private struct HomeScrollMotionFixture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var signal: HomeScrollSignal
    var body: some View {
        HomeScrollView { scroller in
            VStack(spacing: 0) {
                ForEach(0..<60) { index in Text("Application \(index)").frame(height: 40).id("row-\(index)") }
            }
            .onAppear { signal.observedReduceMotion = reduceMotion }
            .onChange(of: signal.reveal) { reveal in if reveal { scroller.reveal("row-59", at: .bottom) } }
        }
    }
}


/// Real authentication and publishing reads, with a fail-closed write observer.
/// This proves the native eligibility gate; it does not validate cloud writes.
@MainActor
final class PublishingAccessLiveTests: XCTestCase {
    func testManagedPublishingEligibilityAndLocalDraftIsolation() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_LIVE_PUBLISHING_ACCESS"] == "1" else {
            throw XCTSkip("Requires explicitly provisioned managed accounts and the current loopback backend")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("This validation is restricted to an owned simulator")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"] else {
            return XCTFail("The exact owned simulator must be supplied")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/publishing-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else {
            return XCTFail("The one-use account file must be private")
        }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-standard": "ylf_prod_standard",
                        "production-member-active": "ylf_prod_member",
                        "production-zero-balance": "ylf_prod_zero"]
        guard pool.accounts.count == 3, Set(pool.accounts.map(\.id)) == Set(expected.keys),
              pool.accounts.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty }) else {
            return XCTFail("Only the three approved synthetic accounts may run this validation")
        }
        let serviceName = "fun.yunle.apps.publishing-access." + UUID().uuidString
        let keychain = KeychainAccountVault(service: serviceName)
        let accounts = AccountStore(session: AccountSession(vault: keychain))
        let directory = cache.appendingPathComponent("PublishingAccess-" + UUID().uuidString)
        let drafts = ApplicationDraftVault(directory: directory)
        let service = ReadOnlyPublishingProbe()
        let store = PublishingStore(accounts: accounts, service: service)
        var evidence: [[String: Any]] = []
        var failure = false
        defer {
            try? FileManager.default.removeItem(at: directory)
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName] as CFDictionary)
        }
        do {
            for credential in pool.accounts.sorted(by: { $0.id < $1.id }) {
                try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
                guard let user = accounts.user, user.username == credential.username, user.isUsable else { throw ValidationFailure.identity }
                _ = try await accounts.authorization(forceRefresh: true)
                // Switching identity must hide the previous account's loaded state immediately.
                guard !store.hasLoaded, store.applications.isEmpty else { throw ValidationFailure.isolation }
                await store.refresh()
                guard store.hasLoaded, store.error == nil, store.publishingAccess?.writePreconditionVersion == 1,
                      !store.canSubmit else { throw ValidationFailure.eligibility }
                let editor = ApplicationEditorModel(application: nil, accounts: accounts, store: store, vault: drafts)
                guard editor.recovered == nil else { throw ValidationFailure.isolation }
                editor.draft.name = "Private eligibility validation"
                editor.draft.slug = "ios-access-" + UUID().uuidString.lowercased()
                editor.draft.description = "Local-only draft: " + credential.id
                editor.draft.audience = .owner
                editor.draft.websiteUrl = "https://apps.yunle.fun"
                editor.draft.privacyPolicyUrl = "https://apps.yunle.fun/privacy"
                editor.draft.supportUrl = "https://apps.yunle.fun/help"
                guard editor.draft.isValid else { throw ValidationFailure.draft }
                try editor.saveLocalDraft()
                let before = try Data(contentsOf: drafts.file(owner: user.id, appID: nil))
                let result = await editor.saveVersion()
                guard result == nil, editor.error == PublishingError.forbidden.message,
                      try Data(contentsOf: drafts.file(owner: user.id, appID: nil)) == before else { throw ValidationFailure.draft }
                let reopened = ApplicationEditorModel(application: nil, accounts: accounts, store: store, vault: drafts)
                reopened.restoreDraft()
                guard reopened.draft == editor.draft else { throw ValidationFailure.draft }
                evidence.append(["account": credential.id, "realLoginAndRefresh": true,
                                 "ownerListRead": true, "ownerListCount": store.applications.count,
                                 "canSubmit": false, "writePreconditionVersion": 1,
                                 "localDraftPreservedAndReopened": true])
            }
        } catch {
            failure = true
            if let stage = error as? ValidationFailure { XCTFail("Publishing live validation failed at \(stage)") }
            else { XCTFail("Publishing live validation failed; private response contents omitted") }
        }
        // Always revoke every session created in this isolated Keychain namespace.
        var allSignedOut = true
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id) }
            catch { allSignedOut = false }
        }
        let restored = AccountStore(session: AccountSession(vault: keychain))
        await restored.restore()
        let empty = restored.user == nil && restored.overview.users.isEmpty
        let counts = await service.counts()
        XCTAssertTrue(allSignedOut && empty, "Revoke test sessions and empty the isolated Keychain")
        XCTAssertEqual(counts.writes, 0, "The native gate must reject before reaching any write method")
        XCTAssertTrue(store.applications.isEmpty && !store.hasLoaded, "Signed-out state must hide owner data")
        if !failure { XCTAssertEqual(counts.reads, 6) }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "accounts": evidence, "realReadCalls": counts.reads, "writeMethodCalls": counts.writes,
            "remoteSignOut": allSignedOut, "emptyKeychain": empty, "businessNetworkWrites": 0,
            "transport": "Real CloudBase auth and loopback publishing reads; write methods fail closed",
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "publishing-access-live-validation"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum ValidationFailure: Error { case identity, isolation, eligibility, draft }
}

private actor ReadOnlyPublishingProbe: PublishingServing {
    private let live = PublishingService(origin: URL(string: "http://127.0.0.1:18748")!)
    private var reads = 0
    private var writes = 0
    func counts() -> (reads: Int, writes: Int) { (reads, writes) }
    func access(identity: AuthorizedAccount) async throws -> PublishingAccess {
        reads += 1; return try await live.access(identity: identity)
    }
    func applications(identity: AuthorizedAccount) async throws -> [ManagedApplication] {
        reads += 1; return try await live.applications(identity: identity)
    }
    func save(id: String?, draft: ApplicationDraft, writeVersion: String?, identity: AuthorizedAccount) async throws -> ManagedApplication {
        writes += 1; throw PublishingError.forbidden
    }
    func submit(id: String, makePublic: Bool, shortName: String, writeVersion: String, identity: AuthorizedAccount) async throws -> MarketSubmissionReceipt {
        writes += 1; throw PublishingError.forbidden
    }
    func delist(id: String, writeVersion: String, identity: AuthorizedAccount) async throws {
        writes += 1; throw PublishingError.forbidden
    }
    func upload(png: Data, role: ApplicationIconRole, identity: AuthorizedAccount) async throws -> String {
        writes += 1; throw PublishingError.forbidden
    }
}

/// Explicit, opt-in integration suite. Passwords are read once from an owner-only
/// simulator cache file and never appear in launch arguments or test attachments.
@MainActor
final class ManagedAccountLiveTests: XCTestCase {
    func testManagedLoginRefreshSwitchWalletAndSignOut() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_FIXED_ACCOUNTS"] == "1" else {
            throw XCTSkip("Requires an explicitly provisioned managed synthetic account pool")
        }
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iOSNativeValidation/test-accounts.json")
        let data = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-standard": "ylf_prod_standard",
                        "production-member-active": "ylf_prod_member",
                        "production-zero-balance": "ylf_prod_zero"]
        let credentials = pool.accounts.filter { expected[$0.id] != nil }
        guard credentials.count == 3, Set(credentials.map(\.id)).count == 3,
              credentials.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty })
        else { return XCTFail("The managed account pool does not match the allowed synthetic identities") }

        let service = "fun.yunle.apps.live-validation." + UUID().uuidString
        let vault = KeychainAccountVault(service: service)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let session = AccountSession(vault: vault)
        let accounts = AccountStore(session: session)
        var identities: [String: String] = [:]
        var evidence: [[String: Any]] = []
        do {
            for credential in credentials.sorted(by: { $0.id < $1.id }) {
                try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
                let user = try XCTUnwrap(accounts.user)
                guard user.username == credential.username, user.isUsable else { throw LiveFailure.identity }
                identities[credential.id] = user.id
                let identity = try await accounts.authorization(forceRefresh: true)
                guard identity.userID == user.id else { throw LiveFailure.identity }
                let wallet = try await WalletService().account(identity: identity)
                if credential.id == "production-member-active" {
                    guard wallet.membership.isActive, (wallet.membership.expiration ?? .distantPast) > Date() else { throw LiveFailure.wallet }
                } else if wallet.membership.isActive { throw LiveFailure.wallet }
                if credential.id == "production-zero-balance", wallet.coin != 0 { throw LiveFailure.wallet }
                let ledger = try await WalletService().transactions(skip: 0, limit: 10, identity: identity)
                if credential.id == "production-member-active" {
                    let assistant = AssistantStore(accounts: accounts)
                    assistant.draft = "推荐几个开发工具"
                    await assistant.send()?.value
                    guard assistant.error == nil, !assistant.running,
                          assistant.messages.last?.status == .done,
                          !(assistant.messages.last?.content.isEmpty ?? true) else {
                        if let message = assistant.error { XCTFail("Native assistant returned: \(message)") }
                        throw LiveFailure.assistant
                    }
                    let catalog = try await CatalogService().applications()
                    guard assistant.messages.flatMap(\.cards).allSatisfy({ $0.resolve(in: catalog) != nil }) else { throw LiveFailure.assistant }
                    evidence.append(["account": credential.id, "nativeAssistantStream": true,
                                     "resolvedCards": assistant.messages.flatMap(\.cards).count])
                }
                evidence.append(["account": credential.id, "passwordLogin": true, "refresh": true,
                                 "coin": wallet.coin, "memberActive": wallet.membership.isActive,
                                 "ledgerRead": true, "ledgerItems": ledger.items.count])
            }
            guard Set(identities.values).count == 3 else { throw LiveFailure.identity }
            for id in expected.keys.sorted() {
                guard let uid = identities[id] else { throw LiveFailure.identity }
                try await accounts.select(uid)
                guard accounts.user?.id == uid, accounts.notice == nil else { throw LiveFailure.restore }
            }
            let restored = AccountStore(session: AccountSession(vault: vault))
            await restored.restore()
            guard restored.notice == nil, restored.overview.users.count == 3,
                  restored.user?.id == accounts.user?.id else { throw LiveFailure.restore }
            for uid in identities.values {
                try await restored.remove(uid)
                guard restored.notice == nil else { throw LiveFailure.signOut }
            }
            let empty = AccountStore(session: AccountSession(vault: vault))
            await empty.restore()
            guard empty.user == nil, empty.overview.users.isEmpty else { throw LiveFailure.signOut }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
                "accounts": evidence, "keychainRestore": true, "accountSwitch": true, "remoteSignOut": true,
                "signedOutRestart": true, "realPayments": false,
            ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "managed-accounts-live-validation"; attachment.lifetime = .keepAlways; add(attachment)
        } catch {
            // Revoke only sessions created by this test. No auth responses or
            // credentials are interpolated into diagnostics.
            for user in accounts.overview.users { try? await accounts.remove(user.id) }
            if let failure = error as? LiveFailure { XCTFail("Managed integration stage failed: \(failure)") }
            else if let failure = error as? AccountError { XCTFail("Native auth failed: \(failure)") }
            else if let failure = error as? WalletError { XCTFail("Native wallet failed: \(failure)") }
            else { XCTFail("Managed integration failed; response contents intentionally omitted") }
        }
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum LiveFailure: Error { case identity, wallet, restore, signOut, assistant }
}

/// App-hosted input audit for the actual AppRootView → FeedbackView → LoginView
/// journey. An external UI driver performs every navigation, submit and cancel.
/// Only text entry uses the focused UIKit control's public UIKeyInput API, so
/// credentials never become XCTest action arguments or pasteboard contents.
@MainActor
final class FeedbackLoginLiveTests: XCTestCase {
    private var draft = "Feedback continuation 🧩\nSteps: open feedback, then sign in.\nExpected: preserve every line.\nActual: return to a fresh feedback page."
    private let canary = "YLF_UIKit_Input_Canary_20261018_Bb8!"
    private var stages: [String] = []
    private var pasteboardCounts: [String: Int] = [:]

    func testFocusedNativeInputAndFeedbackContinuation() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["YUNLEFUN_LIVE_FEEDBACK_INPUT"], ["canary", "managed"].contains(mode) else {
            throw XCTSkip("Requires an explicit native feedback input audit and external UI driver")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an explicitly owned simulator may run this journey")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"],
              mode == "canary" || env["YUNLEFUN_FEEDBACK_INPUT_AUDITED"] == "uikit-input-v1" else {
            return XCTFail("Requires the exact owned simulator and audited input channel")
        }
        executionTimeAllowance = 900
        let uploadRun = env["YUNLEFUN_LIVE_FEEDBACK_UPLOAD"]
        if let uploadRun {
            guard mode == "managed", UUID(uuidString: uploadRun)?.uuidString == uploadRun else {
                return XCTFail("An upload requires managed mode and a canonical, unique run UUID")
            }
            draft += "\nSynthetic validation: " + uploadRun
        }
        let receiptSnapshot = try uploadRun.map { _ in try FeedbackReceiptSnapshot() }
        var receiptOwner: String?
        var uploadEvidence: [String: Any] = [:]
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cache.appendingPathComponent("FeedbackInput-" + UUID().uuidString)
        let service = "fun.yunle.apps.feedback-input." + UUID().uuidString
        let vault = KeychainAccountVault(service: service)
        let auth = FeedbackObservedAuth(canary: mode == "canary")
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let logs = DiagnosticLogStore(directory: directory.appendingPathComponent("logs"))
        let catalog = CatalogStore()
        let runtime = NativeWebRuntime()
        let accounts = AccountStore(session: AccountSession(api: auth, vault: vault), identityDidChange: { id in
            logs.activateAccount(id)
            logs.record(.info, message: "account.scope.activated")
            if let uploadRun, let id {
                receiptOwner = id
                logs.record(.info, message: "feedback.validation.upload." + uploadRun)
            }
            runtime.resetIdentity(to: id)
            library.activateAccount(id)
            library.setAutoSyncEnabled(false)
        })
        await accounts.restore()
        logs.record(.info, message: "feedback.validation.started")
        runtime.configureAuthorization(accounts: accounts)
        let wallet = WalletStore(accounts: accounts)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet)
        runtime.configureCommerce(wallet: wallet, purchases: purchases)
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, monitorNetwork: false)
        let assistant = AssistantStore(accounts: accounts)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        window.rootViewController = UIHostingController(rootView: AppRootView()
            .environmentObject(catalog).environmentObject(library).environmentObject(runtime)
            .environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
            .environmentObject(sync).environmentObject(assistant).environmentObject(logs))
        window.makeKeyAndVisible()
        defer {
            runtime.resetIdentity()
            window.rootViewController = previous
            window.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: directory)
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service] as CFDictionary)
            if let receiptOwner, let receiptSnapshot {
                do { try receiptSnapshot.restore(owner: receiptOwner) }
                catch { XCTFail("Could not restore this synthetic account's previous local receipt") }
            }
        }
        let initialPasteboardCount = UIPasteboard.general.changeCount
        var failure: String?
        var consumed = false
        var uiRemoval = false
        var input = ""
        var inputChecks: [String: Bool] = [:]
        var internalMatches: [[String: Any]] = []
        do {
            mark("ready")
            let editor = try await focused(UITextView.self, identifier: "feedback.description", in: window)
            guard editor.text.isEmpty else { throw InputFailure.state }
            editor.insertText(draft)
            try await pause()
            guard editor.text == draft else { throw InputFailure.state }
            mark("guest-draft-entered")
            let username = try await focused(UITextField.self, identifier: "login.username", in: window)
            if mode == "canary" { input = canary }
            else { input = try Self.consumePassword(cache: cache); consumed = true }
            username.insertText(mode == "canary" ? "feedback-canary" : "ylf_prod_zero")
            mark("username-entered")
            let password = try await focused(UITextField.self, identifier: "login.password", in: window)
            guard password.isSecureTextEntry, password.text?.isEmpty != false else { throw InputFailure.state }
            let inputPasteboardCount = UIPasteboard.general.changeCount
            password.insertText(input)
            try await pause()
            inputChecks = ["textMatches": password.text == input, "secureEntry": password.isSecureTextEntry,
                "inProcessAccessibilityValueContainsInput": (password.accessibilityValue ?? "").contains(input),
                "inProcessViewAccessibilityContainsInput": accessibleText(in: window).contains(input),
                "exposedElementPropertiesContainInput": views(in: window).filter(\.isAccessibilityElement).contains {
                    [$0.accessibilityLabel, $0.accessibilityValue, $0.accessibilityHint].compactMap { $0 }.contains { $0.contains(input) }
                },
                "diagnosticsContainInput": logs.entries.contains(where: { $0.message.contains(input) }),
                "pasteboardUnchangedDuringInput": UIPasteboard.general.changeCount == inputPasteboardCount]
            internalMatches = views(in: window).filter {
                [$0.accessibilityLabel, $0.accessibilityValue, $0.accessibilityHint].compactMap { $0 }.contains { $0.contains(input) }
            }.map { ["class": String(describing: type(of: $0)), "isAccessibilityElement": $0.isAccessibilityElement,
                     "hidden": $0.isHidden, "insideSecureField": $0.isDescendant(of: password)] }
            // In-process property values are recorded separately from the
            // external accessibility tree. Canary evidence must audit both.
            print("YLF_FEEDBACK_INPUT_CHECKS " + inputChecks.keys.sorted().map { $0 + "=" + String(inputChecks[$0]!) }.joined(separator: ","))
            attach(window, name: "focused-native-input-masked")
            mark("password-entered-masked")
            let checksPassed = inputChecks["textMatches"] == true && inputChecks["secureEntry"] == true
                && inputChecks["inProcessAccessibilityValueContainsInput"] == false
                && inputChecks["exposedElementPropertiesContainInput"] == false
                && inputChecks["diagnosticsContainInput"] == false
                && inputChecks["pasteboardUnchangedDuringInput"] == true
            if mode == "managed", !checksPassed { throw InputFailure.privacy }
            if mode == "canary" {
                try await wait { password.window == nil && accounts.user == nil }
                try await wait { self.editor(in: window)?.text == self.draft }
                attach(window, name: "canary-cancelled-draft")
                mark("canary-cancelled-with-draft")
                // Leave time to observe the actual post-cancel sheet/prompt.
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } else {
                try await wait { accounts.user?.username == "ylf_prod_zero" && password.window == nil }
                try await wait { self.editor(in: window)?.text == self.draft }
                guard window.rootViewController?.presentedViewController == nil else { throw InputFailure.state }
                attach(window, name: "managed-feedback-resumed")
                mark("managed-feedback-resumed")
                if let uploadRun, let receiptSnapshot {
                    uploadEvidence = try await exerciseUpload(run: uploadRun, window: window,
                        accounts: accounts, logs: logs, snapshot: receiptSnapshot)
                }
                // The UI driver returns to Me, then opens a new feedback entry.
                try await wait { self.editor(in: window) == nil }
                mark("returned-to-me")
                try await wait { self.editor(in: window) != nil }
                guard self.editor(in: window)?.text == "" else { throw InputFailure.state }
                if uploadRun != nil {
                    let restoredReceipt = DiagnosticUploadStore(accounts: accounts, logs: logs).receipt
                    guard restoredReceipt?.supportCode == uploadEvidence["supportCode"] as? String else { throw InputFailure.state }
                    uploadEvidence["receiptRestoredOnNewEntry"] = true
                }
                attach(window, name: "managed-feedback-new-entry-empty")
                mark("continuation-consumed-once")
                // Only the actual account-management UI removes this account.
                try await wait { accounts.overview.users.isEmpty }
                uiRemoval = true
                mark("native-account-removal-observed")
                try await waitAsync { await auth.counts().signOutSucceeded == 1 }
                let restarted = try await AccountSession(api: auth, vault: vault).overview()
                guard restarted.users.isEmpty, restarted.activeID == nil else { throw InputFailure.state }
                mark("remote-signout-acknowledged-and-vault-empty")
            }
            guard checksPassed else { throw InputFailure.privacy }
        } catch {
            // Do not interpolate errors or object descriptions containing input.
            failure = "Journey failed after " + (stages.last ?? "fixture creation")
        }
        input = ""
        // Failure cleanup is explicit and cannot be mistaken for UI removal.
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id) }
            catch { failure = (failure ?? "Journey completed") + "; fallback cleanup failed" }
        }
        let counts = await auth.counts()
        let report: [String: Any] = ["inputChannel": "uikit-input-v1", "mode": mode,
            "stages": stages, "credentialInputConsumed": consumed,
            "inputChecks": inputChecks, "internalMatchingViews": internalMatches, "pasteboardCounts": pasteboardCounts,
            "passwordSignInAttempts": counts.passwordAttempts, "passwordSignInSucceeded": counts.passwordSucceeded,
            "remoteSignOutSucceeded": counts.signOutSucceeded, "nativeUIAccountRemoval": uiRemoval,
            "upload": uploadEvidence,
            "simulatorPasteboardUnchanged": UIPasteboard.general.changeCount == initialPasteboardCount,
            "failure": failure ?? "none",
            "scope": "App-hosted actual product views; external UI navigation and submission; public focused UIKeyInput text entry"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "feedback-native-input-report"; attachment.lifetime = .keepAlways; add(attachment)
        if let failure { XCTFail(failure) }
        XCTAssertEqual(counts.passwordAttempts, mode == "canary" ? 0 : 1)
        XCTAssertEqual(counts.passwordSucceeded, mode == "canary" ? 0 : 1)
        XCTAssertEqual(counts.signOutSucceeded, mode == "canary" ? 0 : 1)
        if mode == "managed" { XCTAssertTrue(uiRemoval) }
    }

    private func exerciseUpload(run: String, window: UIWindow, accounts: AccountStore,
                                logs: DiagnosticLogStore, snapshot: FeedbackReceiptSnapshot) async throws -> [String: Any] {
        let owner = try XCTUnwrap(accounts.user?.id)
        let expectedMessages = ["account.scope.activated", "feedback.validation.upload." + run]
        guard logs.accountID == owner, logs.entries.map(\.message) == expectedMessages,
              logs.entries.allSatisfy({ $0.level == .info }), DiagnosticText.redact(draft) == draft else {
            throw InputFailure.state
        }
        let before = try snapshot.current(owner: owner)
        mark("upload-waiting-for-first-preview")
        try await wait { window.rootViewController?.presentedViewController != nil }
        attach(window, name: "diagnostic-first-review")
        mark("upload-first-preview-presented")
        // The external UI driver cancels this preview, checks the exact run's
        // database absence, then reopens the review and explicitly consents.
        try await wait { window.rootViewController?.presentedViewController == nil }
        guard try snapshot.current(owner: owner) == before else { throw InputFailure.state }
        mark("upload-preview-cancelled-receipt-unchanged")
        try await wait { window.rootViewController?.presentedViewController != nil }
        guard logs.entries.map(\.message) == expectedMessages else { throw InputFailure.state }
        mark("upload-second-preview-presented")
        var receipt: DiagnosticUploadReceipt?
        try await wait {
            receipt = try? snapshot.receipt(owner: owner)
            return receipt != nil && (try? snapshot.current(owner: owner)) != before
        }
        let saved = try XCTUnwrap(receipt)
        guard saved.logCount == 2, !saved.uploadId.isEmpty else { throw InputFailure.state }
        try DiagnosticUploadRules.validate(saved, count: 2, now: Date().timeIntervalSince1970 * 1000)
        let evidence: [String: Any] = ["run": run, "ownerUid": owner,
            "uploadId": saved.uploadId, "supportCode": saved.supportCode,
            "logCount": saved.logCount, "expiresAt": saved.expiresAt,
            "issueDescription": draft, "expectedMessages": expectedMessages,
            "cancelledPreviewLeftReceiptUnchanged": true,
            "transport": "Unmodified production DiagnosticService over HTTPS; no mocked response"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "diagnostic-upload-live-receipt"; attachment.lifetime = .keepAlways; add(attachment)
        attach(window, name: "diagnostic-upload-success-alert")
        mark("upload-receipt-persisted")
        // Dismiss the real success alert with Done, leaving the receipt visible.
        try await wait { window.rootViewController?.presentedViewController == nil }
        mark("upload-success-alert-dismissed")
        return evidence
    }

    private func mark(_ stage: String) {
        stages.append(stage); pasteboardCounts[stage] = UIPasteboard.general.changeCount
        print("YLF_FEEDBACK_INPUT_STAGE " + stage)
    }
    private func pause() async throws { try await Task.sleep(nanoseconds: 200_000_000) }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(180)
        while !predicate() { guard Date() < deadline else { throw InputFailure.timeout }; try await pause() }
    }
    private func waitAsync(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(45)
        while !(await predicate()) { guard Date() < deadline else { throw InputFailure.timeout }; try await pause() }
    }
    private func views(in view: UIView) -> [UIView] { [view] + view.subviews.flatMap { views(in: $0) } }
    private func editor(in window: UIWindow) -> UITextView? {
        views(in: window).compactMap { $0 as? UITextView }.first { $0.accessibilityIdentifier == "feedback.description" }
    }
    private func focused<T: UIView>(_ type: T.Type, identifier: String, in window: UIWindow) async throws -> T {
        var match: T?
        try await wait {
            match = self.views(in: window).compactMap { $0 as? T }
                .first { $0.accessibilityIdentifier == identifier && $0.isFirstResponder }
            return match != nil
        }
        guard let match else { throw InputFailure.state }; return match
    }
    private func accessibleText(in view: UIView) -> String {
        views(in: view).flatMap { [$0.accessibilityLabel, $0.accessibilityValue, $0.accessibilityHint].compactMap { $0 } }
            .joined(separator: "\n")
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    fileprivate static func consumePassword(cache: URL, fileName: String = "feedback-native-input.json") throws -> String {
        guard ["feedback-native-input.json", "profile-native-input.json"].contains(fileName) else { throw InputFailure.credential }
        let directory = cache.appendingPathComponent("iOSNativeValidation")
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw InputFailure.credential }; defer { close(folder) }
        var folderInfo = stat()
        guard fstat(folder, &folderInfo) == 0, folderInfo.st_uid == geteuid(),
              folderInfo.st_mode & mode_t(0o7777) == mode_t(0o700) else { throw InputFailure.credential }
        let file = openat(folder, fileName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw InputFailure.credential }; defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_mode & mode_t(0o7777) == mode_t(0o600), info.st_size > 0, info.st_size <= 65_536,
              unlinkat(folder, fileName, 0) == 0 else { throw InputFailure.credential }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + max(0, count) <= 65_536 else { throw InputFailure.credential }
            if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        guard let pool = try? JSONDecoder().decode(InputPool.self, from: data), pool.accounts.count == 1,
              let entry = pool.accounts.first, entry.id == "production-zero-balance", entry.environment == "production",
              entry.username == "ylf_prod_zero", !entry.password.isEmpty, entry.password.utf8.count <= 1024,
              entry.password.rangeOfCharacter(from: .controlCharacters) == nil else { throw InputFailure.credential }
        return entry.password
    }
    private struct InputPool: Decodable { let accounts: [InputCredential] }
    private struct InputCredential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum InputFailure: Error { case state, timeout, privacy, credential }
}

/// Real profile writes use the existing production form and service. Login is
/// fixture setup, not a claim about login UI. Every save and logout is clicked
/// externally; focused public UIKit input supplies only synthetic profile text.
@MainActor
final class ManagedProfileLiveTests: XCTestCase {
    private var stages: [String] = []
    private struct Baseline: Codable {
        let run: String
        let owner: String
        let name: String
        let description: String
    }
    private enum ProfileFailure: Error { case state, timeout }

    func testNativeProfileSaveReadBackRestoreAndSignOut() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["YUNLEFUN_LIVE_PROFILE"], ["validate", "recover"].contains(mode) else {
            throw XCTSkip("Requires explicit synthetic profile validation and an external UI driver")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an explicitly owned simulator may run this journey")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty, owned == env["SIMULATOR_UDID"],
              let run = env["YUNLEFUN_LIVE_PROFILE_RUN"], UUID(uuidString: run)?.uuidString == run else {
            return XCTFail("Requires the exact owned simulator and a canonical run UUID")
        }
        executionTimeAllowance = 900
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let baselineURL = cache.appendingPathComponent("iOSNativeValidation/profile-native-baseline.json")
        let service = "fun.yunle.apps.profile-live." + UUID().uuidString
        let vault = KeychainAccountVault(service: service)
        let auth = FeedbackObservedAuth(canary: false)
        let accounts = AccountStore(session: AccountSession(api: auth, vault: vault))
        var baseline: Baseline?
        var window: UIWindow?
        var previous: UIViewController?
        var failure: String?
        var uiRestored = false, remoteRestored = false, uiRemoved = false, fallbackRestored = false
        var sameIdentityGeneration = false, persistedChangedProfile = false, submittedTrimmedName = false
        let changedName = "iOS校验" + run.prefix(8)
        let changedDescription = "Native profile validation 🧩\n" + run
        defer {
            if let window { window.rootViewController = previous; window.makeKeyAndVisible() }
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        }
        do {
            mark("authenticating-private-fixture")
            let password = try FeedbackLoginLiveTests.consumePassword(cache: cache, fileName: "profile-native-input.json")
            try await accounts.passwordSignIn(identifier: "ylf_prod_zero", password: password, captcha: nil)
            let original = try await serverProfile(accounts: accounts, vault: vault)
            guard original.username == "ylf_prod_zero", original.isUsable else { throw ProfileFailure.state }
            if mode == "recover" {
                let attributes = try FileManager.default.attributesOfItem(atPath: baselineURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                      ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_384 else { throw ProfileFailure.state }
                baseline = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: baselineURL))
                guard baseline?.run == run, baseline?.owner == original.id else { throw ProfileFailure.state }
                mark("recovering-owned-profile")
            } else {
                guard let name = original.name, (2...48).contains(name.utf16.count),
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !FileManager.default.fileExists(atPath: baselineURL.path) else { throw ProfileFailure.state }
                let saved = Baseline(run: run, owner: original.id, name: name, description: original.description ?? "")
                let data = try JSONEncoder().encode(saved)
                try data.write(to: baselineURL, options: [.withoutOverwriting, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: baselineURL.path)
                baseline = saved
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let host = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
                window = host; previous = host.rootViewController
                host.rootViewController = UIHostingController(rootView: NavigationStack { AccountProfileView() }.environmentObject(accounts))
                host.makeKeyAndVisible()
                let generation = accounts.identityGeneration
                mark("profile-ready")
                try await replaceFocused("profile.name", with: "  " + changedName + "  ", in: host)
                try await replaceFocused("profile.description", with: changedDescription, in: host)
                mark("synthetic-profile-entered-awaiting-save")
                try await wait { accounts.user?.name == changedName && accounts.user?.description == changedDescription }
                let submitted = await auth.counts().profileInputs
                submittedTrimmedName = submitted.count == 1 && submitted[0].name == changedName
                    && submitted[0].description == changedDescription
                guard submittedTrimmedName else { throw ProfileFailure.state }
                let changed = try await serverProfile(accounts: accounts, vault: vault)
                guard changed.id == original.id, changed.name == changedName, changed.description == changedDescription,
                      changed.username == original.username, changed.email == original.email,
                      changed.phoneNumber == original.phoneNumber else { throw ProfileFailure.state }
                sameIdentityGeneration = accounts.identityGeneration == generation
                let persisted = try await AccountSession(api: auth, vault: vault).overview().activeUser
                persistedChangedProfile = persisted?.name == changedName && persisted?.description == changedDescription
                guard sameIdentityGeneration, persistedChangedProfile else { throw ProfileFailure.state }
                attach(host, name: "profile-updated-and-read-back")
                mark("profile-saved-and-read-back")
                try await replaceFocused("profile.name", with: saved.name, in: host)
                try await replaceFocused("profile.description", with: saved.description, in: host)
                mark("original-profile-entered-awaiting-save")
                try await wait { self.matches(accounts.user, saved) }
                guard matches(try await serverProfile(accounts: accounts, vault: vault), saved) else { throw ProfileFailure.state }
                uiRestored = true; remoteRestored = true
                attach(host, name: "profile-restored-and-read-back")
                mark("profile-restored-via-ui")
                try await wait { accounts.overview.users.isEmpty }
                uiRemoved = true
                try await waitAsync { await auth.counts().signOutSucceeded == 1 }
                mark("native-signout-acknowledged")
            }
        } catch { failure = "Profile journey failed after " + (stages.last ?? "fixture preparation") }

        // A failed UI journey may already have written. Read before restoring;
        // never overwrite an unrelated concurrent profile change or retry blindly.
        if !remoteRestored, let baseline, let user = accounts.user, user.id == baseline.owner {
            do {
                var current = try await serverProfile(accounts: accounts, vault: vault)
                if !matches(current, baseline) {
                    guard current.name == changedName, current.description == changedDescription else { throw ProfileFailure.state }
                    try await accounts.updateProfile(name: baseline.name, description: baseline.description)
                    current = try await serverProfile(accounts: accounts, vault: vault)
                    fallbackRestored = true
                }
                guard matches(current, baseline) else { throw ProfileFailure.state }
                remoteRestored = true
            } catch { failure = (failure ?? "Recovery") + "; original profile still requires recovery" }
        }
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id) }
            catch { failure = (failure ?? "Journey") + "; signout failed" }
        }
        if remoteRestored {
            do { try FileManager.default.removeItem(at: baselineURL) }
            catch { failure = (failure ?? "Journey") + "; baseline cleanup failed" }
        }
        let empty = try await AccountSession(api: auth, vault: vault).overview()
        let counts = await auth.counts()
        let report: [String: Any] = ["run": run, "mode": mode, "stages": stages,
            "profileWritesAttempted": counts.profileAttempts, "profileWritesSucceeded": counts.profileSucceeded,
            "profileReadBackAndPersisted": persistedChangedProfile, "sameIdentityGeneration": sameIdentityGeneration,
            "submittedTrimmedName": submittedTrimmedName,
            "originalProfileRestoredViaUI": uiRestored, "originalProfileRestoredRemotely": remoteRestored,
            "fallbackRestored": fallbackRestored, "nativeUIAccountRemoval": uiRemoved,
            "remoteSignOutSucceeded": counts.signOutSucceeded, "vaultEmpty": empty.users.isEmpty && empty.activeID == nil,
            "baselineRemoved": !FileManager.default.fileExists(atPath: baselineURL.path), "failure": failure ?? "none",
            "scope": "Real production profile form/save/readback/restore; authenticated fixture setup, not login UI; no entitlement changes"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-profile-live-report"; attachment.lifetime = .keepAlways; add(attachment)
        if let failure { XCTFail(failure) }
        XCTAssertTrue(remoteRestored); XCTAssertTrue(empty.users.isEmpty); XCTAssertEqual(counts.signOutSucceeded, 1)
        if mode == "validate" {
            XCTAssertTrue(uiRestored); XCTAssertTrue(uiRemoved); XCTAssertFalse(fallbackRestored)
            XCTAssertEqual(counts.profileAttempts, 2); XCTAssertEqual(counts.profileSucceeded, 2)
        }
    }
    private func matches(_ user: AccountUser?, _ baseline: Baseline) -> Bool {
        user?.id == baseline.owner && user?.name == baseline.name && (user?.description ?? "") == baseline.description
    }
    private func serverProfile(accounts: AccountStore, vault: KeychainAccountVault) async throws -> AccountUser {
        let identity = try await accounts.authorization()
        let state = try JSONDecoder().decode(AccountVaultState.self, from: XCTUnwrap(vault.read()))
        let user = try await CloudbaseAuthService().user(accessToken: identity.accessToken, deviceID: state.deviceID)
        guard user.id == identity.userID, user.username == "ylf_prod_zero", user.isUsable else { throw ProfileFailure.state }
        return user
    }
    private func replaceFocused(_ identifier: String, with text: String, in window: UIWindow) async throws {
        var target: UIView?
        try await wait {
            target = self.views(window).first { $0.isFirstResponder && $0.accessibilityIdentifier == identifier }
            return target != nil
        }
        if let field = target as? UITextField {
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.deleteBackward(); if !text.isEmpty { field.insertText(text) }
        } else if let field = target as? UITextView {
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.deleteBackward(); if !text.isEmpty { field.insertText(text) }
        } else { throw ProfileFailure.state }
    }
    private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(180)
        while !predicate() {
            guard Date() < deadline else { throw ProfileFailure.timeout }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    private func waitAsync(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(45)
        while !(await predicate()) {
            guard Date() < deadline else { throw ProfileFailure.timeout }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    private func mark(_ stage: String) { stages.append(stage); print("YLF_PROFILE_STAGE " + stage) }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

/// Preserve any existing receipt in the owned simulator. Only the synthetic
/// identity used by this run is restored; all other files remain untouched.
@MainActor
private final class FeedbackReceiptSnapshot {
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DiagnosticReceipts")
    private var originals: [String: Data] = [:]
    init() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw DiagnosticError.storage }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard files.count <= 100 else { throw DiagnosticError.storage }
        for file in files { originals[file.lastPathComponent] = try read(file) }
    }
    private func file(_ owner: String) -> URL {
        let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        return directory.appendingPathComponent(name)
    }
    private func read(_ file: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= 8192 else { throw DiagnosticError.storage }
        return try Data(contentsOf: file)
    }
    func current(owner: String) throws -> Data? {
        let file = file(owner)
        return FileManager.default.fileExists(atPath: file.path) ? try read(file) : nil
    }
    func receipt(owner: String) throws -> DiagnosticUploadReceipt? {
        guard let data = try current(owner: owner) else { return nil }
        struct Record: Decodable { let receipt: DiagnosticUploadReceipt }
        return try JSONDecoder().decode(Record.self, from: data).receipt
    }
    func restore(owner: String) throws {
        let file = file(owner)
        let previous = originals[file.lastPathComponent]
        if try current(owner: owner) == previous { return }
        if let previous { try previous.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen]) }
        else { try FileManager.default.removeItem(at: file) }
        guard try current(owner: owner) == previous else { throw DiagnosticError.storage }
    }
}

/// Forwards the same production auth API and counts only successful return values.
/// The canary refuses all authentication requests, even if submit is tapped.
private actor FeedbackObservedAuth: AccountAuthenticating {
    struct Counts {
        var passwordAttempts = 0; var passwordSucceeded = 0; var signOutSucceeded = 0
        var profileAttempts = 0; var profileSucceeded = 0
        var profileInputs: [ProfileInput] = []
    }
    struct ProfileInput { let name: String; let description: String }
    private let api = CloudbaseAuthService()
    private let canary: Bool
    private var observed = Counts()
    init(canary: Bool) { self.canary = canary }
    func counts() -> Counts { observed }
    private func allow() throws { if canary { throw AccountError.unavailable } }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        observed.passwordAttempts += 1; try allow()
        let response = try await api.passwordSignIn(identifier: identifier, password: password, deviceID: deviceID, captcha: captcha)
        observed.passwordSucceeded += 1; return response
    }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge {
        try allow(); return try await api.sendVerification(address: address, deviceID: deviceID, captcha: captcha)
    }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        try allow(); return try await api.verify(challenge, code: code, deviceID: deviceID, captcha: captcha)
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        try allow(); return try await api.refresh(refreshToken, deviceID: deviceID)
    }
    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        try allow(); return try await api.user(accessToken: accessToken, deviceID: deviceID)
    }
    func signOut(accessToken: String, deviceID: String) async throws {
        try allow(); try await api.signOut(accessToken: accessToken, deviceID: deviceID); observed.signOutSucceeded += 1
    }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws {
        try allow(); observed.profileAttempts += 1
        observed.profileInputs.append(ProfileInput(name: name, description: description))
        try await api.updateProfile(userID: userID, name: name, description: description, accessToken: accessToken, deviceID: deviceID)
        observed.profileSucceeded += 1
    }
    func captcha(deviceID: String) async throws -> CaptchaImage { try allow(); return try await api.captcha(deviceID: deviceID) }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String {
        try allow(); return try await api.verifyCaptcha(token: token, text: text, deviceID: deviceID)
    }
}
