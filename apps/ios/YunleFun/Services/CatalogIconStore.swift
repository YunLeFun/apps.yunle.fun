import Combine
import Foundation
import OSLog

/// The public artwork manifest is independent of the application/access catalog.
/// Only selected artwork is accepted; future metadata fields can be ignored.
struct CatalogIconManifest: Sendable {
    static let maximumBytes = 2 * 1024 * 1024
    let data: Data
    let assets: [String: CatalogIconAssets.Asset]
    let websiteIcons: [String: CatalogIconAssets.WebsiteAsset]

    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw CatalogIconError.invalidManifest }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, !document.assets.isEmpty, document.assets.count <= 2_000
        else { throw CatalogIconError.invalidManifest }
        var assets: [String: CatalogIconAssets.Asset] = [:]
        for entry in document.assets {
            let selected = entry.desktopAsset, image = selected.thumbnail
            guard Self.matches(entry.slug, #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#), entry.slug.count <= 100,
                  assets[entry.slug] == nil, selected.usage == "desktop-selected",
                  selected.status == nil || selected.status == "active",
                  ["official", "generated"].contains(selected.kind), Self.matches(selected.version, #"^v[1-9]\d*$"#),
                  image.width == 256, image.height == 256, image.mime == "image/webp",
                  image.bytes > 0, image.bytes <= 5 * 1024 * 1024, Self.isHash(image.sha256),
                  Self.publicURL(image.url) != nil,
                  image.url == "https://yunlefun-cos-1253292018.cos.ap-shanghai.myqcloud.com/desktop/app-icons/\(selected.version)/\(entry.slug).webp"
            else { throw CatalogIconError.invalidManifest }
            var official: String?
            if selected.kind == "official" {
                guard let source = selected.source, source.kind == "official-source", Self.isHash(source.sha256),
                      let sourceURL = source.url, let url = Self.publicURL(sourceURL),
                      ["svg", "png", "webp", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
                else { throw CatalogIconError.invalidManifest }
                official = sourceURL
            }
            // A source can change bytes without changing URL. Its revision also invalidates the image cache.
            let revision = selected.version + ":" + image.sha256 + ":" + (selected.kind == "official" ? selected.source!.sha256 : "")
            assets[entry.slug] = .init(official: official, thumbnail: image.url, revision: revision)
        }
        var websites: [String: CatalogIconAssets.WebsiteAsset] = [:]
        for entry in document.websiteIcons ?? [] {
            guard websites.count < 2_000, websites[entry.origin] == nil,
                  let origin = Self.publicURL(entry.origin), PublicMediaURL.origin(of: origin) == entry.origin,
                  Self.matches(origin.host ?? "", #"^[a-z0-9-]+(?:\.[a-z0-9-]+)+$"#),
                  Self.matches(entry.icon, #"^([a-z0-9]+(?:-[a-z0-9]+)*)-(app-icon|mark)$"#),
                  Self.publicURL(entry.url) != nil, Self.isHash(entry.sha256) else { throw CatalogIconError.invalidManifest }
            let variant = entry.icon.hasSuffix("-app-icon") ? "app-icon" : "mark"
            let product = String(entry.icon.dropLast(variant.count + 1))
            let canonical = "https://icons.yunle.fun/products/\(product)/\(variant).svg"
            let pinned = #"^https://raw\.githubusercontent\.com/YunLeFun/icons/[a-f0-9]{40}/packages/icons/svg/"# + entry.icon + #"\.svg$"#
            guard entry.url == canonical || Self.matches(entry.url, pinned) else { throw CatalogIconError.invalidManifest }
            websites[entry.origin] = .init(url: entry.url, role: variant == "app-icon" ? .appIcon : .mark, revision: entry.sha256)
        }
        self.websiteIcons = websites
        self.data = data
        self.assets = assets
    }

    private static func matches(_ string: String, _ expression: String) -> Bool {
        string.range(of: expression, options: .regularExpression) != nil
    }
    private static func isHash(_ value: String) -> Bool { matches(value, "^[a-f0-9]{64}$") }
    private static func publicURL(_ value: String) -> URL? {
        guard value.count <= 2_048, let parts = URLComponents(string: value), parts.scheme == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.port == nil || parts.port == 443
        else { return nil }
        return parts.url
    }

    private struct Document: Decodable { let schemaVersion: Int; let assets: [Entry]; let websiteIcons: [Website]? }
    private struct Website: Decodable { let origin: String; let icon: String; let url: String; let sha256: String }
    private struct Entry: Decodable { let slug: String; let desktopAsset: Selected }
    private struct Selected: Decodable {
        let kind: String; let version: String; let usage: String; let status: String?
        let thumbnail: Thumbnail; let source: Source?
    }
    private struct Thumbnail: Decodable {
        let url: String; let width: Int; let height: Int; let mime: String; let bytes: Int; let sha256: String
    }
    private struct Source: Decodable { let kind: String; let url: String?; let sha256: String }
}

enum CatalogIconError: Error { case invalidManifest, invalidResponse }

protocol CatalogIconFetching {
    func manifest() async throws -> CatalogIconManifest
}

struct CatalogIconService: CatalogIconFetching {
    static let endpoints = [
        URL(string: "https://icons.yunle.fun/app-assets/manifest.json")!,
        URL(string: "https://raw.githubusercontent.com/YunLeFun/icons/main/assets/catalog/app-assets.json")!
    ]
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config, delegate: CatalogIconRedirectPolicy(), delegateQueue: nil)
        }
    }

    func manifest() async throws -> CatalogIconManifest {
        var lastError: Error = CatalogIconError.invalidResponse
        for endpoint in Self.endpoints {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.expectedContentLength <= CatalogIconManifest.maximumBytes
                else { throw CatalogIconError.invalidResponse }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < CatalogIconManifest.maximumBytes else { throw CatalogIconError.invalidManifest }
                    data.append(byte)
                }
                return try CatalogIconManifest(data: data)
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }
}

private final class CatalogIconRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A manifest request may only reach the two explicitly configured public sources.
        guard let url = request.url, CatalogIconService.endpoints.contains(url) else { completionHandler(nil); return }
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Authorization"); next.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(next)
    }
}

@MainActor
final class CatalogIconStore: ObservableObject {
    static let shared = CatalogIconStore()
    static let refreshInterval: TimeInterval = 60 * 60
    static let retryInterval: TimeInterval = 60
    enum Source: Equatable { case bundled, cache, network }

    /// Only downloaded entries live here. The resolver always keeps the bundled snapshot behind them.
    @Published private(set) var assets: [String: CatalogIconAssets.Asset] = [:]
    @Published private(set) var websiteIcons: [String: CatalogIconAssets.WebsiteAsset] = [:]
    private(set) var source: Source = .bundled
    private(set) var lastSuccess: Date?
    private(set) var lastAttempt: Date?
    private let service: CatalogIconFetching
    private let cacheURL: URL
    private let now: () -> Date
    private var inflight: Task<Void, Never>?
    private let logger = Logger(subsystem: "fun.yunle.apps", category: "catalog-icons")

    init(service: CatalogIconFetching = CatalogIconService(), cacheURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "fun.yunle.apps", isDirectory: true)
            .appendingPathComponent("catalog-icons/manifest.json")
        // Bounded, validated cache reads happen before the first frame. Cache age never blocks offline use.
        if let size = try? self.cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= CatalogIconManifest.maximumBytes,
           let data = try? Data(contentsOf: self.cacheURL), let manifest = try? CatalogIconManifest(data: data) {
            assets = manifest.assets; websiteIcons = manifest.websiteIcons; source = .cache
        }
    }

    func refresh(force: Bool = false) async {
        if let inflight { await inflight.value; return }
        if !force {
            if let lastSuccess, now().timeIntervalSince(lastSuccess) < Self.refreshInterval { return }
            if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.retryInterval { return }
        }
        lastAttempt = now()
        // One shared refresh survives an individual view disappearing; it never blocks the first frame.
        let task = Task { await self.update() }
        inflight = task
        await task.value
        inflight = nil
    }

    private func update() async {
        do {
            let manifest = try await service.manifest()
            try Task.checkCancellation()
            if assets != manifest.assets { assets = manifest.assets }
            if websiteIcons != manifest.websiteIcons { websiteIcons = manifest.websiteIcons }
            source = .network; lastSuccess = now()
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manifest.data.write(to: cacheURL, options: .atomic)
            } catch { logger.error("Icon manifest cache write failed; keeping the downloaded manifest in memory") }
        } catch is CancellationError { return }
        catch { logger.info("Icon manifest refresh failed; retaining cached and bundled artwork") }
    }

    /// Called by the shared foreground lifecycle modifier, not once per icon.
    func refreshWhileActive() async {
        while !Task.isCancelled {
            await refresh()
            let remaining = lastSuccess.map { Self.refreshInterval - now().timeIntervalSince($0) } ?? Self.retryInterval
            let delay = min(Self.refreshInterval, max(Self.retryInterval, remaining))
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
        }
    }
}

extension CatalogStore {
    func refreshWithIcons() async {
        async let icons: Void = CatalogIconStore.shared.refresh(force: true)
        await load()
        await icons
    }
}
