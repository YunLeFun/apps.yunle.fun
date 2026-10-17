import Foundation
import Security
import SwiftUI
import XCTest
@testable import YunleFun

/// The local server or approved preview uses the existing production database.
/// Only explicitly provisioned, managed synthetic identities are accepted.
@MainActor
final class HomeSyncLiveTests: XCTestCase {
    /// Run serially as publish(A), receive(B), returnAndRestore(A). Each input
    /// is private, consumed once, and bound to a different owned simulator.
    /// Keep the baseline and planned writes if any stage fails; recovery must
    /// provide the exact current revision rather than overwrite a third party.
    func testCrossSimulatorSourceRoundtripStage() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOME_CROSS_SIMULATOR"] == "1",
              let simulatorID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] else {
            throw XCTSkip("Requires an explicitly provisioned owned simulator and a managed synthetic account")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let inputURL = cache.appendingPathComponent("iOSNativeValidation/home-cross-simulator.json")
        let data = try Data(contentsOf: inputURL)
        try FileManager.default.removeItem(at: inputURL)
        let input = try JSONDecoder().decode(CrossSimulatorInput.self, from: data)
        guard UUID(uuidString: input.runID) != nil, input.simulatorID == simulatorID,
              input.account.id == "production-zero-balance", input.account.environment == "production",
              input.account.username == "ylf_prod_zero", !input.account.password.isEmpty
        else { return XCTFail("Only the explicitly provisioned simulator and approved synthetic identity may run") }
        let directory = cache.appendingPathComponent("HomeCrossSimulator-" + input.runID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baselineURL = directory.appendingPathComponent("baseline.json")
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let keychainService = "fun.yunle.apps.home-cross-simulator." + UUID().uuidString
        let vault = KeychainAccountVault(service: keychainService)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService] as CFDictionary) }
        let accounts = AccountStore(session: AccountSession(vault: vault)) { id in
            library.activateAccount(id); library.setAutoSyncEnabled(false)
        }
        let service = HomeSyncService(origin: URL(string: "http://127.0.0.1:18746")!)
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, service: service, monitorNetwork: false)
        var receipt = CrossSimulatorReceipt(phase: input.phase, simulatorID: simulatorID)
        var failure: Error?
        do {
            try await accounts.passwordSignIn(identifier: input.account.username, password: input.account.password, captcha: nil)
            let identity = try await accounts.authorization(forceRefresh: false)
            let current = try await service.load(identity: identity)
            receipt.remote = current
            guard current.schemaVersion == 3 else { throw LiveFailure.target }
            if input.phase != .publish {
                guard let expected = input.expected, expected == current else { throw LiveFailure.conflict }
            }
            if input.phase == .recover {
                receipt.remote = try await restoreCrossSimulatorBaseline(baselineURL, current: current, service: service, identity: identity)
                receipt.restoredCloudContent = true
            } else {
                let catalog = try await CatalogService().applications()
                let market = try XCTUnwrap(catalog.first { $0.marketShortName == "air-conditioner" })
                switch input.phase {
                case .publish:
                    guard input.expected == nil, !FileManager.default.fileExists(atPath: baselineURL.path),
                          current.configuration.installedApps.count < 990, current.configuration.folders.count < 199
                    else { throw LiveFailure.fixtureCapacity }
                    try JSONEncoder().encode(current).write(to: baselineURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                    try library.adopt(current)
                    let profile = try await DeveloperProfileService().profile(login: "YunYouJun")
                    let author = try XCTUnwrap(profile.items.first { $0.id == market.id && $0.canOpenAsGuest })
                    library.add(author)
                    let marker = CloudApplication(id: "cross-simulator-" + input.runID, name: "跨模拟器验证", isUnavailable: true)
                    library.add(marker)
                    _ = try XCTUnwrap(library.createFolder(named: "跨模拟器验证", with: [author.id, marker.id], at: author.id))
                    guard library.snapshot.configuration.applicationSources.contains(.init(appId: author.id, ownerLogin: "YunYouJun"))
                    else { throw LiveFailure.upload }
                case .receive:
                    guard library.snapshot.configuration.installedApps.isEmpty, !library.snapshot.hasPendingChanges else { throw LiveFailure.secondClient }
                    await sync.synchronize()
                    guard sync.phase == .idle, library.snapshot.configuration == current.configuration else { throw LiveFailure.secondClient }
                    let received = try XCTUnwrap(library.snapshot.applications.first { $0.id == market.id })
                    let resolved = try await PersonalMarketLaunchAuthorization().resolve(received)
                    guard resolved.personalMarketOwnerLogin == "YunYouJun", resolved.canOpenAsGuest,
                          resolved.homeReference == received.homeReference,
                          !library.snapshot.configuration.folders.isEmpty else { throw LiveFailure.secondClient }
                    library.add(market)
                    guard !library.snapshot.configuration.applicationSources.contains(where: { $0.appId == market.id }),
                          library.snapshot.configuration.folders == current.configuration.folders else { throw LiveFailure.secondClient }
                case .returnAndRestore:
                    guard library.snapshot.configuration.applicationSources.contains(.init(appId: market.id, ownerLogin: "YunYouJun")),
                          !library.snapshot.hasPendingChanges else { throw LiveFailure.restart }
                    await sync.synchronize()
                    guard sync.phase == .idle, library.snapshot.configuration == current.configuration,
                          !library.snapshot.configuration.applicationSources.contains(where: { $0.appId == market.id }),
                          library.snapshot.applications.first(where: { $0.id == market.id })?.personalMarketOwnerLogin == nil
                    else { throw LiveFailure.secondClient }
                    try await snapshot(accounts, library, sync, name: "cross-simulator-returned-market")
                    receipt.remote = try await restoreCrossSimulatorBaseline(baselineURL, current: current, service: service, identity: identity)
                    receipt.restoredCloudContent = true
                case .recover:
                    throw LiveFailure.target
                }
                if input.phase == .publish || input.phase == .receive {
                    let planned = library.snapshot.configuration
                    try JSONEncoder().encode(planned).write(to: directory.appendingPathComponent("planned-\(input.phase.rawValue).json"),
                        options: [.atomic, .completeFileProtectionUnlessOpen])
                    await sync.synchronize()
                    let committed = try await service.load(identity: identity)
                    receipt.remote = committed
                    guard sync.phase == .idle, !library.snapshot.hasPendingChanges,
                          committed.configuration.hasSameContent(as: planned), committed.revision != current.revision else { throw LiveFailure.upload }
                }
            }
            receipt.passed = true
        } catch { failure = error }
        do {
            for user in accounts.overview.users {
                try await accounts.remove(user.id)
                guard accounts.notice == nil else { throw LiveFailure.signout }
            }
            receipt.signedOut = accounts.overview.users.isEmpty
        } catch { if failure == nil { failure = error } }
        let report = try JSONEncoder().encode(receipt)
        try report.write(to: directory.appendingPathComponent("receipt-\(input.phase.rawValue).json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "native-home-cross-simulator-" + input.phase.rawValue; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(receipt.signedOut)
        if let failure = failure as? LiveFailure { XCTFail("Cross-simulator validation failed at \(failure)") }
        else if let failure { XCTFail("Cross-simulator request failed: \(safeMessage(failure))") }
    }

    private func restoreCrossSimulatorBaseline(_ url: URL, current: RemoteHomeScreen,
                                               service: HomeSyncService, identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        let baseline = try JSONDecoder().decode(RemoteHomeScreen.self, from: Data(contentsOf: url))
        _ = try await service.save(HomeScreenWrite(baseRevision: current.revision, mutationId: UUID().uuidString,
            configuration: baseline.configuration), identity: identity)
        let restored = try await service.load(identity: identity)
        guard restored.configuration.hasSameContent(as: baseline.configuration) else { throw LiveFailure.backup }
        return restored
    }

    private enum CrossSimulatorPhase: String, Codable { case publish, receive, returnAndRestore, recover }
    private struct CrossSimulatorInput: Decodable {
        let runID: String
        let simulatorID: String
        let phase: CrossSimulatorPhase
        let account: Credential
        let expected: RemoteHomeScreen?
    }
    private struct CrossSimulatorReceipt: Codable {
        let phase: CrossSimulatorPhase
        let simulatorID: String
        var passed = false
        var signedOut = false
        var restoredCloudContent = false
        var remote: RemoteHomeScreen?
    }

    func testAccountBackupRestoreSyncConflictAndUndo() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOME_BACKUP"] == "1" else {
            throw XCTSkip("Requires managed synthetic accounts and an explicitly enabled real backup/sync validation")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/home-backup-accounts.json")
        let secret = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: secret)
        guard let zero = pool.accounts.first(where: { $0.id == "production-zero-balance" }),
              let standard = pool.accounts.first(where: { $0.id == "production-standard" }),
              zero.environment == "production", zero.username == "ylf_prod_zero",
              standard.environment == "production", standard.username == "ylf_prod_standard"
        else { return XCTFail("Only the approved fixed synthetic accounts may run this test") }

        let directory = cache.appendingPathComponent("HomeBackupLiveValidation-" + UUID().uuidString)
        let homeDirectory = directory.appendingPathComponent("home")
        let origin = try pool.target?.validatedOrigin() ?? URL(string: "http://127.0.0.1:18746")!
        let previewSession = try pool.target?.makeSession()
        defer { previewSession?.invalidateAndCancel() }
        let service = HomeSyncService(session: previewSession, origin: origin)
        let keychainService = "fun.yunle.apps.home-backup-live." + UUID().uuidString
        let vault = KeychainAccountVault(service: keychainService)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService] as CFDictionary) }
        let library = HomeLibrary(directory: homeDirectory)
        let accounts = AccountStore(session: AccountSession(vault: vault)) { id in
            library.activateAccount(id); library.setAutoSyncEnabled(false)
        }
        var activeAccounts = accounts
        var baseline: RemoteHomeScreen?, standardBaseline: RemoteHomeScreen?
        var owner: String?, standardOwner: String?
        var submitted: [HomeConfiguration] = []
        var cloudRestored = false, standardUnchanged = false, signedOut = false
        var failure: Error?
        var stages: [String] = []
        do {
            try await accounts.passwordSignIn(identifier: zero.username, password: zero.password, captcha: nil)
            let identity = try await accounts.authorization(forceRefresh: false); owner = identity.userID
            let before = try await service.load(identity: identity); baseline = before
            guard before.configuration.installedApps.count < 990 else { throw LiveFailure.fixtureCapacity }
            try library.adopt(before)
            try JSONEncoder().encode(before).write(to: directory.appendingPathComponent("baseline.json"),
                options: [.atomic, .completeFileProtectionUnlessOpen])
            let catalog = try await CatalogService().applications()
            let app = try XCTUnwrap(catalog.first { $0.marketShortName == "air-conditioner" })
            library.add(app)
            let unknown = CloudApplication(id: "backup-live-" + UUID().uuidString, name: "待解析的备份应用", isUnavailable: true)
            library.add(unknown); library.recordUse(app); library.setDockVisible(true)
            if library.snapshot.configuration.dockApps.count < 4 { library.setPinned(app, true) }
            let candidate = library.snapshot
            let backup = library.fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
            try JSONEncoder().encode(candidate).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen])
            let sync = HomeSyncCoordinator(accounts: accounts, library: library, service: service, monitorNetwork: false)
            submitted.append(library.snapshot.configuration); await sync.synchronize()
            guard sync.phase == .idle, !library.snapshot.hasPendingChanges else { throw LiveFailure.upload }
            library.add(CloudApplication(id: "after-backup-" + UUID().uuidString, name: "备份后的编辑", isUnavailable: true))
            library.setDockVisible(false)
            submitted.append(library.snapshot.configuration); await sync.synchronize()
            guard sync.phase == .idle, !library.snapshot.hasPendingChanges else { throw LiveFailure.upload }
            let latest = try await service.load(identity: identity)
            guard latest.configuration == library.snapshot.configuration, latest.revision != candidate.base?.revision else { throw LiveFailure.backup }
            let store = HomeBackupStore(library: library, accounts: accounts)
            await store.load(); await store.select(backup.lastPathComponent)
            let stale = try XCTUnwrap(store.confirmation(restoreSettings: true))

            try await accounts.passwordSignIn(identifier: standard.username, password: standard.password, captcha: nil)
            standardOwner = accounts.user?.id
            standardBaseline = try await service.load(identity: accounts.authorization(forceRefresh: false))
            try JSONEncoder().encode(standardBaseline).write(to: directory.appendingPathComponent("standard-baseline.json"),
                options: [.atomic, .completeFileProtectionUnlessOpen])
            guard standardOwner != owner, store.visibleItems.isEmpty, store.visiblePreview == nil else { throw LiveFailure.isolation }
            let otherAccountStore = HomeBackupStore(library: library, accounts: accounts)
            await otherAccountStore.load()
            guard otherAccountStore.visibleItems.isEmpty else { throw LiveFailure.isolation }
            try await accounts.select(identity.userID)
            await store.restore(stale)
            guard store.error == HomeBackupError.identityChanged.localizedDescription,
                  library.snapshot.configuration == latest.configuration else { throw LiveFailure.isolation }
            stages.append("real account A-B-A hides backups and rejects the earlier confirmation")

            let current = library.snapshot
            let restoreStore = HomeBackupStore(library: library, accounts: accounts)
            await restoreStore.select(backup.lastPathComponent)
            if ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_BACKUP_UI_TAP"] == "1" {
                try await interactiveBackupRestore(restoreStore, backupID: backup.lastPathComponent)
                stages.append("real account native detail and system confirmation clicked")
            } else {
                await restoreStore.restore(try XCTUnwrap(restoreStore.confirmation(restoreSettings: true)))
            }
            guard restoreStore.didRestore, restoreStore.error == nil,
                  library.snapshot.configuration == candidate.configuration,
                  library.snapshot.base == current.base, library.snapshot.base?.revision == latest.revision,
                  library.snapshot.mutationId != current.mutationId, library.snapshot.hasPendingChanges,
                  library.snapshot.dockVisible, library.snapshot.containsReference(unknown.id)
            else { throw LiveFailure.backup }
            let receipt = try XCTUnwrap(library.snapshot.lastRestoreID)
            let undo = library.fileURL.deletingPathExtension().appendingPathExtension("before-restore-\(receipt).json")
            let savedCurrent = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: undo))
            guard savedCurrent == current else { throw LiveFailure.backup }
            stages.append("old backup restores layout/settings while keeping latest cloud revision and current safety copy")

            let reopened = HomeLibrary(directory: homeDirectory, accountID: identity.userID)
            let resumedAccounts = AccountStore(session: AccountSession(vault: vault)) { id in
                reopened.activateAccount(id); reopened.setAutoSyncEnabled(false)
            }
            activeAccounts = resumedAccounts
            await resumedAccounts.restore()
            guard resumedAccounts.user?.id == owner, resumedAccounts.notice == nil,
                  reopened.snapshot == library.snapshot else { throw LiveFailure.restart }
            let resumed = HomeSyncCoordinator(accounts: resumedAccounts, library: reopened, service: service, monitorNetwork: false)
            submitted.append(reopened.snapshot.configuration); await resumed.synchronize()
            let restoredRemote = try await service.load(identity: resumedAccounts.authorization(forceRefresh: false))
            guard resumed.phase == .idle, !reopened.snapshot.hasPendingChanges,
                  restoredRemote.configuration.hasSameContent(as: candidate.configuration),
                  restoredRemote.revision != latest.revision, reopened.snapshot.lastRestoreID == receipt else { throw LiveFailure.upload }
            stages.append("Keychain and disk object restart retains restore receipt and uploads against current revision")

            let peer = HomeLibrary(directory: directory.appendingPathComponent("peer"), accountID: identity.userID)
            peer.setAutoSyncEnabled(false); try peer.adopt(restoredRemote)
            peer.add(CloudApplication(id: "peer-backup-live-" + UUID().uuidString, name: "另一客户端的编辑", isUnavailable: true))
            let peerSync = HomeSyncCoordinator(accounts: resumedAccounts, library: peer, service: service, monitorNetwork: false)
            submitted.append(peer.snapshot.configuration); await peerSync.synchronize()
            guard peerSync.phase == .idle, !peer.snapshot.hasPendingChanges else { throw LiveFailure.secondClient }
            let peerRemote = try await service.load(identity: resumedAccounts.authorization(forceRefresh: false))
            let undoStore = HomeBackupStore(library: reopened, accounts: resumedAccounts)
            await undoStore.select(undo.lastPathComponent)
            await undoStore.restore(try XCTUnwrap(undoStore.confirmation(restoreSettings: false)))
            guard undoStore.didRestore, reopened.snapshot.configuration == savedCurrent.configuration,
                  reopened.snapshot.base?.revision == restoredRemote.revision else { throw LiveFailure.backup }
            await resumed.synchronize()
            guard case .conflict(let conflict) = resumed.phase,
                  conflict.remote == peerRemote, reopened.snapshot.configuration == savedCurrent.configuration else { throw LiveFailure.conflict }
            let stillPeer = try await service.load(identity: resumedAccounts.authorization(forceRefresh: false))
            guard stillPeer == peerRemote else { throw LiveFailure.conflict }
            try await snapshot(resumedAccounts, reopened, resumed, name: "live-backup-newer-cloud-conflict", dark: true, accessibility: true)
            await resumed.resolve(.cloud, conflict: conflict)
            guard resumed.phase == .idle, reopened.snapshot.configuration == peerRemote.configuration else { throw LiveFailure.conflict }
            let recoveryItems = try await HomeBackupRepository(directory: homeDirectory).list(ownerFileName: reopened.fileURL.lastPathComponent)
            var preservedLocal = false
            for item in recoveryItems where item.kind == .conflict && item.id != backup.lastPathComponent {
                let value = try await HomeBackupRepository(directory: homeDirectory).preview(id: item.id, ownerFileName: reopened.fileURL.lastPathComponent)
                if value.snapshot.configuration == savedCurrent.configuration && value.snapshot.hasPendingChanges { preservedLocal = true }
            }
            guard preservedLocal else { throw LiveFailure.backup }
            stages.append("restoring safety copy meets newer real cloud revision: conflict preserves both choices")
        } catch { failure = error }

        // Every changed cloud configuration is recorded before submitting. A
        // third party's intervening content is never replaced by cleanup.
        do {
            if let baseline, let owner {
                if activeAccounts.user?.id != owner { try await activeAccounts.select(owner) }
                let identity = try await activeAccounts.authorization(forceRefresh: false)
                let current = try await service.load(identity: identity)
                if current.configuration.hasSameContent(as: baseline.configuration) { cloudRestored = true }
                else if submitted.contains(where: { $0.hasSameContent(as: current.configuration) }) {
                    _ = try await service.save(HomeScreenWrite(baseRevision: current.revision,
                        mutationId: UUID().uuidString, configuration: baseline.configuration), identity: identity)
                    let verified = try await service.load(identity: identity)
                    cloudRestored = verified.configuration.hasSameContent(as: baseline.configuration)
                }
            }
            if let standardBaseline, let standardOwner {
                try await activeAccounts.select(standardOwner)
                let verified = try await service.load(identity: activeAccounts.authorization(forceRefresh: false))
                standardUnchanged = verified == standardBaseline
            }
        } catch { if failure == nil { failure = error } }
        do {
            for user in activeAccounts.overview.users {
                try await activeAccounts.remove(user.id)
                guard activeAccounts.notice == nil else { throw LiveFailure.signout }
            }
            signedOut = activeAccounts.overview.users.isEmpty
        } catch { if failure == nil { failure = error } }
        if cloudRestored && standardUnchanged && signedOut { try FileManager.default.removeItem(at: directory) }
        let report: [String: Any] = ["origin": origin.absoluteString, "account": "production-zero-balance", "stages": stages,
            "restoredCloudContent": cloudRestored, "standardAccountUnchanged": standardUnchanged, "signedOut": signedOut,
            "fixtureRemoved": !FileManager.default.fileExists(atPath: directory.path), "realPayments": false,
            "deviceScope": "one simulator; Keychain/disk object restart and an independent local client"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "native-home-backup-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(cloudRestored); XCTAssertTrue(standardUnchanged); XCTAssertTrue(signedOut)
        if let failure = failure as? LiveFailure { XCTFail("Native backup validation failed at \(failure)") }
        else if let failure { XCTFail("Native backup request failed: \(safeMessage(failure))") }
    }

    private func interactiveBackupRestore(_ store: HomeBackupStore, backupID: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let controller = UIHostingController(rootView: NavigationStack { HomeBackupDetailView(store: store, backupID: backupID) })
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.rootViewController = previous; window.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 300_000_000); controller.view.layoutIfNeeded()
        print("YLF_UI_HOME_BACKUP_READY")
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if store.didRestore {
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.name = "live-backup-native-restored"; attachment.lifetime = .keepAlways; add(attachment)
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw LiveFailure.backup
    }

    func testOfflineRestartSyncConflictAndAccountIsolation() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOME_SYNC"] == "1" else {
            throw XCTSkip("Requires a full-stack server or approved preview and managed synthetic credentials")
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
        let serviceOrigin = try pool.target?.validatedOrigin() ?? URL(string: "http://127.0.0.1:18746")!
        let previewSession = try pool.target?.makeSession()
        defer { previewSession?.invalidateAndCancel() }
        let service = HomeSyncService(session: previewSession, origin: serviceOrigin)
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
        var signedOut = false
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
            let author = try await DeveloperProfileService().profile(login: "YunYouJun")
            let authorApp = try XCTUnwrap(author.items.first { $0.id == app.id && $0.canOpenAsGuest })
            library.add(authorApp)
            let folderID = try XCTUnwrap(library.createFolder(named: "同步验证", with: [app.id, unresolved.id], at: app.id))
            guard library.snapshot.configuration.applicationSources.contains(.init(appId: app.id, ownerLogin: "YunYouJun")),
                  library.snapshot.configuration.folders.contains(where: { $0.id == folderID && $0.appIds == [app.id, unresolved.id] })
            else { throw LiveFailure.upload }
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
            let receivedAuthor = try XCTUnwrap(other.snapshot.applications.first { $0.id == app.id })
            guard receivedAuthor.personalMarketOwnerLogin == "YunYouJun" else { throw LiveFailure.secondClient }
            let resolvedAuthor = try await PersonalMarketLaunchAuthorization().resolve(receivedAuthor)
            guard resolvedAuthor.id == app.id, resolvedAuthor.personalMarketOwnerLogin == "YunYouJun",
                  resolvedAuthor.canOpenAsGuest, resolvedAuthor.homeReference == receivedAuthor.homeReference
            else { throw LiveFailure.secondClient }
            stages.append("schema 3 author source and nonempty folder persist offline and roundtrip; receiver resolves current public author release")
            let localOnly = CloudApplication(id: "native-local-" + UUID().uuidString, name: "此设备待同步", isUnavailable: true)
            let cloudOnly = CloudApplication(id: "native-cloud-" + UUID().uuidString, name: "另一客户端更新", isUnavailable: true)
            reopened.add(localOnly)
            let localContent = reopened.snapshot.configuration
            other.add(app)
            guard !other.snapshot.configuration.applicationSources.contains(where: { $0.appId == app.id }) else { throw LiveFailure.secondClient }
            other.add(cloudOnly); submitted.append(other.snapshot.configuration)
            await otherSync.synchronize()
            guard otherSync.phase == .idle, !other.snapshot.hasPendingChanges else { throw LiveFailure.secondClient }
            await resumed.synchronize()
            guard case .conflict(let conflict) = resumed.phase,
                  reopened.snapshot.configuration == localContent,
                  localContent.applicationSources.contains(.init(appId: app.id, ownerLogin: "YunYouJun")),
                  !conflict.remote.configuration.applicationSources.contains(where: { $0.appId == app.id })
            else { throw LiveFailure.conflict }
            try await snapshot(resumedAccounts, reopened, resumed, name: "live-home-conflict", dark: true, accessibility: true)
            if ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_SYNC_UI_TAP"] == "1" {
                submitted.append(localContent)
                try await interactiveCloudChoice(resumedAccounts, reopened, resumed)
                stages.append("real UI cloud choice and system confirmation")
            } else { await resumed.resolve(.cloud, conflict: conflict) }
            let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("first"),
                includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".conflict-") }
            guard resumed.phase == .idle, !reopened.snapshot.hasPendingChanges, backups.count == 1,
                  reopened.snapshot.containsReference(cloudOnly.id), !reopened.snapshot.containsReference(localOnly.id),
                  !reopened.snapshot.configuration.applicationSources.contains(where: { $0.appId == app.id }),
                  reopened.snapshot.applications.first(where: { $0.id == app.id })?.personalMarketOwnerLogin == nil,
                  reopened.snapshot.configuration.folders.contains(where: { $0.id == folderID })
            else { throw LiveFailure.conflict }
            let recovery = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: backups[0]))
            guard recovery.configuration == localContent, recovery.hasPendingChanges else { throw LiveFailure.conflict }
            stages.append("independent local client reads and produces a real cloud conflict")
            stages.append("cloud choice preserves an offline recovery copy")
            stages.append("market source choice conflicts with local author source; cloud adoption clears author metadata and preserves folder")

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
        do {
            for user in activeAccounts.overview.users {
                try await activeAccounts.remove(user.id)
                guard activeAccounts.notice == nil else { throw LiveFailure.signout }
            }
            signedOut = activeAccounts.overview.users.isEmpty
        } catch { if failure == nil { failure = error } }
        if restored && signedOut { try? FileManager.default.removeItem(at: directory) }
        let report: [String: Any] = ["origin": serviceOrigin.absoluteString,
            "account": "production-zero-balance", "stages": stages, "restoredCloudContent": restored, "signedOut": signedOut,
            "fixtureRemoved": !FileManager.default.fileExists(atPath: directory.path),
            "realPayments": false, "deviceScope": "one simulator, two independent local clients"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "native-home-sync-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(restored, "If cleanup is interrupted, retain the baseline and do not overwrite unrelated cloud changes")
        XCTAssertTrue(signedOut, "The managed validation sessions must be revoked")
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
    func testPreviewReceiptRejectsUnexpectedCredentialDestinations() throws {
        let good = PreviewTarget(projectId: "pages-duzdocfvhq4g", environment: "Preview", status: "Success",
            branch: "codex/ios-native-app", deploymentId: "dpiab6dfwnm5",
            commit: "be0aafdb1018ef2a2f8c57062c8887b04e5a08dd",
            origin: "https://yunlefun-apps-dpiab6dfwnm5.edgeone.cool")
        XCTAssertEqual(try good.validatedOrigin().host, "yunlefun-apps-dpiab6dfwnm5.edgeone.cool")
        for suffix in [":8443", "/redirect", "?next=other", "#fragment", ".evil.test"] {
            var bad = good; bad.origin += suffix; XCTAssertThrowsError(try bad.validatedOrigin())
        }
        var bad = good; bad.origin = "http://yunlefun-apps-dpiab6dfwnm5.edgeone.cool"; XCTAssertThrowsError(try bad.validatedOrigin())
        bad = good; bad.projectId = "other"; XCTAssertThrowsError(try bad.validatedOrigin())
        bad = good; bad.status = "Process"; XCTAssertThrowsError(try bad.validatedOrigin())
        bad = good; bad.environment = "Production"; XCTAssertThrowsError(try bad.validatedOrigin())
        bad = good; bad.branch = "main"; XCTAssertThrowsError(try bad.validatedOrigin())
    }
    func testPreviewAccessRequiresFreshBoundedPlatformCookies() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let good = PreviewAccess(cookie: "eo_token=test-only; eo_time=1792120000", expiresAt: now + 3600000)
        XCTAssertEqual(try good.validatedCookie(now: now), good.cookie)
        for bad in [
            PreviewAccess(cookie: good.cookie, expiresAt: now),
            PreviewAccess(cookie: good.cookie, expiresAt: now + 4 * 3600000),
            PreviewAccess(cookie: "other=test-only; eo_time=1", expiresAt: good.expiresAt),
            PreviewAccess(cookie: "eo_token=test-only; eo_time=1\r\nX-Injected: value", expiresAt: good.expiresAt),
        ] { XCTAssertThrowsError(try bad.validatedCookie(now: now)) }
    }
    private struct Pool: Decodable { let accounts: [Credential]; let target: PreviewTarget? }
    private struct PreviewTarget: Decodable {
        var projectId: String
        var environment: String
        var status: String
        var branch: String
        var deploymentId: String
        var commit: String
        var origin: String
        var previewAccess: PreviewAccess? = nil
        func validatedOrigin() throws -> URL {
            guard projectId == "pages-duzdocfvhq4g", environment == "Preview", status == "Success",
                  branch == "codex/ios-native-app",
                  deploymentId.range(of: #"^dp[a-z0-9]{8,24}$"#, options: .regularExpression) != nil,
                  commit.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil,
                  origin == "https://yunlefun-apps-" + deploymentId + ".edgeone.cool",
                  let url = URL(string: origin) else { throw LiveFailure.target }
            return url
        }
        func makeSession() throws -> URLSession {
            _ = try validatedOrigin()
            guard let previewAccess else { throw LiveFailure.target }
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.httpAdditionalHeaders = ["Cookie": try previewAccess.validatedCookie()]
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            return URLSession(configuration: config, delegate: PreviewRedirectPolicy(), delegateQueue: nil)
        }
    }
    private struct PreviewAccess: Decodable {
        let cookie: String
        let expiresAt: Double
        func validatedCookie(now: Double = Date().timeIntervalSince1970 * 1000) throws -> String {
            let parts = cookie.components(separatedBy: "; ")
            guard expiresAt.isFinite, expiresAt > now, expiresAt <= now + 3 * 3600000 + 60000,
                  cookie.utf8.count <= 8192, cookie.utf8.allSatisfy({ (32...126).contains($0) }),
                  parts.count == 2,
                  parts[0].range(of: #"^eo_token=[^;\s]+$"#, options: .regularExpression) != nil,
                  parts[1].range(of: #"^eo_time=\d{1,16}$"#, options: .regularExpression) != nil
            else { throw LiveFailure.target }
            return cookie
        }
    }
    private final class PreviewRedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum LiveFailure: Error { case fixtureCapacity, offline, restart, upload, secondClient, conflict, isolation, target, backup, signout }
}
private extension HomeLibrarySnapshot {
    func containsReference(_ id: String) -> Bool { configuration.installedApps.contains { $0.appId == id } }
}
