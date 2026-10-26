import XCTest
@testable import YunleFun

final class WalletServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }
    private let identity = AuthorizedAccount(userID: "alice", accessToken: "fixture-token")
    func testFunctionProtocolIsDirectJSONWithBearerAndNoCallerUID() async throws {
        let (service, fixture) = service([(200, walletSnapshotJSON), (200, #"{"items":[],"nextSkip":null}"#)])
        let snapshot = try await service.account(identity: identity)
        XCTAssertEqual(snapshot.coin, 125)
        _ = try await service.transactions(skip: 0, limit: 20, identity: identity)
        XCTAssertEqual(fixture.requests[0].url?.path, "/v1/functions/account-api")
        XCTAssertEqual(fixture.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        let fields = try JSONSerialization.jsonObject(with: walletRequestBody(fixture.requests[0])) as! [String: String]
        XCTAssertEqual(fields, ["action": "getAccount"])
        XCTAssertNil(fixture.requests[0].value(forHTTPHeaderField: "Cookie"))
    }
    func testMalformedBalanceAndSDKWrapperAreNotZeroBalances() async throws {
        for payload in [#"{"result":{"coin":0,"membership":{"isActive":false}}}"#,
                        #"{"coin":-1,"membership":{"isActive":false}}"#,
                        #"{"coin":true,"membership":{"isActive":false}}"#,
                        #"{"coin":1,"membership":{"isActive":true,"level":"basic","expireAt":null}}"#] {
            let (service, _) = service([(200, payload)])
            do { _ = try await service.account(identity: identity); XCTFail("Reject an unverified snapshot") }
            catch { XCTAssertEqual(error as? WalletError, .invalidResponse) }
        }
    }
    func testLedgerRejectsAnotherOwnerAndIntegerOverflow() async throws {
        for uid in ["bob", "alice"] {
            let amount = uid == "alice" ? "-9223372036854775808" : "10"
            let payload = #"{"items":[{"_id":"tx1","userId":"UID","type":"gift","amount":AMOUNT,"balanceAfter":10,"createdAt":1000}],"nextSkip":null}"#
                .replacingOccurrences(of: "UID", with: uid).replacingOccurrences(of: "AMOUNT", with: amount)
            let (service, _) = service([(200, payload)])
            do { _ = try await service.transactions(skip: 0, limit: 20, identity: identity); XCTFail("Do not expose another account or overflow a ledger amount") }
            catch { XCTAssertEqual(error as? WalletError, .invalidResponse) }
        }
    }
    func testUnconfirmedOrMismatchedReceiptCannotFinishAPurchase() async throws {
        for payload in [#"{"granted":false,"outTradeNo":"iap_123"}"#,
                        #"{"granted":true,"outTradeNo":"iap_999"}"#,
                        #"{"result":{"granted":true,"outTradeNo":"iap_123"}}"#] {
            let (service, _) = service([(200, payload)])
            do { _ = try await service.verify(transactionID: "123", identity: identity); XCTFail("Receipt is not sufficient") }
            catch { XCTAssertEqual(error as? WalletError, .invalidResponse) }
        }
        let (service, fixture) = service([(200, #"{"granted":false,"alreadyProcessed":true,"outTradeNo":"iap_123"}"#)])
        _ = try await service.verify(transactionID: "123", identity: identity)
        XCTAssertEqual(fixture.requests[0].url?.path, "/v1/functions/iap-order")
    }
    func testUnauthorizedAndServiceFailureRemainDifferent() async throws {
        for (status, expected) in [(401, WalletError.unauthorized), (403, .forbidden), (503, .unavailable)] {
            let (service, _) = service([(status, "{}")])
            do { _ = try await service.account(identity: identity); XCTFail("Expected an error") }
            catch { XCTAssertEqual(error as? WalletError, expected) }
        }
    }
    func testPurchaseReadinessUsesAnEmptyNonGrantingRestore() async throws {
        let (service, fixture) = service([(200, #"{"results":[]}"#)])
        try await service.purchaseReadiness(identity: identity)
        let fields = try JSONSerialization.jsonObject(with: walletRequestBody(fixture.requests[0])) as! [String: Any]
        XCTAssertEqual(fixture.requests[0].url?.path, "/v1/functions/iap-order")
        XCTAssertEqual(fields["action"] as? String, "restore")
        XCTAssertEqual(fields["transactionIds"] as? [String], [])
        XCTAssertNil(fields["transactionId"])
    }
    func testSandboxRoutesEveryRequestWithoutReconcilingProductionOrders() async throws {
        let (service, fixture) = service([
            (200, sandbox(walletSnapshotJSON)), (200, sandbox(#"{"items":[],"nextSkip":null}"#)),
            (200, sandbox(#"{"granted":true,"outTradeNo":"iap_123"}"#)), (200, sandbox(#"{"results":[]}"#))
        ], environment: .sandbox)
        let reconciliation = try await service.reconcile(identity: identity)
        XCTAssertEqual(reconciliation.reconciled, 0)
        XCTAssertTrue(fixture.requests.isEmpty)
        _ = try await service.account(identity: identity)
        _ = try await service.transactions(skip: 0, limit: 20, identity: identity)
        _ = try await service.verify(transactionID: "123", identity: identity)
        try await service.purchaseReadiness(identity: identity)
        XCTAssertEqual(fixture.requests.compactMap { $0.url?.lastPathComponent },
                       ["account-api-sandbox", "account-api-sandbox", "iap-order-sandbox", "iap-order-sandbox"])
        for request in fixture.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            let fields = try JSONSerialization.jsonObject(with: walletRequestBody(request)) as! [String: Any]
            XCTAssertNil(fields["userId"]); XCTAssertNil(fields["environment"]); XCTAssertNil(fields["collection"])
        }
    }
    func testSandboxRequiresAnExplicitLedgerMarkerForEveryResponse() async throws {
        let payloads = [walletSnapshotJSON, #"{"items":[],"nextSkip":null}"#,
                        #"{"granted":true,"outTradeNo":"iap_123"}"#, #"{"results":[]}"#]
        for (operation, payload) in payloads.enumerated() {
            for marked in [payload, sandbox(payload).replacingOccurrences(of: "Sandbox", with: "Production")] {
                let (service, fixture) = service([(200, marked)], environment: .sandbox)
                do { try await perform(operation, service: service); XCTFail("A test endpoint must identify its test ledger") }
                catch { XCTAssertEqual(error as? WalletError, .invalidResponse) }
                XCTAssertEqual(fixture.requests.count, 1)
                XCTAssertTrue(fixture.requests[0].url!.lastPathComponent.hasSuffix("-sandbox"))
            }
        }
    }
    func testSandboxFailuresNeverRetryAgainstProduction() async throws {
        for operation in 0..<4 {
            for (status, expected) in [(401, WalletError.unauthorized), (403, .forbidden), (404, .unavailable), (503, .unavailable)] {
                let (service, fixture) = service([(status, "{}")], environment: .sandbox)
                do { try await perform(operation, service: service); XCTFail("Expected the test service failure") }
                catch { XCTAssertEqual(error as? WalletError, expected) }
                XCTAssertEqual(fixture.requests.count, 1)
                XCTAssertTrue(fixture.requests[0].url!.lastPathComponent.hasSuffix("-sandbox"))
            }
        }
    }
    func testSandboxLaunchSelectionAndOwnershipStorageAreExplicit() {
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: [], receiptURL: nil), .production)
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: ["--iap-sandbox=false"], receiptURL: nil), .production)
        #if DEBUG
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: ["--iap-sandbox"], receiptURL: nil), .sandbox)
        #else
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: ["--iap-sandbox"], receiptURL: nil), .production)
        #endif
        XCTAssertEqual(WalletEnvironment.production.ownershipService(bundleID: "fixture.app"), "fixture.app.iap-owners")
        XCTAssertEqual(WalletEnvironment.sandbox.ownershipService(bundleID: "fixture.app"), "fixture.app.iap-sandbox-owners")
        XCTAssertEqual(WalletService().environment, .production)
    }
    func testTestFlightReleaseReceiptSelectsIsolatedWalletWithoutLaunchFlag() {
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: [], receiptURL: URL(fileURLWithPath: "/StoreKit/sandboxReceipt")), .sandbox)
        XCTAssertEqual(WalletEnvironment.forLaunch(arguments: [], receiptURL: URL(fileURLWithPath: "/StoreKit/receipt")), .production)
    }
    func testProductionReconciliationKeepsItsExistingEndpoint() async throws {
        let (service, fixture) = service([(200, #"{"reconciled":2,"paid":1,"regranted":0}"#)])
        let result = try await service.reconcile(identity: identity)
        XCTAssertEqual(result.paid, 1)
        XCTAssertEqual(fixture.requests[0].url?.lastPathComponent, "wxpay-order")
    }
    private func sandbox(_ json: String) -> String {
        "{\"ledgerEnvironment\":\"Sandbox\"," + json.dropFirst()
    }
    private func perform(_ operation: Int, service: WalletService) async throws {
        switch operation {
        case 0: _ = try await service.account(identity: identity)
        case 1: _ = try await service.transactions(skip: 0, limit: 20, identity: identity)
        case 2: _ = try await service.verify(transactionID: "123", identity: identity)
        default: try await service.purchaseReadiness(identity: identity)
        }
    }
    private func service(_ replies: [(Int, String)], environment: WalletEnvironment = .production) -> (WalletService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".wallet.test"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (WalletService(session: URLSession(configuration: config), gateway: URL(string: "https://\(host)")!, environment: environment), fixture)
    }
}

@MainActor
final class PurchaseCoordinatorTests: XCTestCase {
    func testSandboxAndUnknownTransactionsNeverReachProductionSettlementOrFinish() async throws {
        for environment: WalletEnvironment? in [.sandbox, nil] {
            var tx = billingTransaction()
            tx.environment = environment
            let rig = billingRig(unfinished: [tx])
            await rig.coordinator.processUnfinished()
            var calls = await rig.log.values
            XCTAssertFalse(calls.contains("verify.begin")); XCTAssertFalse(calls.contains("finish"))
            XCTAssertNotNil(rig.coordinator.error)
            await rig.coordinator.restore()
            calls = await rig.log.values
            XCTAssertFalse(calls.contains("verify.begin")); XCTAssertFalse(calls.contains("finish"))
        }
    }
    func testSuccessfulReceiptPrecedesFinish() async throws {
        let rig = billingRig()
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        let log = await rig.log.values
        XCTAssertEqual(log.filter { $0.hasPrefix("verify") || $0 == "finish" }, ["verify.begin", "verify.confirmed", "finish"])
        XCTAssertNotNil(rig.coordinator.notice)
    }
    func testFailedVerificationLeavesTransactionUnfinished() async throws {
        let rig = billingRig(verifyFailure: true)
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        let log = await rig.log.values
        XCTAssertTrue(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
        XCTAssertNotNil(rig.coordinator.error)
    }
    func testSwitchWhilePaymentSheetIsOpenDoesNotClaimUnderNewAccount() async throws {
        let gate = BillingGate(), rig = billingRig(purchaseGate: gate)
        await rig.coordinator.loadProducts()
        let task = Task { await rig.coordinator.purchase(coinProduct) }
        await fulfillment(of: [gate.entered], timeout: 2)
        rig.accounts.select("bob"); rig.coordinator.identityChanged()
        await gate.open(); await task.value
        let log = await rig.log.values
        XCTAssertFalse(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
        XCTAssertNil(rig.coordinator.notice)
    }
    func testSwitchDuringVerificationNeverFinishesForTheNewIdentity() async throws {
        let gate = BillingGate(), rig = billingRig(verifyGate: gate)
        await rig.coordinator.loadProducts()
        let task = Task { await rig.coordinator.purchase(coinProduct) }
        await fulfillment(of: [gate.entered], timeout: 2)
        rig.accounts.select("bob"); rig.coordinator.identityChanged()
        await gate.open(); await task.value
        let log = await rig.log.values
        XCTAssertTrue(log.contains("verify.confirmed")); XCTAssertFalse(log.contains("finish"))
        XCTAssertNil(rig.coordinator.notice)
    }
    func testABASwitchBeforeAppleSheetPreventsPurchase() async throws {
        let gate = BillingGate(), rig = billingRig(accountGate: gate)
        await rig.coordinator.loadProducts()
        let task = Task { await rig.coordinator.purchase(coinProduct) }
        await fulfillment(of: [gate.entered], timeout: 2)
        rig.accounts.select("bob"); rig.accounts.select("alice")
        await gate.open(); await task.value
        let log = await rig.log.values; XCTAssertFalse(log.contains("purchase"))
    }
    func testPendingAndCancellationDoNotVerifyOrFinish() async throws {
        for outcome in [CommercePurchaseResult.pending, .cancelled] {
            let rig = billingRig(outcome: outcome)
            await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
            let log = await rig.log.values
            XCTAssertFalse(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
            XCTAssertNil(rig.coordinator.error)
        }
    }
    func testOldUntaggedTransactionRequiresExplicitAccountConfirmation() async throws {
        let tx = billingTransaction(token: nil), rig = billingRig(unfinished: [tx])
        await rig.coordinator.processUnfinished()
        var log = await rig.log.values
        XCTAssertFalse(log.contains("verify.begin"))
        let confirmation = try XCTUnwrap(rig.coordinator.legacyConfirmation)
        await rig.coordinator.confirmLegacy(confirmation)
        log = await rig.log.values
        XCTAssertTrue(log.contains("verify.confirmed")); XCTAssertTrue(log.contains("finish"))
        XCTAssertNil(rig.coordinator.legacyConfirmation)
    }
    func testOldConfirmationCannotCrossAnAccountSwitch() async throws {
        let rig = billingRig(unfinished: [billingTransaction(token: nil)])
        await rig.coordinator.processUnfinished()
        let confirmation = try XCTUnwrap(rig.coordinator.legacyConfirmation)
        rig.accounts.select("bob")
        await rig.coordinator.confirmLegacy(confirmation)
        let log = await rig.log.values
        XCTAssertFalse(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
    }
    func testOtherAccountTokenIsNotAutomaticallyClaimed() async throws {
        let rig = billingRig(unfinished: [billingTransaction(token: PurchaseAccountToken.forUser("bob"))])
        await rig.coordinator.processUnfinished()
        let log = await rig.log.values
        XCTAssertFalse(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
        XCTAssertNil(rig.coordinator.legacyConfirmation)
    }
    func testLocalStoreKitNeverReachesOnlineVerification() async throws {
        let local = CommerceTransaction(id: "7", productID: coinProduct, accountToken: nil, isLocalTest: true, isRevoked: false)
        let rig = billingRig(outcome: .transaction(local))
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        let log = await rig.log.values
        XCTAssertTrue(log.contains("finish")); XCTAssertFalse(log.contains("verify.begin"))
        XCTAssertTrue(rig.coordinator.notice?.contains("本地 StoreKit") == true)
    }
    func testJournalFailureStopsBeforeOpeningAppleSheet() async throws {
        let vault = BillingMemoryVault(data: Data("corrupt".utf8)), rig = billingRig(vault: vault)
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        let log = await rig.log.values
        XCTAssertFalse(log.contains("purchase")); XCTAssertEqual(try vault.read(), Data("corrupt".utf8))
    }
    func testAccountSnapshotAndLedgerHideSynchronouslyOnABASwitch() async throws {
        let rig = billingRig()
        await rig.wallet.refreshAccount(); XCTAssertEqual(rig.wallet.snapshot?.coin, 125)
        rig.accounts.select("bob"); rig.accounts.select("alice")
        XCTAssertNil(rig.wallet.snapshot); XCTAssertTrue(rig.wallet.entries.isEmpty)
    }
    func testFailedHistoricalReconciliationStillLoadsCurrentBalance() async throws {
        let rig = billingRig()
        await rig.service.setReconciliationFailure()
        await rig.wallet.reconcileAndRefresh()
        XCTAssertEqual(rig.wallet.snapshot?.coin, 125); XCTAssertNotNil(rig.wallet.reconciliationError)
    }
    func testWalletRemainsLoadingWhileHistoricalOrdersAreBeingReconciled() async {
        for fails in [false, true] {
            let gate = BillingGate(), rig = billingRig(reconciliationGate: gate)
            if fails { await rig.service.setReconciliationFailure() }
            let task = Task { await rig.wallet.reconcileAndRefresh() }
            await fulfillment(of: [gate.entered], timeout: 2)
            XCTAssertTrue(rig.wallet.isLoading, "Balance must not appear idle before its first read")
            XCTAssertTrue(rig.wallet.isLoadingTransactions, "An unread ledger must not appear empty")
            XCTAssertNil(rig.wallet.snapshot)
            XCTAssertTrue(rig.wallet.entries.isEmpty)
            await gate.open(); await task.value
            XCTAssertFalse(rig.wallet.isLoading)
            XCTAssertFalse(rig.wallet.isLoadingTransactions)
            XCTAssertEqual(rig.wallet.snapshot?.coin, 125)
            XCTAssertNil(rig.wallet.nextSkip, "An empty ledger is conclusive only after reading it")
            XCTAssertEqual(rig.wallet.reconciliationError != nil, fails)
        }
    }
    func testReconciliationLoadingAndCompletionCannotCrossAnAccountRoundtrip() async {
        let gate = BillingGate(), rig = billingRig(reconciliationGate: gate)
        let task = Task { await rig.wallet.reconcileAndRefresh() }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertTrue(rig.wallet.isLoading)
        XCTAssertTrue(rig.wallet.isLoadingTransactions)
        rig.accounts.select("bob"); rig.accounts.select("alice")
        XCTAssertFalse(rig.wallet.isLoading)
        XCTAssertFalse(rig.wallet.isLoadingTransactions)
        rig.wallet.identityChanged()
        await gate.open(); await task.value
        XCTAssertNil(rig.wallet.snapshot, "The old operation must not begin reads for the new identity")
        XCTAssertNil(rig.wallet.checkedAt)
        XCTAssertFalse(rig.wallet.isLoading)
        XCTAssertFalse(rig.wallet.isLoadingTransactions)
        await rig.wallet.refresh()
        XCTAssertEqual(rig.wallet.snapshot?.coin, 125)
    }
    func testOpaqueAccountTokenIsStableAndAccountSpecific() {
        XCTAssertEqual(PurchaseAccountToken.forUser("alice"), PurchaseAccountToken.forUser("alice"))
        XCTAssertNotEqual(PurchaseAccountToken.forUser("alice"), PurchaseAccountToken.forUser("bob"))
    }
    func testDuplicateCompensationSharesOneVerificationAndFinish() async throws {
        let gate = BillingGate(), rig = billingRig(verifyGate: gate, unfinished: [billingTransaction()])
        let first = Task { await rig.coordinator.processUnfinished() }
        await fulfillment(of: [gate.entered], timeout: 2)
        let second = Task { await rig.coordinator.processUnfinished() }
        await Task.yield(); await gate.open()
        await first.value; await second.value
        let log = await rig.log.values
        XCTAssertEqual(log.filter { $0 == "verify.begin" }.count, 1)
        XCTAssertEqual(log.filter { $0 == "finish" }.count, 1)
    }
    func testRevocationAndUnconfirmedReceiptDoNotFinish() async throws {
        let revoked = CommerceTransaction(id: "123", productID: coinProduct, accountToken: PurchaseAccountToken.forUser("alice"), isLocalTest: false, isRevoked: true)
        let first = billingRig(outcome: .transaction(revoked))
        await first.coordinator.loadProducts(); await first.coordinator.purchase(coinProduct)
        let revokedLog = await first.log.values; XCTAssertFalse(revokedLog.contains("verify.begin")); XCTAssertFalse(revokedLog.contains("finish"))
        let second = billingRig(validReceipt: false)
        await second.coordinator.loadProducts(); await second.coordinator.purchase(coinProduct)
        let invalidLog = await second.log.values; XCTAssertTrue(invalidLog.contains("verify.begin")); XCTAssertFalse(invalidLog.contains("finish"))
    }
    func testPersistedLegacyOwnerSurvivesRestartAndCannotCrossAccounts() async throws {
        let vault = BillingMemoryVault(), journal = PurchaseOwnershipJournal(vault: vault)
        try await journal.bind("123", to: "alice")
        let first = billingRig(unfinished: [billingTransaction(token: nil)], vault: vault)
        await first.coordinator.processUnfinished()
        let firstLog = await first.log.values; XCTAssertTrue(firstLog.contains("finish"))
        let second = billingRig(unfinished: [billingTransaction(token: nil)], vault: vault)
        second.accounts.select("bob")
        await second.coordinator.processUnfinished()
        let secondLog = await second.log.values; XCTAssertFalse(secondLog.contains("verify.begin")); XCTAssertFalse(secondLog.contains("finish"))
    }
    func testAppStoreSyncIsReservedForExplicitRestore() async throws {
        let rig = billingRig()
        await rig.coordinator.processUnfinished()
        var log = await rig.log.values; XCTAssertFalse(log.contains("restore"))
        await rig.coordinator.restore()
        log = await rig.log.values; XCTAssertTrue(log.contains("restore"))
    }
    func testRestoreAuthenticationCancellationIsNotAClaimFailure() async throws {
        let rig = billingRig(restoreCancelled: true)
        await rig.coordinator.restore()
        XCTAssertNil(rig.coordinator.error); XCTAssertTrue(rig.coordinator.notice?.contains("已取消") == true)
        let log = await rig.log.values; XCTAssertFalse(log.contains("verify.begin")); XCTAssertFalse(log.contains("finish"))
    }
    func testFailedLegacyAttemptCanBeCorrectedByOriginalAccount() async throws {
        let vault = BillingMemoryVault(), tx = billingTransaction(token: nil)
        let wrong = billingRig(verifyFailure: true, unfinished: [tx], vault: vault)
        wrong.accounts.select("bob"); await wrong.coordinator.processUnfinished()
        await wrong.coordinator.confirmLegacy(try XCTUnwrap(wrong.coordinator.legacyConfirmation))
        let pending = try await PurchaseOwnershipJournal(vault: vault).binding(for: tx.id)
        XCTAssertEqual(pending?.uid, "bob"); XCTAssertEqual(pending?.confirmed, false)
        let original = billingRig(unfinished: [tx], vault: vault)
        await original.coordinator.processUnfinished()
        var calls = await original.log.values; XCTAssertFalse(calls.contains("verify.begin"))
        await original.coordinator.confirmLegacy(try XCTUnwrap(original.coordinator.legacyConfirmation))
        calls = await original.log.values; XCTAssertTrue(calls.contains("finish"))
        let confirmed = try await PurchaseOwnershipJournal(vault: vault).binding(for: tx.id)
        XCTAssertEqual(confirmed?.uid, "alice"); XCTAssertEqual(confirmed?.confirmed, true)
    }
    func testPrototypeJournalMigratesAsUnconfirmedAttempt() async throws {
        let data = Data(#"{"version":1,"owners":{"123":"alice"}}"#.utf8), vault = BillingMemoryVault(data: data)
        let journal = PurchaseOwnershipJournal(vault: vault)
        let binding = try await journal.binding(for: "123")
        XCTAssertEqual(binding?.uid, "alice"); XCTAssertEqual(binding?.confirmed, false)
        try await journal.reserve("123", to: "bob", allowUnconfirmedReassignment: true)
        XCTAssertTrue(String(data: try XCTUnwrap(vault.read()), encoding: .utf8)?.contains(#""version":2"#) == true)
    }
    func testNewOperationCannotReactivateLegacyRowsFromAnOlderGeneration() async throws {
        let rig = billingRig(outcome: .cancelled, unfinished: [billingTransaction(token: nil)])
        await rig.coordinator.processUnfinished()
        XCTAssertNotNil(rig.coordinator.legacyConfirmation)
        rig.accounts.select("bob"); rig.accounts.select("alice")
        XCTAssertNil(rig.coordinator.legacyConfirmation)
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        XCTAssertNil(rig.coordinator.legacyConfirmation)
    }
    func testUnavailableIapServiceStopsBeforeAppleCanCharge() async throws {
        let rig = billingRig(readinessFailure: true)
        await rig.coordinator.loadProducts(); await rig.coordinator.purchase(coinProduct)
        let calls = await rig.log.values
        XCTAssertTrue(calls.contains("readiness")); XCTAssertFalse(calls.contains("purchase"))
        XCTAssertFalse(calls.contains("verify.begin")); XCTAssertNotNil(rig.coordinator.error)
    }
}

private let walletSnapshotJSON = #"{"coin":125,"membership":{"isActive":false,"level":null,"expireAt":null}}"#
func walletRequestBody(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 2048)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
