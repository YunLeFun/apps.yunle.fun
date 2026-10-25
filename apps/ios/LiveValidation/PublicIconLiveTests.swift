import XCTest
#if os(macOS)
import AppKit
@testable import YunleFunMac
#else
import UIKit
@testable import YunleFun
#endif

final class PublicIconLiveTests: XCTestCase {
    private func iconAttachment(_ image: CGImage) -> XCTAttachment {
        #if os(macOS)
        XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        #else
        XCTAttachment(image: UIImage(cgImage: image))
        #endif
    }
    func testCurrentFirstPartySVGsRender() async throws {
        let apps = try await CatalogService().applications()
        let keys = ["cook", "yunjian", "play"]
        let pipeline = ApplicationImagePipeline()
        for key in keys {
            let app = try XCTUnwrap(apps.first { $0.marketShortName == key })
            let result = try await pipeline.load(app.iconCandidates(dark: false), pixelSize: 256)
            XCTAssertEqual(result.candidate.url.pathExtension.lowercased(), "svg")
            let attachment = iconAttachment(result.bitmap.image)
            attachment.name = "live-native-svg-" + key; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    @MainActor
    func testPublishedBrandIconsUseRealAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("live-icon-manifest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("manifest.json")
        let store = CatalogIconStore(cacheURL: cacheURL)
        await store.refresh()
        XCTAssertEqual(store.source, .network, "This journey must fetch the real runtime manifest")
        let restored = CatalogIconStore(cacheURL: cacheURL)
        XCTAssertEqual(restored.source, .cache)
        XCTAssertEqual(restored.assets, store.assets)
        let apps = try await CatalogService().applications()
        let withIcons = apps.filter { !$0.iconCandidates(dark: false, downloaded: store.assets).isEmpty }
        XCTAssertFalse(withIcons.isEmpty)
        XCTAssertEqual(withIcons.count, apps.count, "Every published application must have a real icon candidate")
        let pipeline = ApplicationImagePipeline()
        for app in withIcons {
            do {
            let icon = try await pipeline.load(app.iconCandidates(dark: false, downloaded: store.assets), pixelSize: 256)
            XCTAssertGreaterThan(icon.bitmap.image.width, 0, app.name)
            XCTAssertLessThanOrEqual(max(icon.bitmap.image.width, icon.bitmap.image.height), 256, app.name)
            let attachment = iconAttachment(icon.bitmap.image)
            attachment.name = "live-public-icon-" + (app.marketShortName ?? app.id)
            attachment.lifetime = .keepAlways; add(attachment)
            } catch { XCTFail("Public icon failed for \(app.marketShortName ?? app.id): \(error)") }
        }
        XCTAssertNotNil(withIcons.first { $0.marketShortName == "cook" }, "Keep the SVG-backed primary catalog example in this read-only journey")
    }
}
