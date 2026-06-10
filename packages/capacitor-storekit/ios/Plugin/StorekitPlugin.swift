import Capacitor
import Foundation
import StoreKit

/// StoreKit 2 内购插件。
///
/// 设计原则：购买成功后**不在客户端 finish 交易**，由 JS 侧把 transactionId
/// 交给服务端（iap-order 云函数）经 App Store Server API 校验入账，
/// 成功后再调 `finishTransaction`。这样杀进程 / 网络失败时交易保留在
/// `Transaction.unfinished` 中，可随时补单，权益不会丢。
@objc(StorekitPlugin)
public class StorekitPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "StorekitPlugin"
    public let jsName = "Storekit"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getProducts", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "purchase", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "finishTransaction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getUnfinishedTransactions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restorePurchases", returnType: CAPPluginReturnPromise),
    ]

    private var updatesTask: Task<Void, Never>?

    override public func load() {
        // 监听交易更新（待批准完成 / 客服补单 / 其他设备购买）
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { break }
                if let data = Self.transactionData(update) {
                    self.notifyListeners("transactionUpdated", data: data)
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 仅序列化通过 StoreKit 本地验签的交易
    private static func transactionData(_ result: VerificationResult<Transaction>) -> [String: Any]? {
        guard case .verified(let tx) = result else { return nil }
        return [
            "transactionId": String(tx.id),
            "originalTransactionId": String(tx.originalID),
            "productId": tx.productID,
            "jws": result.jwsRepresentation,
        ]
    }

    @objc func getProducts(_ call: CAPPluginCall) {
        guard let ids = call.getArray("productIds", String.self), !ids.isEmpty else {
            call.reject("productIds 必填")
            return
        }
        Task {
            do {
                let products = try await Product.products(for: ids)
                let list: [[String: Any]] = products.map { product in
                    [
                        "productId": product.id,
                        "displayName": product.displayName,
                        "description": product.description,
                        "displayPrice": product.displayPrice,
                        "price": (product.price as NSDecimalNumber).doubleValue,
                        "type": product.type.rawValue,
                    ]
                }
                call.resolve(["products": list])
            } catch {
                call.reject("拉取商品失败: \(error.localizedDescription)")
            }
        }
    }

    @objc func purchase(_ call: CAPPluginCall) {
        guard let productId = call.getString("productId") else {
            call.reject("productId 必填")
            return
        }
        Task {
            do {
                guard let product = try await Product.products(for: [productId]).first else {
                    call.reject("商品不存在: \(productId)")
                    return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    guard let data = Self.transactionData(verification) else {
                        call.reject("交易验签失败", "VERIFICATION_FAILED")
                        return
                    }
                    // 不 finish：等服务端入账成功后由 JS 调 finishTransaction
                    call.resolve(data)
                case .userCancelled:
                    call.reject("用户取消", "USER_CANCELLED")
                case .pending:
                    call.reject("交易待批准，完成后将通过 transactionUpdated 通知", "PENDING")
                @unknown default:
                    call.reject("未知购买结果")
                }
            } catch {
                call.reject("购买失败: \(error.localizedDescription)")
            }
        }
    }

    @objc func finishTransaction(_ call: CAPPluginCall) {
        guard let idString = call.getString("transactionId"), let id = UInt64(idString) else {
            call.reject("transactionId 必填")
            return
        }
        Task {
            for await result in Transaction.unfinished {
                if case .verified(let tx) = result, tx.id == id {
                    await tx.finish()
                    call.resolve()
                    return
                }
            }
            // 未找到视为已结束（幂等）
            call.resolve()
        }
    }

    @objc func getUnfinishedTransactions(_ call: CAPPluginCall) {
        Task {
            var list: [[String: Any]] = []
            for await result in Transaction.unfinished {
                if let data = Self.transactionData(result) {
                    list.append(data)
                }
            }
            call.resolve(["transactions": list])
        }
    }

    @objc func restorePurchases(_ call: CAPPluginCall) {
        Task {
            // 强制与 App Store 同步（会弹登录框）；用户取消不视为致命错误
            try? await AppStore.sync()
            var list: [[String: Any]] = []
            for await result in Transaction.unfinished {
                if let data = Self.transactionData(result) {
                    list.append(data)
                }
            }
            call.resolve(["transactions": list])
        }
    }
}
