import XCTest
@testable import YunleFun

final class ApplicationAcquisitionServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }
    func testPurchaseOnlySendsCanonicalIDAndExpectedPrice() async throws {
        let (service, fixture) = service([(200, acquisitionJSON())])
        _ = try await service.resolve(appID: "paid-app", expectedCoinCost: 10, identity: .init(userID: "alice", accessToken: "fixture-only"))
        let request = try XCTUnwrap(fixture.requests.first)
        let fields = try JSONSerialization.jsonObject(with: walletRequestBody(request)) as! [String: Any]
        XCTAssertEqual(request.url?.path, "/api/apps/acquisition")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
        XCTAssertEqual(Set(fields.keys), ["appId", "action", "expectedCoinCost"])
        XCTAssertEqual(fields["expectedCoinCost"] as? Int, 10)
        XCTAssertEqual(fields["action"] as? String, "purchase")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
    func testInspectionCannotSpendCoins() async throws {
        let (service, fixture) = service([(200, acquisitionJSON(state: "purchase_required", reason: "purchase"))])
        _ = try await service.resolve(appID: "paid-app", expectedCoinCost: nil, identity: .init(userID: "alice", accessToken: "fixture-only"))
        let fields = try JSONSerialization.jsonObject(with: walletRequestBody(fixture.requests[0])) as! [String: Any]
        XCTAssertEqual(fields["action"] as? String, "check")
        XCTAssertNil(fields["expectedCoinCost"])
    }
    func testRejectsForeignIdentityMetadataAndBypassedInvitation() async throws {
        for payload in [
            acquisitionJSON(uid: "bob"), acquisitionJSON(appID: "other"), acquisitionJSON(cost: -1),
            acquisitionJSON(mode: "invite_only"), acquisitionJSON(state: "allowed", reason: "free")
        ] {
            let (service, _) = service([(200, payload)])
            do { _ = try await service.resolve(appID: "paid-app", expectedCoinCost: nil, identity: .init(userID: "alice", accessToken: "fixture-only")); XCTFail("Reject invalid entitlement") }
            catch { XCTAssertEqual(error as? ApplicationAcquisitionError, .invalidResponse) }
        }
    }
    func testPriceConflictAndMissingAccountAreNotOwnedRights() async throws {
        for (status, expected) in [(401, ApplicationAcquisitionError.unauthorized), (403, .forbidden), (404, .notFound), (409, .conflict), (503, .unavailable)] {
            let (service, _) = service([(status, "{}")])
            do { _ = try await service.resolve(appID: "paid-app", expectedCoinCost: nil, identity: .init(userID: "alice", accessToken: "fixture-only")); XCTFail("Reject HTTP failure") }
            catch { XCTAssertEqual(error as? ApplicationAcquisitionError, expected) }
        }
    }
    private func service(_ replies: [(Int, String)]) -> (ApplicationAcquisitionService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".acquisition.test"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (ApplicationAcquisitionService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
}
@MainActor
final class ApplicationAcquisitionStoreTests: XCTestCase {
    func testOldConfirmationCannotSpendAfterAccountSwitchOrABA() async throws {
        for aba in [false, true] {
            let accounts = BillingAccounts(), service = AcquisitionFixture()
            let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
            await store.refresh()
            let confirmation = try XCTUnwrap(store.confirmation)
            accounts.select("bob"); if aba { accounts.select("alice") }
            XCTAssertNil(store.quote); XCTAssertNil(store.confirmation)
            let permit = await store.purchase(confirmation)
            XCTAssertNil(permit)
            let calls = await service.calls; XCTAssertEqual(calls, [nil])
        }
    }
    func testSwitchDuringPurchaseCannotReturnALaunchOrInstallPermit() async throws {
        let accounts = BillingAccounts(), gate = BillingGate(), service = AcquisitionFixture(purchaseGate: gate)
        let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
        await store.refresh()
        let confirmation = try XCTUnwrap(store.confirmation)
        let task = Task { await store.purchase(confirmation) }
        await fulfillment(of: [gate.entered], timeout: 2)
        accounts.select("bob"); accounts.select("alice")
        await gate.open()
        let permit = await task.value
        XCTAssertNil(permit); XCTAssertNil(store.quote)
    }
    func testSuccessfulPurchaseProducesOnlyAnEphemeralAccountBoundPermit() async throws {
        let accounts = BillingAccounts(), service = AcquisitionFixture()
        let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
        await store.refresh()
        let confirmation = try XCTUnwrap(store.confirmation)
        let permit = await store.purchase(confirmation)
        XCTAssertEqual(permit?.application.id, acquisitionApp.id)
        XCTAssertEqual(permit?.boundary, .init(uid: "alice", generation: accounts.identityGeneration))
        let calls = await service.calls; XCTAssertEqual(calls, [nil, 10])
        XCTAssertNil(store.confirmation)
    }
    func testConcurrentConfirmationDoesNotStartTwoPurchases() async throws {
        let accounts = BillingAccounts(), gate = BillingGate(), service = AcquisitionFixture(purchaseGate: gate)
        let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
        await store.refresh()
        let confirmation = try XCTUnwrap(store.confirmation)
        let task = Task { await store.purchase(confirmation) }
        await fulfillment(of: [gate.entered], timeout: 2)
        let duplicate = await store.purchase(confirmation); XCTAssertNil(duplicate)
        await gate.open(); _ = await task.value
        let calls = await service.calls; XCTAssertEqual(calls, [nil, 10])
    }
    func testGuestNeverCallsTheAccountService() async {
        let accounts = BillingAccounts(), service = AcquisitionFixture(); accounts.select(nil)
        let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
        let permit = await store.refresh(); XCTAssertNil(permit)
        let calls = await service.calls; XCTAssertTrue(calls.isEmpty)
    }
    func testInsufficientBalanceCannotCreateAPaymentConfirmation() async {
        let accounts = BillingAccounts(), service = AcquisitionFixture(balance: 1)
        let store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: service)
        await store.refresh(); XCTAssertEqual(store.quote?.state, .purchaseRequired)
        XCTAssertNil(store.confirmation)
    }
}
let acquisitionApp = CloudApplication(id: "paid-app", name: "示例应用", websiteUrl: "https://example.com", accessMode: "public", coinCost: 10)
func acquisitionJSON(uid: String = "alice", appID: String = "paid-app", state: String = "allowed", reason: String = "purchased", cost: Int = 10, mode: String = "public") -> String {
    #"{"userId":"UID","application":{"_id":"APP","name":"示例应用","websiteUrl":"https://example.com","accessMode":"MODE","coinCost":COST},"state":"STATE","reason":"REASON","coinCost":COST,"balance":90}"#
        .replacingOccurrences(of: "UID", with: uid).replacingOccurrences(of: "APP", with: appID)
        .replacingOccurrences(of: "MODE", with: mode).replacingOccurrences(of: "COST", with: String(cost))
        .replacingOccurrences(of: "STATE", with: state).replacingOccurrences(of: "REASON", with: reason)
}
actor AcquisitionFixture: ApplicationAcquisitionServing {
    private(set) var calls: [Int?] = []
    let purchaseGate: BillingGate?
    let balance: Int64
    init(purchaseGate: BillingGate? = nil, balance: Int64 = 100) { self.purchaseGate = purchaseGate; self.balance = balance }
    func resolve(appID: String, expectedCoinCost: Int?, identity: AuthorizedAccount) async throws -> ApplicationAcquisitionQuote {
        calls.append(expectedCoinCost)
        if expectedCoinCost != nil, let purchaseGate { await purchaseGate.wait() }
        return ApplicationAcquisitionQuote(userId: identity.userID, application: acquisitionApp,
            state: expectedCoinCost == nil ? .purchaseRequired : .allowed, reason: expectedCoinCost == nil ? "purchase" : "purchased", coinCost: 10, balance: balance)
    }
}
