import Foundation

enum WalletEnvironment: Sendable {
    case production, sandbox
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments,
                          receiptURL: URL? = Bundle.main.appStoreReceiptURL) -> Self {
        // TestFlight is a Release build, but its Apple transactions are Sandbox.
        // Keep the entire wallet in the isolated lane, including restore/retry.
        if receiptURL?.lastPathComponent == "sandboxReceipt" { return .sandbox }
        #if DEBUG
        if arguments.contains("--iap-sandbox") { return .sandbox }
        #endif
        return .production
    }
    var accountFunction: String { self == .sandbox ? "account-api-sandbox" : "account-api" }
    var purchaseFunction: String { self == .sandbox ? "iap-order-sandbox" : "iap-order" }
    func ownershipService(bundleID: String) -> String {
        bundleID + (self == .sandbox ? ".iap-sandbox-owners" : ".iap-owners")
    }
}

protocol WalletServing: Sendable {
    var environment: WalletEnvironment { get }
    func account(identity: AuthorizedAccount) async throws -> WalletSnapshot
    func transactions(skip: Int, limit: Int, identity: AuthorizedAccount) async throws -> CoinLedgerPage
    func verify(transactionID: String, identity: AuthorizedAccount) async throws -> IapVerificationReceipt
    func reconcile(identity: AuthorizedAccount) async throws -> WalletReconciliation
    func purchaseReadiness(identity: AuthorizedAccount) async throws
}
extension WalletServing { var environment: WalletEnvironment { .production } }
struct WalletService: WalletServing {
    let session: URLSession
    let gateway: URL
    let environment: WalletEnvironment
    init(session: URLSession? = nil, gateway: URL = CloudbaseAuthService.gateway, environment: WalletEnvironment = .production) {
        self.gateway = gateway; self.environment = environment
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: config, delegate: WalletRedirectPolicy(), delegateQueue: nil)
        }
    }
    func account(identity: AuthorizedAccount) async throws -> WalletSnapshot {
        let value: WalletSnapshot = try await call(environment.accountFunction, fields: ["action": "getAccount"], identity: identity)
        try value.validate(); return value
    }
    func transactions(skip: Int, limit: Int, identity: AuthorizedAccount) async throws -> CoinLedgerPage {
        guard skip >= 0, skip <= 1_000_000, (1...100).contains(limit) else { throw WalletError.invalidInput }
        let page: CoinLedgerPage = try await call(environment.accountFunction, fields: ["action": "listTransactions", "skip": skip, "limit": limit], identity: identity)
        guard page.items.count <= limit, Set(page.items.map(\.id)).count == page.items.count,
              page.nextSkip == nil || (page.items.count == limit && page.nextSkip == skip + limit) else { throw WalletError.invalidResponse }
        for item in page.items { try item.validate(owner: identity.userID) }
        return page
    }
    func verify(transactionID: String, identity: AuthorizedAccount) async throws -> IapVerificationReceipt {
        guard transactionID.range(of: #"^[0-9]{1,32}$"#, options: .regularExpression) != nil else { throw WalletError.invalidInput }
        let receipt: IapVerificationReceipt = try await call(environment.purchaseFunction, fields: ["action": "verifyPurchase", "transactionId": transactionID], identity: identity)
        try receipt.validate(transactionID: transactionID); return receipt
    }
    func reconcile(identity: AuthorizedAccount) async throws -> WalletReconciliation {
        // Sandbox has only IAP transactions; StoreKit unfinished/restore owns
        // their verification. Never reconcile real WeChat orders in this lane.
        if environment == .sandbox { return WalletReconciliation(reconciled: 0, paid: 0, regranted: 0) }
        let result: WalletReconciliation = try await call("wxpay-order", fields: ["action": "reconcileOrders"], identity: identity)
        guard (0...20).contains(result.reconciled), result.paid >= 0, result.paid <= result.reconciled,
              result.regranted.map({ (0...20).contains($0) }) ?? true else { throw WalletError.invalidResponse }
        return result
    }
    func purchaseReadiness(identity: AuthorizedAccount) async throws {
        // Existing iap-order checks active/non-synthetic identity and configuration before this empty restore.
        // An empty transaction list performs no Apple lookup or entitlement grant.
        let result: EmptyRestoreReceipt = try await call(environment.purchaseFunction, fields: ["action": "restore", "transactionIds": [] as [String]], identity: identity)
        guard result.results.isEmpty else { throw WalletError.invalidResponse }
    }
    private struct EmptyRestoreReceipt: Decodable {
        let results: [Entry]
        struct Entry: Decodable {}
    }
    private struct SandboxMarker: Decodable { let ledgerEnvironment: String }
    private func call<Value: Decodable>(_ function: String, fields: [String: Any], identity: AuthorizedAccount) async throws -> Value {
        var request = URLRequest(url: gateway.appendingPathComponent("v1/functions").appendingPathComponent(function))
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WalletError.invalidResponse }
        if http.statusCode == 401 { throw WalletError.unauthorized }
        if http.statusCode == 403 { throw WalletError.forbidden }
        guard (200..<300).contains(http.statusCode) else { throw WalletError.unavailable }
        if environment == .sandbox {
            guard let marker = try? JSONDecoder().decode(SandboxMarker.self, from: data), marker.ledgerEnvironment == "Sandbox"
            else { throw WalletError.invalidResponse }
        }
        // Official Functions OpenAPI returns the function's object directly, not the JS SDK {result} wrapper.
        guard data.count <= 2 * 1024 * 1024, let value = try? JSONDecoder().decode(Value.self, from: data) else { throw WalletError.invalidResponse }
        return value
    }
}
private final class WalletRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
