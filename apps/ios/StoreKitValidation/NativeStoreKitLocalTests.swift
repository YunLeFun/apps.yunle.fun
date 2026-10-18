#if targetEnvironment(simulator)
import StoreKitTest
import XCTest
@testable import YunleFun

@MainActor
final class NativeStoreKitLocalTests: XCTestCase {
    private static var localSession: SKTestSession?
    private func configuredSession() throws -> SKTestSession {
        if let value = Self.localSession { value.resetToDefaultState(); value.disableDialogs = true; value.clearTransactions(); return value }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        let value = try SKTestSession(contentsOf: url)
        value.resetToDefaultState(); value.disableDialogs = true; value.clearTransactions()
        Self.localSession = value; return value
    }
    func testNativeStoreKitPreservesAccountTokenAndRestoresFinishedMembership() async throws {
        let session = try configuredSession()
        defer { session.clearTransactions() }
        let native = NativeStoreKit(), token = PurchaseAccountToken.forUser("fixture-member")
        _ = try await native.products()
        guard case .transaction(let tx) = try await native.purchase(id: "fun.yunle.apps.member_month", accountToken: token) else {
            return XCTFail("A local membership transaction is required")
        }
        XCTAssertTrue(tx.isLocalTest); XCTAssertEqual(tx.accountToken, token)
        try await native.finish(id: tx.id)
        let restored = try await native.restore()
        XCTAssertTrue(restored.contains { $0.id == tx.id && $0.accountToken == token })
    }
    func testRealStoreKitLocalPurchaseFinishesWithoutOnlineGrant() async throws {
        let session = try configuredSession()
        defer { session.clearTransactions() }
        let accounts = BillingAccounts(), log = BillingLog(), native = TrackedLocalStoreKit()
        let service = BillingServiceFixture(log: log, verifyFailure: false, accountGate: nil, verifyGate: nil)
        let wallet = WalletStore(accounts: accounts, service: service)
        let coordinator = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: service, commerce: native,
            journal: PurchaseOwnershipJournal(vault: BillingMemoryVault()))
        await coordinator.loadProducts()
        XCTAssertEqual(Set(coordinator.products.map(\.id)), Set(NativeIapCatalog.allIDs))
        await coordinator.purchase(coinProduct)
        XCTAssertNil(coordinator.error)
        XCTAssertTrue(coordinator.notice?.contains("本地 StoreKit") == true)
        let requests = await log.values
        XCTAssertFalse(requests.contains("verify.begin"), "A real local StoreKit transaction must never reach production verification")
        var pending = try await native.unfinished()
        for _ in 0..<20 where !pending.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            pending = try await native.unfinished()
        }
        let calls = await native.calls
        XCTAssertTrue(pending.isEmpty, "Calls \(calls); remaining local transactions: \(pending.map { "\($0.id):\($0.productID)" })")
    }
}

private actor TrackedLocalStoreKit: CommerceServing {
    let native = NativeStoreKit()
    private(set) var calls: [String] = []
    func products() async throws -> [CommerceProduct] { try await native.products() }
    func purchase(id: String, accountToken: UUID) async throws -> CommercePurchaseResult {
        let result = try await native.purchase(id: id, accountToken: accountToken)
        if case .transaction(let tx) = result { calls.append("purchased:" + tx.id) }
        return result
    }
    func finish(id: String) async throws { calls.append("finish:" + id); try await native.finish(id: id) }
    func unfinished() async throws -> [CommerceTransaction] { try await native.unfinished() }
    func restore() async throws -> [CommerceTransaction] { try await native.restore() }
    func updates() async -> AsyncStream<CommerceEvent> { await native.updates() }
}
#endif
