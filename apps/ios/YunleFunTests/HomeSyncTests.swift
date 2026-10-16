import XCTest
@testable import YunleFun

@MainActor
final class HomeSyncTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testRestoresAllReferencesWithoutDroppingUnknownAppsOrChoosingAmbiguousSlugs() async throws {
        let remote = cloud("a", installed: ["old-cook", "unknown", "ambiguous"], dock: ["dock-only"], recent: ["unknown", "old-cook"])
        let service = HomeTestService(remote: remote)
        let library = HomeLibrary(directory: directory, accountID: "a")
        library.updateCatalog([
            CloudApplication(id: "canonical-cook", name: "食用手册", slug: "old-cook"),
            CloudApplication(id: "one", name: "同名应用一", slug: "ambiguous"),
            CloudApplication(id: "two", name: "同名应用二", slug: "ambiguous"),
        ])
        let sync = coordinator(library, service)
        await sync.synchronize()
        XCTAssertEqual(library.snapshot.configuration, remote.configuration)
        XCTAssertEqual(library.snapshot.applications.map(\.homeKey), ["old-cook", "unknown", "ambiguous"])
        XCTAssertEqual(library.snapshot.applications.first?.id, "canonical-cook")
        XCTAssertTrue(library.snapshot.applications[1].isUnavailable == true)
        XCTAssertTrue(library.snapshot.applications[2].isUnavailable == true)
        XCTAssertFalse(library.snapshot.hasPendingChanges)
        let saves = await service.writes
        XCTAssertTrue(saves.isEmpty)
    }

    func testOfflineChangesKeepTheirRetryIdentityAcrossRestartAndAccounts() async throws {
        let library = HomeLibrary(directory: directory, accountID: "a")
        library.add(CloudApplication(id: "a-app", name: "离线应用"))
        let mutationId = library.snapshot.mutationId
        let service = HomeTestService(remote: cloud(nil), loadFailure: URLError(.notConnectedToInternet))
        let sync = coordinator(library, service)
        await sync.synchronize()
        guard case .failed = sync.phase else { return XCTFail("Offline is an explicit retryable state") }
        let reopened = HomeLibrary(directory: directory, accountID: "a")
        XCTAssertEqual(reopened.snapshot.mutationId, mutationId)
        XCTAssertEqual(reopened.snapshot.applications.map(\.id), ["a-app"])
        XCTAssertTrue(reopened.snapshot.hasPendingChanges)
        reopened.activateAccount("b")
        XCTAssertTrue(reopened.snapshot.applications.isEmpty)
    }

    func testFirstSyncConflictRequiresAChoiceAndKeepsARecoveryCopy() async throws {
        let remote = cloud("b", installed: ["cloud-app"])
        let service = HomeTestService(remote: remote)
        let library = HomeLibrary(directory: directory, accountID: "a")
        library.add(CloudApplication(id: "local-app", name: "本地应用"))
        let original = library.snapshot.configuration
        let sync = coordinator(library, service)
        await sync.synchronize()
        guard case .conflict(let conflict) = sync.phase else { return XCTFail("Both versions must remain available") }
        XCTAssertEqual(library.snapshot.configuration, original)
        await sync.resolve(.cloud, conflict: conflict)
        XCTAssertEqual(library.snapshot.configuration, remote.configuration)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".conflict-") }
        XCTAssertEqual(backups.count, 1)
        let backup = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: XCTUnwrap(backups.first)))
        XCTAssertEqual(backup.configuration, original)
        XCTAssertTrue(backup.hasPendingChanges)
    }

    func testUploadAcknowledgementNeverOverwritesEditsMadeDuringUpload() async throws {
        let gate = HomeTestGate()
        let service = HomeTestService(remote: cloud(nil), saveGate: gate)
        let library = HomeLibrary(directory: directory, accountID: "a")
        library.setAutoSyncEnabled(false)
        try library.adopt(cloud(nil))
        library.add(CloudApplication(id: "first", name: "第一个应用"))
        let sync = coordinator(library, service)
        let upload = Task { await sync.synchronize() }
        await gate.waitUntilEntered()
        library.add(CloudApplication(id: "second", name: "后来添加"))
        let latestMutation = library.snapshot.mutationId
        await gate.open()
        await upload.value
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["first", "second"])
        XCTAssertEqual(library.snapshot.mutationId, latestMutation)
        XCTAssertTrue(library.snapshot.hasPendingChanges)
        XCTAssertEqual(library.snapshot.base?.configuration.installedApps.map(\.appId), ["first"])
        await sync.synchronize()
        XCTAssertFalse(library.snapshot.hasPendingChanges)
        let writes = await service.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.last?.configuration.installedApps.map(\.appId), ["first", "second"])
    }

    func testLateResponseCannotEnterAnotherAccountsNamespace() async throws {
        let gate = HomeTestGate()
        let service = HomeTestService(remote: cloud("a", installed: ["private-a"]), loadGate: gate)
        let library = HomeLibrary(directory: directory, accountID: "a")
        let auth = HomeTestAuthorizer("a")
        let sync = HomeSyncCoordinator(accounts: auth, library: library, service: service, monitorNetwork: false)
        let loading = Task { await sync.synchronize() }
        await gate.waitUntilEntered()
        library.activateAccount("b")
        auth.user = AccountUser(id: "b")
        library.setAutoSyncEnabled(false)
        sync.identityChanged()
        await gate.open()
        await loading.value
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertNil(library.snapshot.base)
        XCTAssertEqual(sync.phase, .idle)
    }

    func testDisablingSyncDiscardsAnAlreadyRunningRead() async throws {
        let gate = HomeTestGate()
        let service = HomeTestService(remote: cloud("a", installed: ["remote"]), loadGate: gate)
        let library = HomeLibrary(directory: directory, accountID: "a")
        let sync = coordinator(library, service)
        let loading = Task { await sync.synchronize() }
        await gate.waitUntilEntered()
        library.setSyncEnabled(false)
        await gate.open()
        await loading.value
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertEqual(sync.phase, .idle)
    }

    func testUnauthorizedRequestRefreshesOnceWithoutChangingTheOwner() async {
        let auth = HomeTestAuthorizer("a")
        let service = HomeTestService(remote: cloud("a"), unauthorizedOnce: true)
        let library = HomeLibrary(directory: directory, accountID: "a")
        let sync = HomeSyncCoordinator(accounts: auth, library: library, service: service, monitorNetwork: false)
        await sync.synchronize()
        XCTAssertEqual(auth.refreshRequests, [false, true])
        XCTAssertEqual(sync.phase, .idle)
        XCTAssertNotNil(library.snapshot.base)
    }

    func testChangingLocalDataWhileComparingPreventsAnOutdatedCloudChoice() async {
        let service = HomeTestService(remote: cloud("a", installed: ["remote"]))
        let library = HomeLibrary(directory: directory, accountID: "a")
        library.add(CloudApplication(id: "first", name: "第一个"))
        let sync = coordinator(library, service)
        await sync.synchronize()
        guard case .conflict(let conflict) = sync.phase else { return XCTFail() }
        library.add(CloudApplication(id: "second", name: "第二个"))
        await sync.resolve(.cloud, conflict: conflict)
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["first", "second"])
        guard case .conflict(let refreshed) = sync.phase else { return XCTFail() }
        XCTAssertNotEqual(refreshed.id, conflict.id)
    }

    func testVersionOneMigrationPreservesOrderAndUnknownTimestamps() throws {
        let data = Data(#"{"version":1,"applications":[{"_id":"legacy","name":"旧应用"}],"recentIDs":["legacy","missing"]}"#.utf8)
        let state = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
        XCTAssertEqual(state.version, 2)
        XCTAssertEqual(state.applications.map(\.id), ["legacy"])
        XCTAssertEqual(state.recentIDs, ["legacy", "missing"])
        XCTAssertEqual(state.configuration.recentApps.map(\.usedAt), [0, 0])
        XCTAssertTrue(state.hasPendingChanges)
        XCTAssertThrowsError(try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(#"{"version":3}"#.utf8)))
    }

    func testDockAndLegacyRemovalKeepTheCloudReference() throws {
        let library = HomeLibrary(directory: directory)
        let app = CloudApplication(id: "record", name: "旧应用", slug: "legacy")
        library.updateCatalog([app])
        try library.adopt(cloud("a", installed: ["legacy"], dock: ["legacy"], recent: ["legacy"]))
        XCTAssertTrue(library.contains(app))
        library.remove(app)
        XCTAssertTrue(library.snapshot.configuration.installedApps.isEmpty)
        XCTAssertTrue(library.snapshot.configuration.dockApps.isEmpty)
        XCTAssertTrue(library.snapshot.configuration.recentApps.isEmpty)
        for index in 0..<5 { library.setPinned(CloudApplication(id: String(index), name: "应用"), true) }
        XCTAssertEqual(library.snapshot.dockApplications.count, 4)
    }

    private func coordinator(_ library: HomeLibrary, _ service: HomeTestService) -> HomeSyncCoordinator {
        HomeSyncCoordinator(accounts: HomeTestAuthorizer("a"), library: library, service: service, monitorNetwork: false)
    }
    private func cloud(_ revision: String?, installed: [String] = [], dock: [String] = [], recent: [String] = []) -> RemoteHomeScreen {
        RemoteHomeScreen(revision: revision.map { String(repeating: $0, count: 64) },
                         configuration: HomeConfiguration(installedApps: installed.map { HomeAppReference(appId: $0) },
                                                          dockApps: dock.map { HomeAppReference(appId: $0) },
                                                          recentApps: recent.map { HomeRecentReference(appId: $0, usedAt: 10) },
                                                          updatedAt: revision == nil ? 0 : 100))
    }
}

@MainActor
private final class HomeTestAuthorizer: AccountAuthorizing {
    var user: AccountUser?
    private(set) var refreshRequests: [Bool] = []
    init(_ id: String) { user = AccountUser(id: id) }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        refreshRequests.append(forceRefresh)
        return AuthorizedAccount(userID: user!.id, accessToken: "test-only")
    }
}
private actor HomeTestService: HomeSyncServing {
    private var remote: RemoteHomeScreen
    private let loadFailure: Error?
    private let loadGate: HomeTestGate?
    private let saveGate: HomeTestGate?
    private var unauthorizedOnce: Bool
    private(set) var writes: [HomeScreenWrite] = []
    init(remote: RemoteHomeScreen, loadFailure: Error? = nil, loadGate: HomeTestGate? = nil,
         saveGate: HomeTestGate? = nil, unauthorizedOnce: Bool = false) {
        self.remote = remote; self.loadFailure = loadFailure; self.loadGate = loadGate
        self.saveGate = saveGate; self.unauthorizedOnce = unauthorizedOnce
    }
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        let response = remote
        await loadGate?.wait()
        if let loadFailure { throw loadFailure }
        if unauthorizedOnce { unauthorizedOnce = false; throw HomeSyncError.unauthorized }
        return response
    }
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        writes.append(write)
        await saveGate?.wait()
        var config = write.configuration
        config.updatedAt = Int64(200 + writes.count)
        remote = RemoteHomeScreen(revision: String(repeating: String(writes.count), count: 64), configuration: config)
        return remote
    }
}
private actor HomeTestGate {
    private var entered = false
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var entry: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        entry.forEach { $0.resume() }; entry = []
        if !opened { await withCheckedContinuation { waiting.append($0) } }
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entry.append($0) } } }
    func open() { opened = true; waiting.forEach { $0.resume() }; waiting = [] }
}
