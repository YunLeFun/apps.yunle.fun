import CryptoKit
import Foundation

struct AssistantConversation: Identifiable, Equatable, Codable, Sendable {
    /// The thread ID, so reopening continues the same Agent thread.
    let id: String
    var title: String
    var updatedAt: Date
    var messages: [AssistantMessage]
}

/// Saved assistant conversations, one file per account, kept only on this device.
/// Files are named by a hash of the account ID, protected until first unlock-while-open,
/// and excluded from backups.
struct AssistantHistory: Sendable {
    static let limit = 20
    static let titleLength = 40
    /// Keeps a worst-case history file small enough to read and write on the main actor.
    static let byteLimit = 2 * 1024 * 1024
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assistant", isDirectory: true)
    }
    func fileURL(accountID: String) -> URL {
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
    func load(accountID: String) -> [AssistantConversation] {
        guard let data = try? Data(contentsOf: fileURL(accountID: accountID)),
              let saved = try? Self.decoder.decode([AssistantConversation].self, from: data) else { return [] }
        return Array(saved.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.limit))
    }
    struct SaveResult: Equatable {
        /// What is stored now, newest first; the previous list when the write failed.
        let conversations: [AssistantConversation]
        let saved: Bool
    }
    /// Inserts or replaces the conversation; `saved` is false when it could not be written.
    @discardableResult func save(_ conversation: AssistantConversation, accountID: String) -> SaveResult {
        var list = load(accountID: accountID).filter { $0.id != conversation.id }
        list.insert(conversation, at: 0)
        list.sort { $0.updatedAt > $1.updatedAt }
        let (stored, written) = write(Array(list.prefix(Self.limit)), accountID: accountID)
        return SaveResult(conversations: stored, saved: written && stored.contains { $0.id == conversation.id })
    }
    @discardableResult func delete(_ id: String, accountID: String) -> [AssistantConversation] {
        write(load(accountID: accountID).filter { $0.id != id }, accountID: accountID).0
    }
    /// Removes the account's history file; false when it is still on disk.
    @discardableResult func deleteAll(accountID: String) -> Bool {
        let file = fileURL(accountID: accountID)
        do { try FileManager.default.removeItem(at: file) } catch { return !FileManager.default.fileExists(atPath: file.path) }
        return true
    }
    private func write(_ conversations: [AssistantConversation], accountID: String) -> ([AssistantConversation], Bool) {
        var list = conversations
        guard !list.isEmpty else {
            return deleteAll(accountID: accountID) ? ([], true) : (load(accountID: accountID), false)
        }
        var data = (try? Self.encoder.encode(list)) ?? Data()
        while data.count > Self.byteLimit && list.count > 1 {
            list.removeLast(); data = (try? Self.encoder.encode(list)) ?? Data()
        }
        guard !data.isEmpty, data.count <= Self.byteLimit else { return (load(accountID: accountID), false) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory; try? Self.excludeFromBackup(&folder)
            var file = fileURL(accountID: accountID)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            try? Self.excludeFromBackup(&file)
            return (list, true)
        } catch {
            return (load(accountID: accountID), false)
        }
    }
    private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private static let encoder: JSONEncoder = { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; return encoder }()
    private static let decoder: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder }()

    /// A saved copy of the in-memory messages: no in-flight state, and no conversation without a question.
    static func conversation(id: String, messages: [AssistantMessage], now: Date = Date()) -> AssistantConversation? {
        let kept = messages.compactMap { message -> AssistantMessage? in
            var copy = message
            if copy.status == .streaming { copy.status = .stopped }
            copy.toolStatus = nil
            return copy.role == .assistant && copy.content.isEmpty && copy.cards.isEmpty && copy.status == .done ? nil : copy
        }
        guard let question = kept.first(where: { $0.role == .user }) else { return nil }
        let words = question.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return AssistantConversation(id: id, title: String(words.prefix(titleLength)), updatedAt: now, messages: kept)
    }
}
