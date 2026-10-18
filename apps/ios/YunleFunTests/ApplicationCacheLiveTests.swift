import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationCacheStartupTests: XCTestCase {
    func testRepeatedAnonymousDownloadsReleaseEngines() async throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_STARTUP_PROBE"] == "1",
              ProcessInfo.processInfo.environment["YLF_CACHE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt in to repeated anonymous downloads on a dedicated simulator")
        }
        continueAfterFailure = false
        let url = URL(string: "https://ac.yunyoujun.cn/")!
        for iteration in 1...8 {
            weak var engine: WKWebView?
            let downloader = ApplicationCacheDownloader(makeWebView: { configuration in
                let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
                engine = web
                return web
            })
            let started = ProcessInfo.processInfo.systemUptime
            print("CACHE_STARTUP_PROBE downloading iteration=\(iteration)")
            let archive = try await downloader.download(url, progress: { _ in })
            XCTAssertGreaterThan(try ApplicationCacheRepository.validate(archive, launchURL: url), 2)
            print("CACHE_STARTUP_PROBE archived iteration=\(iteration) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
            for _ in 0..<100 {
                if engine == nil { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertNil(engine, "Anonymous download engine retained after iteration \(iteration)")
            print("CACHE_STARTUP_PROBE engine-released iteration=\(iteration)")
        }
    }
}

/// Explicit anonymous network smoke test; excluded unless the developer opts in.
@MainActor
final class ApplicationCacheLiveTests: XCTestCase {
    func testStoreDownloadsUpdatesAndClearsCloudAir() async throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set YLF_CACHE_LIVE_TEST=1 for anonymous public network validation")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let store = ApplicationCacheStore(repository: repository)
        let application = CloudApplication(id: "cache-live-store", name: "云空调", websiteUrl: "https://ac.yunyoujun.cn/")
        var lastDate: Date?
        for operation in ["download", "update"] {
            let start = Date()
            store.download(application)
            while store.isBusy, Date().timeIntervalSince(start) < 140 {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertFalse(store.isBusy, "\(operation): \(store.message ?? "operation did not settle")")
            let entry = try XCTUnwrap(store.entry(for: application), store.message ?? "No saved cache")
            if let lastDate { XCTAssertGreaterThan(entry.downloadedAt, lastDate) }
            lastDate = entry.downloadedAt
            XCTAssertGreaterThan(entry.resourceCount, 2)
            let archive = try await repository.archive(for: application)
            let saved = try XCTUnwrap(archive)
            try await assertCloudAirRenders(saved, url: application.launchURL!)
            let attachment = XCTAttachment(string: "\(operation): \(Date().timeIntervalSince(start)) s; \(entry.byteCount) bytes, \(entry.resourceCount) resources")
            attachment.lifetime = .keepAlways; add(attachment)
        }
        await store.clear(id: ApplicationCacheEntry.key(for: application))
        XCTAssertFalse(store.isBusy)
        XCTAssertTrue(store.entries.isEmpty)
        let removed = try await repository.archive(for: application)
        XCTAssertNil(removed)
    }

    func testDownloadAndReplayCloudAir() async throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set YLF_CACHE_LIVE_TEST=1 for anonymous public network validation")
        }
        let application = CloudApplication(id: "cache-live-air", name: "云空调", websiteUrl: "https://ac.yunyoujun.cn/")
        let downloader = ApplicationCacheDownloader()
        let archive = try await downloader.download(application.launchURL!, progress: { _ in })
        let count = try ApplicationCacheRepository.validate(archive, launchURL: application.launchURL!)
        XCTAssertGreaterThan(count, 2, "Capture the real application's resources, not only its HTML")
        try await assertCloudAirRenders(archive, url: application.launchURL!)
    }

    private func assertCloudAirRenders(_ archive: Data, url: URL) async throws {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        web.load(archive, mimeType: "application/x-webarchive", characterEncodingName: "UTF-8", baseURL: url)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript("document.body?.innerText.includes('便携小空调') && document.querySelectorAll('button').length > 0")) as? Bool == true {
                let attachment = XCTAttachment(string: "Cloud Air archive: \(archive.count) bytes; fresh WebKit renders app controls.")
                attachment.lifetime = .keepAlways; add(attachment)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Downloaded Cloud Air did not render its controls")
    }
}
