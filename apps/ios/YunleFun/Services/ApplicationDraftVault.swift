import Foundation
import CryptoKit

struct SavedApplicationDraft: Codable, Equatable {
    var draft: ApplicationDraft
    var baseRevision: String?
    var baseUpdatedAt: Double?
    var baseWriteVersion: String?
}
struct ApplicationDraftVault {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ApplicationDrafts", isDirectory: true)
    }
    func load(owner: String, appID: String?) throws -> SavedApplicationDraft? {
        do {
            let record = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file(owner: owner, appID: appID)))
            guard record.version == 1, record.owner == owner, record.appID == appID else { throw PublishingError.storage }
            return record.saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch { throw PublishingError.storage }
    }
    func save(_ draft: SavedApplicationDraft, owner: String, appID: String?) throws {
        // Refuse to overwrite a corrupt or incompatible existing draft.
        _ = try load(owner: owner, appID: appID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Envelope(version: 1, owner: owner, appID: appID, saved: draft))
            try data.write(to: file(owner: owner, appID: appID), options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { throw PublishingError.storage }
    }
    func remove(owner: String, appID: String?) throws {
        _ = try load(owner: owner, appID: appID)
        do { try FileManager.default.removeItem(at: file(owner: owner, appID: appID)) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
        catch { throw PublishingError.storage }
    }
    func file(owner: String, appID: String?) -> URL {
        let value = Data(owner.utf8) + Data([0]) + Data((appID ?? "__new__").utf8)
        let key = SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }
    private struct Envelope: Codable { let version: Int; let owner: String; let appID: String?; let saved: SavedApplicationDraft }
}
