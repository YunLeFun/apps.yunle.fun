import Foundation
import Security
import SwiftUI
import XCTest
@testable import YunleFun

/// The HTTP server runs on the host and uses the existing production database.
/// Only explicitly provisioned, managed synthetic identities are accepted.
@MainActor
final class HomeSyncLiveTests: XCTestCase {
    func testOfflineRestartSyncConflictAndAccountIsolation() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOME_SYNC"] == "1" else {
            throw XCTSkip("Requires the local full-stack server and managed synthetic credentials")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/home-sync-accounts.json")
        let secret = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: secret)
        guard let zero = pool.accounts.first(where: { $0.id == "production-zero-balance" }),
              let standard = pool.accounts.first(where: { $0.id == "production-standard" }),
              zero.environment == "production", zero.username == "ylf_prod_zero",
              standard.environment == "production", standard.username == "ylf_prod_standard"
        else { return XCTFail("Only the approved fixed synthetic accounts may run this test") }

        let directory = cache.appendingPathComponent("HomeSyncLiveValidation-" + UUID().uuidString)
        let service = HomeSyncService(origin: URL(string: "http://127.0.0.1:18746")!)
        let unavailable = HomeSyncService(origin: URL(string: "http://127.0.0.1:1")!)
        let keychainService = "fun.yunle.apps.home-sync-live." + UUID().uuidString
        let vault = KeychainAccountVault(service: keychainService)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService] as CFDictionary) }
        let library = HomeLibrary(directory: directory.appendingPathComponent("first"))
        let accounts = AccountStore(session: AccountSession(vault: vault)) { id in
            library.activateAccount(id); library.setAutoSyncEnabled(false)
        }
        var activeAccounts = accounts
        var baseline: RemoteHomeScreen?
        var owner: String?
        var submitted: [HomeConfiguration] = []
        var restored = false
        var failure: Error?
        var stages: [String] = []
        do {
            try await accounts.passwordSignIn(identifier: zero.username, password: zero.password, captcha: nil)
            let identity = try await accounts.authorization(forceRefresh: false)
            owner = identity.userID
            let before = try await service.load(identity: identity)
            baseline = before
            guard before.configuration.installedApps.count < 995 else { throw LiveFailure.fixtureCapacity }
            try library.adopt(before)
            try JSONEncoder().encode(before).write(to: directory.appendingPathComponent("baseline.json"),
                options: [.atomic, .completeFileProtectionUnlessOpen])
            let catalog = try await CatalogService().applications()
            let app = try XCTUnwrap(catalog.first { $0.marketShortName == "air-conditioner" })
            library.updateCatalog(catalog)
            library.add(app)
            let unresolved = CloudApplication(id: "native-validation-" + UUID().uuidString, name: "待解析应用", isUnavailable: true)
            library.add(unresolved); library.recordUse(app)
            if library.snapshot.configuration.dockApps.count < 4 { library.setPinned(app, true) }
            let offlineContent = library.snapshot.configuration
            let mutation = library.snapshot.mutationId
            let offline = HomeSyncCoordinator(accounts: accounts, library: library, service: unavailable, monitorNetwork: false)
            await offline.synchronize()
            guard case .failed = offline.phase else { throw LiveFailure.offline }
            guard library.snapshot.hasPendingChanges, library.snapshot.mutationId == mutation else { throw LiveFailure.offline }
            stages.append("real unreachable HTTP retains local changes")
            try await snapshot(accounts, library, offline, name: "live-home-offline")

            let reopened = HomeLibrary(directory: directory.appendingPathComponent("first"), accountID: identity.userID)
            let resumedAccounts = AccountStore(session: AccountSession(vault: vault)) { id in
                reopened.activateAccount(id); reopened.setAutoSyncEnabled(false)
            }
            activeAccounts = resumedAccounts
            await resumedAccounts.restore()
            guard resumedAccounts.user?.id == identity.userID, resumedAccounts.notice == nil,
                  reopened.snapshot.mutationId == mutation, reopened.snapshot.hasPendingChanges,
                  reopened.snapshot.configuration == offlineContent,
                  reopened.snapshot.applications.first(where: { $0.id == unresolved.id })?.isUnavailable == true
            else { throw LiveFailure.restart }
            let resumed = HomeSyncCoordinator(accounts: resumedAccounts, library: reopened, service: service, monitorNetwork: false)
            submitted.append(reopened.snapshot.configuration)
            await resumed.synchronize()
            guard resumed.phase == .idle, !reopened.snapshot.hasPendingChanges,
                  reopened.snapshot.base?.revision != before.revision else { throw LiveFailure.upload }
            let authenticated = try await resumedAccounts.authorization(forceRefresh: false)
            let committed = try await service.load(identity: authenticated)
            guard committed.configuration.hasSameContent(as: offlineContent) else { throw LiveFailure.upload }
            stages.append("Keychain and offline home restart then upload")
            try await snapshot(resumedAccounts, reopened, resumed, name: "live-home-synced")

            let other = HomeLibrary(directory: directory.appendingPathComponent("second"), accountID: identity.userID)
            other.setAutoSyncEnabled(false); other.updateCatalog(catalog)
            let otherSync = HomeSyncCoordinator(accounts: resumedAccounts, library: other, service: service, monitorNetwork: false)
            await otherSync.synchronize()
            guard other.snapshot.configuration == committed.configuration else { throw LiveFailure.secondClient }
            let localOnly = CloudApplication(id: "native-local-" + UUID().uuidString, name: "此设备待同步", isUnavailable: true)
            let cloudOnly = CloudApplication(id: "native-cloud-" + UUID().uuidString, name: "另一客户端更新", isUnavailable: true)
            reopened.add(localOnly)
            let localContent = reopened.snapshot.configuration
            other.add(cloudOnly); submitted.append(other.snapshot.configuration)
            await otherSync.synchronize()
            guard otherSync.phase == .idle, !other.snapshot.hasPendingChanges else { throw LiveFailure.secondClient }
            await resumed.synchronize()
            guard case .conflict(let conflict) = resumed.phase,
                  reopened.snapshot.configuration == localContent else { throw LiveFailure.conflict }
            try await snapshot(resumedAccounts, reopened, resumed, name: "live-home-conflict", dark: true, accessibility: true)
            if ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_SYNC_UI_TAP"] == "1" {
                submitted.append(localContent)
                try await interactiveCloudChoice(resumedAccounts, reopened, resumed)
                stages.append("real UI cloud choice and system confirmation")
            } else { await resumed.resolve(.cloud, conflict: conflict) }
            let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("first"),
                includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".conflict-") }
            guard resumed.phase == .idle, !reopened.snapshot.hasPendingChanges, backups.count == 1,
                  reopened.snapshot.containsReference(cloudOnly.id), !reopened.snapshot.containsReference(localOnly.id)
            else { throw LiveFailure.conflict }
            let recovery = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: backups[0]))
            guard recovery.configuration == localContent, recovery.hasPendingChanges else { throw LiveFailure.conflict }
            stages.append("independent local client reads and produces a real cloud conflict")
            stages.append("cloud choice preserves an offline recovery copy")

            try await resumedAccounts.passwordSignIn(identifier: standard.username, password: standard.password, captcha: nil)
            guard resumedAccounts.user?.id != owner, reopened.accountID == resumedAccounts.user?.id,
                  !reopened.snapshot.containsReference(unresolved.id), !reopened.snapshot.containsReference(cloudOnly.id)
            else { throw LiveFailure.isolation }
            _ = try await service.load(identity: resumedAccounts.authorization(forceRefresh: false))
            try await resumedAccounts.select(identity.userID)
            guard reopened.snapshot.containsReference(cloudOnly.id), !reopened.snapshot.containsReference(localOnly.id) else {
                throw LiveFailure.isolation
            }
            stages.append("real account switch hides the previous home and restores its namespace on return")
        } catch { failure = error }

        // Restore content with revision protection. Never overwrite another
        // client's unrelated changes, even on a shared synthetic account.
        do {
            if let baseline, let owner {
                if activeAccounts.user?.id != owner { try await activeAccounts.select(owner) }
                let identity = try await activeAccounts.authorization(forceRefresh: false)
                let current = try await service.load(identity: identity)
                if current.configuration.hasSameContent(as: baseline.configuration) { restored = true }
                else if submitted.contains(where: { $0.hasSameContent(as: current.configuration) }) {
                    let clean = try await service.save(HomeScreenWrite(baseRevision: current.revision,
                        mutationId: UUID().uuidString, configuration: baseline.configuration), identity: identity)
                    restored = clean.configuration.hasSameContent(as: baseline.configuration)
                }
            }
        } catch { if failure == nil { failure = error } }
        for user in activeAccounts.overview.users { try? await activeAccounts.remove(user.id) }
        if restored { try? FileManager.default.removeItem(at: directory) }
        let report: [String: Any] = ["origin": "local HTTP server + existing CloudBase",
            "account": "production-zero-balance", "stages": stages, "restoredCloudContent": restored,
            "realPayments": false, "deviceScope": "one simulator, two independent local clients"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "native-home-sync-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(restored, "If cleanup is interrupted, retain the baseline and do not overwrite unrelated cloud changes")
        if let failure = failure as? LiveFailure { XCTFail("Native sync validation failed at \(failure)") }
        else if let failure { XCTFail("Native sync request failed: \(safeMessage(failure))") }
    }
    private func safeMessage(_ error: Error) -> String {
        if let error = error as? AccountError { return error.localizedDescription }
        if let error = error as? HomeSyncError { return error.localizedDescription }
        return "Response contents omitted"
    }
    private func snapshot(_ accounts: AccountStore, _ library: HomeLibrary, _ sync: HomeSyncCoordinator,
                          name: String, dark: Bool = false, accessibility: Bool = false) async throws {
        let content = NavigationStack { HomeSyncSettingsView() }
            .environmentObject(accounts).environmentObject(library).environmentObject(sync)
            .preferredColorScheme(dark ? .dark : .light)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 300_000_000); controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
        if accessibility, let scroll = scrollView(in: controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(nanoseconds: 150_000_000); controller.view.layoutIfNeeded()
            let bottom = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let options = XCTAttachment(image: bottom); options.name = name + "-options"
            options.lifetime = .keepAlways; add(options)
        }
    }
    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
        for child in view.subviews { if let scroll = scrollView(in: child) { return scroll } }
        return nil
    }
    private func interactiveCloudChoice(_ accounts: AccountStore, _ library: HomeLibrary,
                                        _ sync: HomeSyncCoordinator) async throws {
        let content = NavigationStack { HomeSyncSettingsView() }
            .environmentObject(accounts).environmentObject(library).environmentObject(sync)
            .preferredColorScheme(.light).environment(\.dynamicTypeSize, .large)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.rootViewController = previous; window.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 300_000_000); controller.view.layoutIfNeeded()
        if let scroll = scrollView(in: controller.view) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
        }
        print("YLF_UI_HOME_CONFLICT_READY")
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if sync.phase == .idle && !library.snapshot.hasPendingChanges { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw LiveFailure.conflict
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum LiveFailure: Error { case fixtureCapacity, offline, restart, upload, secondClient, conflict, isolation }
}
private extension HomeLibrarySnapshot {
    func containsReference(_ id: String) -> Bool { configuration.installedApps.contains { $0.appId == id } }
}
