import CryptoKit
import Foundation

struct ApplicationCacheEntry: Codable, Identifiable, Equatable {
    let id: String
    let application: CloudApplication
    let launchURL: URL
    let downloadedAt: Date
    let byteCount: Int
    let resourceCount: Int

    static func key(for application: CloudApplication) -> String {
        let value = [application.id, application.runtimeScope, application.launchURL?.absoluteString ?? ""]
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func supports(_ application: CloudApplication) -> Bool {
        application.canOpenAsGuest && application.runtimeScope == "public"
    }
}

enum ApplicationCacheError: LocalizedError {
    case unsupported, invalidArchive, tooLarge, quotaExceeded, downloadFailed, timedOut, notCacheable
    var errorDescription: String? {
        switch self {
        case .notCacheable: return "这个网站不允许保存下载缓存，请在线使用。"
        case .unsupported: return "暂时只支持下载云乐坊中公开、免费的应用。"
        case .invalidArchive: return "缓存内容不完整，请重新下载。"
        case .tooLarge: return "这个应用的下载缓存超过 25 MB，暂时无法保存。"
        case .quotaExceeded: return "下载缓存已达到 200 MB 上限，请先清理部分应用。"
        case .downloadFailed: return "下载未完成，请检查网络后重试。原有缓存会继续保留。"
        case .timedOut: return "下载超时，请稍后重试。原有缓存会继续保留。"
        }
    }
}

/// One atomic file per application revision: a failed update cannot replace the old copy.
/// Only anonymous public content lives here; account data and the home library are separate.
actor ApplicationCacheRepository {
    static let maximumArchiveBytes = 25 * 1024 * 1024
    static let maximumTotalBytes = 200 * 1024 * 1024
    private struct Record: Codable {
        let version: Int
        let entry: ApplicationCacheEntry
        let archive: Data
        let digest: Data
    }
    private let directory: URL
    private let fileManager = FileManager.default
    private let totalLimit: Int

    init(directory: URL? = nil, totalLimit: Int = maximumTotalBytes) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudApplicationDownloads", isDirectory: true)
        self.totalLimit = totalLimit
    }

    func entries() throws -> [ApplicationCacheEntry] {
        try files().compactMap { url in
            // An interrupted/corrupt file must not prevent management of the other downloads.
            guard let record = try? read(url), record.entry.id == url.deletingPathExtension().lastPathComponent else { return nil }
            return record.entry
        }.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    func archive(for application: CloudApplication) throws -> Data? {
        try snapshot(for: application)?.archive
    }

    func snapshot(for application: CloudApplication) throws -> (entry: ApplicationCacheEntry, archive: Data)? {
        guard ApplicationCacheEntry.supports(application) else { return nil }
        let url = file(for: ApplicationCacheEntry.key(for: application))
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let record = try read(url)
        guard record.entry.id == ApplicationCacheEntry.key(for: application), record.entry.launchURL == application.launchURL else {
            throw ApplicationCacheError.invalidArchive
        }
        return (record.entry, record.archive)
    }

    func save(_ archive: Data, for application: CloudApplication, now: Date = Date()) throws {
        try Task.checkCancellation()
        guard ApplicationCacheEntry.supports(application), let launchURL = application.launchURL else { throw ApplicationCacheError.unsupported }
        let count = try Self.validate(archive, launchURL: launchURL)
        let id = ApplicationCacheEntry.key(for: application)
        let entry = ApplicationCacheEntry(id: id, application: application, launchURL: launchURL,
                                          downloadedAt: now, byteCount: archive.count, resourceCount: count)
        let record = Record(version: 1, entry: entry, archive: archive, digest: Data(SHA256.hash(data: archive)))
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        let existingBytes = try files().filter { $0 != file(for: id) }.reduce(0) { sum, url in
            sum + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        guard existingBytes + data.count <= totalLimit else { throw ApplicationCacheError.quotaExceeded }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Task.checkCancellation()
        try data.write(to: file(for: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(id: String) throws {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { throw ApplicationCacheError.invalidArchive }
        let url = file(for: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func removeAll() throws {
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    private func files() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "cache" }
    }

    private func file(for id: String) -> URL { directory.appendingPathComponent(id).appendingPathExtension("cache") }

    private func read(_ url: URL) throws -> Record {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumArchiveBytes + 1024 * 1024 else { throw ApplicationCacheError.tooLarge }
        let record = try PropertyListDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard record.version == 1, record.entry.byteCount == record.archive.count,
              record.digest == Data(SHA256.hash(data: record.archive)) else { throw ApplicationCacheError.invalidArchive }
        _ = try Self.validate(record.archive, launchURL: record.entry.launchURL)
        return record
    }

    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        first.scheme?.lowercased() == "https" && second.scheme?.lowercased() == "https"
            && first.host?.lowercased() == second.host?.lowercased()
            && (first.port ?? 443) == (second.port ?? 443)
            && first.user == nil && first.password == nil && second.user == nil && second.password == nil
    }

    static func validate(_ data: Data, launchURL: URL) throws -> Int {
        guard data.count <= maximumArchiveBytes else { throw ApplicationCacheError.tooLarge }
        guard let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = archive["WebMainResource"] as? [String: Any],
              let rawURL = main["WebResourceURL"] as? String, let url = URL(string: rawURL),
              sameOrigin(url, launchURL),
              let mime = main["WebResourceMIMEType"] as? String, ["text/html", "application/xhtml+xml"].contains(mime),
              let html = main["WebResourceData"] as? Data, !html.isEmpty else { throw ApplicationCacheError.invalidArchive }
        return 1 + ((archive["WebSubresources"] as? [Any])?.count ?? 0)
    }
}
