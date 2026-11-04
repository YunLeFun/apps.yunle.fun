import Foundation
import UIKit

@MainActor
protocol ApplicationShareIconLoading {
    func image(for application: CloudApplication, appearance: ApplicationShareAppearance) async throws -> UIImage?
}

@MainActor
struct CatalogShareIconLoader: ApplicationShareIconLoading {
    func image(for application: CloudApplication, appearance: ApplicationShareAppearance) async throws -> UIImage? {
        let store = CatalogIconStore.shared
        let candidates = application.iconCandidates(dark: appearance == .dark, downloaded: store.assets, websites: store.websiteIcons)
        guard !candidates.isEmpty else { return nil }
        let result = try await ApplicationImagePipeline.shared.load(candidates, pixelSize: 256)
        return UIImage(cgImage: result.bitmap.image)
    }
}

struct ApplicationShareExportManifest: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    var cards: [Card]
    var failures: [Failure]

    struct Card: Codable {
        let applicationID: String
        let slug: String
        let name: String
        let websiteUrl: String
        let appearance: String
        let filename: String
        let usedFallbackIcon: Bool
    }
    struct Failure: Codable {
        let slug: String
        let message: String
    }
}

/// Retained while the picker copies. UIKit may cache a dismissed coordinator,
/// so successful exports also discard explicitly; deinit is the final fallback.
final class ApplicationShareExportDirectory: Identifiable {
    let id = UUID()
    let url: URL
    let manifest: ApplicationShareExportManifest
    fileprivate init(url: URL, manifest: ApplicationShareExportManifest) { self.url = url; self.manifest = manifest }
    func discard() { try? FileManager.default.removeItem(at: url) }
    deinit { discard() }
}

enum ApplicationShareExportError: LocalizedError, Equatable {
    case invalidSlug, emptySelection, noCards
    var errorDescription: String? {
        switch self {
        case .invalidSlug: return "请输入有效的应用 slug 或公开应用 ID。"
        case .emptySelection: return "当前没有可导出的公开应用。"
        case .noCards: return "没有成功生成卡片，请检查应用网址和网络后重试。"
        }
    }
}

@MainActor
struct ApplicationShareExporter {
    let catalog: any CatalogServing & ApplicationAvailabilityServing
    let icons: any ApplicationShareIconLoading
    let temporaryRoot: URL

    init(catalog: any CatalogServing & ApplicationAvailabilityServing = CatalogService(),
         icons: (any ApplicationShareIconLoading)? = nil,
         temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.catalog = catalog; self.icons = icons ?? CatalogShareIconLoader(); self.temporaryRoot = temporaryRoot
    }

    func application(slug: String) async throws -> CloudApplication {
        guard NativeLink.validAppKey(slug) else { throw ApplicationShareExportError.invalidSlug }
        let app = try await catalog.application(reference: slug)
        guard app.accessWorkshopID == nil, app.accessOwnerID == nil, app.personalMarketOwnerLogin == nil,
              app.isPublic != false, app.isUnavailable != true, app.audience == nil || app.audience == "public"
        else { throw ApplicationUnavailableReason.unavailable }
        return app
    }

    func render(_ application: CloudApplication, appearance: ApplicationShareAppearance) async throws -> (image: UIImage, usedFallbackIcon: Bool) {
        _ = try ApplicationShareQRCode.payload(for: application)
        var icon: UIImage?
        do { icon = try await icons.image(for: application, appearance: appearance) }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation() }
        try Task.checkCancellation()
        return (try ApplicationShareCardRenderer.image(application: application, appearance: appearance, icon: icon), icon == nil)
    }

    /// nil slugs means the live public catalog. Each record is refreshed from
    /// the detail endpoint, even when a cached list supplied its identifier.
    func directory(slugs: [String]? = nil, appearances: [ApplicationShareAppearance],
                   progress: (Int, Int, String) -> Void = { _, _, _ in }) async throws -> ApplicationShareExportDirectory {
        let keys: [String]
        if let slugs { keys = slugs }
        else { keys = try await catalog.applications().map(\.publicKey) }
        var seen = Set<String>()
        let unique = keys.filter { seen.insert($0).inserted }
        let styles = ApplicationShareAppearance.allCases.filter { appearances.contains($0) }
        guard !unique.isEmpty, !styles.isEmpty else { throw ApplicationShareExportError.emptySelection }
        try Task.checkCancellation()
        let directory = temporaryRoot.appendingPathComponent("YunLeFun-Share-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifest = ApplicationShareExportManifest(schemaVersion: 1, generatedAt: Date(), pixelWidth: 1080,
            pixelHeight: 1620, cards: [], failures: [])
        do {
            for (index, key) in unique.enumerated() {
                try Task.checkCancellation()
                progress(index, unique.count, key)
                do {
                    let current = try await application(slug: key)
                    guard key.utf8.count <= 200 else { throw ApplicationShareExportError.invalidSlug }
                    for style in styles {
                        try Task.checkCancellation()
                        let result = try await render(current, appearance: style)
                        let filename = key + "-" + style.rawValue + ".png"
                        guard let data = result.image.pngData() else { throw ApplicationShareCardError.renderingFailed }
                        try data.write(to: directory.appendingPathComponent(filename), options: .withoutOverwriting)
                        manifest.cards.append(.init(applicationID: current.id, slug: current.marketShortName ?? current.slug ?? key,
                            name: current.name, websiteUrl: try ApplicationShareQRCode.payload(for: current), appearance: style.rawValue,
                            filename: filename, usedFallbackIcon: result.usedFallbackIcon))
                        await Task.yield()
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    manifest.failures.append(.init(slug: key, message: error.localizedDescription))
                }
                progress(index + 1, unique.count, key)
            }
            try Task.checkCancellation()
            guard !manifest.cards.isEmpty else { throw ApplicationShareExportError.noCards }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            return ApplicationShareExportDirectory(url: directory, manifest: manifest)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
