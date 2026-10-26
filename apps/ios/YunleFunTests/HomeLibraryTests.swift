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

    func testLegacyBuiltInYunHomeRestoresWithoutChangingCloudReferences() throws {
        let library = HomeLibrary(directory: directory)
        let configuration = HomeConfiguration(installedApps: [.init(appId: "yun-home"), .init(appId: "valaxy")],
                                              recentApps: [.init(appId: "yun-home", usedAt: 1)])
        try library.adopt(RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: configuration))
        let home = try XCTUnwrap(library.snapshot.applications.first)
        XCTAssertEqual(home.name, "Yun Home")
        XCTAssertEqual(home.launchURL?.absoluteString, "https://home.yunle.fun/")
        XCTAssertTrue(home.canOpenAsGuest)
        XCTAssertEqual(home.homeKey, "yun-home")
        XCTAssertEqual(library.snapshot.recentApplications.first, home)
        XCTAssertEqual(library.snapshot.configuration, configuration)
        XCTAssertFalse(library.snapshot.hasPendingChanges)
        XCTAssertEqual(library.snapshot.applications[1].isUnavailable, true, "An intentionally unlisted app must not be republished by a legacy fallback")
    }

    func testUnknownHomeApplicationUsesShortUnavailableName() throws {
        var snapshot = HomeLibrarySnapshot()
        snapshot.configuration.installedApps = [.init(appId: "unknown")]
        let app = try XCTUnwrap(snapshot.applications.first)
        XCTAssertEqual(app.name, "暂不可用")
        XCTAssertEqual(app.homeKey, "unknown")
        XCTAssertEqual(app.isUnavailable, true)
        XCTAssertNil(app.launchURL)
    }

    func testConfirmedPublicRemovalPreservesArtworkAndDoesNotDisableScopedApps() throws {
        let library = HomeLibrary(directory: directory)
        let cached = CloudApplication(id: "former-public", name: "原应用", logo: "https://example.test/icon.png", emoji: "🎨")
        let personal = CloudApplication(id: "personal", name: "作者作品", personalMarketOwnerLogin: "Author")
        let workshop = CloudApplication(id: "workshop", name: "工坊应用", accessWorkshopID: "ABC234")
        let owner = CloudApplication(id: "owner", name: "本人作品", accessOwnerID: "owner")
        [cached, personal, workshop, owner].forEach(library.add)
        let configuration = library.snapshot.configuration
        let mutation = library.snapshot.mutationId
        library.updateCatalog([])
        XCTAssertNotEqual(library.snapshot.applications[0].isUnavailable, true, "A partial or offline merge cannot establish removal")
        library.updateCatalog([], markingMissingPublicAppsUnavailable: true)
        let unavailable = library.snapshot.applications[0]
        XCTAssertEqual(unavailable.name, cached.name)
        XCTAssertEqual(unavailable.logo, cached.logo)
        XCTAssertEqual(unavailable.emoji, cached.emoji)
        XCTAssertEqual(unavailable.isUnavailable, true)
        XCTAssertFalse(unavailable.canOpenAsGuest)
        XCTAssertTrue(library.snapshot.applications.dropFirst().allSatisfy { $0.isUnavailable != true })
        XCTAssertEqual(library.snapshot.configuration, configuration)
        XCTAssertEqual(library.snapshot.mutationId, mutation, "Availability metadata must not rewrite the cloud layout")
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot, library.snapshot)
        library.updateCatalog([cached], markingMissingPublicAppsUnavailable: true)
        XCTAssertNotEqual(library.snapshot.applications[0].isUnavailable, true, "A relisted application becomes usable again")
    }

    func testChangingSourceKeepsOnlyCachedPresentationForAnUnavailableMarketEntry() throws {
        let library = HomeLibrary(directory: directory)
        let personal = CloudApplication(id: "record", name: "旧作品", websiteUrl: "https://author.invalid/", logo: "https://example.test/icon.png",
                                        emoji: "🎨", trustedHosts: ["author.invalid"], personalMarketOwnerLogin: "Author")
        library.add(personal)
        try library.adopt(RemoteHomeScreen(revision: String(repeating: "a", count: 64),
                                          configuration: HomeConfiguration(installedApps: [.init(appId: "record")])))
        let app = try XCTUnwrap(library.snapshot.applications.first)
        XCTAssertEqual(app.name, personal.name)
        XCTAssertEqual(app.logo, personal.logo)
        XCTAssertEqual(app.emoji, personal.emoji)
        XCTAssertEqual(app.isUnavailable, true)
        XCTAssertNil(app.launchURL)
        XCTAssertTrue(app.runtimeTrustedHosts.isEmpty)
        XCTAssertNil(app.personalMarketOwnerLogin)
    }

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

    func testExplicitSourceSelectionChangesAlreadyInstalledAppAndSurvivesRestart() throws {
        let library = HomeLibrary(directory: directory, accountID: "a")
        let market = CloudApplication(id: "cook", name: "市场版本", websiteUrl: "https://market.invalid/")
        let author = CloudApplication(id: "cook", name: "作者版本", websiteUrl: "https://author.invalid/", personalMarketOwnerLogin: "Author")
        library.add(market)
        let before = library.snapshot.mutationId
        library.add(author)
        XCTAssertNotEqual(library.snapshot.mutationId, before)
        XCTAssertEqual(library.snapshot.configuration.applicationSources, [.init(appId: "cook", ownerLogin: "Author")])
        XCTAssertEqual(library.snapshot.configuration.installedApps.count, 1)
        library.updateCatalog([market])
        let reopened = HomeLibrary(directory: directory, accountID: "a")
        XCTAssertEqual(reopened.snapshot.applications.first?.launchURL, author.launchURL)
        library.add(market)
        XCTAssertTrue(library.snapshot.configuration.applicationSources.isEmpty)
        XCTAssertEqual(HomeLibrary(directory: directory, accountID: "a").snapshot.applications.first?.launchURL, market.launchURL)
        library.activateAccount("b")
        XCTAssertTrue(library.snapshot.configuration.applicationSources.isEmpty)
        XCTAssertTrue(library.snapshot.cachedApplications.isEmpty)
    }

    func testAnotherDeviceUsesSelectedAuthorWithoutTrustingItsMarketCache() throws {
        let library = HomeLibrary(directory: directory)
        library.updateCatalog([CloudApplication(id: "cook", name: "市场资料", websiteUrl: "https://market.invalid/", trustedHosts: ["market.invalid"])])
        let content = HomeConfiguration(installedApps: [.init(appId: "cook"), .init(appId: "author-only")],
                                        applicationSources: [.init(appId: "cook", ownerLogin: "Author"), .init(appId: "author-only", ownerLogin: "Other")])
        try library.adopt(RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: content))
        for app in library.snapshot.applications {
            XCTAssertNotNil(app.personalMarketOwnerLogin)
            XCTAssertNil(app.launchURL, "The selected author must be resolved online before any URL can run")
            XCTAssertTrue(app.runtimeTrustedHosts.isEmpty)
            XCTAssertFalse(app.canOpenAsGuest)
            XCTAssertNotEqual(app.isUnavailable, true, "The existing personal resolver must be reachable for an uncached source")
        }
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot.applications.map(\.personalMarketOwnerLogin), ["Author", "Other"])
    }

    func testRemoteMarketSelectionCannotReusePreviousAuthorURLAndCanRefreshPublicMetadata() throws {
        let library = HomeLibrary(directory: directory)
        library.add(CloudApplication(id: "cook", name: "作者版本", websiteUrl: "https://author.invalid/", personalMarketOwnerLogin: "Author"))
        let marketContent = HomeConfiguration(installedApps: [.init(appId: "cook")])
        try library.adopt(RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: marketContent))
        XCTAssertNil(library.snapshot.applications.first?.launchURL)
        XCTAssertNil(library.snapshot.applications.first?.personalMarketOwnerLogin)
        XCTAssertEqual(library.snapshot.applications.first?.isUnavailable, true)
        library.updateCatalog([CloudApplication(id: "cook", name: "市场版本", websiteUrl: "https://market.invalid/")])
        XCTAssertEqual(library.snapshot.applications.first?.launchURL?.host, "market.invalid")
        XCTAssertNil(library.snapshot.applications.first?.personalMarketOwnerLogin)
    }

    func testVersionTwoMigratesAuthorProvenanceWithoutChangingReferencesOrLosingPendingEdits() throws {
        var old = HomeLibrarySnapshot()
        old.configuration = HomeConfiguration(installedApps: [.init(appId: "legacy")], dockApps: [.init(appId: "legacy")],
                                              recentApps: [.init(appId: "legacy", usedAt: 42)])
        old.cachedApplications = [CloudApplication(id: "record", name: "旧作者版本", slug: "legacy", websiteUrl: "https://author.invalid/", personalMarketOwnerLogin: "Author")]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json["version"] = 2
        var configuration = try XCTUnwrap(json["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "applicationSources"); json["configuration"] = configuration
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let file = HomeLibrary(directory: directory).fileURL
        try oldData.write(to: file)
        let library = HomeLibrary(directory: directory)
        XCTAssertNil(library.storageError)
        XCTAssertEqual(library.snapshot.version, 3)
        XCTAssertEqual(library.snapshot.configuration.installedApps, old.configuration.installedApps)
        XCTAssertEqual(library.snapshot.configuration.recentApps, old.configuration.recentApps)
        XCTAssertEqual(library.snapshot.configuration.applicationSources, [.init(appId: "legacy", ownerLogin: "Author")])
        XCTAssertTrue(library.snapshot.hasPendingChanges)
        XCTAssertNotEqual(library.snapshot.mutationId, old.mutationId)
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot.mutationId, library.snapshot.mutationId, "Unwritten migration must keep the retry identity across restart")
        XCTAssertEqual(try Data(contentsOf: file), oldData, "Reading alone must not rewrite the old file")
        library.setDockVisible(true)
        XCTAssertEqual(HomeLibrary(directory: directory).snapshot, library.snapshot)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains(".before-native-migration-") })
        XCTAssertEqual(try Data(contentsOf: backup), oldData)
        XCTAssertEqual(HomeBackupRepository.kind(name: backup.lastPathComponent, ownerFileName: "guest.json"), .nativeMigration)
    }

    func testSourceLifetimeFollowsAllReferencesAndOldServersCannotEraseIt() throws {
        let library = HomeLibrary(directory: directory)
        let author = CloudApplication(id: "cook", name: "作者版本", personalMarketOwnerLogin: "Author")
        library.recordUse(author)
        XCTAssertEqual(library.snapshot.configuration.applicationSources.count, 1, "A recent-only app retains its selected source")
        let previousMutation = library.snapshot.mutationId
        let v2 = RemoteHomeScreen(schemaVersion: 2, revision: String(repeating: "a", count: 64),
                                  configuration: HomeConfiguration(recentApps: [.init(appId: "cook", usedAt: 42)]))
        try library.adopt(v2)
        XCTAssertEqual(library.snapshot.recentApplications.first?.personalMarketOwnerLogin, "Author")
        XCTAssertEqual(library.snapshot.configuration.recentApps.first?.usedAt, 42)
        XCTAssertNotEqual(library.snapshot.mutationId, previousMutation, "A changed pending payload must not reuse the earlier request identity")
        XCTAssertTrue(library.snapshot.hasPendingChanges, "An old response cannot acknowledge the selected source")
        XCTAssertThrowsError(try library.acknowledge(v2, uploadedMutationId: library.snapshot.mutationId))
        library.clearRecent()
        XCTAssertTrue(library.snapshot.configuration.applicationSources.isEmpty)
    }

    func testSourceValidationRejectsAmbiguityDanglingReferencesAndInvalidAuthorNames() throws {
        for sources in [
            [HomeApplicationSource(appId: "missing", ownerLogin: "Author")],
            [.init(appId: "cook", ownerLogin: "../other")],
            [.init(appId: "cook", ownerLogin: " Author")],
            [.init(appId: "cook", ownerLogin: "Author"), .init(appId: "cook", ownerLogin: "Other")],
        ] {
            let content = HomeConfiguration(installedApps: [.init(appId: "cook")], applicationSources: sources)
            XCTAssertThrowsError(try content.validate())
        }
        let content = HomeConfiguration(installedApps: [.init(appId: "cook")], applicationSources: [.init(appId: "cook", ownerLogin: "Author")])
        XCTAssertThrowsError(try RemoteHomeScreen(schemaVersion: 2, revision: String(repeating: "a", count: 64), configuration: content).validate())
        var snapshot = HomeLibrarySnapshot(); snapshot.configuration = content
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var invalid = try XCTUnwrap(json["configuration"] as? [String: Any]); invalid.removeValue(forKey: "applicationSources")
        json["configuration"] = invalid
        XCTAssertThrowsError(try JSONDecoder().decode(HomeLibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    func testMigrationCannotOverwriteAChangedOldFileAndCanRetryAfterRestoringThatFile() throws {
        let data = Data(#"{"version":1,"applications":[{"_id":"cook","name":"作者版本","personalMarketOwnerLogin":"Author"}],"recentIDs":[]}"#.utf8)
        let file = HomeLibrary(directory: directory).fileURL
        try data.write(to: file)
        let library = HomeLibrary(directory: directory)
        let initial = library.snapshot
        let changed = Data("a different writer's data".utf8)
        try changed.write(to: file)
        library.setDockVisible(true)
        XCTAssertNotNil(library.storageError)
        XCTAssertEqual(library.snapshot, initial)
        XCTAssertEqual(try Data(contentsOf: file), changed)
        try data.write(to: file)
        library.setDockVisible(true)
        XCTAssertNil(library.storageError)
        XCTAssertTrue(library.snapshot.dockVisible)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".before-native-migration-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), data)
    }
}
