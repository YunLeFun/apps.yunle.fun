import XCTest
@testable import YunleFun

final class ApplicationCacheRepositoryTests: XCTestCase {
    func testPersistsAcrossInstancesAndSeparatesApplicationsAndURLs() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let first = app(), data = try archive()
        var second = first; second.websiteUrl = "https://cache.example/new/"
        let third = app(id: "other-app")
        try await repository.save(data, for: first)
        let reopened = ApplicationCacheRepository(directory: directory)
        let stored = try await reopened.archive(for: first)
        let changedURL = try await reopened.archive(for: second)
        let otherApp = try await reopened.archive(for: third)
        XCTAssertEqual(stored, data); XCTAssertNil(changedURL); XCTAssertNil(otherApp)
        let entries = try await reopened.entries()
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.byteCount, data.count)
    }

    func testFailedUpdatePreservesOldVersionAndSuccessfulUpdateReplacesIt() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let application = app(), original = try archive(title: "old"), update = try archive(title: "new")
        try await repository.save(original, for: application)
        do { try await repository.save(Data("broken".utf8), for: application); XCTFail("Invalid content must be rejected") }
        catch ApplicationCacheError.invalidArchive { }
        let afterFailure = try await repository.archive(for: application)
        XCTAssertEqual(afterFailure, original)
        try await repository.save(update, for: application, now: Date(timeIntervalSince1970: 1000))
        let afterUpdate = try await repository.archive(for: application)
        let entries = try await repository.entries()
        XCTAssertEqual(afterUpdate, update); XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.downloadedAt, Date(timeIntervalSince1970: 1000))
    }

    func testClearOneKeepsOtherAppAndClearAllLeavesOtherDirectoriesAlone() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("home.json")
        try Data("home-and-account-data".utf8).write(to: sentinel)
        let repository = ApplicationCacheRepository(directory: directory.appendingPathComponent("downloads"))
        let first = app(), second = app(id: "second")
        try await repository.save(archive(), for: first); try await repository.save(archive(), for: second)
        try await repository.remove(id: ApplicationCacheEntry.key(for: first))
        let remaining = try await repository.entries()
        XCTAssertEqual(remaining.map(\.application.id), ["second"])
        try await repository.removeAll()
        let empty = try await repository.entries()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(try String(contentsOf: sentinel), "home-and-account-data")
    }

    func testQuotaFailurePreservesOldCacheAndCorruptFilesCanBeCleared() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory, totalLimit: 4096)
        let application = app(), original = try archive()
        try await repository.save(original, for: application)
        do { try await repository.save(archive(title: String(repeating: "x", count: 8000)), for: application); XCTFail() }
        catch ApplicationCacheError.quotaExceeded { }
        let preserved = try await repository.archive(for: application)
        XCTAssertEqual(preserved, original)
        let file = directory.appendingPathComponent(ApplicationCacheEntry.key(for: application)).appendingPathExtension("cache")
        try Data("corrupt".utf8).write(to: file)
        let entries = try await repository.entries()
        XCTAssertTrue(entries.isEmpty)
        do { _ = try await repository.archive(for: application); XCTFail() } catch { }
        try await repository.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPolicyRejectsProtectedVariantsAndArchiveOriginSubstitution() async throws {
        var gated = app(); gated.requiresMembership = true
        var workshop = app(); workshop.accessWorkshopID = "private"
        var personal = app(); personal.personalMarketOwnerLogin = "someone"
        var unavailable = app(); unavailable.isUnavailable = true
        for application in [gated, workshop, personal, unavailable] { XCTAssertFalse(ApplicationCacheEntry.supports(application)) }
        XCTAssertThrowsError(try ApplicationCacheRepository.validate(archive(), launchURL: URL(string: "https://other.example")!))
        XCTAssertThrowsError(try ApplicationCacheRepository.validate(Data(repeating: 0, count: ApplicationCacheRepository.maximumArchiveBytes + 1), launchURL: app().launchURL!))
        XCTAssertFalse(ApplicationCacheRepository.sameOrigin(URL(string: "https://user:pass@cache.example")!, app().launchURL!))
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        try await repository.save(archive(), for: app())
        let protectedRead = try await repository.archive(for: gated)
        XCTAssertNil(protectedRead)
        do { try await repository.remove(id: "../home"); XCTFail() } catch ApplicationCacheError.invalidArchive { }
    }
}

@MainActor
final class ApplicationCacheStoreTests: XCTestCase {
    func testCancelDiscardsLateResponseAndRetainsPreviousDownload() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        let original = try archive(title: "old")
        try await repository.save(original, for: app())
        let downloader = DelayedCacheDownloader()
        let store = ApplicationCacheStore(repository: repository, makeDownloader: { downloader })
        store.download(app())
        try await wait { downloader.continuation != nil }
        store.cancelDownload()
        downloader.finish(try archive(title: "late"))
        try await wait { !store.isBusy }
        let preserved = try await repository.archive(for: app())
        XCTAssertEqual(preserved, original)
    }

    func testClearWaitsForDownloadAndDoesNotAllowLateRepopulation() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ApplicationCacheRepository(directory: directory)
        try await repository.save(archive(), for: app())
        let downloader = DelayedCacheDownloader()
        let store = ApplicationCacheStore(repository: repository, makeDownloader: { downloader })
        store.download(app())
        try await wait { downloader.continuation != nil }
        let clear = Task { await store.clear() }
        try await wait { store.isClearing }
        store.download(app(id: "ignored-during-clear"))
        downloader.finish(try archive(title: "late"))
        await clear.value
        let entries = try await repository.entries()
        XCTAssertTrue(entries.isEmpty); XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(store.isBusy)
    }

    func testDownloadPublishesMetadataAndCoalescesConcurrentRequests() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = DelayedCacheDownloader()
        let store = ApplicationCacheStore(repository: ApplicationCacheRepository(directory: directory), makeDownloader: { downloader })
        store.download(app()); store.download(app(id: "ignored"))
        try await wait { downloader.continuation != nil }
        XCTAssertEqual(downloader.calls, 1)
        downloader.finish(try archive())
        try await wait { !store.isBusy }
        XCTAssertEqual(store.entries.map(\.application.id), [app().id])
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Cache operation did not settle"); throw URLError(.timedOut)
    }
}

@MainActor
private final class DelayedCacheDownloader: ApplicationCacheDownloading {
    var continuation: CheckedContinuation<Data, Error>?
    var calls = 0
    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        calls += 1; progress(0.5)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}

private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func app(id: String = "cache-app") -> CloudApplication { CloudApplication(id: id, name: "缓存测试", websiteUrl: "https://cache.example/") }
private func archive(title: String = "fixture") throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: [
        "WebMainResource": ["WebResourceURL": "https://cache.example/", "WebResourceMIMEType": "text/html",
                            "WebResourceData": Data("<html><title>\(title)</title><body>cache</body></html>".utf8)],
        "WebSubresources": []
    ], format: .binary, options: 0)
}
