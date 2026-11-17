import SwiftUI
import XCTest
@testable import YunleFun

/// Read-only production journey; deliberately outside the daily test scheme.
@MainActor
final class ApplicationShareLiveTests: XCTestCase {
    func testDirectoryExportUsesTheLiveDetailsAndContainsScannablePNGsAndAManifest() async throws {
        await CatalogIconStore.shared.refresh()
        let directory = try await ApplicationShareExporter().directory(slugs: ["dayun-kicker", "air-conditioner"],
            appearances: ApplicationShareAppearance.allCases)
        XCTAssertEqual(directory.manifest.cards.count, 4)
        XCTAssertTrue(directory.manifest.failures.isEmpty)
        for card in directory.manifest.cards {
            let data = try Data(contentsOf: directory.url.appendingPathComponent(card.filename))
            let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
            XCTAssertEqual(decoded, [card.websiteUrl])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "batch-" + card.filename; attachment.lifetime = .keepAlways; add(attachment)
        }
        let manifest = XCTAttachment(data: try Data(contentsOf: directory.url.appendingPathComponent("manifest.json")),
            uniformTypeIdentifier: "public.json")
        manifest.name = "batch-manifest.json"; manifest.lifetime = .keepAlways; add(manifest)
    }

    func testPublicDetailAndRealIconsExportScannableLightAndDarkCards() async throws {
        let apps = try await CatalogService().applications()
        let manifest = try await CatalogIconService().manifest()
        let pipeline = ApplicationImagePipeline()
        for key in ["dayun-kicker"] {
            let listed = try XCTUnwrap(apps.first { $0.marketShortName == key })
            let current = try await CatalogService().application(reference: key)
            XCTAssertEqual(listed.id, current.id)
            XCTAssertEqual(listed.websiteUrl, current.websiteUrl)
            for appearance in ApplicationShareAppearance.allCases {
                let icon = try await pipeline.load(current.iconCandidates(dark: appearance == .dark,
                    downloaded: manifest.assets, websites: manifest.websiteIcons), pixelSize: 256)
                let image = try ApplicationShareCardRenderer.image(application: current, appearance: appearance,
                    icon: UIImage(cgImage: icon.bitmap.image))
                let decoded = try await PhotoQRCodeDecoder().payloads(in: XCTUnwrap(image.pngData()))
                XCTAssertEqual(decoded, [current.websiteUrl!])
                let attachment = XCTAttachment(image: image)
                attachment.name = "live-share-\(key)-\(appearance.rawValue)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
