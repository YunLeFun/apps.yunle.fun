import Foundation
import ImageIO
import CoreGraphics
import CryptoKit

struct ApplicationBitmap: @unchecked Sendable {
    let image: CGImage
}
struct LoadedApplicationIcon: Sendable {
    let bitmap: ApplicationBitmap
    let candidate: ApplicationIconCandidate
}

enum ApplicationImageDecoder {
    static func decode(_ data: Data, maximumPixelSize: Int) throws -> ApplicationBitmap {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 5 * 1024 * 1024 else { throw ApplicationImageError.oversized }
        if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            guard width.doubleValue > 0, height.doubleValue > 0,
                  width.doubleValue * height.doubleValue <= 100_000_000 else { throw ApplicationImageError.oversized }
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, min(2048, maximumPixelSize)),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw ApplicationImageError.invalid }
            return ApplicationBitmap(image: image)
        }
        return ApplicationBitmap(image: try SVGIconDecoder.decode(data, maximumPixelSize: maximumPixelSize))
    }
}

actor ApplicationImagePipeline {
    static let shared = ApplicationImagePipeline()
    private let session: URLSession
    private let diskCache: ApplicationImageDiskCache?
    private nonisolated let cache = ApplicationImageMemoryCache()
    private var inflight: [String: Task<ApplicationBitmap, Error>] = [:]
    private var failedUntil: [String: Date] = [:]
    private let gate = ApplicationImageWorkGate()
    // Local artwork must not queue behind slow network refreshes.
    private let diskDecodeGate = ApplicationImageWorkGate()

    nonisolated static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "fun.yunle.apps", isDirectory: true)
            .appendingPathComponent("application-icons-v1", isDirectory: true)
    }

    init(session: URLSession? = nil, cacheDirectory: URL? = ApplicationImagePipeline.defaultCacheDirectory) {
        diskCache = cacheDirectory.map { ApplicationImageDiskCache(directory: $0) }
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: config, delegate: IconRedirectPolicy(), delegateQueue: nil)
        }
    }

    /// A view can draw a warm icon on its first frame without waiting for an actor hop.
    nonisolated func cachedIcon(_ candidates: [ApplicationIconCandidate], pixelSize: Int) -> LoadedApplicationIcon? {
        for candidate in candidates {
            guard PublicMediaURL.resolve(candidate.url.absoluteString) == candidate.url else { continue }
            let key = Self.cacheKey(candidate.url, pixelSize: pixelSize, revision: candidate.revision)
            if let bitmap = cache.bitmap(for: key) {
                return LoadedApplicationIcon(bitmap: bitmap, candidate: candidate)
            }
        }
        return nil
    }

    /// Disk I/O and decoding stay off the main actor. Stale artwork is presentation
    /// only: it must never make a new revision look fresh to the network loader.
    func cachedIconFromDisk(_ candidates: [ApplicationIconCandidate], pixelSize: Int) async throws -> LoadedApplicationIcon? {
        if let value = cachedIcon(candidates, pixelSize: pixelSize) { return value }
        guard let diskCache else { return nil }
        for candidate in candidates {
            try Task.checkCancellation()
            guard PublicMediaURL.resolve(candidate.url.absoluteString) == candidate.url,
                  let entry = await diskCache.entry(for: candidate.url) else { continue }
            do {
                let bitmap = try await decodeCached(entry.data, pixelSize: pixelSize)
                let stored = ApplicationIconCandidate(url: candidate.url, role: candidate.role, revision: entry.revision)
                if entry.revision != nil, entry.revision == candidate.revision {
                    cache.insert(bitmap, for: Self.cacheKey(candidate.url, pixelSize: pixelSize, revision: entry.revision))
                }
                return LoadedApplicationIcon(bitmap: bitmap, candidate: stored)
            } catch is CancellationError { throw CancellationError() }
            catch { await diskCache.remove(candidate.url) }
        }
        return nil
    }

    private func decodeCached(_ data: Data, pixelSize: Int) async throws -> ApplicationBitmap {
        await diskDecodeGate.acquire()
        do {
            let result = try await Task.detached(priority: .utility) {
                try ApplicationImageDecoder.decode(data, maximumPixelSize: min(1024, max(64, pixelSize)))
            }.value
            try Task.checkCancellation()
            await diskDecodeGate.release()
            return result
        } catch {
            await diskDecodeGate.release()
            throw error
        }
    }

    private nonisolated static func cacheKey(_ url: URL, pixelSize: Int, revision: String?) -> String {
        url.absoluteString + "#" + String(min(1024, max(64, pixelSize))) + "#" + (revision ?? "")
    }

    func load(_ candidates: [ApplicationIconCandidate], pixelSize: Int) async throws -> LoadedApplicationIcon {
        var lastError: Error = ApplicationImageError.unavailable
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                let value = try await bitmap(candidate.url, pixelSize: min(1024, max(64, pixelSize)), revision: candidate.revision)
                try Task.checkCancellation()
                return LoadedApplicationIcon(bitmap: value, candidate: candidate)
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }

    private func bitmap(_ url: URL, pixelSize: Int, revision: String?) async throws -> ApplicationBitmap {
        guard PublicMediaURL.resolve(url.absoluteString) == url else { throw ApplicationImageError.invalid }
        let key = Self.cacheKey(url, pixelSize: pixelSize, revision: revision)
        if let bitmap = cache.bitmap(for: key) { return bitmap }
        if let task = inflight[key] { return try await task.value }
        if let retryAt = failedUntil[key], retryAt > Date() { throw ApplicationImageError.unavailable }
        let session = session, gate = gate, diskCache = diskCache
        let task = Task<ApplicationBitmap, Error> {
            await gate.acquire()
            do {
                var entry = await diskCache?.entry(for: url)
                if let stored = entry {
                    // Validate before reusing a body, including for a 304 response.
                    do {
                        let value = try await Task.detached(priority: .utility) {
                            try ApplicationImageDecoder.decode(stored.data, maximumPixelSize: pixelSize)
                        }.value
                        if revision != nil, stored.revision == revision {
                            await gate.release()
                            return value
                        }
                    } catch {
                        await diskCache?.remove(url)
                        entry = nil
                    }
                }
                let conditional = revision == nil && entry?.revision == nil ? entry : nil
                let (data, response) = try await Self.download(url, session: session, cached: conditional)
                let decode = Task.detached(priority: .utility) { try ApplicationImageDecoder.decode(data, maximumPixelSize: pixelSize) }
                let result = try await decode.value
                let stored = ApplicationImageDiskCache.Entry(url: url.absoluteString, revision: revision,
                    eTag: response.value(forHTTPHeaderField: "ETag") ?? (response.statusCode == 304 ? entry?.eTag : nil),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? (response.statusCode == 304 ? entry?.lastModified : nil), data: data)
                await diskCache?.store(stored, for: url)
                await gate.release()
                return result
            } catch {
                await gate.release()
                throw error
            }
        }
        inflight[key] = task
        do {
            let value = try await task.value
            inflight[key] = nil; failedUntil[key] = nil
            cache.insert(value, for: key)
            return value
        } catch {
            inflight[key] = nil
            failedUntil = failedUntil.filter { $0.value > Date() }
            if failedUntil.count >= 128 { failedUntil.removeAll() }
            failedUntil[key] = Date().addingTimeInterval(30)
            throw error
        }
    }

    private static func download(_ url: URL, session: URLSession, cached: ApplicationImageDiskCache.Entry?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/svg+xml,image/png,image/webp,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(cached?.eTag, forHTTPHeaderField: "If-None-Match")
        request.setValue(cached?.lastModified, forHTTPHeaderField: "If-Modified-Since")
        // Streaming bounds the allocation even if a server omits or lies about Content-Length.
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw ApplicationImageError.unavailable }
        if http.statusCode == 304, let cached, cached.eTag != nil || cached.lastModified != nil { return (cached.data, http) }
        guard http.statusCode == 200 else { throw ApplicationImageError.unavailable }
        let limit = 5 * 1024 * 1024
        guard response.expectedContentLength <= limit else { throw ApplicationImageError.oversized }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count >= limit { throw ApplicationImageError.oversized }
            data.append(byte)
        }
        return (data, http)
    }
}

/// One atomically replaced source file per URL, shared by all display sizes.
/// The operating system may reclaim Caches; missing or damaged files are cache misses.
actor ApplicationImageDiskCache {
    struct Entry: Codable, Sendable {
        var formatVersion = 1
        let url: String
        let revision: String?
        let eTag: String?
        let lastModified: String?
        let data: Data
    }

    private let directory: URL
    private let byteLimit: Int
    private let countLimit: Int
    private let manager = FileManager.default
    private static let maximumEntryBytes = 5 * 1024 * 1024 + 64 * 1024

    init(directory: URL, byteLimit: Int = 64 * 1024 * 1024, countLimit: Int = 256) {
        self.directory = directory; self.byteLimit = byteLimit; self.countLimit = countLimit
    }

    private func file(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".icon")
    }

    func entry(for url: URL) -> Entry? {
        let path = file(for: url)
        guard let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        guard size > 0, size <= Self.maximumEntryBytes,
              let data = try? Data(contentsOf: path),
              let entry = try? PropertyListDecoder().decode(Entry.self, from: data),
              entry.formatVersion == 1, entry.url == url.absoluteString,
              !entry.data.isEmpty, entry.data.count <= 5 * 1024 * 1024,
              (entry.revision?.utf8.count ?? 0) <= 1024,
              (entry.eTag?.utf8.count ?? 0) <= 4096, (entry.lastModified?.utf8.count ?? 0) <= 4096
        else { remove(url); return nil }
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return entry
    }

    func store(_ entry: Entry, for url: URL) {
        do {
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try encoder.encode(entry)
            guard data.count <= Self.maximumEntryBytes, data.count <= byteLimit else { return }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(for: url), options: .atomic)
            prune()
        } catch { /* Cache writes are best effort; the last valid file remains usable. */ }
    }

    func remove(_ url: URL) { try? manager.removeItem(at: file(for: url)) }

    private func prune() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard url.pathExtension == "icon", url.deletingPathExtension().lastPathComponent.count == 64,
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }, count = entries.count
        for (url, size, _) in entries {
            guard bytes > byteLimit || count > countLimit else { break }
            do { try manager.removeItem(at: url); bytes -= size; count -= 1 } catch { continue }
        }
    }
}

/// NSCache synchronizes reads and writes; entries and their decoded bitmaps are immutable.
private final class ApplicationImageMemoryCache: @unchecked Sendable {
    private let entries = NSCache<NSString, CacheEntry>()

    init() {
        entries.totalCostLimit = 32 * 1024 * 1024
        entries.countLimit = 128
    }

    func bitmap(for key: String) -> ApplicationBitmap? {
        guard let entry = entries.object(forKey: key as NSString), entry.expiresAt > Date() else { return nil }
        return entry.bitmap
    }

    func insert(_ bitmap: ApplicationBitmap, for key: String) {
        entries.setObject(CacheEntry(bitmap: bitmap), forKey: key as NSString, cost: bitmap.image.bytesPerRow * bitmap.image.height)
    }

    private final class CacheEntry {
        let bitmap: ApplicationBitmap
        let expiresAt = Date().addingTimeInterval(1800)
        init(bitmap: ApplicationBitmap) { self.bitmap = bitmap }
    }
}

private actor ApplicationImageWorkGate {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if active < 4 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
}

private final class IconRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Public CDN redirects are allowed only to credential-free HTTPS. This session never carries host identity.
        guard let url = request.url, PublicMediaURL.resolve(url.absoluteString) == url else { completionHandler(nil); return }
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Authorization"); next.setValue(nil, forHTTPHeaderField: "Cookie")
        // Validators belong to one resource; a redirect can select different artwork.
        next.setValue(nil, forHTTPHeaderField: "If-None-Match"); next.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
        completionHandler(next)
    }
}
