import Foundation

@MainActor
final class WalletStore: ObservableObject {
    private let access: AccountRequestAccess<WalletError>
    private let service: WalletServing
    private var projection: AccountRequestBoundary?
    @Published private var storedSnapshot: WalletSnapshot?
    @Published private var storedEntries: [CoinLedgerEntry] = []
    @Published private var storedNextSkip: Int? = 0
    @Published private var accountError: String?
    @Published private var ledgerError: String?
    @Published private var accountLoading = false
    @Published private var ledgerLoading = false
    @Published private var fetchedAt: Date?
    @Published private var storedReconciliationError: String?
    @Published private var reconciliation: UUID?
    private var accountRequest = UUID(), ledgerRequest = UUID()
    init(accounts: IdentityScopedAccountAuthorizing, service: WalletServing = WalletService()) {
        access = AccountRequestAccess(accounts: accounts); self.service = service
    }
    private var isCurrent: Bool { projection == access.boundary }
    var snapshot: WalletSnapshot? { isCurrent ? storedSnapshot : nil }
    var entries: [CoinLedgerEntry] { isCurrent ? storedEntries : [] }
    var nextSkip: Int? { isCurrent ? storedNextSkip : 0 }
    var snapshotError: String? { isCurrent ? accountError : nil }
    var transactionsError: String? { isCurrent ? ledgerError : nil }
    var isLoading: Bool { isCurrent && (accountLoading || reconciliation != nil) }
    var isLoadingTransactions: Bool { isCurrent && (ledgerLoading || reconciliation != nil) }
    var checkedAt: Date? { isCurrent ? fetchedAt : nil }
    var reconciliationError: String? { isCurrent ? storedReconciliationError : nil }

    func identityChanged() {
        projection = access.boundary; storedSnapshot = nil; storedEntries = []; storedNextSkip = 0
        accountError = nil; ledgerError = nil; fetchedAt = nil; accountLoading = false; ledgerLoading = false
        accountRequest = UUID(); ledgerRequest = UUID()
        storedReconciliationError = nil; reconciliation = nil
    }
    func reconcileAndRefresh() async {
        if !isCurrent { identityChanged() }
        let boundary = access.boundary
        guard boundary.uid != nil, reconciliation == nil else { return }
        let request = UUID(); reconciliation = request; storedReconciliationError = nil
        defer { if reconciliation == request { reconciliation = nil } }
        do { _ = try await access.perform(boundary: boundary) { try await service.reconcile(identity: $0) } }
        catch {
            if access.isCurrent(boundary) { storedReconciliationError = "历史订单暂未完成核对，已继续读取当前账户。" }
        }
        guard access.isCurrent(boundary) else { return }
        await refresh()
    }
    func refresh() async {
        async let account: Void = refreshAccount()
        async let ledger: Void = loadTransactions(reset: true)
        _ = await (account, ledger)
    }
    func refreshAccount() async {
        if !isCurrent { identityChanged() }
        let boundary = access.boundary
        guard boundary.uid != nil, !accountLoading else { return }
        let request = UUID(); accountRequest = request; accountLoading = true; accountError = nil
        defer { if accountRequest == request { accountLoading = false } }
        do {
            let value = try await access.perform(boundary: boundary) { try await service.account(identity: $0) }
            guard access.isCurrent(boundary), accountRequest == request else { return }
            storedSnapshot = value; fetchedAt = Date()
        } catch {
            guard access.isCurrent(boundary), accountRequest == request else { return }
            accountError = WalletError.message(for: error)
        }
    }
    func loadTransactions(reset: Bool = false) async {
        if !isCurrent { identityChanged() }
        let boundary = access.boundary
        guard boundary.uid != nil, !ledgerLoading, let skip = reset ? 0 : storedNextSkip else { return }
        let request = UUID(); ledgerRequest = request; ledgerLoading = true; ledgerError = nil
        defer { if ledgerRequest == request { ledgerLoading = false } }
        do {
            let page = try await access.perform(boundary: boundary) { try await service.transactions(skip: skip, limit: 20, identity: $0) }
            guard access.isCurrent(boundary), ledgerRequest == request else { return }
            if reset { storedEntries = page.items }
            else { let existing = Set(storedEntries.map(\.id)); storedEntries += page.items.filter { !existing.contains($0.id) } }
            storedNextSkip = page.nextSkip
        } catch {
            guard access.isCurrent(boundary), ledgerRequest == request else { return }
            ledgerError = WalletError.message(for: error)
        }
    }
}
