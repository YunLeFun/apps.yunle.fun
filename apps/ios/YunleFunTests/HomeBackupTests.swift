import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class HomeBackupTests: XCTestCase {
    func testNativeBundleIncludesOwnFileAndPreferenceAPIReasons() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let entries = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String, let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
    }

    func testOnlyCurrentOwnerAndRecognizedRegularBackupsAreListed() async throws {
        let f = try Fixture(); defer { f.close() }
        _ = try f.backup()
        let other = HomeLibrary(directory: f.directory, accountID: "alice")
        let foreign = other.fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
        try f.write(f.candidate, to: foreign)
        try f.write(f.candidate, to: f.directory.appendingPathComponent("guest.unrecognized.json"))
        let link = f.directory.appendingPathComponent("guest.before-restore-\(UUID().uuidString).json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
        await f.store.load()
        XCTAssertEqual(f.store.visibleItems.count, 1)
        XCTAssertEqual(f.store.visibleItems.first?.kind, .legacy)
        XCTAssertNil(HomeBackupRepository.kind(name: "../guest.conflict-\(UUID().uuidString).json", ownerFileName: "guest.json"))
        do { _ = try await f.repository.preview(id: foreign.lastPathComponent, ownerFileName: "guest.json"); XCTFail("Foreign backup must not be read") } catch {}
    }

    func testRestoreKeepsCloudRevisionImportReceiptAndReversibleCurrentVersion() async throws {
        let f = try Fixture(); defer { f.close() }
        var old = f.candidate
        old.base = RemoteHomeScreen(revision: String(repeating: "b", count: 64), configuration: old.configuration)
        let backup = try f.backup(old)
        f.library.add(CloudApplication(id: "current", name: "当前应用"))
        let currentRemote = RemoteHomeScreen(revision: String(repeating: "c", count: 64), configuration: f.library.snapshot.configuration)
        try f.library.adopt(currentRemote)
        let record = try LegacyLocalData(values: ["ylf:homescreen-apps": #"[{"appId":"current"}]"#])
        try f.library.importLegacy(record, expectedGeneration: f.library.generation)
        let before = f.library.snapshot; let generation = f.library.generation
        await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        await f.store.restore(confirmation)
        XCTAssertNil(f.store.error); XCTAssertTrue(f.store.didRestore)
        XCTAssertEqual(f.library.snapshot.configuration, old.configuration)
        XCTAssertEqual(f.library.snapshot.base, currentRemote)
        XCTAssertEqual(f.library.snapshot.legacyImportID, before.legacyImportID)
        XCTAssertNotEqual(f.library.generation, generation)
        XCTAssertNotEqual(f.library.snapshot.mutationId, before.mutationId)
        XCTAssertTrue(f.library.snapshot.hasPendingChanges)
        XCTAssertFalse(f.library.snapshot.syncEnabled); XCTAssertTrue(f.library.snapshot.dockVisible)
        let safety = f.directory.appendingPathComponent("guest.before-restore-\(confirmation.id.uuidString).json")
        XCTAssertEqual(try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: safety)), before)
        XCTAssertEqual(HomeLibrary(directory: f.directory).snapshot, f.library.snapshot)
        XCTAssertEqual(try Data(contentsOf: backup), JSONEncoderData(old))
    }

    func testLayoutOnlyRestorePreservesCurrentPreferencesAndPrivateScope() async throws {
        let f = try Fixture(); defer { f.close() }
        var snapshot = f.candidate
        snapshot.cachedApplications = [CloudApplication(id: "restored", name: "私有版本", websiteUrl: "https://private.invalid/", accessWorkshopID: "workshop-a")]
        let backup = try f.backup(snapshot)
        f.library.updateCatalog([CloudApplication(id: "restored", name: "公开目录", websiteUrl: "https://public.invalid/")])
        f.library.setSyncEnabled(true); f.library.setAutoSyncEnabled(true); f.library.setDockVisible(false)
        await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: false))
        f.library.setAutoSyncEnabled(false)
        await f.store.restore(confirmation)
        XCTAssertNil(f.store.error)
        XCTAssertTrue(f.library.snapshot.syncEnabled); XCTAssertFalse(f.library.snapshot.autoSyncEnabled); XCTAssertFalse(f.library.snapshot.dockVisible)
        XCTAssertEqual(f.library.snapshot.application(reference: "restored").accessWorkshopID, "workshop-a")
    }

    func testChangedCurrentHomeOrSettingsInvalidatesConfirmation() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup(); await f.store.select(backup.lastPathComponent)
        let first = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        f.library.add(CloudApplication(id: "new-edit", name: "新更改"))
        await f.store.restore(first)
        XCTAssertEqual(f.store.error, HomeBackupError.currentChanged.localizedDescription)
        XCTAssertNil(f.library.snapshot.lastRestoreID)
        let second = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        f.library.setDockVisible(!f.library.snapshot.dockVisible)
        await f.store.restore(second)
        XCTAssertEqual(f.store.error, HomeBackupError.currentChanged.localizedDescription)
    }

    func testAccountRoundTripInvalidatesConfirmationAndHidesPrivateContent() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup(); await f.store.load(); await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        f.accounts.select("alice"); f.library.activateAccount("alice")
        XCTAssertTrue(f.store.visibleItems.isEmpty); XCTAssertNil(f.store.visiblePreview)
        f.accounts.select(nil); f.library.activateAccount(nil)
        await f.store.restore(confirmation)
        XCTAssertEqual(f.store.error, HomeBackupError.identityChanged.localizedDescription)
        XCTAssertNil(f.library.snapshot.lastRestoreID)
    }

    func testChangedOrMissingBackupCannotBeRestoredFromCachedPreview() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup(); await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        var changed = f.candidate; changed.configuration.installedApps = [.init(appId: "changed")]
        try f.write(changed, to: backup)
        await f.store.restore(confirmation)
        XCTAssertEqual(f.store.error, HomeBackupError.backupChanged.localizedDescription)
        XCTAssertNil(f.library.snapshot.lastRestoreID)
        try FileManager.default.removeItem(at: backup)
        await f.store.restore(confirmation)
        XCTAssertEqual(f.store.error, HomeBackupError.unreadable.localizedDescription)
    }

    func testRepeatedCompletionDoesNotOverwriteLaterEditsOrCreateMoreBackups() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup(); await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        await f.store.restore(confirmation)
        f.library.add(CloudApplication(id: "later", name: "后来的编辑"))
        let edited = f.library.snapshot
        await f.store.restore(confirmation)
        XCTAssertEqual(f.library.snapshot, edited)
        let records = try await f.repository.list(ownerFileName: "guest.json")
        XCTAssertEqual(records.filter { $0.kind == .restore }.count, 1)
    }

    func testCorruptCurrentFileCanRecoverWithoutDeletingItsOriginalBytes() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup()
        let damaged = Data("damaged-native-home".utf8)
        try damaged.write(to: f.library.fileURL)
        f.library.activateAccount(nil)
        XCTAssertTrue(f.library.needsRecovery)
        await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        await f.store.restore(confirmation)
        XCTAssertNil(f.store.error); XCTAssertFalse(f.library.needsRecovery); XCTAssertNil(f.library.storageError)
        XCTAssertEqual(f.library.snapshot.configuration, f.candidate.configuration)
        let original = f.directory.appendingPathComponent("guest.before-repair-\(confirmation.id.uuidString).bin")
        XCTAssertEqual(try Data(contentsOf: original), damaged)
        XCTAssertEqual(HomeLibrary(directory: f.directory).snapshot, f.library.snapshot)
    }

    func testDamagedBackupAndUnwritableSafetyCopyLeaveHomeUntouched() async throws {
        let f = try Fixture(); defer { f.close() }
        let backup = try f.backup()
        let before = f.library.snapshot
        await f.store.select(backup.lastPathComponent)
        let confirmation = try XCTUnwrap(f.store.confirmation(restoreSettings: true))
        let blocked = f.directory.appendingPathComponent("guest.before-restore-\(confirmation.id.uuidString).json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        await f.store.restore(confirmation)
        XCTAssertNotNil(f.store.error); XCTAssertEqual(f.library.snapshot, before)
        try FileManager.default.removeItem(at: blocked)
        await f.store.restore(confirmation)
        XCTAssertNil(f.store.error); XCTAssertNotNil(f.library.snapshot.lastRestoreID)
        try Data("corrupt backup".utf8).write(to: backup)
        await f.store.select(backup.lastPathComponent, force: true)
        XCTAssertNil(f.store.visiblePreview); XCTAssertNotNil(f.store.error)
    }

    func testRestoreCancelsOldSyncReadAndCannotReceiveItsLateResponse() async throws {
        let f = try Fixture(); defer { f.close() }
        f.accounts.select("alice"); f.library.activateAccount("alice")
        f.library.setAutoSyncEnabled(false)
        f.library.add(CloudApplication(id: "current", name: "当前云居"))
        let gate = BackupSyncGate()
        let remote = RemoteHomeScreen(revision: String(repeating: "d", count: 64), configuration: HomeConfiguration(installedApps: [.init(appId: "late-cloud")]))
        let service = BackupSyncService(remote: remote, gate: gate)
        let sync = HomeSyncCoordinator(accounts: f.accounts, library: f.library, service: service, monitorNetwork: false)
        let originalRead = Task { await sync.synchronize() }
        await gate.waitUntilEntered()
        let backup = f.library.fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
        try f.write(f.candidate, to: backup)
        await f.store.select(backup.lastPathComponent)
        await f.store.restore(try XCTUnwrap(f.store.confirmation(restoreSettings: false)))
        XCTAssertEqual(sync.phase, .idle)
        await gate.open(); await originalRead.value
        XCTAssertEqual(f.library.snapshot.configuration, f.candidate.configuration)
        XCTAssertEqual(sync.phase, .idle)
    }

    func testRestoreReplacesObsoleteConflictAndRejectsItsOldChoice() async throws {
        let f = try Fixture(); defer { f.close() }
        f.accounts.select("alice"); f.library.activateAccount("alice"); f.library.setAutoSyncEnabled(false)
        f.library.add(CloudApplication(id: "local", name: "本地"))
        let remote = RemoteHomeScreen(revision: String(repeating: "e", count: 64), configuration: HomeConfiguration(installedApps: [.init(appId: "cloud")]))
        let sync = HomeSyncCoordinator(accounts: f.accounts, library: f.library, service: BackupSyncService(remote: remote), monitorNetwork: false)
        await sync.synchronize()
        guard case .conflict(let conflict) = sync.phase else { return XCTFail("Expected a real coordinator conflict") }
        let backup = f.library.fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
        try f.write(f.candidate, to: backup)
        await f.store.select(backup.lastPathComponent)
        await f.store.restore(try XCTUnwrap(f.store.confirmation(restoreSettings: false)))
        XCTAssertEqual(sync.phase, .idle)
        await sync.resolve(.cloud, conflict: conflict)
        XCTAssertEqual(f.library.snapshot.configuration, f.candidate.configuration)
    }

    func testNativeBackupListPreviewErrorAndRecoveryScreenshots() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for state in ["list", "preview", "empty", "failure", "recovery", "completed"] {
            let f = try Fixture(); defer { f.close() }
            let backup = state == "empty" ? nil : try f.backup()
            if state == "failure", let backup { try Data("invalid".utf8).write(to: backup) }
            if state == "recovery" { try Data("damaged home".utf8).write(to: f.library.fileURL); f.library.activateAccount(nil) }
            await f.store.load()
            if let backup { await f.store.select(backup.lastPathComponent) }
            if state == "completed" { await f.store.restore(try XCTUnwrap(f.store.confirmation(restoreSettings: true))) }
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = state == "failure" ? .dark : .light
            if let backup, !["list", "recovery"].contains(state) {
                window.rootViewController = UIHostingController(rootView: NavigationStack { HomeBackupDetailView(store: f.store, backupID: backup.lastPathComponent) }.dynamicTypeSize(state == "failure" ? .accessibility3 : .large))
            } else { window.rootViewController = UIHostingController(rootView: NavigationStack { HomeBackupsView(store: f.store) }) }
            window.makeKeyAndVisible(); try await Task.sleep(nanoseconds: 200_000_000)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "home-backup-\(state)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
        }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accounts = BillingAccounts()
        let library: HomeLibrary
        let candidate: HomeLibrarySnapshot
        lazy var repository = HomeBackupRepository(directory: directory)
        lazy var store = HomeBackupStore(library: library, accounts: accounts, reader: repository)
        init() throws {
            library = HomeLibrary(directory: directory)
            accounts.select(nil)
            var snapshot = HomeLibrarySnapshot()
            snapshot.configuration = HomeConfiguration(installedApps: [.init(appId: "restored"), .init(appId: "unknown")], dockApps: [.init(appId: "restored")], recentApps: [.init(appId: "restored", usedAt: 1_790_000_000_123)])
            snapshot.cachedApplications = [CloudApplication(id: "restored", name: "备份中的应用")]
            snapshot.syncEnabled = false; snapshot.autoSyncEnabled = false; snapshot.dockVisible = true
            candidate = snapshot
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func backup(_ snapshot: HomeLibrarySnapshot? = nil) throws -> URL {
            let url = directory.appendingPathComponent("guest.before-legacy-\(String(repeating: "a", count: 64)).json")
            try write(snapshot ?? candidate, to: url); return url
        }
        func write(_ snapshot: HomeLibrarySnapshot, to url: URL) throws { try JSONEncoderData(snapshot).write(to: url) }
        func close() { try? FileManager.default.removeItem(at: directory) }
    }
}

private func JSONEncoderData(_ snapshot: HomeLibrarySnapshot) -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try! encoder.encode(snapshot)
}

private actor BackupSyncService: HomeSyncServing {
    let remote: RemoteHomeScreen
    let gate: BackupSyncGate?
    init(remote: RemoteHomeScreen, gate: BackupSyncGate? = nil) { self.remote = remote; self.gate = gate }
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen { await gate?.wait(); return remote }
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen { throw HomeSyncError.unavailable }
}
private actor BackupSyncGate {
    var entered = false, opened = false
    var waiting: CheckedContinuation<Void, Never>?
    var entry: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true; entry?.resume(); entry = nil
        if !opened { await withCheckedContinuation { waiting = $0 } }
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func open() { opened = true; waiting?.resume(); waiting = nil }
}
