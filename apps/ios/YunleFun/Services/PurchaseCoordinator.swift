import Foundation

struct LegacyPurchaseConfirmation: Identifiable {
    let id = UUID()
    let boundary: AccountRequestBoundary
    let transactionIDs: Set<String>
}

@MainActor
final class PurchaseCoordinator: ObservableObject {
    private let access: AccountRequestAccess<WalletError>
    private let service: WalletServing
    private let commerce: CommerceServing
    private let journal: PurchaseOwnershipJournal
    private let wallet: WalletStore
    @Published private(set) var products: [CommerceProduct] = []
    @Published private(set) var productsLoading = false
    @Published private(set) var productsError: String?
    @Published private var operation: UUID?
    @Published private var stateBoundary: AccountRequestBoundary?
    @Published private var storedNotice: String?
    @Published private var storedError: String?
    @Published private var legacy: [CommerceTransaction] = []
    private var observer: Task<Void, Never>?
    private var settlementTasks: [String: Task<Settlement, Error>] = [:]
    private enum Settlement { case confirmed, localTest, needsConfirmation }
    var isBusy: Bool { operation != nil }
    var notice: String? { stateBoundary == access.boundary ? storedNotice : nil }
    var error: String? { stateBoundary == access.boundary ? storedError : nil }
    var legacyConfirmation: LegacyPurchaseConfirmation? {
        guard stateBoundary == access.boundary, !legacy.isEmpty else { return nil }
        return LegacyPurchaseConfirmation(boundary: access.boundary, transactionIDs: Set(legacy.map(\.id)))
    }
    init(accounts: IdentityScopedAccountAuthorizing, wallet: WalletStore, service: WalletServing = WalletService(),
         commerce: CommerceServing = NativeStoreKit(), journal: PurchaseOwnershipJournal = PurchaseOwnershipJournal()) {
        access = AccountRequestAccess(accounts: accounts); self.wallet = wallet
        self.service = service; self.commerce = commerce; self.journal = journal
    }
    deinit { observer?.cancel() }
    func identityChanged() {
        stateBoundary = access.boundary; storedNotice = nil; storedError = nil; legacy = []
    }
    private func prepareState(_ boundary: AccountRequestBoundary) {
        guard stateBoundary != boundary else { return }
        stateBoundary = boundary; storedNotice = nil; storedError = nil; legacy = []
    }
    func start() async {
        guard observer == nil else { return }
        let stream = await commerce.updates()
        observer = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .transaction(let tx): await self.process([tx], boundary: self.access.boundary)
                case .unverified:
                    if self.access.boundary.uid != nil {
                        self.prepareState(self.access.boundary)
                        self.storedError = "有购买尚未通过 App Store 验证，已保留待核对。"
                    }
                }
            }
        }
    }
    func loadProducts() async {
        guard !productsLoading else { return }
        productsLoading = true; productsError = nil
        defer { productsLoading = false }
        do {
            let result = try await commerce.products()
            guard Set(result.map(\.id)).count == result.count,
                  result.allSatisfy({ NativeIapCatalog.title($0.id) != nil && !$0.displayPrice.isEmpty }) else { throw CommerceError.unavailable }
            products = result
            if result.isEmpty { productsError = "App Store 商品暂不可用，请稍后重试。" }
        } catch { products = []; productsError = "暂时无法读取 App Store 商品，请稍后重试。" }
    }
    func purchase(_ id: String) async {
        guard !isBusy, products.contains(where: { $0.id == id }), let uid = access.boundary.uid else { return }
        let boundary = access.boundary, operationID = UUID()
        prepareState(boundary); operation = operationID; storedError = nil; storedNotice = nil
        defer { if operation == operationID { operation = nil } }
        do {
            try await journal.prepare()
            // Check account-service access immediately before presenting Apple's payment sheet.
            _ = try await access.perform(boundary: boundary) { try await service.account(identity: $0) }
            try await access.perform(boundary: boundary) { try await service.purchaseReadiness(identity: $0) }
            guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
            switch try await commerce.purchase(id: id, accountToken: PurchaseAccountToken.forUser(uid)) {
            case .cancelled: return
            case .pending:
                if access.isCurrent(boundary) { storedNotice = "购买正在等待批准，完成后会再次核对入账。" }
            case .transaction(let tx):
                guard tx.productID == id else { throw WalletError.invalidResponse }
                let result = try await settle(tx, boundary: boundary, allowLegacy: true)
                if access.isCurrent(boundary) {
                    switch result {
                    case .localTest: storedNotice = "本地 StoreKit 模拟已完成，未向线上发放权益。"
                    case .confirmed:
                        storedNotice = "购买记录已核对，请查看账户更新结果。"
                        await wallet.refresh()
                    case .needsConfirmation: storedNotice = "请先核对旧购买所属的云乐坊账号。"
                    }
                }
            }
        } catch {
            if access.isCurrent(boundary) { storedError = purchaseMessage(error) }
        }
    }
    func processUnfinished() async {
        let boundary = access.boundary
        guard boundary.uid != nil else { return }
        prepareState(boundary); storedError = nil
        do { let values = try await commerce.unfinished(); await process(values, boundary: boundary) }
        catch { if access.isCurrent(boundary) { stateBoundary = boundary; storedError = purchaseMessage(error) } }
    }
    func restore() async {
        guard !isBusy, access.boundary.uid != nil else { return }
        let boundary = access.boundary, operationID = UUID()
        prepareState(boundary); operation = operationID; storedError = nil; storedNotice = nil
        defer { if operation == operationID { operation = nil } }
        do {
            _ = try await access.perform(boundary: boundary) { try await service.account(identity: $0) }
            guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
            let transactions = try await commerce.restore()
            await process(transactions, boundary: boundary)
            guard access.isCurrent(boundary) else { return }
            await wallet.refresh()
            if storedError == nil && legacy.isEmpty { storedNotice = "已同步 App Store，请查看账户更新结果。已完成的云币与会员记录以云乐坊账号为准。" }
        } catch CommerceError.cancelled {
            if access.isCurrent(boundary) { storedNotice = "已取消恢复购买。" }
        } catch { if access.isCurrent(boundary) { storedError = purchaseMessage(error) } }
    }
    func confirmLegacy(_ confirmation: LegacyPurchaseConfirmation) async {
        guard !isBusy, access.isCurrent(confirmation.boundary), stateBoundary == confirmation.boundary else { return }
        let values = legacy.filter { confirmation.transactionIDs.contains($0.id) }
        guard !values.isEmpty else { return }
        let operationID = UUID(); operation = operationID
        storedError = nil
        defer { if operation == operationID { operation = nil } }
        await process(values, boundary: confirmation.boundary, allowLegacy: true)
    }
    private func process(_ values: [CommerceTransaction], boundary: AccountRequestBoundary, allowLegacy: Bool = false) async {
        guard access.isCurrent(boundary), let uid = boundary.uid else { return }
        prepareState(boundary)
        var confirmed = false
        var failed = false
        for tx in values {
            guard access.isCurrent(boundary) else { return }
            // A token belonging to another CloudBase account must never be automatically claimed here.
            if let token = tx.accountToken, token != PurchaseAccountToken.forUser(uid) { continue }
            do {
                let result = try await settle(tx, boundary: boundary, allowLegacy: allowLegacy)
                if result == .confirmed { confirmed = true }
            } catch {
                failed = true
                if access.isCurrent(boundary) { storedError = purchaseMessage(error) }
            }
        }
        if confirmed && access.isCurrent(boundary) {
            if !failed { storedError = nil; storedNotice = "购买记录已核对，请查看账户更新结果。" }
            await wallet.refresh()
        }
    }
    private func settle(_ tx: CommerceTransaction, boundary: AccountRequestBoundary, allowLegacy: Bool) async throws -> Settlement {
        guard access.isCurrent(boundary), let uid = boundary.uid else { throw WalletError.identityChanged }
        let key = tx.id + ":" + uid + ":" + boundary.generation.uuidString
        if let task = settlementTasks[key] { return try await task.value }
        let task = Task { try await self.settleCore(tx, boundary: boundary, allowLegacy: allowLegacy) }
        settlementTasks[key] = task
        defer { settlementTasks[key] = nil }
        return try await task.value
    }
    private func settleCore(_ tx: CommerceTransaction, boundary: AccountRequestBoundary, allowLegacy: Bool) async throws -> Settlement {
        guard access.isCurrent(boundary), let uid = boundary.uid, NativeIapCatalog.title(tx.productID) != nil else { throw WalletError.identityChanged }
        if tx.isLocalTest {
            try await commerce.finish(id: tx.id)
            return .localTest
        }
        guard !tx.isRevoked else { throw CommerceError.revoked }
        let binding = try await journal.binding(for: tx.id)
        guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
        if let token = tx.accountToken {
            guard token == PurchaseAccountToken.forUser(uid) else { throw WalletError.forbidden }
        } else if (binding == nil || (binding?.uid != uid && binding?.confirmed == false)) && !allowLegacy {
            if !legacy.contains(where: { $0.id == tx.id }) { legacy.append(tx) }
            return .needsConfirmation
        }
        let canReassignAttempt = binding?.confirmed == false && (allowLegacy || tx.accountToken != nil)
        guard binding == nil || binding?.uid == uid || canReassignAttempt else { throw WalletError.forbidden }
        try await journal.reserve(tx.id, to: uid, allowUnconfirmedReassignment: canReassignAttempt)
        guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
        let receipt = try await access.perform(boundary: boundary) { try await service.verify(transactionID: tx.id, identity: $0) }
        try receipt.validate(transactionID: tx.id)
        guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
        try await journal.bind(tx.id, to: uid)
        guard access.isCurrent(boundary) else { throw WalletError.identityChanged }
        try await commerce.finish(id: tx.id)
        if access.isCurrent(boundary) { legacy.removeAll { $0.id == tx.id } }
        return .confirmed
    }
    private func purchaseMessage(_ error: Error) -> String {
        if let error = error as? WalletError, error == .identityChanged { return error.message }
        if let error = error as? WalletError, error == .storage { return error.message }
        return "购买暂未完成核对。请保留原购买账号并稍后重试；未确认的交易会继续保留。"
    }
}
