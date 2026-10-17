import CryptoKit
import Foundation

protocol HomeBackupReading {
    func list(ownerFileName: String) async throws -> [HomeBackupItem]
    func preview(id: String, ownerFileName: String) async throws -> HomeBackupPreview
}

struct HomeBackupRepository: HomeBackupReading {
    let directory: URL
    static let maximumBytes = 16 * 1024 * 1024

    func list(ownerFileName: String) async throws -> [HomeBackupItem] {
        let task = Task.detached(priority: .utility) { () throws -> [HomeBackupItem] in
            let files: [URL]
            do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
            var items: [HomeBackupItem] = []
            for file in files {
                try Task.checkCancellation()
                guard let kind = Self.kind(name: file.lastPathComponent, ownerFileName: ownerFileName),
                      let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                items.append(HomeBackupItem(id: file.lastPathComponent, kind: kind, date: values.creationDate, byteCount: Int64(values.fileSize ?? 0)))
            }
            return items.sorted { ($0.date ?? .distantPast, $0.id) > ($1.date ?? .distantPast, $1.id) }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func preview(id: String, ownerFileName: String) async throws -> HomeBackupPreview {
        let task = Task.detached(priority: .utility) { try read(id: id, ownerFileName: ownerFileName) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func read(id: String, ownerFileName: String) throws -> HomeBackupPreview {
        guard let kind = Self.kind(name: id, ownerFileName: ownerFileName) else { throw HomeBackupError.unreadable }
        do {
            let file = directory.appendingPathComponent(id)
            let values = try file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= Self.maximumBytes else { throw HomeBackupError.unreadable }
            let data = try Data(contentsOf: file)
            guard data.count <= Self.maximumBytes else { throw HomeBackupError.unreadable }
            let snapshot = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
            return HomeBackupPreview(item: .init(id: id, kind: kind, date: values.creationDate, byteCount: Int64(data.count)),
                                     snapshot: snapshot, digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        } catch { throw HomeBackupError.unreadable }
    }

    static func kind(name: String, ownerFileName: String) -> HomeBackupItem.Kind? {
        guard ownerFileName.hasSuffix(".json"), !ownerFileName.contains("/"), !ownerFileName.contains("\\") else { return nil }
        let prefix = String(ownerFileName.dropLast(5)) + "."
        guard name.hasPrefix(prefix), name.hasSuffix(".json"), !name.contains("/"), !name.contains("\\") else { return nil }
        let suffix = String(name.dropFirst(prefix.count).dropLast(5))
        for (key, kind) in [("before-legacy-", HomeBackupItem.Kind.legacy), ("before-native-migration-", .nativeMigration)] {
            if suffix.hasPrefix(key) {
                let digest = suffix.dropFirst(key.count)
                return digest.count == 64 && digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) ? kind : nil
            }
        }
        for (key, kind) in [("conflict-", HomeBackupItem.Kind.conflict), ("before-restore-", .restore)] {
            if suffix.hasPrefix(key), UUID(uuidString: String(suffix.dropFirst(key.count))) != nil { return kind }
        }
        return nil
    }
}
