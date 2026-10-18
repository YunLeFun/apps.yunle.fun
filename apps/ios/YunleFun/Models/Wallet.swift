import Foundation

enum WalletError: Error, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, unavailable, invalidResponse, identityChanged, invalidInput, storage
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .unauthorized: return "登录状态已失效，请重新登录。"
        case .forbidden: return "当前账号暂不能使用账户服务。"
        case .invalidResponse: return "账户资料暂时无法核对，请稍后刷新。"
        case .identityChanged: return "账号已变化，请重新打开钱包。"
        case .storage: return "无法安全保存购买归属，请稍后重试。"
        default: return "暂时无法连接账户服务，请检查网络后重试。"
        }
    }
    static func message(for error: Error) -> String { (error as? WalletError)?.message ?? "暂时无法连接账户服务，请稍后重试。" }
}

struct WalletSnapshot: Codable, Equatable, Sendable {
    let coin: Int64
    let membership: Membership
    struct Membership: Codable, Equatable, Sendable {
        let isActive: Bool
        let level: String?
        let expireAt: Double?
        var title: String { level == "basic" || level == nil ? "云乐坊会员" : "会员" }
        var expiration: Date? { expireAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    }
    func validate() throws {
        guard coin >= 0, coin <= 9_007_199_254_740_991,
              membership.expireAt.map({ $0.isFinite && $0 >= 0 && $0 <= 253_402_300_799_000 }) ?? true,
              !membership.isActive || (membership.level?.isEmpty == false && (membership.expireAt ?? 0) > 0)
        else { throw WalletError.invalidResponse }
    }
}

struct CoinLedgerEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let type: String
    let amount: Int64
    let balanceAfter: Int64
    let createdAt: Double
    let appId: String?
    enum CodingKeys: String, CodingKey { case id = "_id"; case userId, type, amount, balanceAfter, createdAt, appId }
    var title: String {
        switch type { case "recharge": return "充值"; case "consume": return "消费"; case "refund": return "退款"; case "gift": return "赠送"; default: return "账务调整" }
    }
    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    func validate(owner: String) throws {
        guard !id.isEmpty, id.utf16.count <= 200, userId == owner,
              (-9_007_199_254_740_991...9_007_199_254_740_991).contains(amount), balanceAfter >= 0, balanceAfter <= 9_007_199_254_740_991,
              createdAt.isFinite, (0...253_402_300_799_000).contains(createdAt) else { throw WalletError.invalidResponse }
    }
}
struct CoinLedgerPage: Decodable, Sendable {
    let items: [CoinLedgerEntry]
    let nextSkip: Int?
}
struct WalletReconciliation: Decodable, Sendable {
    let reconciled: Int
    let paid: Int
    let regranted: Int?
}
struct IapVerificationReceipt: Decodable, Sendable {
    let granted: Bool
    let alreadyProcessed: Bool?
    let outTradeNo: String
    func validate(transactionID: String) throws {
        guard outTradeNo == "iap_" + transactionID, granted || alreadyProcessed == true else { throw WalletError.invalidResponse }
    }
}

enum NativeIapCatalog {
    static let coinAmounts: [String: Int] = [
        "fun.yunle.apps.coin_100": 100, "fun.yunle.apps.coin_500": 500, "fun.yunle.apps.coin_1000": 1000
    ]
    static let memberships: [String: String] = ["fun.yunle.apps.member_month": "月度会员", "fun.yunle.apps.member_year": "年度会员"]
    static let allIDs = coinAmounts.keys.sorted() + memberships.keys.sorted()
    static func title(_ id: String) -> String? { coinAmounts[id].map { "\($0) 云币" } ?? memberships[id] }
}
