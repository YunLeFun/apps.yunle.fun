import Combine
import CryptoKit
import Foundation

@MainActor
final class DiagnosticLogStore: ObservableObject {
    @Published private(set) var entries: [DiagnosticLogEntry] = []
    @Published private(set) var accountID: String?
    @Published private(set) var scopeGeneration = UUID()
    @Published private(set) var storageError: String?
    private let directory: URL
    private let now: () -> Date
    private var storageBlocked = false
    private static let maximumFileBytes = 8 * 1024 * 1024

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiagnosticLogs", isDirectory: true)).standardizedFileURL
        self.now = now
        activateAccount(nil)
    }

    func activateAccount(_ id: String?) {
        // Publish no old partition while changing the upload boundary. A to B
        // to A invalidates a previously frozen confirmation, even for one UID.
        entries = []; accountID = id; scopeGeneration = UUID()
        storageError = nil; storageBlocked = false
        do {
            let file = try checkedDirectory(create: false).appendingPathComponent(scopeKey + ".json")
            guard try inspectFile(file) else { return }
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
            guard envelope.version == 1, envelope.scope == scopeKey else { throw StorageFailure.invalid }
            entries = normalized(envelope.entries)
            // Rewrite the strict projection after pruning/redaction; unknown
            // fields from a modified file must not survive on disk.
            persist()
        } catch {
            if Self.isMissing(error) { return }
            storageBlocked = true
            storageError = "无法读取已保存的诊断日志。原文件已保留，新记录暂时仅保存在内存；可清除本地日志后重试。"
        }
    }

    func record(_ level: DiagnosticLogLevel, message: String) {
        let timestamp = now().timeIntervalSince1970 * 1000
        guard timestamp.isFinite else { return }
        let redacted = DiagnosticText.redact(message)
        guard !redacted.isEmpty else { return }
        entries = normalized(entries + [DiagnosticLogEntry(level: level, message: redacted, timestamp: timestamp.rounded(.towardZero))])
        persist()
    }

    func clear() {
        entries = []; scopeGeneration = UUID()
        do {
            let file = try checkedDirectory(create: false).appendingPathComponent(scopeKey + ".json")
            // Removing our own leaf symlink does not follow or erase its target.
            if try leafExists(file) { try FileManager.default.removeItem(at: file) }
            storageBlocked = false; storageError = nil
        } catch {
            if Self.isMissing(error) { storageBlocked = false; storageError = nil; return }
            storageBlocked = true
            storageError = "本次会话的诊断日志已清空，但未能清除已保存的文件，重新启动后可能再次出现。请稍后重试清除。"
        }
    }

    /// A pure projection suitable for SwiftUI body and frozen confirmations.
    /// Expiration here never publishes state or performs a disk write.
    func select(startTime: Double, endTime: Double) -> [DiagnosticLogEntry] {
        guard startTime.isFinite, endTime.isFinite, startTime <= endTime else { return [] }
        return normalized(entries).filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }

    private var scopeKey: String {
        guard let accountID else { return "guest" }
        return "account-" + SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func normalized(_ values: [DiagnosticLogEntry]) -> [DiagnosticLogEntry] {
        let current = now().timeIntervalSince1970 * 1000
        guard current.isFinite else { return [] }
        let earliest = current - DiagnosticLimits.retentionMilliseconds
        let latest = current + DiagnosticLimits.futureClockSkewMilliseconds
        return Array(values.enumerated().compactMap { index, entry -> (Int, DiagnosticLogEntry)? in
            guard entry.timestamp.isFinite else { return nil }
            let timestamp = entry.timestamp.rounded(.towardZero)
            guard timestamp >= earliest, timestamp <= latest else { return nil }
            let message = DiagnosticText.redact(entry.message)
            guard !message.isEmpty else { return nil }
            return (index, DiagnosticLogEntry(level: entry.level, message: message, timestamp: timestamp))
        }.sorted { left, right in
            left.1.timestamp == right.1.timestamp ? left.0 < right.0 : left.1.timestamp < right.1.timestamp
        }.suffix(DiagnosticLimits.maximumEntries).map(\.1))
    }

    private func persist() {
        guard !storageBlocked else { return }
        do {
            let file = try checkedDirectory(create: true).appendingPathComponent(scopeKey + ".json")
            _ = try inspectFile(file)
            let data = try JSONEncoder().encode(Envelope(version: 1, scope: scopeKey, entries: entries))
            guard data.count <= Self.maximumFileBytes else { throw StorageFailure.invalid }
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
        } catch {
            storageError = "诊断日志暂未保存到此设备。本次会话的记录仍保留在内存中，可稍后重试。"
        }
    }

    /// Resolve the system-managed home prefix once, then refuse symbolic links
    /// in every app-controlled component, including a missing leaf's parents.
    private func checkedDirectory(create: Bool) throws -> URL {
        let requested = directory.pathComponents
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        let homeParts = home.pathComponents
        let insideHome = requested.starts(with: homeParts)
        var current = insideHome ? home.resolvingSymlinksInPath() : URL(fileURLWithPath: "/", isDirectory: true)
        let parts = insideHome ? Array(requested.dropFirst(homeParts.count)) : Array(requested.dropFirst())
        for part in parts {
            current.appendPathComponent(part, isDirectory: true)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw StorageFailure.invalid }
            } catch {
                guard Self.isMissing(error), create else { throw error }
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
        }
        return current
    }

    @discardableResult
    private func inspectFile(_ file: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value >= 0, size.int64Value <= Int64(Self.maximumFileBytes) else { throw StorageFailure.invalid }
            return true
        } catch {
            if Self.isMissing(error) { return false }
            throw error
        }
    }

    private func leafExists(_ file: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let type = attributes[.type] as? FileAttributeType,
                  type == .typeRegular || type == .typeSymbolicLink else { throw StorageFailure.invalid }
            return true
        } catch {
            if Self.isMissing(error) { return false }
            throw error
        }
    }

    private static func isMissing(_ error: Error) -> Bool {
        guard let error = error as? CocoaError else { return false }
        return error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }
    private struct Envelope: Codable {
        let version: Int
        let scope: String
        let entries: [DiagnosticLogEntry]
    }
    private enum StorageFailure: Error { case invalid }
}
