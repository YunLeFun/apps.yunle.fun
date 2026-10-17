import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class WalletVisualFixtureTests: XCTestCase {
    func testWalletUsesNativeRowsInLightMode() async throws { try await render(membership: false) }
    func testMembershipAtAccessibilitySizeInDarkMode() async throws { try await render(membership: true) }
    private func render(membership: Bool) async throws {
        let host = UUID().uuidString.lowercased() + ".wallet.test"
        let auth = AuthHTTPFixture(replies: [(200, #"{"sub":"alice","name":"样例账号","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: auth); defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState()
        state.activeID = "alice"
        state.accounts = [SavedAccount(user: AccountUser(id: "alice"), credential: AccountCredential(accessToken: "visual-only", refreshToken: "not-used", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: config),
            origin: URL(string: "https://\(host)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        let log = BillingLog(), service = BillingServiceFixture(log: log, verifyFailure: false, accountGate: nil, verifyGate: nil)
        let wallet = WalletStore(accounts: accounts, service: service)
        let commerce = BillingCommerceFixture(log: log, gate: nil, outcome: .cancelled, unfinished: [])
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: service, commerce: commerce,
            journal: PurchaseOwnershipJournal(vault: BillingMemoryVault()))
        await wallet.refresh(); await purchases.loadProducts()
        let content = NavigationStack {
            Group { if membership { MembershipView() } else { WalletView() } }
        }
        .environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
        .environment(\.dynamicTypeSize, membership ? .accessibility3 : .large)
        .preferredColorScheme(membership ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = membership ? "membership-fixture-dark-accessibility" : "wallet-fixture-light"
        attachment.lifetime = .keepAlways; add(attachment)
        let operations = await log.values
        XCTAssertFalse(operations.contains("purchase")); XCTAssertFalse(operations.contains("verify.begin"))
    }
}
