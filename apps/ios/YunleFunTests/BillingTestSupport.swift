import XCTest
@testable import YunleFun

let coinProduct = "fun.yunle.apps.coin_100"
func billingTransaction(token: UUID? = PurchaseAccountToken.forUser("alice")) -> CommerceTransaction {
    CommerceTransaction(id: "123", productID: coinProduct, accountToken: token, isLocalTest: false, isRevoked: false)
}
actor BillingLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
actor BillingGate {
    let entered = XCTestExpectation(description: "billing operation entered")
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
@MainActor
final class BillingAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser? = AccountUser(id: "alice")
    var identityGeneration = UUID()
    func select(_ uid: String?) { user = uid.map { AccountUser(id: $0) }; identityGeneration = UUID() }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: "fixture-" + user.id)
    }
}
actor BillingServiceFixture: WalletServing {
    let log: BillingLog
    let verifyFailure: Bool
    let validReceipt: Bool
    let readinessFailure: Bool
    let accountGate: BillingGate?, verifyGate: BillingGate?, reconciliationGate: BillingGate?
    private var reconciliationFailure = false
    init(log: BillingLog, verifyFailure: Bool, accountGate: BillingGate?, verifyGate: BillingGate?, validReceipt: Bool = true, readinessFailure: Bool = false, reconciliationGate: BillingGate? = nil) {
        self.log = log; self.verifyFailure = verifyFailure; self.accountGate = accountGate; self.verifyGate = verifyGate
        self.validReceipt = validReceipt
        self.readinessFailure = readinessFailure
        self.reconciliationGate = reconciliationGate
    }
    func account(identity: AuthorizedAccount) async throws -> WalletSnapshot {
        if let accountGate { await accountGate.wait() }
        return WalletSnapshot(coin: 125, membership: .init(isActive: false, level: nil, expireAt: nil))
    }
    func transactions(skip: Int, limit: Int, identity: AuthorizedAccount) async throws -> CoinLedgerPage { CoinLedgerPage(items: [], nextSkip: nil) }
    func verify(transactionID: String, identity: AuthorizedAccount) async throws -> IapVerificationReceipt {
        await log.append("verify.begin"); if let verifyGate { await verifyGate.wait() }
        if verifyFailure { throw WalletError.unavailable }
        await log.append("verify.confirmed")
        return IapVerificationReceipt(granted: validReceipt, alreadyProcessed: nil, outTradeNo: "iap_" + transactionID)
    }
    func reconcile(identity: AuthorizedAccount) async throws -> WalletReconciliation {
        if let reconciliationGate { await reconciliationGate.wait() }
        if reconciliationFailure { throw WalletError.unavailable }
        return WalletReconciliation(reconciled: 0, paid: 0, regranted: 0)
    }
    func setReconciliationFailure() { reconciliationFailure = true }
    func purchaseReadiness(identity: AuthorizedAccount) async throws {
        await log.append("readiness")
        if readinessFailure { throw WalletError.unavailable }
    }
}
actor BillingCommerceFixture: CommerceServing {
    let log: BillingLog, purchaseGate: BillingGate?
    let outcome: CommercePurchaseResult, pending: [CommerceTransaction]
    let restoreCancelled: Bool
    init(log: BillingLog, gate: BillingGate?, outcome: CommercePurchaseResult, unfinished: [CommerceTransaction], restoreCancelled: Bool = false) {
        self.log = log; purchaseGate = gate; self.outcome = outcome; pending = unfinished
        self.restoreCancelled = restoreCancelled
    }
    func products() async throws -> [CommerceProduct] { NativeIapCatalog.allIDs.map { CommerceProduct(id: $0, displayPrice: "测试价格") } }
    func purchase(id: String, accountToken: UUID) async throws -> CommercePurchaseResult {
        await log.append("purchase"); if let purchaseGate { await purchaseGate.wait() }; return outcome
    }
    func unfinished() async throws -> [CommerceTransaction] { pending }
    func restore() async throws -> [CommerceTransaction] {
        await log.append("restore")
        if restoreCancelled { throw CommerceError.cancelled }
        return pending
    }
    func finish(id: String) async throws { await log.append("finish") }
    func updates() async -> AsyncStream<CommerceEvent> { AsyncStream { $0.finish() } }
}
final class BillingMemoryVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(data: Data? = nil) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
}
@MainActor
func billingRig(verifyFailure: Bool = false, accountGate: BillingGate? = nil, verifyGate: BillingGate? = nil,
                purchaseGate: BillingGate? = nil, outcome: CommercePurchaseResult = .transaction(billingTransaction()),
                unfinished: [CommerceTransaction] = [], vault: BillingMemoryVault = BillingMemoryVault(), validReceipt: Bool = true, restoreCancelled: Bool = false, readinessFailure: Bool = false, reconciliationGate: BillingGate? = nil)
-> (coordinator: PurchaseCoordinator, wallet: WalletStore, accounts: BillingAccounts, service: BillingServiceFixture, log: BillingLog) {
    let log = BillingLog(), accounts = BillingAccounts()
    let service = BillingServiceFixture(log: log, verifyFailure: verifyFailure, accountGate: accountGate, verifyGate: verifyGate, validReceipt: validReceipt, readinessFailure: readinessFailure, reconciliationGate: reconciliationGate)
    let commerce = BillingCommerceFixture(log: log, gate: purchaseGate, outcome: outcome, unfinished: unfinished, restoreCancelled: restoreCancelled)
    let wallet = WalletStore(accounts: accounts, service: service)
    let coordinator = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: service, commerce: commerce,
                                          journal: PurchaseOwnershipJournal(vault: vault))
    return (coordinator, wallet, accounts, service, log)
}
