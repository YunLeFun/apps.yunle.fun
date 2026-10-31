import Combine
import CryptoKit
import Foundation

/// A last-confirmed reference is a navigation aid, never a live seat or a
/// reconnect credential. Play checks the room again when it is opened.
@MainActor
final class NativeGameRoomStore: ObservableObject {
    private struct Record: Codable {
        let gameID: String
        let inviteCode: String
        let role: String
        let confirmedAt: Date
    }
    @Published private(set) var continuation: NativeGameRoomIntent?
    private(set) var gameID: String?
    private var accountID: String?
    private var activated = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func activate(accountID: String?) {
        guard !activated || self.accountID != accountID else { return }
        activated = true
        self.accountID = accountID
        continuation = nil; gameID = nil
        guard accountID != nil, let data = defaults.data(forKey: key), data.count <= 2048,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              NativeGame.firstReleaseIDs.contains(record.gameID),
              let role = NativeGameRoomIntent.Role(rawValue: record.role),
              let intent = try? NativeGameRoomIntent(input: record.inviteCode, role: role) else { return }
        continuation = intent; gameID = record.gameID
    }

    func confirmed(gameID: String, room: NativeGameLifecycleEvent.Room, accountID: String?) {
        guard activated, accountID != nil, self.accountID == accountID,
              let role = NativeGameRoomIntent.Role(rawValue: room.role),
              let intent = try? NativeGameRoomIntent(input: room.inviteCode, role: role) else { return }
        if ["ended", "closed", "expired", "removed", "left"].contains(room.state ?? "") {
            if continuation == intent { clear() }
            return
        }
        guard NativeGame.firstReleaseIDs.contains(gameID) else {
            if continuation?.inviteCode == intent.inviteCode { clear() }
            return
        }
        let record = Record(gameID: gameID, inviteCode: room.inviteCode, role: room.role, confirmedAt: Date())
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
        continuation = intent; self.gameID = gameID
    }

    func clear() {
        defaults.removeObject(forKey: key)
        continuation = nil; gameID = nil
    }

    private var key: String {
        let scope = accountID.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "guest"
        return "games.lastRoom.v1." + (NativeGameHostEnvironment.previewOrigin == nil ? "" : "preview18146.") + scope
    }
}
