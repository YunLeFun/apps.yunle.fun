import Foundation
import SwiftUI
import XCTest
@testable import YunleFun

/// External simulator UI automation drives the actual detail link, cancellation
/// and confirmation. Authentication and all records are synthetic and local.
@MainActor
final class WebProfileRecoveryLiveTests: XCTestCase {
    func testActualRecoveryControlsCancelThenSwapWithoutLosingEitherStore() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_LIVE_PROFILE_RECOVERY_UI"] == "1" else { throw XCTSkip("Requires explicit isolated recovery UI validation") }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an owned simulator may run the recovery fixture")
        #endif
        guard #available(iOS 17, *), let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty,
              owned == env["SIMULATOR_UDID"] else { return XCTFail("Requires named stores and the exact owned simulator") }
        let largeDark = env["YUNLEFUN_PROFILE_RECOVERY_LARGE_DARK"] == "1"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileRecoveryUI-" + UUID().uuidString)
        let repository = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: "ui-fixture")
        let runtime = NativeWebRuntime(webProfiles: repository)
        let app = CloudApplication(id: "recovery-ui-fixture", name: "应用数据恢复验证", websiteUrl: "https://profile-recovery.invalid/", emoji: "🧪")
        let original = try repository.select(.account("synthetic-a"), application: app)
        try repository.retire("synthetic-a")
        let current = try repository.select(.account("synthetic-a"), application: app)
        var state = AccountVaultState(); state.activeID = "synthetic-a"
        state.accounts = [SavedAccount(user: AccountUser(id: "synthetic-a", name: "本机验证账号"), credential:
            AccountCredential(accessToken: "synthetic-a", refreshToken: "synthetic-a", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: RecoveryUIAuth(), vault: RecoveryUIVault(try JSONEncoder().encode(state))),
                                    identityDidChange: { runtime.resetIdentity(to: $0) })
        await accounts.restore(); runtime.configureAuthorization(accounts: accounts)
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
        library.add(app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow)); let previous = window.rootViewController
        let content = NavigationStack { ApplicationDetailView(application: app) }
            .environmentObject(runtime).environmentObject(accounts).environmentObject(library).environmentObject(catalog)
            .environment(\.dynamicTypeSize, largeDark ? .accessibility5 : .large)
            .preferredColorScheme(largeDark ? .dark : .light)
        let root = UIHostingController(rootView: content)
        window.rootViewController = root; window.makeKeyAndVisible(); runtime.anchor = root
        defer {
            runtime.resetIdentity(); root.dismiss(animated: false)
            window.rootViewController = previous; window.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: directory)
        }
        try await wait(seconds: 10) { root.view.window != nil }
        try await Task.sleep(nanoseconds: 400_000_000)
        attach(window, name: "recovery-detail-entry")
        try await wait(seconds: 45) { self.alert(in: root)?.title == "使用这份数据？" }
        XCTAssertEqual(try repository.snapshot(for: .account("synthetic-a"), application: app).active, current)
        attach(window, name: "recovery-confirmation")
        try await wait(seconds: 20) { self.alert(in: root) == nil }
        XCTAssertEqual(try repository.snapshot(for: .account("synthetic-a"), application: app), .init(active: current, retained: [original]),
                       "The first confirmation must be cancelled without changing assignments")
        attach(window, name: "recovery-cancelled")
        try await wait(seconds: 45) {
            try repository.snapshot(for: .account("synthetic-a"), application: app).active == original
        }
        XCTAssertEqual(try repository.snapshot(for: .account("synthetic-a"), application: app), .init(active: original, retained: [current]))
        try await Task.sleep(nanoseconds: 400_000_000)
        attach(window, name: "recovery-completed")
        let report: [String: Any] = ["actualDetailNavigationUsed": true, "firstConfirmationCancelled": true,
            "confirmedStoreActive": true, "displacedStoreRetained": true, "realAccountsOrNetworkUsed": false,
            "swiftUIEnvironment": largeDark ? "accessibility5-dark" : "large-light", "systemSettingsChanged": false,
            "scope": "Actual SwiftUI detail and recovery controls driven through simulator UI; local synthetic account and metadata"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "profile-recovery-ui-report"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func alert(in root: UIViewController) -> UIAlertController? {
        if let alert = root as? UIAlertController { return alert }
        if let next = root.presentedViewController, let alert = alert(in: next) { return alert }
        return root.children.compactMap { alert(in: $0) }.first
    }
    private func wait(seconds: TimeInterval, condition: () throws -> Bool) async throws {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "ProfileRecoveryUI", code: 1)
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private final class RecoveryUIVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    init(_ data: Data) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
}
private struct RecoveryUIAuth: AccountAuthenticating {
    func user(accessToken: String, deviceID: String) async throws -> AccountUser { AccountUser(id: accessToken, name: "本机验证账号") }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw AccountError.invalidResponse }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.invalidResponse }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse { throw AccountError.invalidResponse }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse { throw AccountError.invalidResponse }
    func signOut(accessToken: String, deviceID: String) async throws { throw AccountError.invalidResponse }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { throw AccountError.invalidResponse }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.invalidResponse }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.invalidResponse }
}
