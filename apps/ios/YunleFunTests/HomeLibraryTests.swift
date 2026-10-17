import XCTest
@testable import YunleFun

@MainActor
final class HomeLibraryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testPersistsOrderAndRecentUseWithoutMixingAccounts() {
        let a = CloudApplication(id: "a", name: "应用 A")
        let b = CloudApplication(id: "b", name: "应用 B")
        let first = HomeLibrary(directory: directory, accountID: "account/one")
        first.add(a)
        first.add(b)
        first.add(a)
        first.move(from: IndexSet(integer: 0), to: 2)
        first.recordUse(a)
        first.recordUse(b)
        first.recordUse(a)
        XCTAssertEqual(first.snapshot.applications.map(\.id), ["b", "a"])
        XCTAssertEqual(first.snapshot.recentIDs, ["a", "b"])
        let restored = HomeLibrary(directory: directory, accountID: "account/one")
        XCTAssertEqual(restored.snapshot, first.snapshot)
        XCTAssertTrue(HomeLibrary(directory: directory, accountID: "account/two").snapshot.applications.isEmpty)
        XCTAssertTrue(HomeLibrary(directory: directory).snapshot.applications.isEmpty)
    }

    func testCorruptDataIsReportedAndNeverOverwritten() throws {
        let library = HomeLibrary(directory: directory)
        let original = Data("corrupt-but-preserved".utf8)
        try original.write(to: library.fileURL)
        let reopened = HomeLibrary(directory: directory)
        XCTAssertNotNil(reopened.storageError)
        reopened.add(CloudApplication(id: "new", name: "新应用"))
        XCTAssertEqual(try Data(contentsOf: library.fileURL), original)
    }

    func testReorderingASubsetKeepsHiddenSlotsAndPersists() {
        let library = HomeLibrary(directory: directory)
        let apps = ["a", "b", "c", "d"].map { CloudApplication(id: $0, name: $0) }
        apps.forEach(library.add)
        library.setPinned(apps[1], true)
        // 我的应用 hides pinned "b"; the visible subset is reordered around it.
        library.reorder(["d", "a", "c"], inDock: false)
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["d", "b", "a", "c"])
        XCTAssertTrue(library.snapshot.hasPendingChanges)
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot, library.snapshot)
    }

    func testReorderingTheDock() {
        let library = HomeLibrary(directory: directory)
        let apps = ["a", "b", "c"].map { CloudApplication(id: $0, name: $0) }
        apps.forEach { library.add($0); library.setPinned($0, true) }
        library.reorder(["c", "a", "b"], inDock: true)
        XCTAssertEqual(library.snapshot.configuration.dockApps.map(\.appId), ["c", "a", "b"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["a", "b", "c"])
    }

    func testReorderIgnoresUnknownDuplicateAndUnchangedKeys() {
        let library = HomeLibrary(directory: directory)
        ["a", "b", "c"].forEach { library.add(CloudApplication(id: $0, name: $0)) }
        let mutation = library.snapshot.mutationId
        library.reorder(["a", "gone", "b", "c"], inDock: false)
        XCTAssertEqual(library.snapshot.mutationId, mutation, "An unchanged order must not write or schedule a sync")
        library.reorder(["c", "c", "gone", "a"], inDock: false)
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["c", "b", "a"])
        XCTAssertNoThrow(try library.snapshot.configuration.validate())
    }

    func testBatchPinningIsAllOrNothingAndWritesOnce() {
        let library = HomeLibrary(directory: directory)
        let apps = ["a", "b", "c", "d", "e"].map { CloudApplication(id: $0, name: $0) }
        apps.forEach(library.add)
        library.setPinned(apps[0], true)
        let mutation = library.snapshot.mutationId
        XCTAssertFalse(library.setPinned(Array(apps[1...4]), true), "five docked apps must be rejected")
        XCTAssertEqual(library.snapshot.mutationId, mutation, "a rejected pin must not write")
        XCTAssertTrue(library.setPinned([apps[2], apps[0], apps[1]], true), "already-pinned apps don't count twice")
        XCTAssertEqual(library.snapshot.configuration.dockApps.map(\.appId), ["a", "c", "b"])
        XCTAssertTrue(library.setPinned([apps[0], apps[1]], false))
        XCTAssertEqual(library.snapshot.configuration.dockApps.map(\.appId), ["c"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.count, 5, "unpinning keeps apps installed")
    }

    func testEditOrderMovingAndLanding() {
        let order = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(HomeEditOrder.moving("a", in: order, to: 3), ["b", "c", "d", "a", "e"])
        XCTAssertEqual(HomeEditOrder.moving("e", in: order, to: 0), ["e", "a", "b", "c", "d"])
        XCTAssertEqual(HomeEditOrder.moving("c", in: order, to: 99), ["a", "b", "d", "e", "c"])
        XCTAssertEqual(HomeEditOrder.moving("zz", in: order, to: 1), order)
        // Stacked "d" and "a" land right after the primary "c", in pick-up order.
        XCTAssertEqual(HomeEditOrder.landing(["d", "a"], after: "c", in: ["b", "c", "e"]), ["b", "c", "d", "a", "e"])
    }

    func testGridMetricsAlignColumnsToTheLayoutMargins() {
        for width: CGFloat in [343, 370, 408] {
            let metrics = HomeGridMetrics(width: width, sizeClass: .compact)
            XCTAssertEqual(metrics.columns, 4)
            XCTAssertEqual(CGFloat(metrics.columns) * HomeGridMetrics.iconSize + CGFloat(metrics.columns - 1) * metrics.gap,
                           width, accuracy: 0.001, "first and last icons must sit on the margins")
            XCTAssertLessThanOrEqual(metrics.labelWidth - HomeGridMetrics.iconSize, metrics.gap - 8,
                                     "names must not touch the neighbouring name")
            XCTAssertLessThanOrEqual((metrics.labelWidth - HomeGridMetrics.iconSize) / 2, HomeGridMetrics.margin - 4,
                                     "edge names must stay off the screen edge")
        }
        XCTAssertGreaterThan(HomeGridMetrics(width: 760, sizeClass: .regular).columns, 4)
    }

    private func folderLibrary() -> (HomeLibrary, [CloudApplication]) {
        let library = HomeLibrary(directory: directory)
        let apps = ["a", "b", "c", "d", "e"].map { CloudApplication(id: $0, name: $0) }
        apps.forEach(library.add)
        return (library, apps)
    }

    func testCreatingAFolderGathersMembersAtTheDropTarget() {
        let (library, _) = folderLibrary()
        // Drop "e" onto "b": the folder takes b's place, members kept together.
        let id = library.createFolder(named: "  游戏 ", with: ["b", "e"], at: "b")
        let folder = library.snapshot.configuration.folders.first
        XCTAssertEqual(folder?.id, id)
        XCTAssertEqual(folder?.name, "游戏")
        XCTAssertEqual(folder?.appIds, ["b", "e"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["a", "b", "e", "c", "d"])
        XCTAssertNoThrow(try library.snapshot.configuration.validate())
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot, library.snapshot, "folders persist")
    }

    func testFolderMembershipFollowsAddRemovePinAndDissolve() throws {
        let (library, apps) = folderLibrary()
        let id = try XCTUnwrap(library.createFolder(named: "", with: ["a", "b"], at: "a"))
        XCTAssertEqual(library.snapshot.configuration.folders.first?.name, "文件夹")
        library.addToFolder(id, keys: ["d"])
        XCTAssertEqual(library.snapshot.configuration.folders.first?.appIds, ["a", "b", "d"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["a", "b", "d", "c", "e"])
        library.removeFromFolder("a")
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["b", "d", "a", "c", "e"], "lands after the folder")
        library.setPinned(apps[1], true)
        XCTAssertEqual(library.snapshot.configuration.folders.first?.appIds, ["d"], "pinning leaves the folder")
        library.remove(apps[3])
        XCTAssertTrue(library.snapshot.configuration.folders.isEmpty, "an emptied folder disappears")
        let second = try XCTUnwrap(library.createFolder(named: "工具", with: ["c", "e"], at: "c"))
        library.renameFolder(second, to: "效率")
        XCTAssertEqual(library.snapshot.configuration.folders.first?.name, "效率")
        library.dissolveFolder(second)
        XCTAssertTrue(library.snapshot.configuration.folders.isEmpty)
        XCTAssertEqual(library.snapshot.configuration.installedApps.count, 4, "dissolving keeps the apps")
    }

    func testReorderingGridItemsMovesWholeFolders() throws {
        let (library, _) = folderLibrary()
        let id = try XCTUnwrap(library.createFolder(named: "组", with: ["b", "c"], at: "b"))
        library.reorderItems(["d", HomeLibrary.folderKey(id), "a", "e"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["d", "b", "c", "a", "e"])
        library.reorderFolder(id, appIds: ["c", "b"])
        XCTAssertEqual(library.snapshot.configuration.folders.first?.appIds, ["c", "b"])
        XCTAssertEqual(library.snapshot.configuration.installedApps.map(\.appId), ["d", "c", "b", "a", "e"])
    }

    func testSnapshotsAndServerCopiesWithoutFoldersStayCompatible() throws {
        // A snapshot saved before folders existed still decodes.
        let legacy = #"{"installedApps":[{"appId":"a"}],"dockApps":[],"recentApps":[],"updatedAt":1}"#
        let decoded = try JSONDecoder().decode(HomeConfiguration.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.folders, [])
        // A schema 1 server can't store folders: adopting its copy keeps ours.
        var local = HomeConfiguration(installedApps: ["a", "b", "c"].map(HomeAppReference.init))
        local.folders = [HomeFolder(id: "f", name: "组", appIds: ["a", "b"])]
        let v1 = RemoteHomeScreen(schemaVersion: 1, revision: String(repeating: "a", count: 64),
                                  configuration: HomeConfiguration(installedApps: ["b", "c"].map(HomeAppReference.init)))
        XCTAssertEqual(local.adopting(v1).folders, [HomeFolder(id: "f", name: "组", appIds: ["b"])])
        XCTAssertTrue(HomeConfiguration(installedApps: local.installedApps, folders: local.folders)
            .matches(RemoteHomeScreen(schemaVersion: 1, revision: v1.revision, configuration: HomeConfiguration(installedApps: local.installedApps))))
        var v2Config = HomeConfiguration(installedApps: local.installedApps); v2Config.folders = []
        let v2 = RemoteHomeScreen(schemaVersion: 2, revision: v1.revision, configuration: v2Config)
        XCTAssertFalse(local.matches(v2), "a schema 2 server without the folder is a real difference")
        XCTAssertEqual(local.adopting(v2).folders, [])
        // Invalid folders are rejected, never trusted.
        for bad in [HomeFolder(id: "x", name: "组", appIds: ["zz"]), HomeFolder(id: "bad id", name: "组", appIds: ["a"]),
                    HomeFolder(id: "x", name: " ", appIds: ["a"]), HomeFolder(id: "x", name: "组", appIds: [])] {
            var config = HomeConfiguration(installedApps: local.installedApps); config.folders = [bad]
            XCTAssertThrowsError(try config.validate())
        }
    }

    func testRemovingAnApplicationRemovesItsRecentEntry() {
        let app = CloudApplication(id: "a", name: "应用")
        let library = HomeLibrary(directory: directory)
        library.add(app)
        library.recordUse(app)
        library.remove(app)
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertTrue(library.snapshot.recentIDs.isEmpty)
    }

    func testAccountSwitchClearsProjectionAndRestoresOnlyTheSelectedNamespace() throws {
        let library = HomeLibrary(directory: directory)
        library.add(CloudApplication(id: "guest", name: "访客应用"))
        library.activateAccount("a")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        library.add(CloudApplication(id: "private-a", name: "A 的应用"))
        library.activateAccount("b")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        try Data("corrupt".utf8).write(to: library.fileURL)
        library.activateAccount("a")
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["private-a"])
        library.activateAccount("b")
        XCTAssertTrue(library.snapshot.applications.isEmpty)
        XCTAssertNotNil(library.storageError)
        library.activateAccount(nil)
        XCTAssertEqual(library.snapshot.applications.map(\.id), ["guest"])
        XCTAssertNil(library.storageError)
    }
}
