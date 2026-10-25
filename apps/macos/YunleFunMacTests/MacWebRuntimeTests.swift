import WebKit
import XCTest
@testable import YunleFunMac

@MainActor
final class MacWebRuntimeTests: XCTestCase {
    private var application: CloudApplication {
        CloudApplication(id: "runtime-fixture", name: "Fixture", websiteUrl: "https://runtime.example/start", audience: "public", isPublic: true)
    }

    func testClosingToCatalogueReusesTheLivePageAndTerminationDiscardsIt() async throws {
        try await withRuntime { runtime, _, requests, _ in
            runtime.open(application)
            let first = try XCTUnwrap(runtime.webView)
            runtime.close()
            XCTAssertEqual(runtime.application?.id, application.id)
            XCTAssertTrue(runtime.webView === first)
            runtime.open(application)
            XCTAssertTrue(runtime.webView === first)
            XCTAssertEqual(requests.values.count, 1)
            runtime.terminate()
            XCTAssertNil(runtime.application)
            XCTAssertNil(runtime.webView)
            XCTAssertNil(first.navigationDelegate)
            XCTAssertNil(first.uiDelegate)
        }
    }

    func testChangingAnApplicationsURLDiscardsTheLivePageButKeepsItsOriginProfile() async throws {
        try await withRuntime { runtime, _, requests, _ in
            runtime.open(application)
            let first = try XCTUnwrap(runtime.webView)
            let profile = first.configuration.websiteDataStore.identifier
            var changed = application
            changed.websiteUrl = "https://runtime.example/replacement"
            runtime.open(changed)
            let replacement = try XCTUnwrap(runtime.webView)
            XCTAssertFalse(replacement === first)
            XCTAssertNil(first.navigationDelegate)
            XCTAssertEqual(replacement.configuration.websiteDataStore.identifier, profile)
            XCTAssertEqual(requests.values.last?.url, changed.launchURL)
        }
    }

    func testChangingApplicationsDiscardsHiddenPagesAndIsolatesTheirWebsiteData() async throws {
        try await withRuntime { runtime, _, requests, _ in
            runtime.open(application)
            let first = try XCTUnwrap(runtime.webView)
            runtime.close()
            let other = CloudApplication(id: "other-runtime-fixture", name: "Other", websiteUrl: application.websiteUrl, audience: "public", isPublic: true)
            runtime.open(other)
            let second = try XCTUnwrap(runtime.webView)
            XCTAssertNotEqual(first.configuration.websiteDataStore.identifier, second.configuration.websiteDataStore.identifier)
            XCTAssertNil(first.navigationDelegate)
            runtime.open(application)
            XCTAssertFalse(runtime.webView === first)
            XCTAssertNil(second.navigationDelegate)
            XCTAssertEqual(requests.values.count, 3)
        }
    }

    func testAccountSwitchesAndGuestUseIndependentPersistentProfiles() async throws {
        try await withRuntime { runtime, profiles, _, _ in
            runtime.open(application)
            let guest = try XCTUnwrap(runtime.webView?.configuration.websiteDataStore.identifier)
            runtime.accountDidChange("account-a")
            XCTAssertNil(runtime.application)
            runtime.open(application)
            let accountA = try XCTUnwrap(runtime.webView?.configuration.websiteDataStore.identifier)
            runtime.accountDidChange("account-b")
            runtime.open(application)
            let accountB = try XCTUnwrap(runtime.webView?.configuration.websiteDataStore.identifier)
            XCTAssertEqual(Set([guest, accountA, accountB]).count, 3)
            runtime.accountDidChange("account-a")
            runtime.open(application)
            XCTAssertEqual(runtime.webView?.configuration.websiteDataStore.identifier, accountA)
            XCTAssertTrue(try XCTUnwrap(runtime.webView).configuration.websiteDataStore.isPersistent)
            XCTAssertEqual(try profiles.select(.guest, application: application).identifier, guest)
        }
    }

    func testRestoringTheRepositoryRecoversTheSameOwnerAndApplicationProfile() async throws {
        try await withRuntime { runtime, profiles, _, file in
            runtime.accountDidChange("account-a")
            runtime.open(application)
            let selected = try profiles.select(.account("account-a"), application: application)
            XCTAssertEqual(runtime.webView?.configuration.websiteDataStore.identifier, selected.identifier)
            runtime.terminate()
            let restoredRepository = WebProfileRepository(fileURL: file, namespace: "mac-runtime-tests")
            let restoredRuntime = MacWebRuntime(webProfiles: restoredRepository, loadRequest: { _, _ in })
            restoredRuntime.accountDidChange("account-a")
            restoredRuntime.open(application)
            XCTAssertEqual(restoredRuntime.webView?.configuration.websiteDataStore.identifier, selected.identifier)
            restoredRuntime.terminate()
        }
    }

    func testTerminatingPagesRetainsTheExactNamedStoreForTheRuntimeLifetime() async throws {
        try await withRuntime { runtime, _, _, _ in
            weak var originalStore: WKWebsiteDataStore?
            autoreleasepool {
                XCTAssertTrue(runtime.open(application))
                originalStore = runtime.webView?.configuration.websiteDataStore
                runtime.terminate()
            }
            XCTAssertNil(runtime.webView)
            XCTAssertNotNil(originalStore, "Pending website writes must outlive the closed page")
            XCTAssertTrue(runtime.open(application))
            XCTAssertTrue(runtime.webView?.configuration.websiteDataStore === originalStore)
        }
    }

    func testAccountSwitchRetainsItsStoreButRetirementNeverReassignsIt() async throws {
        try await withRuntime { runtime, profiles, _, _ in
            weak var accountAStore: WKWebsiteDataStore?
            var accountAIdentifier: UUID?
            autoreleasepool {
                runtime.accountDidChange("account-a")
                XCTAssertTrue(runtime.open(application))
                accountAStore = runtime.webView?.configuration.websiteDataStore
                accountAIdentifier = accountAStore?.identifier
                runtime.accountDidChange("account-b")
            }
            XCTAssertNotNil(accountAStore, "Switching identity must retain pending storage without retaining the page")
            XCTAssertNil(runtime.webView)
            runtime.accountDidChange("account-a")
            XCTAssertTrue(runtime.open(application))
            XCTAssertTrue(runtime.webView?.configuration.websiteDataStore === accountAStore)

            try profiles.retire("account-a")
            runtime.accountDidChange(nil)
            XCTAssertTrue(runtime.open(application))
            let guestIdentifier = try XCTUnwrap(runtime.webView?.configuration.websiteDataStore.identifier)
            XCTAssertNotEqual(guestIdentifier, accountAIdentifier)
            runtime.accountDidChange("account-a")
            XCTAssertTrue(runtime.open(application))
            let replacement = try XCTUnwrap(runtime.webView?.configuration.websiteDataStore)
            XCTAssertNotEqual(replacement.identifier, accountAIdentifier)
            XCTAssertNotEqual(replacement.identifier, guestIdentifier)
            XCTAssertFalse(replacement === accountAStore)
            XCTAssertEqual(try profiles.retained(for: .account("account-a"), application: application).map(\.identifier),
                           [try XCTUnwrap(accountAIdentifier)])
        }
    }

    func testProfileWriteFailureDoesNotReportAnOlderApplicationAsTheNewLaunch() async throws {
        try await withRuntime { runtime, _, requests, file in
            XCTAssertTrue(runtime.open(application))
            let first = try XCTUnwrap(runtime.webView)
            let original = try Data(contentsOf: file)
            defer { try? original.write(to: file, options: .atomic) }
            try Data("corrupt-profile-state".utf8).write(to: file, options: .atomic)
            let other = CloudApplication(id: "other", name: "Other", websiteUrl: "https://other.example/")
            XCTAssertFalse(runtime.open(other))
            XCTAssertEqual(runtime.application?.id, application.id)
            XCTAssertTrue(runtime.webView === first)
            XCTAssertNotNil(runtime.error)
            XCTAssertEqual(requests.values.count, 1)
        }
    }

    private final class Requests { var values: [URLRequest] = [] }

    private struct CleanupManifest: Encodable {
        let owner = "YunleFunMacTests.MacWebRuntimeTests"
        let identifier: UUID
        let bundleIdentifier: String
        let testName: String
        let createdAt: Date
    }

    private func withRuntime(testName: String = #function,
                             _ body: (MacWebRuntime, WebProfileRepository, Requests, URL) throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-web-runtime-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("profiles.json")
        let manifests = directory.appendingPathComponent("cleanup-manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        var identifiers = Set<UUID>()
        var failure: Error?
        var runtime: MacWebRuntime?
        do {
            try autoreleasepool {
                let profiles = WebProfileRepository(fileURL: file, namespace: "mac-runtime-tests") { data, destination in
                    // Record the exact ownership before select() returns and a
                    // WKWebView can create a named store. Never infer ownership
                    // by enumerating every store in the developer's container.
                    if let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let active = (state["active"] as? [String: String])?.values.map { $0 } ?? []
                        let retained = (state["retained"] as? [String: [String]])?.values.flatMap { $0 } ?? []
                        for identifier in (active + retained).compactMap(UUID.init(uuidString:)) where !identifiers.contains(identifier) {
                            let manifest = CleanupManifest(identifier: identifier,
                                                           bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown-test-host",
                                                           testName: testName, createdAt: Date())
                            try JSONEncoder().encode(manifest).write(
                                to: manifests.appendingPathComponent(identifier.uuidString + ".json"), options: .atomic)
                            identifiers.insert(identifier)
                        }
                    }
                    try data.write(to: destination, options: .atomic)
                }
                let requests = Requests()
                // No network request is sent. Keeping all WebKit allocation and
                // synchronous assertions inside this pool releases Objective-C
                // autoreleased owners as well as Swift's strong references.
                runtime = MacWebRuntime(webProfiles: profiles) { _, request in requests.values.append(request) }
                defer {
                    runtime?.terminate()
                    runtime = nil
                }
                try body(try XCTUnwrap(runtime), profiles, requests, file)
            }
        } catch { failure = error }

        // Observation tasks and WebKit's main-runloop teardown may outlive ARC
        // release. Yield before asking WebKit to remove the now-unused stores.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)
        var cleanupComplete = true
        for identifier in identifiers {
            let manifest = manifests.appendingPathComponent(identifier.uuidString + ".json")
            var cleanupError: Error?
            for attempt in 0..<6 {
                cleanupError = await withCheckedContinuation { continuation in
                    WKWebsiteDataStore.remove(forIdentifier: identifier) { continuation.resume(returning: $0) }
                }
                if cleanupError == nil { break }
                await Task.yield()
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 100_000_000)
            }
            if let cleanupError {
                cleanupComplete = false
                XCTFail("Test-owned WebKit profile \(identifier) could not be removed: \(cleanupError). Cleanup pending: \(manifest.path)")
            } else {
                try FileManager.default.removeItem(at: manifest)
            }
        }
        if cleanupComplete {
            try FileManager.default.removeItem(at: directory)
        }
        if let failure { throw failure }
    }
}
