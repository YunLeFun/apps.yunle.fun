import Foundation
import ImageIO
import CoreGraphics

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
    private let cache = NSCache<NSString, CacheEntry>()
    private var inflight: [String: Task<ApplicationBitmap, Error>] = [:]
    private var failedUntil: [String: Date] = [:]
    private let gate = ApplicationImageWorkGate()

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: config, delegate: IconRedirectPolicy(), delegateQueue: nil)
        }
        cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 128
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
        let key = url.absoluteString + "#" + String(pixelSize) + "#" + (revision ?? "")
        if let entry = cache.object(forKey: key as NSString), entry.expiresAt > Date() { return entry.bitmap }
        if let task = inflight[key] { return try await task.value }
        if let retryAt = failedUntil[key], retryAt > Date() { throw ApplicationImageError.unavailable }
        let session = session, gate = gate
        let task = Task<ApplicationBitmap, Error> {
            await gate.acquire()
            do {
                let data = try await Self.download(url, session: session)
                let decode = Task.detached(priority: .utility) { try ApplicationImageDecoder.decode(data, maximumPixelSize: pixelSize) }
                let result = try await decode.value
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
            cache.setObject(CacheEntry(bitmap: value), forKey: key as NSString, cost: value.image.bytesPerRow * value.image.height)
            return value
        } catch {
            inflight[key] = nil
            failedUntil = failedUntil.filter { $0.value > Date() }
            if failedUntil.count >= 128 { failedUntil.removeAll() }
            failedUntil[key] = Date().addingTimeInterval(30)
            throw error
        }
    }

    private static func download(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/svg+xml,image/png,image/webp,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        // Streaming bounds the allocation even if a server omits or lies about Content-Length.
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ApplicationImageError.unavailable }
        let limit = 5 * 1024 * 1024
        guard response.expectedContentLength <= limit else { throw ApplicationImageError.oversized }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count >= limit { throw ApplicationImageError.oversized }
            data.append(byte)
        }
        return data
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
        completionHandler(next)
    }
}
