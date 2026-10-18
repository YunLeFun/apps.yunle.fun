import Foundation
import WebKit
import XCTest
@testable import YunleFun

/// Run seed and verify in separate app launches with the same UUID. No real
/// identities or network are used; only this run's named stores are touched.
@MainActor
final class WebProfileProcessLiveTests: XCTestCase {
    private var pages: [WKWebView] = []
    private let app = CloudApplication(id: "profile-process-fixture", name: "Process fixture",
                                       websiteUrl: "https://profile-process.invalid/")
    private struct Checkpoint: Codable {
        let processID: Int32
        let profiles: [UUID]
    }

    func testPersistentProfilesAcrossSeparateAppProcesses() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let phase = env["YUNLEFUN_LIVE_WEB_PROFILE_PROCESS"], ["seed", "verify", "cleanup"].contains(phase) else {
            throw XCTSkip("Requires explicit two-process profile validation")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only an owned isolated simulator may run this fixture")
        #endif
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent profiles require iOS 17") }
        guard let owned = env["YUNLEFUN_OWNED_SIMULATOR_UDID"], !owned.isEmpty, owned == env["SIMULATOR_UDID"],
              let run = env["YUNLEFUN_WEB_PROFILE_PROCESS_RUN"], let runID = UUID(uuidString: run) else {
            return XCTFail("An exact owned simulator and a valid run UUID are required")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebProfileProcessValidation/" + runID.uuidString)
        let checkpointURL = directory.appendingPathComponent("checkpoint.json")
        let repository = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: runID.uuidString)
        defer { pages.forEach { $0.stopLoading() }; pages.removeAll() }
        let checkpoint: Checkpoint
        if phase == "seed" {
            guard !FileManager.default.fileExists(atPath: directory.path) else { return XCTFail("Never overwrite an earlier run") }
            let a = try repository.select(.account("a"), application: app)
            let b = try repository.select(.account("b"), application: app)
            let guest = try repository.select(.guest, application: app)
            _ = try repository.bindGuestContinuation(guest, to: "a")
            try repository.retire("b")
            let freshB = try repository.select(.account("b"), application: app)
            let freshGuest = try repository.select(.guest, application: app)
            checkpoint = Checkpoint(processID: ProcessInfo.processInfo.processIdentifier,
                                    profiles: [a.identifier, b.identifier, guest.identifier, freshB.identifier, freshGuest.identifier])
            // Persist cleanup addresses before writing any fixture values.
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL, options: .atomic)
            for (id, value) in zip(checkpoint.profiles, ["account-a", "retired-b", "continued-guest", "", ""]) {
                let web = try await page(id)
                let actual = try await contents(web, writing: value.isEmpty ? nil : value)
                XCTAssertEqual(actual, expected(value))
            }
        } else {
            checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL))
            guard checkpoint.profiles.count == 5, Set(checkpoint.profiles).count == 5 else { return XCTFail("Invalid fixture checkpoint") }
            if phase == "verify" {
                XCTAssertNotEqual(checkpoint.processID, ProcessInfo.processInfo.processIdentifier,
                                  "Object recreation in one app process is insufficient")
                let a = try repository.select(.account("a"), application: app)
                let b = try repository.select(.account("b"), application: app)
                let guest = try repository.select(.guest, application: app)
                XCTAssertEqual(a.identifier, checkpoint.profiles[0])
                XCTAssertEqual(b.identifier, checkpoint.profiles[3])
                XCTAssertEqual(guest.identifier, checkpoint.profiles[4])
                XCTAssertEqual(try repository.retained(for: .account("a"), application: app).map(\.identifier), [checkpoint.profiles[2]])
                XCTAssertEqual(try repository.retained(for: .account("b"), application: app).map(\.identifier), [checkpoint.profiles[1]])
                XCTAssertTrue(try repository.retained(for: .guest, application: app).isEmpty)
                for (id, value) in zip(checkpoint.profiles, ["account-a", "retired-b", "continued-guest", "", ""]) {
                    let actual = try await contents(page(id))
                    XCTAssertEqual(actual, expected(value), "Data and isolation must survive the app process boundary")
                }
            }
            // Verification (or explicit recovery cleanup) removes only this
            // fixture's values. Keep empty WebKit containers; never clear all.
            for id in checkpoint.profiles {
                let web = try await page(id)
                let cleared = try await web.callAsyncJavaScript("""
                localStorage.removeItem('process_draft');
                document.cookie = 'process_draft=; Max-Age=0; path=/; Secure; SameSite=Lax';
                await new Promise((resolve, reject) => {
                  const timer = setTimeout(() => reject(new Error('cleanup timeout')), 5000);
                  const r = indexedDB.deleteDatabase('process_draft');
                  r.onsuccess = () => { clearTimeout(timer); resolve(); };
                  r.onerror = () => { clearTimeout(timer); reject(new Error('cleanup')); };
                });
                return localStorage.getItem('process_draft') === null && !document.cookie.includes('process_draft=') &&
                  !(await indexedDB.databases()).some(x => x.name === 'process_draft');
                """, arguments: [:], in: nil, contentWorld: .page) as? Bool
                XCTAssertEqual(cleared, true)
            }
            try FileManager.default.removeItem(at: directory)
        }
        let report: [String: Any] = ["phase": phase, "run": runID.uuidString,
            "seedProcessID": checkpoint.processID, "currentProcessID": ProcessInfo.processInfo.processIdentifier,
            "profiles": checkpoint.profiles.count, "fixtureDirectoryRemoved": !FileManager.default.fileExists(atPath: directory.path),
            "realCredentialsUsed": false, "scope": "Named WebKit stores across separate XCTest-hosted app processes; synthetic identities"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "web-profile-process-" + phase; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func expected(_ value: String) -> [String: String] { ["local": value, "draft": value, "cookie": value] }

    private func page(_ id: UUID) async throws -> WKWebView {
        guard #available(iOS 17, *) else { throw XCTSkip("Named persistent stores require iOS 17") }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        pages.append(web)
        web.loadHTMLString("<title>profile-process-fixture</title><p>Process fixture</p>", baseURL: app.launchURL)
        for _ in 0..<100 {
            if !web.isLoading, (try? await web.evaluateJavaScript("document.title")) as? String == "profile-process-fixture" { return web }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "WebProfileProcessFixture", code: 1)
    }

    private func contents(_ web: WKWebView, writing value: String? = nil) async throws -> [String: String] {
        try await web.callAsyncJavaScript("""
        const db = await new Promise((resolve, reject) => {
          const r = indexedDB.open('process_draft', 1);
          r.onupgradeneeded = () => r.result.createObjectStore('drafts');
          r.onsuccess = () => resolve(r.result); r.onerror = () => reject(new Error('open'));
        });
        try {
          if (value !== null) {
            localStorage.setItem('process_draft', value);
            document.cookie = 'process_draft=' + value + '; Max-Age=3600; path=/; Secure; SameSite=Lax';
            await new Promise((resolve, reject) => {
              const tx = db.transaction('drafts', 'readwrite'); tx.objectStore('drafts').put(value, 'draft');
              tx.oncomplete = resolve; tx.onerror = tx.onabort = () => reject(new Error('write'));
            });
          }
          const draft = await new Promise((resolve, reject) => {
            const r = db.transaction('drafts').objectStore('drafts').get('draft');
            r.onsuccess = () => resolve(r.result ?? ''); r.onerror = () => reject(new Error('read'));
          });
          return { local: localStorage.getItem('process_draft') || '', draft,
            cookie: document.cookie.split('; ').find(x => x.startsWith('process_draft='))?.split('=')[1] || '' };
        } finally { db.close(); }
        """, arguments: ["value": value as Any? ?? NSNull()], in: nil, contentWorld: .page) as? [String: String] ?? [:]
    }
}
