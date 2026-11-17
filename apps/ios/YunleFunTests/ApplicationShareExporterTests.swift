import XCTest
@testable import YunleFun

@MainActor
final class ApplicationShareExporterTests: XCTestCase {
    func testPublicCatalogBatchRefreshesDetailsAndExportsBothThemesWithScannablePNGs() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var old = app("one"); old.websiteUrl = "https://old.example.com/"
        let latest = app("one"), second = app("two")
        let catalog = ShareExportCatalog(list: [old, second, old], details: ["one": latest, "two": second])
        let icons = ShareExportIcons(fail: true)
        let exporter = ApplicationShareExporter(catalog: catalog, icons: icons, temporaryRoot: root)
        var progress: [Int] = []
        var directory: ApplicationShareExportDirectory? = try await exporter.directory(appearances: [.dark, .light, .dark]) { done, _, _ in progress.append(done) }
        let url = try XCTUnwrap(directory?.url), manifest = try XCTUnwrap(directory?.manifest)
        XCTAssertEqual(manifest.cards.count, 4)
        XCTAssertTrue(manifest.failures.isEmpty)
        XCTAssertEqual(Set(manifest.cards.map(\.appearance)), ["light", "dark"])
        XCTAssertTrue(manifest.cards.allSatisfy(\.usedFallbackIcon))
        XCTAssertEqual(progress.last, 2)
        let requests = await catalog.detailRequests
        XCTAssertEqual(requests, ["one", "two"])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(ApplicationShareExportManifest.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
        XCTAssertEqual(stored.pixelWidth, 1080); XCTAssertEqual(stored.pixelHeight, 1620)
        for card in stored.cards {
            XCTAssertEqual(card.websiteUrl, app(card.slug).websiteUrl)
            let payloads = try await PhotoQRCodeDecoder().payloads(in: Data(contentsOf: url.appendingPathComponent(card.filename)))
            XCTAssertEqual(payloads, [card.websiteUrl])
        }
        directory = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "The staging owner removes rebuildable files when released")
    }

    func testSingleSlugSkipsTheListAndAlwaysLoadsTheDetail() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = ShareExportCatalog(list: [], details: ["one": app("one")])
        let exporter = ApplicationShareExporter(catalog: catalog, icons: ShareExportIcons(), temporaryRoot: root)
        let preview = try await exporter.application(slug: "one")
        XCTAssertEqual(preview.name, "应用 one")
        let directory = try await exporter.directory(slugs: ["one"], appearances: [.dark])
        XCTAssertEqual(directory.manifest.cards.map(\.filename), ["one-dark.png"])
        let listRequests = await catalog.listRequests
        XCTAssertEqual(listRequests, 0)
    }

    func testInvalidPrivateAndUnavailableRecordsAreReportedWithoutInventingQRs() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var hidden = app("hidden"); hidden.accessWorkshopID = "ABC234"
        var missing = app("missing"); missing.websiteUrl = nil
        let catalog = ShareExportCatalog(list: [], details: ["one": app("one"), "hidden": hidden, "missing": missing])
        let exporter = ApplicationShareExporter(catalog: catalog, icons: ShareExportIcons(), temporaryRoot: root)
        let directory = try await exporter.directory(slugs: ["one", "hidden", "missing", "../escape"], appearances: [.dark])
        XCTAssertEqual(directory.manifest.cards.count, 1)
        XCTAssertEqual(Set(directory.manifest.failures.map(\.slug)), ["hidden", "missing", "../escape"])
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        XCTAssertEqual(Set(contents), ["manifest.json", "one-dark.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape-dark.png").path))
        let requests = await catalog.detailRequests
        XCTAssertFalse(requests.contains("../escape"))
    }

    func testCancellationAfterWritingAPNGRemovesThePartialDirectory() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = ShareExportCatalog(list: [], details: ["one": app("one"), "two": app("two")])
        let exporter = ApplicationShareExporter(catalog: catalog, icons: ShareExportIcons(cancelAt: 2), temporaryRoot: root)
        do {
            _ = try await exporter.directory(slugs: ["one", "two"], appearances: [.dark])
            XCTFail("Cancellation must stop export")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testAllFailedRecordsDoNotLeaveAnEmptyExportFolder() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let exporter = ApplicationShareExporter(catalog: ShareExportCatalog(list: [], details: [:]), icons: ShareExportIcons(), temporaryRoot: root)
        do { _ = try await exporter.directory(slugs: ["missing"], appearances: [.dark]); XCTFail() }
        catch { XCTAssertEqual(error as? ApplicationShareExportError, .noCards) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("share-export-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func app(_ key: String) -> CloudApplication {
        CloudApplication(id: key, name: "应用 " + key, slug: key, marketShortName: key, description: "公开目录测试",
            websiteUrl: "https://example.com/\(key)?source=share#hello", emoji: "🛵", themeColor: "#FFD447", accessMode: "public")
    }
}

private actor ShareExportCatalog: CatalogServing, ApplicationAvailabilityServing {
    let list: [CloudApplication]
    let details: [String: CloudApplication]
    var detailRequests: [String] = []
    var listRequests = 0
    init(list: [CloudApplication], details: [String: CloudApplication]) { self.list = list; self.details = details }
    func applications() async throws -> [CloudApplication] { listRequests += 1; return list }
    func application(reference: String) async throws -> CloudApplication {
        detailRequests.append(reference)
        guard let app = details[reference] else { throw ApplicationUnavailableReason.unavailable }
        return app
    }
}

@MainActor
private final class ShareExportIcons: ApplicationShareIconLoading {
    let fail: Bool
    let cancelAt: Int?
    var calls = 0
    init(fail: Bool = false, cancelAt: Int? = nil) { self.fail = fail; self.cancelAt = cancelAt }
    func image(for application: CloudApplication, appearance: ApplicationShareAppearance) async throws -> UIImage? {
        calls += 1
        if calls == cancelAt { throw CancellationError() }
        if fail { throw URLError(.cannotLoadFromNetwork) }
        return nil
    }
}
