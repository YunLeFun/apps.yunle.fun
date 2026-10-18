import SwiftUI
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class LegacyImportTests: XCTestCase {
    func testOldStorageContractPreservesLayoutAndAccountHintsWithoutAuthenticating() throws {
        let data = try LegacyLocalData(values: legacyValues())
        XCTAssertEqual(data.configuration?.installedApps.map(\.appId), ["air-conditioner", "missing-old-app"])
        XCTAssertEqual(data.configuration?.dockApps.map(\.appId), ["air-conditioner"])
        XCTAssertEqual(data.configuration?.recentApps.first?.usedAt, 1_790_000_000_123)
        XCTAssertEqual(data.accounts.map(\.label), ["旧版样例账号"])
        XCTAssertEqual(data.appearance, "dark"); XCTAssertEqual(data.syncEnabled, false)
        XCTAssertEqual(data, try JSONDecoder().decode(LegacyLocalData.self, from: JSONEncoder().encode(data)))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(data), as: UTF8.self).contains("ignored-fixture-value"))
        var reordered: [String: String] = [:]
        for key in data.values.keys.sorted(by: >) { reordered[key] = data.values[key] }
        XCTAssertEqual(data.id, try LegacyLocalData(values: reordered).id)
    }

    func testMalformedStorageCannotEraseOrGrantNativeData() throws {
        let invalid = [
            ["ylf_access_token": "never-import-credential"],
            ["ylf:homescreen-apps": "broken"],
            ["ylf:homescreen-apps": #"[{"appId":"a"},{"appId":"a"}]"#],
            ["ylf:dock-apps": #"[{"appId":"a"},{"appId":"b"},{"appId":"c"},{"appId":"d"},{"appId":"e"}]"#],
            ["ylf:recent-apps-v2": #"[{"appId":"a","usedAt":-1}]"#],
            ["ylf:cloud-sync-enabled": "yes"], ["ylf_theme_mode": "unknown"],
            ["ylf_saved_accounts": #"[{"uid":"","nickname":"invalid"}]"#],
            ["ylf:preview-window-size": String(repeating: "x", count: 524_289)]
        ]
        for values in invalid { XCTAssertThrowsError(try LegacyLocalData(values: values)) }
    }

    func testDiscoverStagesProtectedCopyAndLeavesNativeHomeUntouched() async throws {
        let f = try Fixture(); defer { f.close() }
        f.library.add(CloudApplication(id: "native", name: "新云居"))
        await f.store.load()
        XCTAssertEqual(f.library.snapshot.applications.map(\.id), ["native"])
        XCTAssertNil(f.store.archive?.claim); XCTAssertNotNil(f.store.archive)
        XCTAssertNil(f.accounts.user)
        let archived = try JSONDecoder().decode(LegacyImportArchive.self, from: Data(contentsOf: f.archiveURL))
        XCTAssertEqual(archived.record, f.store.archive?.record)
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: f.archiveURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUnlessOpen)
        #endif
        XCTAssertEqual(f.reader.reads, 1)
    }

    func testImportPreservesReferencesPreferencesAndBackupAcrossRestart() async throws {
        let f = try Fixture(); defer { f.close() }
        f.library.add(CloudApplication(id: "native", name: "原来的应用"))
        f.library.updateCatalog([CloudApplication(id: "market-id", name: "云空调", marketShortName: "air-conditioner", websiteUrl: "https://runtime.invalid/")])
        let before = f.library.snapshot
        await f.store.load()
        f.store.apply(try XCTUnwrap(f.store.confirmation()))
        XCTAssertTrue(f.store.archive?.claim?.completed == true)
        XCTAssertEqual(f.library.snapshot.configuration, f.store.archive?.record.configuration)
        XCTAssertEqual(f.library.snapshot.applications.first?.id, "market-id")
        XCTAssertEqual(f.library.snapshot.applications.first?.homeKey, "air-conditioner")
        XCTAssertEqual(f.library.snapshot.applications.last?.isUnavailable, true)
        XCTAssertFalse(f.library.snapshot.syncEnabled); XCTAssertFalse(f.library.snapshot.autoSyncEnabled)
        XCTAssertTrue(f.library.snapshot.dockVisible)
        XCTAssertEqual(f.preferences.string(forKey: "appearance"), "dark")
        XCTAssertTrue(f.library.snapshot.hasPendingChanges)
        let backup = f.library.fileURL.deletingPathExtension().appendingPathExtension("before-legacy-\(try XCTUnwrap(f.store.archive).record.id).json")
        XCTAssertEqual(try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: backup)), before)
        let restarted = HomeLibrary(directory: f.homeDirectory)
        XCTAssertEqual(restarted.snapshot, f.library.snapshot)
        let next = f.newStore(library: restarted)
        await next.load()
        XCTAssertTrue(next.archive?.claim?.completed == true)
        XCTAssertEqual(f.reader.reads, 1, "A protected staged copy, not a changed browser record, controls retries")
    }

    func testCompletedImportCannotOverwriteLaterHomeEdits() async throws {
        let f = try Fixture(); defer { f.close() }
        await f.store.load(); let confirmation = try XCTUnwrap(f.store.confirmation())
        f.store.apply(confirmation)
        f.library.add(CloudApplication(id: "later", name: "导入之后的编辑"))
        let later = f.library.snapshot
        f.store.apply(confirmation)
        XCTAssertEqual(f.library.snapshot, later)
        XCTAssertNil(f.store.confirmation())
    }

    func testInterruptedCompletionDoesNotReplaceEditsMadeAfterHomeCommit() async throws {
        let f = try Fixture(); defer { f.close() }
        let record = try LegacyLocalData(values: legacyValues())
        try f.write(LegacyImportArchive(record: record, claim: .init(accountID: nil)))
        try f.library.importLegacy(record, expectedGeneration: f.library.generation)
        f.library.add(CloudApplication(id: "after-commit", name: "写入完成后的编辑"))
        let edited = f.library.snapshot
        await f.store.load(); f.store.apply(try XCTUnwrap(f.store.confirmation()))
        XCTAssertTrue(f.store.archive?.claim?.completed == true)
        XCTAssertEqual(f.library.snapshot, edited)
        XCTAssertEqual(f.preferences.string(forKey: "appearance"), "dark")
    }

    func testConfirmationRejectsAccountRoundTripAndGuestTransition() async throws {
        let f = try Fixture(); defer { f.close() }
        await f.store.load(); let confirmation = try XCTUnwrap(f.store.confirmation())
        f.accounts.select("alice"); f.library.activateAccount("alice")
        f.accounts.select(nil); f.library.activateAccount(nil)
        f.store.apply(confirmation)
        XCTAssertNotNil(f.store.error); XCTAssertNil(f.store.archive?.claim)
        XCTAssertTrue(f.library.snapshot.configuration.installedApps.isEmpty)
    }

    func testInterruptedClaimOnlyResumesForOriginalAccountAndKeepsCloudBase() async throws {
        let f = try Fixture(); defer { f.close() }
        let record = try LegacyLocalData(values: legacyValues())
        try f.write(LegacyImportArchive(record: record, claim: .init(accountID: "alice")))
        f.accounts.select("bob"); f.library.activateAccount("bob")
        await f.store.load()
        XCTAssertNil(f.store.confirmation()); XCTAssertFalse(f.store.belongsToCurrentTarget)
        XCTAssertNil(f.store.visibleArchive, "A different account must not receive the claimed layout or old account hints")
        XCTAssertTrue(f.library.snapshot.applications.isEmpty)
        f.accounts.select("alice"); f.library.activateAccount("alice")
        XCTAssertNotNil(f.store.visibleArchive)
        let remote = RemoteHomeScreen(revision: String(repeating: "a", count: 64), configuration: HomeConfiguration(installedApps: [.init(appId: "cloud")]))
        try f.library.adopt(remote)
        f.store.apply(try XCTUnwrap(f.store.confirmation()))
        XCTAssertEqual(f.library.snapshot.base, remote, "Existing cloud revision remains subject to normal conflict checks")
        XCTAssertEqual(f.store.archive?.claim?.accountID, "alice")
        f.accounts.select("bob"); f.library.activateAccount("bob")
        XCTAssertTrue(f.library.snapshot.applications.isEmpty)
    }

    func testHomeWriteFailureKeepsClaimAndCanResumeAfterRepair() async throws {
        let f = try Fixture(); defer { f.close() }
        f.library.add(CloudApplication(id: "native", name: "原云居"))
        let original = try Data(contentsOf: f.library.fileURL)
        try FileManager.default.removeItem(at: f.library.fileURL)
        try FileManager.default.createDirectory(at: f.library.fileURL, withIntermediateDirectories: true)
        await f.store.load(); f.store.apply(try XCTUnwrap(f.store.confirmation()))
        XCTAssertNotNil(f.store.error); XCTAssertEqual(f.library.snapshot.applications.map(\.id), ["native"])
        XCTAssertFalse(try XCTUnwrap(f.store.archive?.claim).completed)
        XCTAssertNil(f.preferences.string(forKey: "appearance"))
        try FileManager.default.removeItem(at: f.library.fileURL); try original.write(to: f.library.fileURL)
        f.store.apply(try XCTUnwrap(f.store.confirmation()))
        XCTAssertTrue(f.store.archive?.claim?.completed == true)
        XCTAssertEqual(f.library.snapshot.configuration.installedApps.map(\.appId), ["air-conditioner", "missing-old-app"])
    }

    func testArchiveFailureAndCorruptionNeverFallBackToReplacingData() async throws {
        let f = try Fixture(); defer { f.close() }
        try FileManager.default.createDirectory(at: f.archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupted existing archive".utf8).write(to: f.archiveURL)
        await f.store.load()
        XCTAssertNotNil(f.store.error); XCTAssertNil(f.store.archive); XCTAssertEqual(f.reader.reads, 0)
        XCTAssertEqual(f.store.error, LegacyImportError.invalidData.localizedDescription)
        XCTAssertEqual(try String(contentsOf: f.archiveURL), "corrupted existing archive")
        try FileManager.default.removeItem(at: f.archiveURL.deletingLastPathComponent())
        try Data("blocking file".utf8).write(to: f.archiveURL.deletingLastPathComponent())
        await f.store.load(retry: true)
        XCTAssertNotNil(f.store.error); XCTAssertNil(f.library.snapshot.legacyImportID)
    }

    func testFailedArchiveReloadInvalidatesPreviouslyDisplayedConfirmation() async throws {
        let f = try Fixture(); defer { f.close() }
        await f.store.load(); let confirmation = try XCTUnwrap(f.store.confirmation())
        try Data("corrupt-on-reload".utf8).write(to: f.archiveURL)
        await f.store.load(retry: true)
        XCTAssertFalse(f.store.isLoaded); XCTAssertNil(f.store.confirmation())
        f.store.apply(confirmation)
        XCTAssertNil(f.library.snapshot.legacyImportID)
        XCTAssertEqual(try String(contentsOf: f.archiveURL), "corrupt-on-reload")
    }

    func testAnotherImporterCannotReassignAnAlreadyClaimedRecord() async throws {
        let f = try Fixture(); defer { f.close() }
        let earlier = f.newStore(); await earlier.load()
        await f.store.load(); f.store.apply(try XCTUnwrap(f.store.confirmation()))
        f.accounts.select("bob"); f.library.activateAccount("bob")
        let stale = earlier.confirmation()
        XCTAssertNil(stale)
        if let stale { earlier.apply(stale) }
        XCTAssertTrue(f.library.snapshot.applications.isEmpty)
        let saved = try JSONDecoder().decode(LegacyImportArchive.self, from: Data(contentsOf: f.archiveURL))
        XCTAssertNil(saved.claim?.accountID); XCTAssertTrue(saved.claim?.completed == true)
    }

    func testLateReaderCannotReplaceAnImportCompletedByAnotherWindow() async throws {
        let f = try Fixture(); defer { f.close() }
        f.reader.delay = true
        let late = f.newStore()
        let loading = Task { await late.load() }
        try await Task.sleep(nanoseconds: 30_000_000)
        f.reader.delay = false
        await f.store.load(); f.store.apply(try XCTUnwrap(f.store.confirmation()))
        await loading.value
        let saved = try JSONDecoder().decode(LegacyImportArchive.self, from: Data(contentsOf: f.archiveURL))
        XCTAssertTrue(saved.claim?.completed == true)
        XCTAssertTrue(late.archive?.claim?.completed == true)
    }

    func testConfirmRechecksArchiveIntegrityWithoutAnExplicitReload() async throws {
        let f = try Fixture(); defer { f.close() }
        await f.store.load(); let confirmation = try XCTUnwrap(f.store.confirmation())
        try Data("corrupt-after-review".utf8).write(to: f.archiveURL)
        f.store.apply(confirmation)
        XCTAssertNil(f.library.snapshot.legacyImportID)
        XCTAssertEqual(try String(contentsOf: f.archiveURL), "corrupt-after-review")
    }

    func testCancelledReadDoesNotStageOrPublishPartialData() async throws {
        let f = try Fixture(); defer { f.close() }
        f.reader.delay = true
        let work = Task { await f.store.load() }
        try await Task.sleep(nanoseconds: 30_000_000); work.cancel(); await work.value
        XCTAssertNil(f.store.error); XCTAssertNil(f.store.archive); XCTAssertFalse(f.store.isLoaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.archiveURL.path))
        f.reader.delay = false; await f.store.load()
        XCTAssertNotNil(f.store.archive)
    }

    func testRealWebKitReaderFindsNoLegacyDataInFreshStore() async throws {
        let reader = LegacyLocalDataReader(dataStore: .nonPersistent())
        let values = try await reader.read()
        XCTAssertTrue(values.isEmpty)
    }

    func testRealWebKitReaderUsesSameOriginAndNeverReadsCredentialKeys() async throws {
        try await verifyRealWebKitReader(dataStore: .nonPersistent())
    }

    func testRealPersistentWebKitRecordsAreNotMistakenForEmptyStorage() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Named isolated persistent WebKit stores require iOS 17") }
        let id = UUID()
        var failure: Error?
        do { try await verifyRealWebKitReader(dataStore: WKWebsiteDataStore(forIdentifier: id)) }
        catch { failure = error }
        var cleanupError: Error?
        for attempt in 0..<100 {
            cleanupError = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.remove(forIdentifier: id) { continuation.resume(returning: $0) }
            }
            guard let issue = cleanupError as NSError?, issue.domain == "WKWebSiteDataStore", issue.code == 1 else { break }
            // WebKit releases cancelled and completed views asynchronously.
            if attempt < 99 { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        XCTAssertNil(cleanupError)
        if let failure { throw failure }
    }

    private func verifyRealWebKitReader(dataStore: WKWebsiteDataStore) async throws {
        func stage(_ name: String) { XCTContext.runActivity(named: "Legacy WebKit: " + name) { _ in } }
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = dataStore
        configuration.setURLSchemeHandler(LegacyImportSchemeHandler(), forURLScheme: "capacitor")
        let old = WKWebView(frame: .zero, configuration: configuration)
        defer { old.navigationDelegate = nil; old.stopLoading() }
        let navigation = LegacyTestNavigation(); old.navigationDelegate = navigation
        stage("navigate isolated fixture")
        old.load(URLRequest(url: LegacyLocalDataReader.url))
        let ready = await XCTWaiter.fulfillment(of: [navigation.completed], timeout: 20)
        guard ready == .completed else {
            XCTFail("The real WebKit fixture must finish navigation before storage is seeded")
            throw NSError(domain: "LegacyImportTests", code: 2)
        }
        if let failure = navigation.failure { throw failure }
        XCTAssertTrue(navigation.loaded)
        var values = legacyValues(); values["ylf_access_token"] = "fixture-secret-must-stay-in-old-storage"
        stage("seed synthetic local storage")
        _ = try await old.callAsyncJavaScript("for (const [key,value] of Object.entries(values)) localStorage.setItem(key,value); return true;", arguments: ["values": values], in: nil, contentWorld: .page)
        stage("reject expired read")
        do {
            _ = try await LegacyLocalDataReader(dataStore: dataStore, timeoutNanoseconds: 1).read()
            XCTFail("The expired read must not report empty or partial data")
        } catch LegacyImportError.timedOut { }
        stage("first complete read")
        let first = try await LegacyLocalDataReader(dataStore: dataStore).read()
        stage("second complete read")
        let second = try await LegacyLocalDataReader(dataStore: dataStore).read()
        XCTAssertEqual(first, try LegacyLocalData(values: legacyValues()).values); XCTAssertEqual(second, first)
        XCTAssertFalse(first.keys.contains("ylf_access_token"))
        stage("verify original synthetic credential remains")
        let token = try await old.evaluateJavaScript("localStorage.getItem('ylf_access_token')") as? String
        stage("verify original applications remain")
        let apps = try await old.evaluateJavaScript("localStorage.getItem('ylf:homescreen-apps')") as? String
        XCTAssertEqual(token, values["ylf_access_token"]); XCTAssertEqual(apps, values["ylf:homescreen-apps"])
    }

    func testNativeImportStateScreenshots() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for state in ["review", "empty", "failure", "completed", "other-account"] {
            let f = try Fixture(); defer { f.close() }
            if state == "empty" { f.reader.values = [:] }
            if state == "failure" {
                try FileManager.default.createDirectory(at: f.archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("invalid".utf8).write(to: f.archiveURL)
            }
            if state == "other-account" {
                try f.write(LegacyImportArchive(record: LegacyLocalData(values: legacyValues()), claim: .init(accountID: "alice")))
                f.accounts.select("bob"); f.library.activateAccount("bob")
            }
            await f.store.load()
            if state == "completed" { f.store.apply(try XCTUnwrap(f.store.confirmation())) }
            let dark = state == "failure"
            let host = UIHostingController(rootView: NavigationStack { LegacyMigrationView(store: f.store) }
                .environmentObject(AccountStore(session: AccountSession(vault: BillingMemoryVault())))
                .dynamicTypeSize(dark ? .accessibility3 : .large))
            let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 200_000_000)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "legacy-import-\(state)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
        }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accounts = BillingAccounts()
        let reader = LegacyReaderFixture()
        let preferences: UserDefaults
        let suite = "LegacyImportTests." + UUID().uuidString
        let library: HomeLibrary
        var homeDirectory: URL { directory.appendingPathComponent("home") }
        var archiveURL: URL { directory.appendingPathComponent("import/record.json") }
        lazy var store = newStore()
        init() throws {
            preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            library = HomeLibrary(directory: directory.appendingPathComponent("home"))
            accounts.select(nil)
        }
        func newStore(library: HomeLibrary? = nil) -> LegacyImportStore {
            LegacyImportStore(library: library ?? self.library, accounts: accounts, reader: reader, archiveURL: archiveURL, preferences: preferences)
        }
        func write(_ archive: LegacyImportArchive) throws {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: archiveURL)
        }
        func close() { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor
private final class LegacyReaderFixture: LegacyLocalDataReading {
    var reads = 0
    var delay = false
    var values = legacyValues()
    func read() async throws -> [String: String] {
        reads += 1
        if delay { try await Task.sleep(nanoseconds: 5_000_000_000) }
        return values
    }
}

@MainActor
private final class LegacyTestNavigation: NSObject, WKNavigationDelegate {
    var loaded = false
    var failure: Error?
    let completed = XCTestExpectation(description: "The real WebKit storage fixture completed navigation")
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url == LegacyLocalDataReader.url else { return }
        complete()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { complete(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { complete(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        complete(NSError(domain: "LegacyImportTests.WebContent", code: 1))
    }
    private func complete(_ error: Error? = nil) {
        guard !loaded, failure == nil else { return }
        failure = error; loaded = error == nil; completed.fulfill()
    }
}

private func legacyValues() -> [String: String] {
    ["ylf:homescreen-apps": #"[{"appId":"air-conditioner"},{"appId":"missing-old-app"}]"#,
     "ylf:dock-apps": #"[{"appId":"air-conditioner"}]"#,
     "ylf:recent-apps-v2": #"[{"appId":"air-conditioner","usedAt":1790000000123}]"#,
     "ylf:homescreen-sync-at": "1790000000456", "ylf_theme_mode": "dark",
     "ylf:cloud-sync-enabled": "false", "ylf:cloud-auto-sync": "false", "ylf:dock-visible": "true",
     "ylf_saved_accounts": #"[{"uid":"old-fixture-uid","nickname":"旧版样例账号","access_token":"ignored-fixture-value"}]"#]
}
