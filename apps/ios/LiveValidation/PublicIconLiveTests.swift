import XCTest
import UIKit
@testable import YunleFun

final class PublicIconLiveTests: XCTestCase {
    func testCurrentFirstPartySVGsRender() async throws {
        let apps = try await CatalogService().applications()
        let keys = ["cook", "yunjian", "play"]
        let pipeline = ApplicationImagePipeline()
        for key in keys {
            let app = try XCTUnwrap(apps.first { $0.marketShortName == key })
            let result = try await pipeline.load(app.iconCandidates(dark: false), pixelSize: 256)
            XCTAssertEqual(result.candidate.url.pathExtension.lowercased(), "svg")
            let attachment = XCTAttachment(image: UIImage(cgImage: result.bitmap.image))
            attachment.name = "live-native-svg-" + key; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testPublishedBrandIconsUseRealAssets() async throws {
        let apps = try await CatalogService().applications()
        let withIcons = apps.filter { !$0.iconCandidates(dark: false).isEmpty }
        XCTAssertFalse(withIcons.isEmpty)
        let pipeline = ApplicationImagePipeline()
        for app in withIcons {
            do {
            let icon = try await pipeline.load(app.iconCandidates(dark: false), pixelSize: 256)
            XCTAssertGreaterThan(icon.bitmap.image.width, 0, app.name)
            XCTAssertLessThanOrEqual(max(icon.bitmap.image.width, icon.bitmap.image.height), 256, app.name)
            let attachment = XCTAttachment(image: UIImage(cgImage: icon.bitmap.image))
            attachment.name = "live-public-icon-" + (app.marketShortName ?? app.id)
            attachment.lifetime = .keepAlways; add(attachment)
            } catch { XCTFail("Public icon failed for \(app.marketShortName ?? app.id): \(error)") }
        }
        XCTAssertNotNil(withIcons.first { $0.marketShortName == "cook" }, "Keep the SVG-backed primary catalog example in this read-only journey")
    }
}
