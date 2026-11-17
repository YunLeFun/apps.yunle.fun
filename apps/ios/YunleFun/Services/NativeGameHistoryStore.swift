import Combine
import CryptoKit
import Foundation

struct NativeGameHistoryEntry: Codable, Identifiable, Equatable {
    let gameID: String
    let modeID: String
    let lastReadyAt: Date
    var id: String { gameID }
}

/// Only records a game after the current runtime confirms it is ready to play.
@MainActor
final class NativeGameHistoryStore: ObservableObject {
    @Published private(set) var entries: [NativeGameHistoryEntry] = []
    @Published private(set) var error: String?
    private(set) var generation = UUID()
    private(set) var accountID: String?
    private let directory: URL
    private var activated = false

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(NativeGameHostEnvironment.previewOrigin == nil ? "Games/History" : "Games/Preview18146/History", isDirectory: true)
    }

    func activate(accountID: String?) {
        guard !activated || self.accountID != accountID else { return }
        activated = true
        self.accountID = accountID
        generation = UUID()
        entries = []
        error = nil
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 65_536 else { throw NativeGameError.invalidCatalog }
            let restored = try JSONDecoder().decode([NativeGameHistoryEntry].self, from: data)
            var seen = Set<String>()
            guard restored.count <= 12, restored.allSatisfy({
                NativeGame.validIdentifier($0.gameID) && NativeGameMode.supportedIDs.contains($0.modeID)
                    && seen.insert($0.gameID).inserted
            }) else { throw NativeGameError.invalidCatalog }
            entries = restored.sorted { $0.lastReadyAt > $1.lastReadyAt }
        } catch let issue as CocoaError where issue.code == .fileReadNoSuchFile {
            // No history for a new guest or account.
        } catch {
            self.error = "本机最近游玩记录暂时无法读取。"
        }
    }

    func recordReady(gameID: String, modeID: String, accountID: String?, expectedGeneration: UUID? = nil, now: Date = Date()) {
        guard activated, self.accountID == accountID, expectedGeneration == nil || expectedGeneration == generation,
              NativeGame.validIdentifier(gameID), NativeGameMode.supportedIDs.contains(modeID) else { return }
        entries.removeAll { $0.gameID == gameID }
        entries.insert(NativeGameHistoryEntry(gameID: gameID, modeID: modeID, lastReadyAt: now), at: 0)
        entries = Array(entries.prefix(12))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
            error = nil
        } catch {
            self.error = "最近游玩已更新，本机暂时无法保存记录。"
        }
    }

    private var fileURL: URL {
        let scope = accountID.map { id in
            "account-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        } ?? "guest"
        return directory.appendingPathComponent(scope + ".json")
    }
}
