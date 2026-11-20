import Foundation

/// The portable envelope is specified in packages/app-core/contracts/conversation-card.v1.schema.json.
/// A card stores a reference and a text fallback. Live snapshots are loaded separately.
struct ConversationCard: Codable, Equatable, Identifiable, Sendable {
    private struct Payload: Codable, Equatable, Sendable {
        var inviteCode: String?
        var signupId: String?
        var boardId: String?
        var instanceId: String?
    }

    let id: String
    let type: String
    let schemaVersion: Int
    let fallbackText: String
    private let payload: Payload?

    init(publicRoom: NativePublicRoom) {
        id = "play-room:" + publicRoom.inviteCode
        type = "play.public-room"
        schemaVersion = 1
        fallbackText = "公开联机房间 · " + publicRoom.inviteCode
        payload = Payload(inviteCode: publicRoom.inviteCode)
    }

    init(teamSignup: TeamSignupSnapshot) {
        self.init(type: "team.signup", instanceID: teamSignup.signupId, fallback: teamSignup.title)
    }

    init(board: ConversationBoardSnapshot) {
        self.init(type: "play.board", instanceID: board.boardId, fallback: "联机五子棋")
    }

    private init(type: String, instanceID: String, fallback: String) {
        id = type + ":" + instanceID
        self.type = type
        schemaVersion = 2
        fallbackText = fallback
        payload = Payload(instanceId: instanceID)
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        type = try fields.decode(String.self, forKey: .type)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        fallbackText = String(try fields.decode(String.self, forKey: .fallbackText).prefix(160))
        // A newer payload can have a different shape; the message still has its summary.
        payload = try? fields.decode(Payload.self, forKey: .payload)
    }

    var publicRoomCode: String? {
        guard schemaVersion == 1, type == "play.public-room", let code = payload?.inviteCode,
              NativeGameRoomIntent.validCode(code), id == "play-room:" + code else { return nil }
        return code
    }

    var reference: ConversationCardReference? {
        switch (schemaVersion, type) {
        case (2, _):
            guard let value = payload?.instanceId, id == type + ":" + value else { return nil }
            return ConversationCardReference(type: type, instanceID: value)
        case (1, "team.signup"):
            guard let value = payload?.signupId, id == "team-signup:" + value else { return nil }
            return ConversationCardReference(type: type, instanceID: value)
        case (1, "play.board"):
            guard let value = payload?.boardId, id == "play-board:" + value else { return nil }
            return ConversationCardReference(type: type, instanceID: value)
        default: return nil
        }
    }

    var teamSignupId: String? { reference?.type == "team.signup" ? reference?.instanceId : nil }
    var boardId: String? { reference?.type == "play.board" ? reference?.instanceId : nil }

    static func validInstanceID(_ value: String) -> Bool {
        value.range(of: #"\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z"#,
                    options: .regularExpression) != nil
    }
}
