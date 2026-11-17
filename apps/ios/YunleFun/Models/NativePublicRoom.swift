import Foundation

struct NativePublicRoom: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case waiting, playing, completed }
    let inviteCode: String
    let gameId: String?
    let status: Status
    let memberCount: Int
    let capacity: Int
    var id: String { inviteCode }
    var isSpectating: Bool { status == .playing }
    var actionTitle: String { isSpectating ? "观战" : "加入房间" }
    var statusTitle: String {
        switch status {
        case .waiting: return "等待玩家"
        case .playing: return "对局进行中"
        case .completed: return "等待下一局"
        }
    }
    func intent() throws -> NativeGameRoomIntent {
        try NativeGameRoomIntent(input: inviteCode, role: isSpectating ? .spectator : .player)
    }

    static func decodeList(_ data: Data) throws -> [Self] {
        struct Response: Decodable { let ok: Bool; let rooms: [NativePublicRoom] }
        guard data.count <= 65_536 else { throw NativePublicRoomError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.ok, response.rooms.count <= 50 else { throw NativePublicRoomError.invalidResponse }
        var codes = Set<String>()
        for room in response.rooms {
            guard codes.insert(room.inviteCode).inserted,
                  (try? room.intent())?.inviteCode == room.inviteCode,
                  room.gameId.map(NativeGame.validIdentifier) ?? true,
                  [4, 8].contains(room.capacity), (1..<room.capacity).contains(room.memberCount)
            else { throw NativePublicRoomError.invalidResponse }
        }
        return response.rooms
    }
}

enum NativePublicRoomError: LocalizedError {
    case invalidResponse, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "暂时无法读取公开房间，请稍后刷新。"
        case .unavailable: return "公开房间暂时不可用，请稍后重试，也可以凭房间号加入。"
        }
    }
}
