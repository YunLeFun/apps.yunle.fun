import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationAcquisitionVisualTests: XCTestCase {
    func testPurchaseConditionsUseNativeRows() async throws { try await render(accessibility: false) }
    func testPurchaseConditionsSupportDarkAccessibilityText() async throws { try await render(accessibility: true) }
    private func render(accessibility: Bool) async throws {
        let host = UUID().uuidString.lowercased() + ".acquisition.test"
        let auth = AuthHTTPFixture(replies: [(200, #"{"sub":"alice","name":"样例账号","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: auth); defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState(); state.activeID = "alice"
        state.accounts = [SavedAccount(user: AccountUser(id: "alice"), credential: AccountCredential(accessToken: "visual-only", refreshToken: "not-used", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: config),
            origin: URL(string: "https://\(host)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        XCTAssertEqual(accounts.user?.id, "alice")
        let log = BillingLog(), service = BillingServiceFixture(log: log, verifyFailure: false, accountGate: nil, verifyGate: nil)
        let wallet = WalletStore(accounts: accounts, service: service)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: service,
            commerce: BillingCommerceFixture(log: log, gate: nil, outcome: .cancelled, unfinished: []),
            journal: PurchaseOwnershipJournal(vault: BillingMemoryVault()))
        let acquisition = AcquisitionFixture(), store = ApplicationAcquisitionStore(application: acquisitionApp, accounts: accounts, service: acquisition)
        await store.refresh()
        let content = ApplicationAcquisitionView(store: store, intent: .install) { _ in XCTFail("Rendering must not authorize an acquisition") }
            .environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .preferredColorScheme(accessibility ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try await Task.sleep(nanoseconds: 50_000_000)
        } while (store.quote == nil || controller.view.bounds.isEmpty) && Date() < deadline
        try await Task.sleep(nanoseconds: 200_000_000)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(store.quote?.state, .purchaseRequired)
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = accessibility ? "acquisition-fixture-dark-accessibility" : "acquisition-fixture-light"
        attachment.lifetime = .keepAlways; add(attachment)
        let calls = await acquisition.calls
        XCTAssertTrue(calls.allSatisfy { $0 == nil }, "Only read rights while displaying conditions")
    }
}
