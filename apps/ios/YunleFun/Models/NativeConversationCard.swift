import Foundation

struct ConversationCardReference: Codable, Hashable, Sendable {
    let type: String
    let instanceId: String

    init?(type: String, instanceID: String) {
        guard Self.validKey(type), ConversationCard.validInstanceID(instanceID) else { return nil }
        self.type = type
        self.instanceId = instanceID
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(type: try fields.decode(String.self, forKey: .type),
                               instanceID: try fields.decode(String.self, forKey: .instanceId))
        else { throw NativeConversationCardError.unsupported }
        self = value
    }

    var messageID: String { type + ":" + instanceId }

    static func validKey(_ key: String) -> Bool {
        key.utf8.count <= 65 && key.range(of: #"\A[a-z][a-z0-9-]{0,31}\.[a-z][a-z0-9-]{0,31}\z"#, options: .regularExpression) != nil
    }
}

struct ConversationCardLink: Hashable {
    let reference: ConversationCardReference

    var url: URL {
        CatalogService.productionOrigin.appendingPathComponent("cards")
            .appendingPathComponent(reference.type).appendingPathComponent(reference.instanceId)
    }

    static func parse(_ url: URL) -> Self? {
        if let board = ConversationBoardLink.parse(url),
           let reference = ConversationCardReference(type: "play.board", instanceID: board.boardID) {
            return Self(reference: reference)
        }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        var segments = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.first == "" else { return nil }
        segments.removeFirst()
        switch (parts.scheme?.lowercased(), parts.host?.lowercased(), parts.port) {
        case ("https", "apps.yunle.fun", nil), ("https", "apps.yunle.fun", 443):
            guard segments.first == "cards" else { return nil }
            segments.removeFirst()
        case ("yunlefun", "card", nil): break
        default: return nil
        }
        guard segments.count == 2,
              let reference = ConversationCardReference(type: String(segments[0]), instanceID: String(segments[1]))
        else { return nil }
        return Self(reference: reference)
    }
}

struct NativeConversationCardSnapshot: Decodable, Equatable, Sendable {
    struct Template: Decodable, Equatable, Sendable {
        let schemaVersion: Int
        let components: [Component]
    }

    struct Component: Decodable, Equatable, Sendable {
        enum Kind: String, Decodable, Sendable { case title, text, seats, button, gomoku }
        let kind: Kind
        let field: String?
        let filled: String?
        let total: String?
        let action: String?
    }

    struct Action: Decodable, Equatable, Sendable {
        let label: String
        let enabled: Bool
    }

    enum Value: Decodable, Equatable, Sendable {
        case text(String), number(Int), board(ConversationBoardSnapshot), unsupported

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { self = .text(text) }
            else if let number = try? value.decode(Int.self) { self = .number(number) }
            else if let board = try? value.decode(ConversationBoardSnapshot.self) { self = .board(board) }
            else { self = .unsupported }
        }
    }

    let schemaVersion: Int
    let reference: ConversationCardReference
    let revision: Int
    let finished: Bool
    let fallbackText: String
    let template: Template
    let data: [String: Value]
    let actions: [String: Action]

    func text(_ field: String?) -> String? {
        guard let field, case .text(let text) = data[field] else { return nil }
        return text
    }

    func number(_ field: String?) -> Int? {
        guard let field, case .number(let number) = data[field] else { return nil }
        return number
    }

    func board(_ field: String?) -> ConversationBoardSnapshot? {
        guard let field, case .board(let board) = data[field] else { return nil }
        return board
    }

    func validate(for expected: ConversationCardReference) throws {
        guard reference == expected, (1...9_007_199_254_740_991).contains(revision),
              schemaVersion == 1, template.schemaVersion == 1, (1...16).contains(template.components.count),
              (1...160).contains(fallbackText.count), data.count <= 32, actions.count <= 16,
              actions.allSatisfy({ ConversationCardReference.validKey($0.key) && (1...60).contains($0.value.label.count) }),
              !finished || actions.values.allSatisfy({ !$0.enabled })
        else { throw NativeConversationCardError.unsupported }
        for component in template.components {
            switch component.kind {
            case .title, .text:
                guard let text = text(component.field), text.count <= 512 else { throw NativeConversationCardError.unsupported }
            case .seats:
                guard let total = number(component.total), (1...16).contains(total),
                      let filled = number(component.filled), (0...total).contains(filled) else { throw NativeConversationCardError.unsupported }
            case .button:
                guard let action = component.action, ConversationCardReference.validKey(action) else { throw NativeConversationCardError.unsupported }
            case .gomoku:
                guard let action = component.action, ConversationCardReference.validKey(action),
                      let board = board(component.field), board.revision == revision, board.isFinal == finished
                else { throw NativeConversationCardError.unsupported }
                do { try board.validate(for: reference.instanceId) }
                catch { throw NativeConversationCardError.unsupported }
            }
        }
    }
}

struct NativeConversationCardAction: Encodable, Equatable, Sendable {
    let schemaVersion = 1
    let action: String
    let actionId: String
    let expectedRevision: Int
    let input: [String: Int]?
}

enum NativeConversationCardError: LocalizedError, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, identityChanged, missing, conflict, unavailable, unsupported

    var isUnauthorized: Bool { self == .unauthorized }
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录。"
        case .forbidden: return "当前账号无法执行此操作。"
        case .identityChanged: return "账号已切换，请重新打开卡片。"
        case .missing: return "找不到这张卡片。"
        case .conflict: return "卡片状态已变化，请根据最新状态再试。"
        case .unavailable: return "暂时无法同步卡片。"
        case .unsupported: return "当前版本仅可查看卡片摘要。"
        }
    }
}
