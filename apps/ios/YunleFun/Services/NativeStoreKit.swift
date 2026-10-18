import Foundation
import StoreKit

struct CommerceProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayPrice: String
    var title: String { NativeIapCatalog.title(id) ?? "商品" }
}
struct CommerceTransaction: Equatable, Sendable {
    let id: String
    let productID: String
    let accountToken: UUID?
    let isLocalTest: Bool
    let isRevoked: Bool
}
enum CommercePurchaseResult: Sendable { case transaction(CommerceTransaction), cancelled, pending }
enum CommerceEvent: Sendable { case transaction(CommerceTransaction), unverified }
enum CommerceError: Error { case unavailable, unverified, unknownProduct, revoked, cancelled }
protocol CommerceServing: Sendable {
    func products() async throws -> [CommerceProduct]
    func purchase(id: String, accountToken: UUID) async throws -> CommercePurchaseResult
    func unfinished() async throws -> [CommerceTransaction]
    func restore() async throws -> [CommerceTransaction]
    func finish(id: String) async throws
    func updates() async -> AsyncStream<CommerceEvent>
}

actor NativeStoreKit: CommerceServing {
    private var loadedProducts: [String: Product] = [:]
    private var verifiedTransactions: [String: Transaction] = [:]
    func products() async throws -> [CommerceProduct] {
        let values = try await Product.products(for: NativeIapCatalog.allIDs)
        let accepted = values.filter { product in
            NativeIapCatalog.coinAmounts[product.id] != nil ? product.type == .consumable :
                NativeIapCatalog.memberships[product.id] != nil && product.type == .nonRenewable
        }
        loadedProducts = Dictionary(uniqueKeysWithValues: accepted.map { ($0.id, $0) })
        return accepted.map { CommerceProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }
    func purchase(id: String, accountToken: UUID) async throws -> CommercePurchaseResult {
        guard let product = loadedProducts[id] else { throw CommerceError.unknownProduct }
        do { switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
        case .success(let result): return .transaction(try record(result))
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw CommerceError.unavailable
        } } catch StoreKitError.userCancelled { return .cancelled }
    }
    func unfinished() async throws -> [CommerceTransaction] {
        var values: [CommerceTransaction] = []
        for await result in Transaction.unfinished { values.append(try record(result)) }
        return values
    }
    func restore() async throws -> [CommerceTransaction] {
        // Only the explicit Restore Purchases action reaches AppStore.sync.
        do { try await AppStore.sync() }
        catch StoreKitError.userCancelled { throw CommerceError.cancelled }
        var values = Dictionary(uniqueKeysWithValues: try await unfinished().map { ($0.id, $0) })
        // Includes the latest non-renewing membership even after finish; consumables remain server-account balances.
        for await result in Transaction.currentEntitlements {
            let tx = try record(result); values[tx.id] = tx
        }
        return Array(values.values)
    }
    func finish(id: String) async throws {
        // Refresh the verified transaction from StoreKit's queue, as the existing plugin does.
        // A retained purchase result may belong to a previous StoreKit synchronization snapshot.
        for await result in Transaction.unfinished {
            if case .unverified(let value, _) = result, String(value.id) == id { throw CommerceError.unverified }
            guard case .verified(let transaction) = result, String(transaction.id) == id else { continue }
            let value = try record(result)
            if value.id == id, let transaction = verifiedTransactions[id] {
                await transaction.finish(); verifiedTransactions[id] = nil; return
            }
        }
        if let value = verifiedTransactions[id] { await value.finish(); verifiedTransactions[id] = nil }
        // A duplicate successful settlement may have already finished it.
    }
    func updates() async -> AsyncStream<CommerceEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if Task.isCancelled { break }
                    do { continuation.yield(.transaction(try self.record(result))) }
                    catch { continuation.yield(.unverified) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private func record(_ result: VerificationResult<Transaction>) throws -> CommerceTransaction {
        guard case .verified(let tx) = result else { throw CommerceError.unverified }
        guard NativeIapCatalog.title(tx.productID) != nil else { throw CommerceError.unknownProduct }
        let id = String(tx.id)
        verifiedTransactions[id] = tx
        return CommerceTransaction(id: id, productID: tx.productID, accountToken: tx.appAccountToken,
                                  isLocalTest: tx.environment == .xcode || tx.originalID == 0, isRevoked: tx.revocationDate != nil)
    }
}
