import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class WebProfileRepositoryTests: XCTestCase {
    private var directory: URL!
    private var pages: [WKWebView] = []
    private var ownership: StorageFixtureOwnership!
    private var window: UIWindow?
    private weak var previousWindow: UIWindow?
    private var file: URL { directory.appendingPathComponent("profiles.json") }
    private var app: CloudApplication {
        CloudApplication(id: "profile-fixture", name: "Profile fixture", websiteUrl: "https://profiles.invalid/app")
    }
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebProfiles-" + UUID().uuidString)
        ownership = StorageFixtureOwnership(directory: directory, label: "web-profile-repository")
    }
    override func tearDown() async throws {
        // The test method's local references have left their async frame.
        // Release the remaining WebViews before requesting whole-store removal.
        pages.forEach { $0.stopLoading(); $0.removeFromSuperview() }
        pages.removeAll()
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        previousWindow?.makeKey()
        await Task.yield()
        await ownership.cleanup()
    }
    private func repository(namespace: String = "provider-a") -> WebProfileRepository {
        WebProfileRepository(fileURL: file, namespace: namespace)
    }

    func testAccountsGuestAndProvidersRemainSeparateAfterRepositoryRecreation() throws {
        let first = repository()
        let a = try first.select(.account("account-a"), application: app)
        let b = try first.select(.account("account-b"), application: app)
        let guest = try first.select(.guest, application: app)
        let namedGuest = try first.select(.account("guest"), application: app)
        let providerB = try repository(namespace: "provider-b").select(.account("account-a"), application: app)
        XCTAssertEqual(Set([a.identifier, b.identifier, guest.identifier, namedGuest.identifier, providerB.identifier]).count, 5)
        XCTAssertEqual(try repository().select(.account("account-a"), application: app), a)
        XCTAssertEqual(try repository().select(.guest, application: app), guest)
        XCTAssertEqual(try repository(namespace: "provider-b").select(.account("account-a"), application: app), providerB)
    }

    func testApplicationOriginAndTrustScopeAreBoundWithoutPersistingURLSecrets() throws {
        let repo = repository()
        let original = try repo.select(.account("account-a"), application: app)
        var revision = app
        revision.websiteUrl = "https://profiles.invalid:443/new-path?ticket=private-query#fragment"
        XCTAssertEqual(try repo.select(.account("account-a"), application: revision), original)
        revision.websiteUrl = "https://different.invalid/app"
        let origin = try repo.select(.account("account-a"), application: revision)
        revision = app; revision.personalMarketOwnerLogin = "Author"
        let personal = try repo.select(.account("account-a"), application: revision)
        revision = CloudApplication(id: "another-application", name: "Other", websiteUrl: app.websiteUrl)
        let other = try repo.select(.account("account-a"), application: revision)
        XCTAssertEqual(Set([original.identifier, origin.identifier, personal.identifier, other.identifier]).count, 4)
        let text = try String(contentsOf: file, encoding: .utf8)
        for raw in ["account-a", "provider-a", "profile-fixture", "private-query", "profiles.invalid", "Author"] {
            XCTAssertFalse(text.contains(raw), "Metadata must not retain raw account identifiers or URL values")
        }
    }

    func testGuestLoginAdoptsOnlyTheAcceptedApplicationAndRotatesItsGuestAssignment() throws {
        let repo = repository()
        let guest = try repo.select(.guest, application: app)
        let other = CloudApplication(id: "another-application", name: "Other", websiteUrl: app.websiteUrl)
        let otherGuest = try repo.select(.guest, application: other)
        let result = try repo.bindGuestContinuation(guest, to: "account-a")
        guard case .adopted(let adopted) = result else { return XCTFail("First login must preserve the live store") }
        XCTAssertEqual(adopted.identifier, guest.identifier)
        XCTAssertEqual(try repository().select(.account("account-a"), application: app), adopted)
        XCTAssertNotEqual(try repo.select(.guest, application: app).identifier, guest.identifier)
        XCTAssertEqual(try repo.select(.guest, application: other), otherGuest)
        XCTAssertNotEqual(try repo.select(.account("account-b"), application: app).identifier, guest.identifier)
    }

    func testReturningAccountPreservesItsExistingDraftsAndRetainsGuestContinuation() throws {
        let repo = repository()
        let existing = try repo.select(.account("account-a"), application: app)
        let guest = try repo.select(.guest, application: app)
        let result = try repo.bindGuestContinuation(guest, to: "account-a")
        guard case .retained(let continuation, let kept) = result else { return XCTFail("Existing data must not be replaced") }
        XCTAssertEqual(kept, existing)
        XCTAssertEqual(continuation.identifier, guest.identifier)
        XCTAssertEqual(try repository().select(.account("account-a"), application: app), existing)
        XCTAssertEqual(try repository().retained(for: .account("account-a"), application: app), [continuation])
        XCTAssertTrue(try repo.retained(for: .account("account-b"), application: app).isEmpty)
        XCTAssertTrue(try repo.retained(for: .guest, application: app).isEmpty)
        XCTAssertNotEqual(try repo.select(.guest, application: app).identifier, continuation.identifier)
    }

    func testStaleGuestPageCannotRebindOrConsumeANewerGuestsAssignment() throws {
        let repo = repository()
        let guest = try repo.select(.guest, application: app)
        _ = try repo.bindGuestContinuation(guest, to: "account-a")
        let replacement = try repo.select(.guest, application: app)
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try repo.bindGuestContinuation(guest, to: "account-b")) {
            XCTAssertEqual($0 as? WebProfileRepository.Failure, .staleSelection)
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try repo.select(.guest, application: app), replacement)
        let authenticated = try repo.select(.account("account-a"), application: app)
        XCTAssertThrowsError(try repo.bindGuestContinuation(authenticated, to: "account-b"))
    }

    func testRemovingAccountRetainsDataWithoutExposingItToGuestOrAnotherAccount() throws {
        let repo = repository()
        let a = try repo.select(.account("account-a"), application: app)
        let b = try repo.select(.account("account-b"), application: app)
        let guest = try repo.select(.guest, application: app)
        try repo.retire("account-a")
        try repo.retire("account-a")
        XCTAssertEqual(try repository().retained(for: .account("account-a"), application: app), [a])
        XCTAssertTrue(try repo.retained(for: .account("account-b"), application: app).isEmpty)
        XCTAssertEqual(try repo.select(.account("account-b"), application: app), b)
        XCTAssertEqual(try repo.select(.guest, application: app), guest)
        XCTAssertNotEqual(try repo.select(.account("account-a"), application: app).identifier, a.identifier)
    }

    func testWriteFailureCannotPublishGuestOwnershipTransfer() throws {
        let repo = repository()
        let guest = try repo.select(.guest, application: app)
        let before = try Data(contentsOf: file)
        let failing = WebProfileRepository(fileURL: file, namespace: "provider-a") { _, _ in throw FixtureFailure.write }
        XCTAssertThrowsError(try failing.bindGuestContinuation(guest, to: "account-a"))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try repo.select(.guest, application: app), guest)
        guard case .adopted(let adopted) = try repo.bindGuestContinuation(guest, to: "account-a") else {
            return XCTFail("Retry must retain the original guest store")
        }
        XCTAssertEqual(adopted.identifier, guest.identifier)
    }

    func testWriteFailureDuringRemovalPreservesEveryAssignment() throws {
        let repo = repository()
        let a = try repo.select(.account("account-a"), application: app)
        let before = try Data(contentsOf: file)
        let failing = WebProfileRepository(fileURL: file, namespace: "provider-a") { _, _ in throw FixtureFailure.write }
        XCTAssertThrowsError(try failing.retire("account-a"))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try repo.select(.account("account-a"), application: app), a)
        XCTAssertTrue(try repo.retained(for: .account("account-a"), application: app).isEmpty)
    }

    func testTwoRepositoryInstancesReloadBeforeMutationInsteadOfLosingAssignments() throws {
        let first = repository(), second = repository()
        let a = try first.select(.account("account-a"), application: app)
        let b = try second.select(.account("account-b"), application: app)
        let guest = try first.select(.guest, application: app)
        XCTAssertEqual(try second.select(.account("account-a"), application: app), a)
        XCTAssertEqual(try first.select(.account("account-b"), application: app), b)
        XCTAssertEqual(try repository().select(.guest, application: app), guest)
    }

    func testCorruptFutureAndDuplicateOwnershipFilesArePreservedAndRejected() throws {
        _ = try repository().select(.guest, application: app)
        let original = try Data(contentsOf: file)
        var duplicate = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let active = try XCTUnwrap(duplicate["active"] as? [String: String])
        let key = try XCTUnwrap(active.keys.first), id = try XCTUnwrap(active[key])
        duplicate["retained"] = [key: [id]]
        let cases = [Data("not-json".utf8), Data("{\"version\":2,\"active\":{},\"retained\":{}}".utf8),
                     try JSONSerialization.data(withJSONObject: duplicate)]
        for data in cases {
            try data.write(to: file, options: .atomic)
            XCTAssertThrowsError(try repository().select(.account("account-a"), application: app))
            XCTAssertEqual(try Data(contentsOf: file), data, "Invalid metadata must not be reset or replaced")
        }
    }

    func testInvalidIdentityDoesNotCreateMetadataAndMissingStateNeverAdoptsLegacyData() throws {
        XCTAssertThrowsError(try repository().select(.account(" "), application: app))
        XCTAssertThrowsError(try repository(namespace: "").select(.guest, application: app))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let selected = try repository().select(.account("account-a"), application: app)
        XCTAssertNotEqual(selected.identifier, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertTrue(try repository().retained(for: .account("account-a"), application: app).isEmpty)
    }

    func testReadingRecoveryChoicesDoesNotCreateAnAssignmentOrFile() throws {
        let state = try repository().snapshot(for: .account("a"), application: app)
        XCTAssertNil(state.active); XCTAssertTrue(state.retained.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExplicitRecoverySwapsStoresAndPreservesTheDisplacedData() throws {
        let repo = repository()
        let original = try repo.select(.account("a"), application: app)
        try repo.retire("a")
        let current = try repo.select(.account("a"), application: app)
        try repo.activateRetained(original, accountID: "a", application: app, replacing: current)
        XCTAssertEqual(try repository().snapshot(for: .account("a"), application: app),
                       .init(active: original, retained: [current]))
        try repo.activateRetained(current, accountID: "a", application: app, replacing: original)
        XCTAssertEqual(try repository().snapshot(for: .account("a"), application: app),
                       .init(active: current, retained: [original]))
    }

    func testRecoveryRejectsForeignAccountApplicationProviderAndStaleConfirmation() throws {
        let repo = repository()
        let original = try repo.select(.account("a"), application: app)
        try repo.retire("a")
        let current = try repo.select(.account("a"), application: app)
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try repo.activateRetained(original, accountID: "b", application: app, replacing: nil))
        let other = CloudApplication(id: "other", name: "Other", websiteUrl: app.websiteUrl)
        XCTAssertThrowsError(try repo.activateRetained(original, accountID: "a", application: other, replacing: nil))
        XCTAssertThrowsError(try repository(namespace: "another-provider").activateRetained(original, accountID: "a", application: app, replacing: current))
        XCTAssertThrowsError(try repo.activateRetained(original, accountID: "a", application: app, replacing: nil))
        XCTAssertEqual(try Data(contentsOf: file), before)
        try repo.activateRetained(original, accountID: "a", application: app, replacing: current)
        let changed = try Data(contentsOf: file)
        XCTAssertThrowsError(try repo.activateRetained(original, accountID: "a", application: app, replacing: current))
        XCTAssertEqual(try Data(contentsOf: file), changed)
    }

    func testRecoveryWriteFailurePreservesBothAssignmentsAndAllowsRetry() throws {
        let repo = repository()
        let original = try repo.select(.account("a"), application: app)
        try repo.retire("a")
        let before = try Data(contentsOf: file)
        let failing = WebProfileRepository(fileURL: file, namespace: "provider-a") { _, _ in throw FixtureFailure.write }
        XCTAssertThrowsError(try failing.activateRetained(original, accountID: "a", application: app, replacing: nil))
        XCTAssertEqual(try Data(contentsOf: file), before)
        try repo.activateRetained(original, accountID: "a", application: app, replacing: nil)
        XCTAssertEqual(try repo.snapshot(for: .account("a"), application: app), .init(active: original, retained: []))
    }

    func testActualWebKitStoresKeepAccountDataAfterRecreatingRepositoryAndBrowser() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent WebKit stores require iOS 17") }
        let a = try await page(repository().select(.account("account-a"), application: app))
        let savedA = try await contents(a, writing: "account-a")
        XCTAssertEqual(savedA, ["local": "account-a", "draft": "account-a", "cookie": "account-a"])
        let b = try await page(repository().select(.account("account-b"), application: app))
        let emptyB = try await contents(b)
        XCTAssertEqual(emptyB, ["local": "", "draft": "", "cookie": ""])
        _ = try await contents(b, writing: "account-b")
        let recreatedA = try await page(repository().select(.account("account-a"), application: app))
        let restoredA = try await contents(recreatedA)
        XCTAssertEqual(restoredA, savedA)
        let recreatedB = try await page(repository().select(.account("account-b"), application: app))
        let restoredB = try await contents(recreatedB)
        XCTAssertEqual(restoredB, ["local": "account-b", "draft": "account-b", "cookie": "account-b"])
    }

    func testActualGuestContinuationRetainsBothStoresWhenAccountAlreadyHasData() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent WebKit stores require iOS 17") }
        let existing = try repository().select(.account("account-a"), application: app)
        let existingPage = try await page(existing)
        _ = try await contents(existingPage, writing: "previous-account-draft")
        let guest = try repository().select(.guest, application: app)
        let guestPage = try await page(guest)
        _ = try await contents(guestPage, writing: "continuation-draft")
        guard case .retained(let continuation, _) = try repository().bindGuestContinuation(guest, to: "account-a") else {
            return XCTFail("Both existing persistent stores must be retained")
        }
        let newGuest = try await page(repository().select(.guest, application: app))
        let emptyGuest = try await contents(newGuest)
        XCTAssertEqual(emptyGuest, ["local": "", "draft": "", "cookie": ""])
        let reopenedAccount = try await page(repository().select(.account("account-a"), application: app))
        let previous = try await contents(reopenedAccount)
        XCTAssertEqual(previous, ["local": "previous-account-draft", "draft": "previous-account-draft", "cookie": "previous-account-draft"])
        let retained = try XCTUnwrap(repository().retained(for: .account("account-a"), application: app).first)
        XCTAssertEqual(retained, continuation)
        let reopenedContinuation = try await page(retained)
        let draft = try await contents(reopenedContinuation)
        XCTAssertEqual(draft, ["local": "continuation-draft", "draft": "continuation-draft", "cookie": "continuation-draft"])
        try repository().activateRetained(retained, accountID: "account-a", application: app, replacing: existing)
        let restoredPage = try await page(repository().select(.account("account-a"), application: app))
        let restoredDraft = try await contents(restoredPage)
        XCTAssertEqual(restoredDraft, draft)
        let displaced = try XCTUnwrap(repository().retained(for: .account("account-a"), application: app).first)
        let displacedPage = try await page(displaced)
        let displacedDraft = try await contents(displacedPage)
        XCTAssertEqual(displacedDraft, previous)
    }

    @available(iOS 17, *)
    private func page(_ selected: WebProfileRepository.Selection) async throws -> WKWebView {
        // Record ownership before creating the store, including navigation failures.
        try ownership.record(selected.identifier)
        let config = WKWebViewConfiguration()
        // Previously visited pages remain alive for exact fixture cleanup.
        config.preferences.inactiveSchedulingPolicy = .none
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: selected.identifier)
        let web = WKWebView(frame: .zero, configuration: config)
        pages.append(web)
        if window == nil {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previousWindow = scene.windows.first(where: \.isKeyWindow)
            let host = UIWindow(windowScene: scene)
            host.rootViewController = UIViewController()
            host.makeKeyAndVisible()
            window = host
        }
        let host = try XCTUnwrap(window?.rootViewController?.view)
        host.subviews.forEach { $0.removeFromSuperview() }
        web.frame = host.bounds; web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(web)
        try await WebStoragePageFixture.load(in: web, origin: URL(string: "https://profiles.invalid/")!, title: "profile-probe")
        return web
    }

    private func contents(_ web: WKWebView, writing value: String? = nil) async throws -> [String: String] {
        try await WebStoragePageFixture.evaluate(in: web, script: """
        const key = 'profile_test_draft';
        const db = await new Promise((resolve, reject) => {
          const r = indexedDB.open(key, 1);
          r.onupgradeneeded = () => r.result.createObjectStore('drafts');
          r.onsuccess = () => resolve(r.result); r.onerror = () => reject(new Error('open'));
        });
        try {
          if (value !== null) {
            localStorage.setItem(key, value);
            document.cookie = key + '=' + value + '; path=/; Secure; SameSite=Lax';
            await new Promise((resolve, reject) => {
              const tx = db.transaction('drafts', 'readwrite'); tx.objectStore('drafts').put(value, 'draft');
              tx.oncomplete = resolve; tx.onerror = tx.onabort = () => reject(new Error('write'));
            });
          }
          const draft = await new Promise((resolve, reject) => {
            const r = db.transaction('drafts').objectStore('drafts').get('draft');
            r.onsuccess = () => resolve(r.result ?? ''); r.onerror = () => reject(new Error('read'));
          });
          return { local: localStorage.getItem(key) || '', draft,
            cookie: document.cookie.split('; ').find(x => x.startsWith(key + '='))?.split('=')[1] || '' };
        } finally { db.close(); }
        """, arguments: ["value": value as Any? ?? NSNull()]) as? [String: String] ?? [:]
    }

    private enum FixtureFailure: Error { case write }
}

/// Shared only by the two storage regression fixtures. Never discovers cleanup
/// targets by enumerating unrelated stores; every target is recorded at creation.
@MainActor
final class StorageFixtureOwnership {
    let directory: URL
    private let label: String
    private var identifiers = Set<UUID>()
    private var cleaned = false

    init(directory: URL, label: String) {
        self.directory = directory
        self.label = label
    }

    func record(_ identifier: UUID) throws {
        guard identifiers.insert(identifier).inserted else { return }
        try persist()
    }

    /// A runtime can create its profile before presenting a browser. Observe the
    /// fixture's own repository writes so an early presentation failure is owned.
    func writeProfiles(_ data: Data, to url: URL) throws {
        struct Profiles: Decodable {
            let active: [String: UUID]
            let retained: [String: [UUID]]
        }
        let profiles = try JSONDecoder().decode(Profiles.self, from: data)
        for identifier in Array(profiles.active.values) + profiles.retained.values.flatMap({ $0 }) {
            try record(identifier)
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func cleanup() async {
        guard !cleaned else { return }
        cleaned = true
        var failures: [String] = []
        if #available(iOS 17, *), !identifiers.isEmpty {
            do {
                let keeper = try await StorageFixtureStoreCleanup.initializedKeeper()
                defer { keeper.stopLoading() }
                // Repository metadata may name a store before WebKit creates it.
                // An API-confirmed absent owned ID needs no removal request.
                let existing = try await StorageFixtureStoreCleanup.identifiers()
                for identifier in existing.intersection(identifiers).sorted(by: { $0.uuidString < $1.uuidString }) {
                    do { try await StorageFixtureStoreCleanup.remove(identifier) }
                    catch { failures.append("\(identifier.uuidString): \(error)") }
                }
                let remaining = try await StorageFixtureStoreCleanup.identifiers().intersection(identifiers)
                if !remaining.isEmpty {
                    failures.append("Owned stores still exist: \(remaining.map(\.uuidString).sorted().joined(separator: ","))")
                }
            } catch { failures.append("WebKit cleanup initialization/enumeration: \(error)") }
        }
        if failures.isEmpty {
            do {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            } catch { failures.append("Owned directory removal: \(error)") }
        }
        guard !failures.isEmpty else { return }
        // Keep both the repository and the independent UUID list until a later
        // allowlisted recovery confirms deletion. A timeout is never success.
        try? persist()
        XCTContext.runActivity(named: "Preserved \(label) fixture ownership") { activity in
            let attachment = XCTAttachment(string: "label=\(label)\ndirectory=\(directory.path)\nprofiles=\(identifiers.map(\.uuidString).sorted().joined(separator: ","))\nfailures=\(failures.joined(separator: "\n"))")
            attachment.name = "\(label)-cleanup-ownership"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTFail("\(label) fixture cleanup failed; ownership preserved: \(failures.joined(separator: "; "))")
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: [
            "kind": "owned-storage-regression-fixture", "label": label,
            "directory": directory.path, "profiles": identifiers.map(\.uuidString).sorted()
        ], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("fixture-store-ownership.json"),
                       options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

@available(iOS 17, *)
@MainActor
private enum StorageFixtureStoreCleanup {
    private static var initializationKeeper: WKWebView?

    static func initializedKeeper() async throws -> WKWebView {
        if let initializationKeeper { return initializationKeeper }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let keeper = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        // Fixed HTML with no external resources initializes WebKit without any
        // network request or named profile before the identifier APIs are used.
        try await WebStoragePageFixture.load(in: keeper, origin: URL(string: "https://storage-cleanup.invalid/")!,
                                             title: "Storage fixture cleanup keeper")
        initializationKeeper = keeper
        return keeper
    }

    static func remove(_ identifier: UUID) async throws {
        var lastFailure: Error = URLError(.unknown)
        let deadline = Date().addingTimeInterval(30)
        for seconds in [0, 1, 2, 4, 8, 8] {
            guard deadline.timeIntervalSinceNow > Double(seconds) else { break }
            if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) }
            do {
                try await removeOnce(identifier, timeout: deadline.timeIntervalSinceNow)
                return
            } catch {
                lastFailure = error
                if (error as? URLError)?.code == .timedOut { throw error }
            }
        }
        throw lastFailure
    }

    static func identifiers() async throws -> Set<UUID> {
        let completion = StorageFixtureCleanupCallback<[UUID]>()
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { completion.value = $0 }
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let result = completion.value { return Set(result) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }

    private static func removeOnce(_ identifier: UUID, timeout: TimeInterval) async throws {
        let completion = StorageFixtureCleanupCallback<Result<Void, Error>>()
        let started = ProcessInfo.processInfo.systemUptime
        WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
            completion.value = error.map(Result.failure) ?? .success(())
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            print("STORAGE_FIXTURE_STORE_REMOVAL id=\(identifier.uuidString) elapsed-ms=\(elapsed) success=\(error == nil)")
        }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline {
            if let result = completion.value { return try result.get() }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }
}

@MainActor
private final class StorageFixtureCleanupCallback<Value> {
    var value: Value?
}
