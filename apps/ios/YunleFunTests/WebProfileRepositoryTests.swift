import Foundation
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class WebProfileRepositoryTests: XCTestCase {
    private var directory: URL!
    private var pages: [WKWebView] = []
    private var stores: Set<UUID> = []
    private var file: URL { directory.appendingPathComponent("profiles.json") }
    private var app: CloudApplication {
        CloudApplication(id: "profile-fixture", name: "Profile fixture", websiteUrl: "https://profiles.invalid/app")
    }
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebProfiles-" + UUID().uuidString)
    }
    override func tearDown() async throws {
        // Delete exactly the fixture's three values while its pages are alive.
        // Whole-store removal returned InvalidTransition on iOS 27; clearing
        // every WebKit data type subsequently took 88 seconds in one test.
        if #available(iOS 17, *) {
            for id in stores {
                let web = try XCTUnwrap(pages.first { $0.configuration.websiteDataStore.identifier == id })
                let cleared = try await web.callAsyncJavaScript("""
                const key = 'profile_test_draft';
                localStorage.removeItem(key);
                document.cookie = key + '=; Max-Age=0; path=/; Secure; SameSite=Lax';
                await new Promise((resolve, reject) => {
                  const timer = setTimeout(() => reject(new Error('cleanup timeout')), 5000);
                  const r = indexedDB.deleteDatabase(key);
                  r.onsuccess = () => { clearTimeout(timer); resolve(); };
                  r.onerror = () => { clearTimeout(timer); reject(new Error('cleanup')); };
                });
                const databases = await indexedDB.databases();
                return localStorage.getItem(key) === null && !document.cookie.split('; ').some(x => x.startsWith(key + '=')) &&
                  !databases.some(x => x.name === key);
                """, arguments: [:], in: nil, contentWorld: .page) as? Bool
                XCTAssertEqual(cleared, true, "All fixture identity and draft values must be deleted")
            }
        }
        pages.forEach { $0.stopLoading() }; pages.removeAll()
        stores.removeAll()
        try? FileManager.default.removeItem(at: directory)
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
        stores.insert(selected.identifier)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: selected.identifier)
        let web = WKWebView(frame: .zero, configuration: config)
        pages.append(web)
        web.loadHTMLString("<html><head><title>profile-probe</title></head><body>Profile fixture</body></html>",
                           baseURL: URL(string: "https://profiles.invalid/"))
        for _ in 0..<100 {
            if !web.isLoading, (try? await web.evaluateJavaScript("document.title")) as? String == "profile-probe" { return web }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw FixtureFailure.webKitTimeout
    }

    private func contents(_ web: WKWebView, writing value: String? = nil) async throws -> [String: String] {
        try await web.callAsyncJavaScript("""
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
        """, arguments: ["value": value as Any? ?? NSNull()], in: nil, contentWorld: .page) as? [String: String] ?? [:]
    }

    private enum FixtureFailure: Error { case write, webKitTimeout }
}
