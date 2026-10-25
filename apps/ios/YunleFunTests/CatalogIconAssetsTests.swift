import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class CatalogIconAssetsTests: XCTestCase {
    func testExplicitDarkAndLightIconsPrecedeOfficialAndSelectedFallbacks() {
        let app = CloudApplication(id: "record", name: "做菜", marketShortName: "cook",
            logo: "https://example.test/legacy.png",
            iconAssets: .init(appIcon: .init(src: "https://example.test/light.svg", darkSrc: "https://example.test/dark.svg"),
                              mark: .init(src: "https://example.test/mark.svg")))
        let urls = app.iconCandidates(dark: true).map { $0.url.absoluteString }
        XCTAssertEqual(urls, ["https://example.test/dark.svg", "https://example.test/light.svg",
                             CatalogIconAssets.bySlug["cook"]!.official!, "https://example.test/mark.svg",
                             "https://example.test/legacy.png", CatalogIconAssets.bySlug["cook"]!.thumbnail])
        XCTAssertEqual(app.iconCandidates(dark: false).first?.url.absoluteString, "https://example.test/light.svg")
    }

    func testPublishedLegacyURLsAreReplacedAndDeduplicated() {
        for (slug, old) in [("paper-star", "https://play.yunle.fun/games/paper-star/icon.png"),
                            ("smap", "https://smap.yunle.fun/smap-logo.svg")] {
            let app = CloudApplication(id: "record", name: slug, marketShortName: slug, logo: old,
                                       iconAssets: .init(appIcon: .init(src: old)))
            let candidates = app.iconCandidates(dark: false)
            XCTAssertEqual(candidates.map { $0.url.absoluteString }, [CatalogIconAssets.bySlug[slug]!.official!,
                                                                    CatalogIconAssets.bySlug[slug]!.thumbnail])
            XCTAssertEqual(candidates.first?.role, .appIcon)
        }
    }

    func testEverySelectedApplicationHasAnImageAndMissingMetadataUsesOfficialFirst() {
        XCTAssertEqual(CatalogIconAssets.bySlug.count, 28)
        for (slug, asset) in CatalogIconAssets.bySlug {
            let app = CloudApplication(id: "record", name: slug, marketShortName: slug, emoji: "☁️")
            let candidates = app.iconCandidates(dark: false)
            XCTAssertEqual(candidates.first?.url.absoluteString, asset.official ?? asset.thumbnail, slug)
            XCTAssertEqual(candidates.last?.url.absoluteString, asset.thumbnail, slug)
        }
        // The approved brush stays selected; never restore Saier's superseded S artwork.
        XCTAssertTrue(CatalogIconAssets.bySlug["pixi-painter"]!.thumbnail.contains("/v1/"))
    }

    func testPrivateAndPersonalRevisionsNeverInheritPublicBrandBySlug() {
        let base = CloudApplication(id: "private", name: "自己的应用", slug: "cook", logo: "https://example.test/private.png")
        var variants: [CloudApplication] = []
        var app = base; app.accessWorkshopID = "w"; variants.append(app)
        app = base; app.accessOwnerID = "u"; variants.append(app)
        app = base; app.personalMarketOwnerLogin = "author"; variants.append(app)
        app = base; app.isPublic = false; variants.append(app)
        app = base; app.audience = "workshop"; variants.append(app)
        for app in variants {
            XCTAssertEqual(app.iconCandidates(dark: false).map { $0.url.absoluteString }, ["https://example.test/private.png"])
        }
        XCTAssertTrue(CloudApplication(id: "unknown", name: "新应用", emoji: "☁️").iconCandidates(dark: false).isEmpty)
    }
}
