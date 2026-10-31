import ImageIO
import SwiftUI
import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class ApplicationIconTests: XCTestCase {
    func testFirstPartyWorkshopIconsReuseTheirWebsiteAssets() {
        let admin = CloudApplication(id: "private-admin", name: "管理后台", websiteUrl: "https://admin.yunle.fun/console?tab=apps",
            emoji: "🛠️", audience: "workshop", accessWorkshopID: "ABC234")
        let support = CloudApplication(id: "private-support", name: "支持中心", websiteUrl: "https://support.yunle.fun/tickets",
            emoji: "💬", audience: "workshop", accessWorkshopID: "ABC234")
        XCTAssertEqual(admin.iconCandidates(dark: false).first?.url.absoluteString, CatalogIconAssets.byOrigin["https://admin.yunle.fun"]?.url)
        XCTAssertEqual(admin.iconCandidates(dark: true).first?.role, .appIcon)
        XCTAssertEqual(support.iconCandidates(dark: false).first?.url.absoluteString, CatalogIconAssets.byOrigin["https://support.yunle.fun"]?.url)
        XCTAssertEqual(support.iconCandidates(dark: true).first?.role, .appIcon)
    }
    func testWebsiteIconFallbackRespectsConfiguredArtworkAndExactOrigin() {
        let app = CloudApplication(id: "support", name: "支持中心", websiteUrl: "https://support.yunle.fun/",
            logo: "https://example.test/custom.svg", iconAssets: .init(appIcon: .init(src: "https://example.test/app.png")))
        XCTAssertEqual(app.iconCandidates(dark: false).map { $0.url.absoluteString },
            ["https://example.test/app.png", "https://example.test/custom.svg", CatalogIconAssets.byOrigin["https://support.yunle.fun"]!.url])
        for url in ["https://support.yunle.fun.attacker.test", "https://support.yunle.fun:8443", "http://support.yunle.fun", "https://user:password@admin.yunle.fun"] {
            let unverified = CloudApplication(id: "admin", name: "应用", websiteUrl: url)
            XCTAssertTrue(unverified.iconCandidates(dark: false).isEmpty, url)
        }
    }
    func testPublicCloudIconReopensWithoutSignedURLOrAccount() throws {
        let path = "/app-icons/0123456789abcdef/123e4567-e89b-12d3-a456-426614174000.png"
        let source = "cloud://" + PublicMediaURL.environment + "." + PublicMediaURL.bucket + path
        let expected = PublicMediaURL.origin + path
        XCTAssertEqual(PublicMediaURL.resolve(source)?.absoluteString, expected)
        XCTAssertEqual(PublicMediaURL.resolve(expected + "?sign=expired#old")?.absoluteString, expected)
        let privateURL = PublicMediaURL.origin + "/private/file.png?sign=keep"
        XCTAssertEqual(PublicMediaURL.resolve(privateURL)?.absoluteString, privateURL)
        for value in [
            "cloud://other." + PublicMediaURL.bucket + path,
            source + "?sign=untrusted", source + "#part",
            "cloud://" + PublicMediaURL.environment + ".other" + path,
            "cloud://" + PublicMediaURL.environment + "." + PublicMediaURL.bucket + "/private/image.png",
            "https://user:secret@example.test/icon.png", "http://example.test/icon.png", "file:///icon.png"
        ] { XCTAssertNil(PublicMediaURL.resolve(value), value) }
        XCTAssertEqual(PublicMediaURL.resolve("https://example.test/icon.png?size=50")?.query, "size=50")
    }

    func testDarkVariantPrecedesLightRasterAndMarkRemainsSeparate() {
        let full = CloudApplication.IconAssets.Variants(src: "https://example.test/full.svg", darkSrc: "https://example.test/dark.svg", png: "https://example.test/full.png")
        let mark = CloudApplication.IconAssets.Variants(src: "https://example.test/mark.svg", darkSrc: "https://example.test/mark-dark.svg")
        let app = CloudApplication(id: "a", name: "作品", logo: "https://example.test/legacy.ico", iconAssets: .init(appIcon: full, mark: mark))
        XCTAssertEqual(app.iconCandidates(dark: false).first?.url.lastPathComponent, "full.png")
        XCTAssertEqual(app.iconCandidates(dark: true).first?.url.lastPathComponent, "dark.svg")
        XCTAssertEqual(app.iconCandidates(dark: true).first(where: { $0.role == .mark })?.url.lastPathComponent, "mark-dark.svg")
        let fallback = CloudApplication(id: "b", name: "作品", logo: "https://example.test/legacy.png",
            iconAssets: .init(appIcon: .init(src: "cloud://other.bucket/private.png"), mark: mark))
        XCTAssertEqual(fallback.iconCandidates(dark: false).first?.role, .mark)
    }

    func testActualSVGGradientAndOrientationAreRasterized() throws {
        let data = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="yellow"/></linearGradient></defs><rect width="100" height="50" fill="url(#g)"/><rect y="50" width="100" height="50" fill="blue"/></svg>"##.utf8)
        let image = try ApplicationImageDecoder.decode(data, maximumPixelSize: 128).image
        XCTAssertEqual(image.width, 128); XCTAssertEqual(image.height, 128)
        let top = try pixel(image, x: 16, y: 16), bottom = try pixel(image, x: 16, y: 112)
        XCTAssertGreaterThan(top[0], 220); XCTAssertLessThan(top[2], 30)
        XCTAssertGreaterThan(bottom[2], 220); XCTAssertLessThan(bottom[0], 30)
    }

    func testSVGRejectsExternalResourcesDTDAndReferenceCycles() {
        let contents = [
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><use href="https://example.test/secret.svg#a"/></svg>"##,
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script>alert(1)</script></svg>"##,
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><style>.loop{fill:url(#p)}</style><defs><pattern id="p" width="1" height="1" patternUnits="objectBoundingBox"><rect class="loop" width="10" height="10"/></pattern></defs><rect class="loop" width="10" height="10"/></svg>"##,
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><g id="a"><use href="#a"/></g></svg>"##,
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><defs><g id="a"><use href="#b"/></g><g id="b"><use href="#a"/></g></defs><use href="#a"/></svg>"##,
            ##"<!DOCTYPE svg [<!ENTITY e SYSTEM "file:///tmp/data">]><svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">&e;</svg>"##,
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="url(https://example.test/a)"/></svg>"##
        ]
        for xml in contents { XCTAssertThrowsError(try ApplicationImageDecoder.decode(Data(xml.utf8), maximumPixelSize: 128), xml) }
    }

    #if os(iOS)
    func testSVGUploadUsesSamePNGAndMarkSafeAreaContract() async throws {
        let xml = ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect x="25" y="25" width="50" height="50" fill="red"/></svg>"##
        let data = try await ApplicationIconNormalizer().normalize(Data(xml.utf8), role: .mark)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1024); XCTAssertEqual(image.height, 1024)
        XCTAssertEqual(try pixel(image, x: 0, y: 0)[3], 0)
        XCTAssertGreaterThan(try pixel(image, x: 512, y: 512)[3], 250)
        let nonSquare = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="red"/></svg>"##.utf8)
        do { _ = try await ApplicationIconNormalizer().normalize(nonSquare, role: .appIcon); XCTFail("Reject a stretched full icon") }
        catch { XCTAssertEqual(error as? IconNormalizationError, .notSquare) }
    }

    #endif

    func testConcurrentLoadsCoalesceAndUseMemoryCache() async throws {
        let fixture = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)]
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<12 { group.addTask { try await pipeline.load(candidates, pixelSize: 128).bitmap.image.width } }
            for try await width in group { XCTAssertEqual(width, 128) }
        }
        _ = try await pipeline.load(candidates, pixelSize: 128)
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Cookie"))
    }

    @MainActor
    func testRecreatedIconRendersCachedArtworkBeforeItsLoadingTaskRuns() async throws {
        let fixture = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)]
        _ = try await pipeline.load(candidates, pixelSize: 128)

        // ImageRenderer does not run .task: each render is the first frame of
        // a newly created icon, as when returning to a recreated home screen.
        for _ in 0..<3 {
            let renderer = ImageRenderer(content: ApplicationIconImage(candidates: candidates, pixelSize: 128, pipeline: pipeline) {
                Color.blue
            }.frame(width: 48, height: 48))
            let image = try XCTUnwrap(renderer.cgImage)
            let center = try pixel(image, x: image.width / 2, y: image.height / 2)
            XCTAssertGreaterThan(center[0], 240, "A warm icon must draw its artwork on the first frame, without showing loading")
            XCTAssertLessThan(center[2], 20)
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testInvalidPrimaryFallsBackToMarkAndFailuresDoNotSpin() async throws {
        let fixture = IconHTTPFixture(replies: ["/bad.svg": (200, Data("not an image".utf8), nil), "/mark.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/bad.svg")!, role: .appIcon),
                          ApplicationIconCandidate(url: URL(string: "https://\(host)/mark.svg")!, role: .mark)]
        let loaded = try await pipeline.load(candidates, pixelSize: 128)
        XCTAssertEqual(loaded.candidate.role, .mark)
        XCTAssertEqual(pipeline.cachedIcon(candidates, pixelSize: 128)?.candidate.role, .mark)
        _ = try await pipeline.load(candidates, pixelSize: 128)
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testImmediateCacheLookupUsesTheSamePixelSizeLimitsAsLoading() async throws {
        let fixture = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)]
        XCTAssertNil(pipeline.cachedIcon(candidates, pixelSize: 16))
        _ = try await pipeline.load(candidates, pixelSize: 16)
        XCTAssertEqual(pipeline.cachedIcon(candidates, pixelSize: 16)?.bitmap.image.width, 64)
        XCTAssertNotNil(pipeline.cachedIcon(candidates, pixelSize: 64))
        XCTAssertNil(pipeline.cachedIcon(candidates, pixelSize: 128))
        _ = try await pipeline.load(candidates, pixelSize: 2048)
        XCTAssertEqual(pipeline.cachedIcon(candidates, pixelSize: 2048)?.bitmap.image.width, 1024)
        XCTAssertNotNil(pipeline.cachedIcon(candidates, pixelSize: 1024))
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testOversizedHTTPResponseFallsBackBeforeDecode() async throws {
        let fixture = IconHTTPFixture(replies: ["/large": (200, Data(), 20 * 1024 * 1024), "/valid": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let result = try await pipeline.load([
            ApplicationIconCandidate(url: URL(string: "https://\(host)/large")!, role: .appIcon),
            ApplicationIconCandidate(url: URL(string: "https://\(host)/valid")!, role: .legacy)
        ], pixelSize: 128)
        XCTAssertEqual(result.candidate.role, .legacy)
    }

    func testCompleteCandidateChainReachesSelectedImageAfterAllVariantsFail() async throws {
        let fixture = IconHTTPFixture(replies: ["/selected.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        var candidates = (0..<10).map {
            ApplicationIconCandidate(url: URL(string: "https://\(host)/missing-\($0)")!, role: .appIcon)
        }
        candidates.append(ApplicationIconCandidate(url: URL(string: "https://\(host)/selected.svg")!, role: .appIcon))
        let result = try await pipeline.load(candidates, pixelSize: 128)
        XCTAssertEqual(result.candidate.url.lastPathComponent, "selected.svg")
        XCTAssertEqual(fixture.requests.count, 11)
    }

    func testUnavailableIsReportedOnlyAfterEveryImageSourceFails() async throws {
        let fixture = IconHTTPFixture(replies: [:])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let candidates = ["official.svg", "selected.webp"].map {
            ApplicationIconCandidate(url: URL(string: "https://\(host)/\($0)")!, role: .appIcon)
        }
        do { _ = try await pipeline.load(candidates, pixelSize: 128); XCTFail("All missing sources must fail") }
        catch { XCTAssertEqual(fixture.requests.count, 2) }
    }

    func testManifestRevisionInvalidatesMemoryCacheForTheSameURL() async throws {
        let fixture = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let url = URL(string: "https://\(host)/icon.svg")!
        let old = ApplicationIconCandidate(url: url, role: .appIcon, revision: "revision-1")
        let new = ApplicationIconCandidate(url: url, role: .appIcon, revision: "revision-2")
        _ = try await pipeline.load([old], pixelSize: 128)
        XCTAssertNotNil(pipeline.cachedIcon([old], pixelSize: 128))
        XCTAssertNil(pipeline.cachedIcon([new], pixelSize: 128), "First-frame rendering must not reuse a previous manifest revision")
        _ = try await pipeline.load([old], pixelSize: 128)
        XCTAssertEqual(fixture.requests.count, 1)
        _ = try await pipeline.load([new], pixelSize: 128)
        XCTAssertEqual(fixture.requests.count, 2, "A new manifest revision must not reuse pixels from the previous revision")
    }

    func testDiskCacheReopensOfflineAndReusesSourceAcrossSizes() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon, revision: "v1")]
        _ = try await writer.load(candidates, pixelSize: 128)
        let offline = IconHTTPFixture(replies: [:])
        let (reopened, _) = iconPipeline(offline, cacheDirectory: directory, host: host)
        XCTAssertNil(reopened.cachedIcon(candidates, pixelSize: 64), "A new pipeline has no decoded memory cache")
        let cached = try await reopened.cachedIconFromDisk(candidates, pixelSize: 64)
        XCTAssertEqual(cached?.bitmap.image.width, 64)
        let loaded = try await reopened.load(candidates, pixelSize: 256)
        XCTAssertEqual(loaded.bitmap.image.width, 256)
        XCTAssertEqual(first.requests.count, 1)
        XCTAssertTrue(offline.requests.isEmpty, "Unchanged versioned artwork must reopen without network access")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testUnversionedDiskCacheRevalidatesWithHTTPValidators() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let modified = "Wed, 21 Oct 2015 07:28:00 GMT"
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)], headers: ["ETag": "\"icon-v1\"", "Last-Modified": modified])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)]
        _ = try await writer.load(candidates, pixelSize: 128)
        let unchanged = IconHTTPFixture(replies: ["/icon.svg": (304, Data(), nil)])
        let (reopened, _) = iconPipeline(unchanged, cacheDirectory: directory, host: host)
        let cached = try await reopened.cachedIconFromDisk(candidates, pixelSize: 128)
        XCTAssertNotNil(cached)
        XCTAssertTrue(unchanged.requests.isEmpty, "Local artwork must be available before checking for updates")
        let loaded = try await reopened.load(candidates, pixelSize: 128)
        XCTAssertEqual(loaded.bitmap.image.width, 128)
        XCTAssertEqual(unchanged.requests.count, 1)
        XCTAssertEqual(unchanged.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "\"icon-v1\"")
        XCTAssertEqual(unchanged.requests.first?.value(forHTTPHeaderField: "If-Modified-Since"), modified)
        _ = try await reopened.load(candidates, pixelSize: 128)
        XCTAssertEqual(unchanged.requests.count, 1, "A revalidated image is fresh in memory")
    }

    func testUnversionedChangedResponseReplacesDiskArtwork() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let modified = "Wed, 21 Oct 2015 07:28:00 GMT"
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)], headers: ["Last-Modified": modified])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)]
        _ = try await writer.load(candidates, pixelSize: 128)
        let changedSVG = Data(String(decoding: iconTestSVG, as: UTF8.self).replacingOccurrences(of: "#ff6600", with: "#0000ff").utf8)
        let changed = IconHTTPFixture(replies: ["/icon.svg": (200, changedSVG, nil)], headers: ["ETag": "\"new\""])
        let (reopened, _) = iconPipeline(changed, cacheDirectory: directory, host: host)
        let cached = try await reopened.cachedIconFromDisk(candidates, pixelSize: 128)
        XCTAssertLessThan(try pixel(XCTUnwrap(cached).bitmap.image, x: 64, y: 64)[2], 20)
        let updated = try await reopened.load(candidates, pixelSize: 128)
        XCTAssertGreaterThan(try pixel(updated.bitmap.image, x: 64, y: 64)[2], 240)
        XCTAssertNil(changed.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(changed.requests.first?.value(forHTTPHeaderField: "If-Modified-Since"), modified)
        let (nextLaunch, _) = iconPipeline(IconHTTPFixture(replies: [:]), cacheDirectory: directory, host: host)
        let persisted = try await nextLaunch.cachedIconFromDisk(candidates, pixelSize: 128)
        XCTAssertGreaterThan(try pixel(XCTUnwrap(persisted).bitmap.image, x: 64, y: 64)[2], 240)
    }

    func testNewRevisionDisplaysOldDiskImageThenAtomicallyReplacesIt() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)], headers: ["ETag": "\"old\""])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let url = URL(string: "https://\(host)/icon.svg")!
        let old = ApplicationIconCandidate(url: url, role: .appIcon, revision: "v1")
        let new = ApplicationIconCandidate(url: url, role: .appIcon, revision: "v2")
        _ = try await writer.load([old], pixelSize: 128)
        let updatedSVG = Data(String(decoding: iconTestSVG, as: UTF8.self).replacingOccurrences(of: "#ff6600", with: "#0000ff").utf8)
        let changed = IconHTTPFixture(replies: ["/icon.svg": (200, updatedSVG, nil)])
        let (reopened, _) = iconPipeline(changed, cacheDirectory: directory, host: host)
        let cached = try await reopened.cachedIconFromDisk([new], pixelSize: 128)
        XCTAssertEqual(cached?.candidate.revision, "v1")
        XCTAssertNil(reopened.cachedIcon([new], pixelSize: 128), "Stale display data must not satisfy a new revision")
        let updated = try await reopened.load([new], pixelSize: 128)
        XCTAssertGreaterThan(try pixel(updated.bitmap.image, x: 64, y: 64)[2], 240)
        XCTAssertEqual(changed.requests.count, 1)
        XCTAssertNil(changed.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "A manifest revision change requires fresh bytes")
        let offline = IconHTTPFixture(replies: [:])
        let (nextLaunch, _) = iconPipeline(offline, cacheDirectory: directory, host: host)
        let persisted = try await nextLaunch.load([new], pixelSize: 128)
        XCTAssertGreaterThan(try pixel(persisted.bitmap.image, x: 64, y: 64)[2], 240)
        XCTAssertTrue(offline.requests.isEmpty)
    }

    func testFailedRefreshPreservesLastValidDiskImage() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let url = URL(string: "https://\(host)/icon.svg")!
        let old = ApplicationIconCandidate(url: url, role: .appIcon, revision: "v1")
        let new = ApplicationIconCandidate(url: url, role: .appIcon, revision: "v2")
        _ = try await writer.load([old], pixelSize: 128)
        for reply in [(503, Data(), nil as Int?), (200, Data("broken image".utf8), nil as Int?)] {
            let failed = IconHTTPFixture(replies: ["/icon.svg": reply])
            let (reopened, _) = iconPipeline(failed, cacheDirectory: directory, host: host)
            let before = try await reopened.cachedIconFromDisk([new], pixelSize: 128)
            XCTAssertEqual(before?.candidate.revision, "v1")
            do { _ = try await reopened.load([new], pixelSize: 128); XCTFail("The new revision is not available") }
            catch { XCTAssertEqual(failed.requests.count, 1) }
            let after = try await reopened.cachedIconFromDisk([new], pixelSize: 128)
            XCTAssertEqual(after?.candidate.revision, "v1", "Failed HTTP or decoding must not overwrite the previous image")
        }
    }

    func testCorruptDiskEntryIsDiscardedAndDownloadedAgain() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let candidates = [ApplicationIconCandidate(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon, revision: "v1")]
        _ = try await writer.load(candidates, pixelSize: 128)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("damaged cache".utf8).write(to: file)
        let recovered = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (reopened, _) = iconPipeline(recovered, cacheDirectory: directory, host: host)
        let cached = try await reopened.cachedIconFromDisk(candidates, pixelSize: 128)
        XCTAssertNil(cached)
        _ = try await reopened.load(candidates, pixelSize: 128)
        XCTAssertEqual(recovered.requests.count, 1)
        let cache = ApplicationImageDiskCache(directory: directory)
        await cache.store(.init(url: candidates[0].url.absoluteString, revision: "v1", eTag: nil, lastModified: nil,
                                data: Data("invalid cached image".utf8)), for: candidates[0].url)
        let (invalidImage, _) = iconPipeline(recovered, cacheDirectory: directory, host: host)
        _ = try await invalidImage.load(candidates, pixelSize: 128)
        XCTAssertEqual(recovered.requests.count, 2, "Malformed image data inside a valid cache envelope also needs recovery")
    }

    func testDiskCacheEvictsLeastRecentlyUsedEntriesAndHonorsByteBudget() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ApplicationImageDiskCache(directory: directory, byteLimit: 4096, countLimit: 2)
        let urls = (0..<3).map { URL(string: "https://cache.test/\($0).svg")! }
        for index in 0..<2 {
            await cache.store(.init(url: urls[index].absoluteString, revision: "v1", eTag: nil, lastModified: nil, data: iconTestSVG), for: urls[index])
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: file.path) }
        }
        _ = await cache.entry(for: urls[0])
        await cache.store(.init(url: urls[2].absoluteString, revision: "v1", eTag: nil, lastModified: nil, data: iconTestSVG), for: urls[2])
        let retained = await cache.entry(for: urls[0]), evicted = await cache.entry(for: urls[1]), newest = await cache.entry(for: urls[2])
        XCTAssertNotNil(retained); XCTAssertNil(evicted); XCTAssertNotNil(newest)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let entry = ApplicationImageDiskCache.Entry(url: urls[0].absoluteString, revision: nil, eTag: nil, lastModified: nil, data: iconTestSVG)
        let byteLimit = try encoder.encode(entry).count * 2
        let small = ApplicationImageDiskCache(directory: directory.appendingPathComponent("small"), byteLimit: byteLimit, countLimit: 256)
        for url in urls { await small.store(.init(url: url.absoluteString, revision: nil, eTag: nil, lastModified: nil, data: iconTestSVG), for: url) }
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("small"), includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(bytes, byteLimit)
        XCTAssertLessThan(files.count, 3)
    }

    func testUnwritableDiskCacheDoesNotPreventLoadingArtwork() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("blocked")
        try Data("preserve".utf8).write(to: blocked)
        let fixture = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture, cacheDirectory: blocked); defer { IconHTTPProtocol.unregister(host) }
        let loaded = try await pipeline.load([.init(url: URL(string: "https://\(host)/icon.svg")!, role: .appIcon)], pixelSize: 128)
        XCTAssertEqual(loaded.bitmap.image.width, 128)
        XCTAssertEqual(try Data(contentsOf: blocked), Data("preserve".utf8))
    }

    private func iconCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("icon-cache-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    #if os(iOS)
    @MainActor
    func testIconViewKeepsDiskArtworkWhenNewRevisionRefreshFails() async throws {
        let directory = try iconCacheDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = IconHTTPFixture(replies: ["/icon.svg": (200, iconTestSVG, nil)])
        let (writer, host) = iconPipeline(first, cacheDirectory: directory); defer { IconHTTPProtocol.unregister(host) }
        let url = URL(string: "https://\(host)/icon.svg")!
        _ = try await writer.load([.init(url: url, role: .appIcon, revision: "v1")], pixelSize: 128)
        let failed = IconHTTPFixture(replies: ["/icon.svg": (503, Data(), nil)])
        let (reopened, _) = iconPipeline(failed, cacheDirectory: directory, host: host)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let content = ApplicationIconImage(candidates: [.init(url: url, role: .appIcon, revision: "v2")], pixelSize: 128, pipeline: reopened) {
            Color.blue
        }.frame(width: 100, height: 100)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        let deadline = Date().addingTimeInterval(10)
        var observedCenter: [UInt8]?
        // Disk decoding and SwiftUI's task can start later on a busy runner.
        // Require the failed refresh to finish and the real artwork to render.
        while Date() < deadline {
            if failed.completedResponseCount > 0 {
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let cg = try XCTUnwrap(image.cgImage)
                let center = try pixel(cg, x: cg.width / 2, y: cg.height / 2)
                observedCenter = center
                if center[0] > 240 && center[2] < 20 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(failed.completedResponseCount, 1, "The actual 503 refresh must finish before checking retained artwork")
        let center = try XCTUnwrap(observedCenter, "The view must render after the failed refresh within ten seconds")
        XCTAssertGreaterThan(center[0], 240, "The view must retain locally loaded artwork after a failed update")
        XCTAssertLessThan(center[2], 20)
        XCTAssertEqual(failed.requests.count, 1)
    }

    @MainActor
    func testIconLightAndDarkRenderFixtures() async throws {
        let darkSVG = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="#4f46e5"/><circle cx="50" cy="50" r="25" fill="#fbbf24"/></svg>"##.utf8)
        let markSVG = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40" fill="#22c55e"/></svg>"##.utf8)
        let fixture = IconHTTPFixture(replies: ["/light": (200, iconTestSVG, nil), "/dark": (200, darkSVG, nil), "/mark": (200, markSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let full = CloudApplication(id: "full", name: "完整图标", iconAssets: .init(appIcon: .init(src: "https://\(host)/light", darkSrc: "https://\(host)/dark")))
        let mark = CloudApplication(id: "mark", name: "透明主体", iconAssets: .init(mark: .init(src: "https://\(host)/mark")))
        let fallback = CloudApplication(id: "fallback", name: "备用图标", emoji: "☁️")
        for app in [full, mark] {
            _ = try await pipeline.load(app.iconCandidates(dark: false), pixelSize: Int(96 * UIScreen.main.scale))
            _ = try await pipeline.load(app.iconCandidates(dark: true), pixelSize: Int(96 * UIScreen.main.scale))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for dark in [false, true] {
            let content = VStack(alignment: .leading, spacing: 32) {
                Text("原生图标渲染样例").font(.title.bold())
                Text("隔离测试数据").foregroundStyle(.secondary)
                ForEach([full, mark, fallback]) { app in
                    HStack(spacing: 24) {
                        ApplicationIcon(application: app, size: 96, pipeline: pipeline)
                        Text(app.name).font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(32)
            .background(Color(uiColor: .systemBackground))
            .preferredColorScheme(dark ? .dark : .light)
            let controller = UIHostingController(rootView: content)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 300_000_000)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "icon-fixture-dark" : "icon-fixture-light"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(fixture.requests.count, 3)
    }

    @MainActor
    func testUnavailableArtworkIsGrayAndMissingArtworkKeepsADashedPlaceholder() async throws {
        let fixture = IconHTTPFixture(replies: ["/art.svg": (200, iconTestSVG, nil)])
        let (pipeline, host) = iconPipeline(fixture); defer { IconHTTPProtocol.unregister(host) }
        let original = CloudApplication(id: "artwork", name: "原应用", logo: "https://\(host)/art.svg")
        var cached = original; cached.isUnavailable = true
        let missing = CloudApplication(id: "unknown", name: "暂不可用", isUnavailable: true)
        let emoji = CloudApplication(id: "emoji", name: "缓存图标", emoji: "🎨", isUnavailable: true)
        _ = try await pipeline.load(original.iconCandidates(dark: false), pixelSize: Int(64 * UIScreen.main.scale))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 280)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for dark in [false, true] {
            for (name, app) in [("available", original), ("cached-unavailable", cached), ("missing", missing), ("emoji-unavailable", emoji)] {
                let controller = UIHostingController(rootView: ApplicationIcon(application: app, size: 64, pipeline: pipeline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground)).preferredColorScheme(dark ? .dark : .light))
                window.rootViewController = controller; window.makeKeyAndVisible()
                try await Task.sleep(nanoseconds: 180_000_000)
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
                let cg = try XCTUnwrap(image.cgImage)
                let center = try pixel(cg, x: cg.width / 2, y: cg.height / 2)
                if name == "available" { XCTAssertGreaterThan(Int(center[0]) - Int(center[2]), 100, "Actual loaded artwork must render before testing its unavailable state") }
                else { XCTAssertLessThanOrEqual(Int(center.prefix(3).max()!) - Int(center.prefix(3).min()!), 2, "Unavailable artwork must be desaturated in both appearances") }
            }
            let apps = [missing, cached, emoji, CloudApplication(id: "available-emoji", name: "云空调", emoji: "❄️")]
            let content = VStack(alignment: .leading, spacing: 24) {
                Text("我的应用").font(.title2.bold())
                HStack(alignment: .top, spacing: 30) {
                    ForEach(apps) { app in
                        HomeAppGlyph(name: app.name, labelWidth: 64, isUnavailable: app.isUnavailable == true) {
                            ApplicationIcon(application: app, size: 64, pipeline: pipeline)
                        }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: .systemBackground)).preferredColorScheme(dark ? .dark : .light)
            let controller = UIHostingController(rootView: content)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 200_000_000)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "home-unavailable-icons-" + (dark ? "dark" : "light")
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(fixture.requests.count, 1, "Showing cached unavailable artwork must reuse the existing image cache")
    }

    #endif

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        let offset = y * image.width * 4 + x * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }
}

let iconTestSVG = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="#ff6600"/></svg>"##.utf8)
private func iconPipeline(_ fixture: IconHTTPFixture, cacheDirectory: URL? = nil, host: String = UUID().uuidString.lowercased() + ".icons.test") -> (ApplicationImagePipeline, String) {
    IconHTTPProtocol.register(host, fixture)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [IconHTTPProtocol.self]
    config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
    return (ApplicationImagePipeline(session: URLSession(configuration: config), cacheDirectory: cacheDirectory), host)
}
final class IconHTTPFixture: @unchecked Sendable {
    let replies: [String: (Int, Data, Int?)]
    let headers: [String: String]
    private let lock = NSLock()
    private var captured: [URLRequest] = []
    private var completedResponses = 0
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    var completedResponseCount: Int { lock.lock(); defer { lock.unlock() }; return completedResponses }
    init(replies: [String: (Int, Data, Int?)], headers: [String: String] = [:]) { self.replies = replies; self.headers = headers }
    func response(_ request: URLRequest) -> (Int, Data, Int?) {
        lock.lock(); defer { lock.unlock() }; captured.append(request)
        return replies[request.url!.path] ?? (404, Data(), nil)
    }
    func responseDidFinish() { lock.lock(); defer { lock.unlock() }; completedResponses += 1 }
}
final class IconHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: IconHTTPFixture] = [:]
    static func register(_ host: String, _ fixture: IconHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[host] = fixture }
    static func unregister(_ host: String) { lock.lock(); defer { lock.unlock() }; fixtures[host] = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixtures[request.url!.host!]; Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let (status, data, size) = fixture.response(request)
        var headers = fixture.headers
        headers["Content-Length"] = String(size ?? data.count)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        fixture.responseDidFinish()
    }
    override func stopLoading() {}
}
