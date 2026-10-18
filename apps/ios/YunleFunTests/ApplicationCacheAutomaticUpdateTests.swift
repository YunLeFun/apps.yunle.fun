import XCTest
@testable import YunleFun

@MainActor
final class ApplicationCacheAutomaticUpdateTests: XCTestCase {
    func testOptInAndWifiPreferencePersist() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        XCTAssertFalse(fixture.store.automaticUpdatesEnabled)
        XCTAssertTrue(fixture.store.wifiOnly)
        fixture.store.setApplicationActive(true)
        XCTAssertEqual(fixture.monitor.starts, 0)
        fixture.store.automaticUpdatesEnabled = true
        fixture.store.wifiOnly = false
        let reopened = ApplicationCacheStore(repository: fixture.repository, defaults: fixture.defaults)
        XCTAssertTrue(reopened.automaticUpdatesEnabled)
        XCTAssertFalse(reopened.wifiOnly)
        XCTAssertEqual(fixture.monitor.starts, 1)
    }

    func testWifiGateExcludesCellularHotspotLowDataModeAndOffline() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed()
        fixture.enable()
        for path in [ApplicationCacheNetwork(),
                     ApplicationCacheNetwork(connected: true, expensive: true),
                     ApplicationCacheNetwork(connected: true, wifi: true, expensive: true),
                     ApplicationCacheNetwork(connected: true, wifi: true, constrained: true)] {
            fixture.monitor.emit(path)
            await settle()
            XCTAssertEqual(fixture.downloader.calls, 0)
        }
        fixture.monitor.emit(.wifiConnection)
        try await wait { fixture.downloader.pending }
        XCTAssertEqual(fixture.requestedWifiPolicies, [true])
        fixture.downloader.finish(try autoArchive("new"))
        try await wait { !fixture.store.isBusy }
    }

    func testExplicitCellularOptInStillHonorsLowDataMode() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed(); fixture.enable(); fixture.store.wifiOnly = false
        fixture.monitor.emit(ApplicationCacheNetwork(connected: true, expensive: true, constrained: true))
        await settle(); XCTAssertEqual(fixture.downloader.calls, 0)
        fixture.monitor.emit(ApplicationCacheNetwork(connected: true, expensive: true))
        try await wait { fixture.downloader.pending }
        XCTAssertEqual(fixture.requestedWifiPolicies, [false])
        fixture.downloader.finish(try autoArchive("new"))
        try await wait { !fixture.store.isBusy }
    }

    func testOnlyDownloadedPublicCurrentCatalogEntriesBecomeDueAfter24Hours() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed(date: fixture.clock.date)
        fixture.enable(); fixture.monitor.emit(.wifiConnection)
        await settle(); XCTAssertEqual(fixture.downloader.calls, 0)
        fixture.clock.date.addTimeInterval(ApplicationCacheStore.automaticUpdateInterval)
        var protected = autoApp(); protected.requiresMembership = true
        fixture.store.updateAutomaticApplications([protected, autoApp("never-downloaded")])
        await settle(); XCTAssertEqual(fixture.downloader.calls, 0)
        var changedURL = autoApp(); changedURL.websiteUrl = "https://cache.example/changed/"
        fixture.store.updateAutomaticApplications([changedURL])
        await settle(); XCTAssertEqual(fixture.downloader.calls, 0)
        fixture.store.updateAutomaticApplications([autoApp()])
        try await wait { fixture.downloader.pending }
        fixture.downloader.finish(try autoArchive("new"))
        try await wait { !fixture.store.isBusy }
        fixture.monitor.emit(.wifiConnection)
        await settle(); XCTAssertEqual(fixture.downloader.calls, 1)
    }

    func testSuccessfulUpdateSignalsNextLaunchWithoutReplacingRunningRevision() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed()
        let originalSnapshot = try await fixture.repository.snapshot(for: autoApp())
        let loaded = try XCTUnwrap(originalSnapshot)
        fixture.store.sessionStarted(autoApp(), revision: loaded.entry.downloadedAt)
        fixture.enable(); fixture.monitor.emit(.wifiConnection)
        try await wait { fixture.downloader.pending }
        let update = try autoArchive("new")
        fixture.downloader.finish(update)
        try await wait { !fixture.store.isBusy }
        let updatedSnapshot = try await fixture.repository.snapshot(for: autoApp())
        let next = try XCTUnwrap(updatedSnapshot)
        XCTAssertEqual(loaded.archive, fixture.originalData)
        XCTAssertEqual(next.archive, update)
        XCTAssertEqual(fixture.store.updatesReady, [ApplicationCacheEntry.key(for: autoApp())])
        fixture.store.sessionEnded(autoApp())
        fixture.store.sessionStarted(autoApp(), revision: next.entry.downloadedAt)
        XCTAssertTrue(fixture.store.updatesReady.isEmpty)
    }

    func testTimeoutPreservesOldCacheAndBackoffSurvivesRestart() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed(); fixture.enable(); fixture.monitor.emit(.wifiConnection)
        try await wait { fixture.downloader.pending }
        fixture.downloader.fail(ApplicationCacheError.timedOut)
        try await wait { !fixture.store.isBusy }
        let preserved = try await fixture.repository.archive(for: autoApp())
        XCTAssertEqual(preserved, fixture.originalData)
        fixture.store.setApplicationActive(false)
        let monitor = AutoCacheMonitor(), downloader = AutoCacheDownloader()
        let reopened = ApplicationCacheStore(repository: fixture.repository, defaults: fixture.defaults,
                                              monitor: monitor, now: { fixture.clock.date },
                                              makeAutomaticDownloader: { _ in downloader })
        defer { reopened.setApplicationActive(false); downloader.fail(CancellationError()) }
        reopened.updateAutomaticApplications([autoApp()]); reopened.setApplicationActive(true)
        monitor.emit(.wifiConnection)
        await settle(); XCTAssertEqual(downloader.calls, 0)
        fixture.clock.date.addTimeInterval(3601)
        monitor.emit(.wifiConnection)
        try await wait { downloader.pending }
        downloader.finish(Data("invalid update".utf8))
        try await wait { !reopened.isBusy }
        fixture.clock.date.addTimeInterval(3601)
        monitor.emit(.wifiConnection)
        await settle(); XCTAssertEqual(downloader.calls, 1, "Second failure waits two hours")
        let afterInvalidUpdate = try await fixture.repository.archive(for: autoApp())
        XCTAssertEqual(afterInvalidUpdate, fixture.originalData)
    }

    func testNetworkLossBackgroundDisableAndCatalogRevocationDiscardLateResults() async throws {
        for reason in ["network", "background", "disabled", "catalog"] {
            let fixture = AutoCacheFixture(); defer { fixture.close() }
            try await fixture.seed(); fixture.enable(); fixture.monitor.emit(.wifiConnection)
            try await wait { fixture.downloader.pending }
            switch reason {
            case "network": fixture.monitor.emit(ApplicationCacheNetwork(connected: true, expensive: true))
            case "background": fixture.store.setApplicationActive(false)
            case "disabled": fixture.store.automaticUpdatesEnabled = false
            default: fixture.store.updateAutomaticApplications([])
            }
            fixture.downloader.finish(try autoArchive("late"))
            try await wait { !fixture.store.isBusy }
            let preserved = try await fixture.repository.archive(for: autoApp())
            XCTAssertEqual(preserved, fixture.originalData, reason)
            await settle(); XCTAssertEqual(fixture.downloader.calls, 1, reason)
        }
    }

    func testClearingDuringAutomaticUpdateCannotRecreateDownloads() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed(); fixture.enable(); fixture.monitor.emit(.wifiConnection)
        try await wait { fixture.downloader.pending }
        let clear = Task { await fixture.store.clear() }
        try await wait { fixture.store.isClearing }
        fixture.downloader.finish(try autoArchive("late"))
        await clear.value
        fixture.monitor.emit(.wifiConnection)
        await settle()
        let entries = try await fixture.repository.entries()
        XCTAssertTrue(entries.isEmpty); XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertEqual(fixture.downloader.calls, 1)
    }

    func testAutomaticQueueIsSerialAndManualDownloadCanRetryImmediately() async throws {
        let fixture = AutoCacheFixture(); defer { fixture.close() }
        try await fixture.seed()
        try await fixture.repository.save(autoArchive("old"), for: autoApp("second"), now: fixture.clock.date.addingTimeInterval(-90000))
        fixture.enable(applications: [autoApp(), autoApp("second")]); fixture.monitor.emit(.wifiConnection)
        try await wait { fixture.downloader.pending }
        fixture.store.download(autoApp("ignored-while-busy"))
        XCTAssertEqual(fixture.downloader.calls, 1)
        fixture.downloader.finish(try autoArchive("new"))
        try await wait { fixture.downloader.calls == 2 && fixture.downloader.pending }
        fixture.downloader.fail(ApplicationCacheError.timedOut)
        try await wait { !fixture.store.isBusy }
        fixture.store.setApplicationActive(false)
        fixture.store.download(autoApp("second"))
        try await wait { fixture.downloader.calls == 3 && fixture.downloader.pending }
        fixture.downloader.finish(try autoArchive("manual retry"))
        try await wait { !fixture.store.isBusy }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Automatic cache operation did not settle")
        throw URLError(.timedOut)
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }
}

@MainActor
private final class AutoCacheFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "cache-auto-tests.\(UUID().uuidString)"
    let clock = AutoCacheClock()
    let monitor = AutoCacheMonitor()
    let downloader = AutoCacheDownloader()
    let originalData = try! autoArchive("old")
    lazy var defaults = UserDefaults(suiteName: suite)!
    lazy var repository = ApplicationCacheRepository(directory: directory)
    var requestedWifiPolicies: [Bool] = []
    lazy var store = ApplicationCacheStore(repository: repository, defaults: defaults, monitor: monitor,
                                          now: { [clock] in clock.date },
                                          makeAutomaticDownloader: { [unowned self] wifiOnly in
                                              requestedWifiPolicies.append(wifiOnly); return downloader
                                          }, makeDownloader: { [downloader] in downloader })
    func seed(date: Date? = nil) async throws {
        try await repository.save(originalData, for: autoApp(), now: date ?? clock.date.addingTimeInterval(-100000))
    }
    func enable(applications: [CloudApplication] = [autoApp()]) {
        store.updateAutomaticApplications(applications)
        store.automaticUpdatesEnabled = true; store.setApplicationActive(true)
    }
    func close() {
        store.setApplicationActive(false); downloader.fail(CancellationError())
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class AutoCacheClock { var date = Date(timeIntervalSince1970: 2000000) }

@MainActor
private final class AutoCacheMonitor: ApplicationCacheNetworkMonitoring {
    var changed: ((ApplicationCacheNetwork) -> Void)?
    var starts = 0
    func start(_ changed: @escaping @MainActor (ApplicationCacheNetwork) -> Void) { starts += 1; self.changed = changed }
    func stop() { changed = nil }
    func emit(_ path: ApplicationCacheNetwork) { changed?(path) }
}

@MainActor
private final class AutoCacheDownloader: ApplicationCacheDownloading {
    var continuation: CheckedContinuation<Data, Error>?
    var calls = 0
    var pending: Bool { continuation != nil }
    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        calls += 1
        // Deliberately ignore cancellation to cover late WebKit callbacks.
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
    func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
}

private extension ApplicationCacheNetwork {
    static let wifiConnection = ApplicationCacheNetwork(connected: true, wifi: true)
}
private func autoApp(_ id: String = "auto-cache") -> CloudApplication {
    CloudApplication(id: id, name: "自动更新测试", websiteUrl: "https://cache.example/")
}
private func autoArchive(_ title: String) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: [
        "WebMainResource": ["WebResourceURL": "https://cache.example/", "WebResourceMIMEType": "text/html",
                            "WebResourceData": Data("<html><title>\(title)</title><body>cache</body></html>".utf8)],
        "WebSubresources": []
    ], format: .binary, options: 0)
}
