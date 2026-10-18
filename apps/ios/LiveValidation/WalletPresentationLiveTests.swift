import SwiftUI
import UIKit
import Vision
import XCTest
@testable import YunleFun

/// Renders the production wallet with in-memory auth, ledger and commerce.
/// This exercises native layout/scrolling, not Apple or CloudBase Sandbox.
@MainActor
final class WalletPresentationLiveTests: XCTestCase {
    func testWalletShowsLoadingUntilReconciliationCompletes() async throws {
        try await checkReconciliation(fails: false)
    }

    func testFailedReconciliationStillReadsCurrentBalanceAndLedger() async throws {
        try await checkReconciliation(fails: true)
    }

    func testSandboxWalletWarningIsVisibleInLightMode() async throws {
        try await checkSandbox(largest: false)
    }

    func testSandboxWalletWarningRemainsReadableAtLargestTextInDarkMode() async throws {
        try await checkSandbox(largest: true)
    }

    private func requireOwnedSimulator() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_LIVE_WALLET_PRESENTATION"] == "1" else {
            throw XCTSkip("Requires explicit wallet presentation validation")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an owned isolated simulator may run this validation")
        #endif
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"] else { throw PresentationFailure.precondition }
    }

    private func checkReconciliation(fails: Bool) async throws {
        try requireOwnedSimulator()
        let fixture = try await WalletPresentationFixture(sandbox: false, largest: false, reconciliationFails: fails)
        defer { fixture.close() }
        do {
            try await wait { await fixture.service.reconciliationEntered }
            let balance = try await fixture.readScreen(containing: ["正在读取余额"], bottom: false, name: "reconciliation-balance-loading", test: self)
            let pending = try await fixture.readScreen(containing: ["正在读取流水"], bottom: true, name: "reconciliation-ledger-loading", test: self)
            XCTAssertFalse(pending.contains("暂无流水"))
            XCTAssertFalse(balance.contains("尚未获取余额"))
            XCTAssertTrue(fixture.wallet.isLoading && fixture.wallet.isLoadingTransactions)
            let readsWhilePending = await fixture.service.readCount()
            XCTAssertEqual(readsWhilePending, 0)
            await fixture.service.releaseReconciliation()
            try await wait { !fixture.wallet.isLoading && !fixture.wallet.isLoadingTransactions && fixture.wallet.snapshot != nil }
            let empty = try await fixture.readScreen(containing: ["暂无流水"], bottom: true, name: "reconciliation-ledger-read", test: self)
            XCTAssertFalse(empty.contains("正在读取流水"))
            _ = try await fixture.readScreen(containing: ["云币余额", "125"], bottom: false, name: "reconciliation-balance-read", test: self)
            if fails {
                _ = try await fixture.readScreen(containing: ["历史订单暂未完成核对", "已继续读取当前账户"], bottom: false,
                                                 name: "reconciliation-error-after-read", test: self)
            }
            XCTAssertEqual(fixture.wallet.reconciliationError != nil, fails)
            let readsAfterReconciliation = await fixture.service.readCount()
            XCTAssertEqual(readsAfterReconciliation, 2)
            await record(fixture, extra: ["reconciliationFails": fails, "pendingLedgerVisible": true,
                "emptyLedgerOnlyAfterRead": true, "balanceVisibleAfterRead": true])
        } catch {
            await fixture.service.releaseReconciliation()
            throw error
        }
    }

    private func checkSandbox(largest: Bool) async throws {
        try requireOwnedSimulator()
        let fixture = try await WalletPresentationFixture(sandbox: true, largest: largest, reconciliationFails: false)
        defer { fixture.close() }
        await fixture.service.releaseReconciliation()
        try await wait { fixture.wallet.snapshot != nil && !fixture.wallet.isLoading }
        _ = try await fixture.readScreen(containing: ["内购测试钱包", "测试余额和会员仅用于内购验证", "其他功能仍使用正式账号服务"],
                                         bottom: false, name: "sandbox-warning-\(largest ? "largest-dark" : "standard-light")", test: self)
        _ = try await fixture.readScreen(containing: ["云币余额", "125"], bottom: false,
                                         name: "sandbox-balance-\(largest ? "largest-dark" : "standard-light")", test: self)
        await record(fixture, extra: ["sandbox": true, "largestText": largest, "warningReachable": true, "balanceReachable": true])
    }

    private func wait(_ ready: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if await ready() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        throw PresentationFailure.timeout
    }

    private func record(_ fixture: WalletPresentationFixture, extra: [String: Any]) async {
        let commerce = await fixture.commerce.calls
        XCTAssertFalse(commerce.contains("purchase"))
        XCTAssertFalse(commerce.contains("restore"))
        let financial = await fixture.service.financialCalls
        XCTAssertTrue(financial.isEmpty)
        var report = extra
        report["commerceCalls"] = commerce
        report["financialCalls"] = financial
        report["scope"] = "Actual WalletView and native List scrolling with only in-memory auth/wallet/commerce; no Apple Sandbox or remote service verification"
        let attachment = XCTAttachment(data: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "wallet-presentation-report"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private enum PresentationFailure: Error { case precondition, timeout, forbiddenOperation }

@MainActor
private final class WalletPresentationFixture {
    let wallet: WalletStore
    let service: WalletPresentationService
    let commerce = WalletPresentationCommerce()
    private let window: UIWindow
    private let previous: UIWindow?
    private let controller: UIViewController

    init(sandbox: Bool, largest: Bool, reconciliationFails: Bool) async throws {
        var state = AccountVaultState()
        state.activeID = "wallet-presentation-fixture"
        state.accounts = [SavedAccount(user: AccountUser(id: state.activeID!, name: "本机钱包样例"),
            credential: AccountCredential(accessToken: "wallet-presentation-fixture", refreshToken: "never-used",
                                          expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: WalletPresentationAuth(),
            vault: WalletPresentationVault(try JSONEncoder().encode(state))))
        await accounts.restore()
        guard accounts.user?.id == state.activeID else { throw PresentationFailure.precondition }
        service = WalletPresentationService(environment: sandbox ? .sandbox : .production, fails: reconciliationFails)
        wallet = WalletStore(accounts: accounts, service: service)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: service, commerce: commerce,
            journal: PurchaseOwnershipJournal(vault: WalletPresentationVault(nil)))
        let content = NavigationStack { WalletView() }
            .environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
            .environment(\.dynamicTypeSize, largest ? .accessibility5 : .large)
            .preferredColorScheme(largest ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
    }

    func close() {
        controller.dismiss(animated: false)
        window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
    }

    func readScreen(containing expected: [String], bottom: Bool, name: String, test: XCTestCase) async throws -> String {
        let deadline = Date().addingTimeInterval(10)
        var samples: [[String]] = [], visible = "", captured = false
        var image: UIImage?
        func settle() async throws {
            try await Task.sleep(nanoseconds: 150_000_000)
            controller.view.layoutIfNeeded()
        }
        try await settle()
        let list = try XCTUnwrap(scrollView(in: controller.view) as? UICollectionView)
        let sections = (0..<list.numberOfSections).filter { list.numberOfItems(inSection: $0) > 0 }
        let section = try XCTUnwrap(bottom ? sections.last : sections.first)
        let item = bottom ? list.numberOfItems(inSection: section) - 1 : 0
        list.scrollToItem(at: IndexPath(item: item, section: section), at: bottom ? .bottom : .top, animated: false)
        repeat {
            try await settle()
            let frame = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            image = frame
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(frame.cgImage)).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            samples.append(lines); visible = lines.joined().filter { !$0.isWhitespace }
            if expected.allSatisfy({ visible.contains($0) }) { captured = true; break }
            let top = -list.adjustedContentInset.top
            let end = max(top, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
            let step = max(100, (list.bounds.height - list.adjustedContentInset.top - list.adjustedContentInset.bottom) / 2)
            let next = bottom ? max(top, list.contentOffset.y - step) : min(end, list.contentOffset.y + step)
            if abs(next - list.contentOffset.y) < 1 { break }
            list.setContentOffset(CGPoint(x: 0, y: next), animated: false)
        } while Date() < deadline
        if let image {
            let screenshot = XCTAttachment(image: image); screenshot.name = name; screenshot.lifetime = .keepAlways; test.add(screenshot)
        }
        let text = XCTAttachment(string: samples.map { $0.joined(separator: "\n") }.joined(separator: "\n--- viewport ---\n"))
        text.name = name + "-visible-text"; text.lifetime = .keepAlways; test.add(text)
        guard captured else { throw PresentationFailure.timeout }
        return visible
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UICollectionView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}

private actor WalletPresentationService: WalletServing {
    nonisolated let environment: WalletEnvironment
    private let fails: Bool
    private var released = false
    private(set) var reconciliationEntered = false
    private var reads = 0
    private(set) var financialCalls: [String] = []
    init(environment: WalletEnvironment, fails: Bool) { self.environment = environment; self.fails = fails }
    func releaseReconciliation() { released = true }
    func readCount() -> Int { reads }
    func reconcile(identity: AuthorizedAccount) async throws -> WalletReconciliation {
        reconciliationEntered = true
        while !released { try await Task.sleep(nanoseconds: 50_000_000) }
        if fails { throw WalletError.unavailable }
        return WalletReconciliation(reconciled: 0, paid: 0, regranted: 0)
    }
    func account(identity: AuthorizedAccount) async throws -> WalletSnapshot {
        reads += 1
        return WalletSnapshot(coin: 125, membership: .init(isActive: false, level: nil, expireAt: nil))
    }
    func transactions(skip: Int, limit: Int, identity: AuthorizedAccount) async throws -> CoinLedgerPage {
        reads += 1; return CoinLedgerPage(items: [], nextSkip: nil)
    }
    func verify(transactionID: String, identity: AuthorizedAccount) async throws -> IapVerificationReceipt {
        financialCalls.append("verify"); throw PresentationFailure.forbiddenOperation
    }
    func purchaseReadiness(identity: AuthorizedAccount) async throws {
        financialCalls.append("readiness"); throw PresentationFailure.forbiddenOperation
    }
}

private actor WalletPresentationCommerce: CommerceServing {
    private(set) var calls: [String] = []
    func products() async throws -> [CommerceProduct] { calls.append("products"); return [] }
    func unfinished() async throws -> [CommerceTransaction] { calls.append("unfinished"); return [] }
    func purchase(id: String, accountToken: UUID) async throws -> CommercePurchaseResult {
        calls.append("purchase"); throw PresentationFailure.forbiddenOperation
    }
    func restore() async throws -> [CommerceTransaction] { calls.append("restore"); throw PresentationFailure.forbiddenOperation }
    func finish(id: String) async throws { calls.append("finish"); throw PresentationFailure.forbiddenOperation }
    func updates() async -> AsyncStream<CommerceEvent> { AsyncStream { $0.finish() } }
}

private final class WalletPresentationVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(_ data: Data?) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
}

private struct WalletPresentationAuth: AccountAuthenticating {
    func user(accessToken: String, deviceID: String) async throws -> AccountUser { AccountUser(id: "wallet-presentation-fixture", name: "本机钱包样例") }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw PresentationFailure.forbiddenOperation }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw PresentationFailure.forbiddenOperation }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw PresentationFailure.forbiddenOperation }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse { throw PresentationFailure.forbiddenOperation }
    func signOut(accessToken: String, deviceID: String) async throws { throw PresentationFailure.forbiddenOperation }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { throw PresentationFailure.forbiddenOperation }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw PresentationFailure.forbiddenOperation }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw PresentationFailure.forbiddenOperation }
}
