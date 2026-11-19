import Foundation

struct RoomInviteFriend: Decodable, Identifiable {
    let userId: String
    let login: String?
    let nickname: String
    var id: String { userId }
}

struct RoomInviteMessage: Decodable, Identifiable {
    struct Actor: Decodable { let nickname: String }
    struct Room: Decodable {
        let inviteCode: String
        let gameId: String?

        var intent: NativeGameRoomIntent? {
            guard NativeGameRoomIntent.validCode(inviteCode) else { return nil }
            return try? NativeGameRoomIntent(input: inviteCode)
        }
    }

    let id: String
    let actor: Actor
    let type: String?
    let roomInvite: Room?
    let roomInviteReply: String?
    let roomInviteGameId: String?

    var isLaterReply: Bool { type == "room_invite_reply" && roomInviteReply == "later" }
    var hasRepliedLater: Bool { roomInviteReply == "later" }
}

struct RoomInvitePage<Item: Decodable>: Decodable {
    let items: [Item]
    let nextSkip: Int?
    let repliesEnabled: Bool?
}

enum RoomInviteError: LocalizedError, AccountRequestFailure {
    case unauthorized, identityChanged, unavailable, roomUnavailable, inviteUnavailable, notMutual, recipientUnavailable

    var isUnauthorized: Bool { self == .unauthorized }
    var errorDescription: String? {
        switch self {
        case .unauthorized, .identityChanged: return "请确认当前账号后重试。"
        case .unavailable: return "暂时无法处理游戏邀请，请稍后重试。"
        case .roomUnavailable: return "这个房间已不可邀请，请返回房间后重试。"
        case .inviteUnavailable: return "这条邀请已无法回复。"
        case .notMutual: return "互相关注后才能发送邀请或回复。"
        case .recipientUnavailable: return "对方暂时无法接收邀请或回复。"
        }
    }
}

struct RoomInviteService {
    private let transport: CloudbaseAuthService
    private static let pageSize = 20

    init(transport: CloudbaseAuthService = CloudbaseAuthService()) { self.transport = transport }

    func friends(skip: Int, identity: AuthorizedAccount) async throws -> RoomInvitePage<RoomInviteFriend> {
        try await page("listRoomInviteFriends", skip: skip, identity: identity)
    }

    func messages(skip: Int, identity: AuthorizedAccount) async throws -> RoomInvitePage<RoomInviteMessage> {
        try await page("listRoomInvites", skip: skip, identity: identity, includeReplies: true)
    }

    func send(room: NativeGameRoomIntent, to friend: RoomInviteFriend, identity: AuthorizedAccount) async throws {
        let receipt: Receipt = try await call(["action": "sendRoomInvite", "targetId": friend.id,
                                               "inviteCode": room.inviteCode], identity: identity)
        try requireSuccess(receipt)
    }

    func replyLater(to inviteID: String, identity: AuthorizedAccount) async throws {
        let receipt: Receipt = try await call(["action": "replyRoomInviteLater", "inviteId": inviteID], identity: identity)
        try requireSuccess(receipt)
    }

    private func requireSuccess(_ receipt: Receipt) throws {
        guard receipt.ok else {
            switch receipt.code {
            case "room_unavailable", "invalid_room": throw RoomInviteError.roomUnavailable
            case "invite_unavailable": throw RoomInviteError.inviteUnavailable
            case "not_mutual": throw RoomInviteError.notMutual
            case "recipient_unavailable": throw RoomInviteError.recipientUnavailable
            default: throw RoomInviteError.unavailable
            }
        }
    }

    private struct Receipt: Decodable { let ok: Bool; let code: String? }

    private func page<Item: Decodable & Identifiable>(_ action: String, skip: Int,
                                                      identity: AuthorizedAccount, includeReplies: Bool = false) async throws -> RoomInvitePage<Item> {
        guard (0...1_000_000).contains(skip) else { throw RoomInviteError.unavailable }
        var fields: [String: Any] = ["action": action, "skip": skip, "limit": Self.pageSize]
        if includeReplies { fields["includeReplies"] = true }
        let result: RoomInvitePage<Item> = try await call(fields, identity: identity)
        guard result.items.count <= Self.pageSize, Set(result.items.map(\.id)).count == result.items.count,
              result.nextSkip == nil || result.nextSkip == skip + Self.pageSize else { throw RoomInviteError.unavailable }
        return result
    }

    private func call<Value: Decodable>(_ fields: [String: Any], identity: AuthorizedAccount) async throws -> Value {
        let endpoint = transport.origin.appendingPathComponent("v1/functions/account-api")
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await transport.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RoomInviteError.unavailable }
        if http.statusCode == 401 { throw RoomInviteError.unauthorized }
        guard (200..<300).contains(http.statusCode), data.count <= 512 * 1024,
              let value = try? JSONDecoder().decode(Value.self, from: data) else { throw RoomInviteError.unavailable }
        return value
    }
}
