import Foundation

struct NativeRoomCreationDraft: Codable, Equatable {
    var gameID: String?
    var isPublic = false

    static let rulesets = ["gomoku": "freestyle-15", "stone-chess": "erdingyi-4", "animal-chess": "classic-7x9",
                           "dark-animal-chess": "basic-4x4", "flight-chess": "classic-4", "ganyandyan": "classic-wild", "snake": "arena-24-v1"]
    func payload() throws -> Data {
        var fields: [String: Any] = ["roomCapacity": 4, "visibility": isPublic ? "public" : "private"]
        if let gameID {
            guard let ruleset = Self.rulesets[gameID] else { throw NativeRoomCreationError.invalidInput }
            fields["game"] = ["gameId": gameID, "rulesetId": ruleset, "rulesetVersion": 1]
        } else { fields["game"] = NSNull() }
        return try JSONSerialization.data(withJSONObject: fields)
    }
}

enum NativeRoomCreationError: Error, LocalizedError, Equatable, AccountRequestFailure {
    case unauthorized, identityChanged, consentRequired, invalidResponse, invalidInput, forbidden, unavailable
    var isUnauthorized: Bool { self == .unauthorized }
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录后再试。"
        case .identityChanged: return "账号已变化，请重新打开创建房间。"
        case .consentRequired: return "需要允许云乐坊间使用当前账号的标识、昵称和头像后继续。"
        case .invalidInput: return "这个游戏暂不支持原生创房，请重新选择。"
        case .forbidden: return "当前账号暂时无法创房，请确认账号状态及手机号验证。"
        case .invalidResponse, .unavailable: return "暂时无法确认创房结果。请重试，同一次操作会沿用原请求，避免重复创建。"
        }
    }
}

struct NativeRoomCreationOperation: Codable {
    let key: UUID
    let draft: NativeRoomCreationDraft
    var inviteCode: String?
}
