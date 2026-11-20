import Foundation

struct ConversationBoardScene: Codable, Equatable, Sendable {
    struct Palette: Codable, Equatable, Sendable {
        let board: String
        let grid: String
        let black: String
        let white: String

        var valid: Bool { [board, grid, black, white].allSatisfy { Self.rgb($0) != nil } }

        static func rgb(_ value: String) -> UInt32? {
            let bytes = value.utf8
            guard bytes.count == 7, bytes.first == 35,
                  bytes.dropFirst().allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
            else { return nil }
            return UInt32(value.dropFirst(), radix: 16)
        }
    }

    struct Interaction: Codable, Equatable, Sendable {
        enum Gesture: String, Codable, Sendable { case dragToPlace = "drag-to-place" }
        enum Action: String, Codable, Sendable { case place }
        let gesture: Gesture
        let action: Action
    }

    let schemaVersion: Int
    let size: Int
    let palette: Palette
    let interaction: Interaction

    var valid: Bool { schemaVersion == 1 && (5...15).contains(size) && palette.valid }
}

struct ConversationBoardPosition: Codable, Hashable, Sendable {
    let row: Int
    let column: Int

    func fits(size: Int) -> Bool { (0..<size).contains(row) && (0..<size).contains(column) }
}

struct ConversationBoardSnapshot: Codable, Equatable, Sendable {
    enum Seat: String, Codable, Sendable {
        case black, white
        var title: String { self == .black ? "黑棋" : "白棋" }
    }
    enum Status: String, Codable, Sendable { case waiting, playing, won, draw }
    struct Piece: Codable, Equatable, Sendable {
        let row: Int
        let column: Int
        let color: Seat
        var position: ConversationBoardPosition { .init(row: row, column: column) }
    }

    let schemaVersion: Int
    let boardId: String
    let scene: ConversationBoardScene
    let revision: Int
    let status: Status
    let seat: Seat?
    let turn: Seat?
    let winner: Seat?
    let pieces: [Piece]

    var isFinal: Bool { status == .won || status == .draw }
    var canPlace: Bool { status == .playing && turn != nil && seat == turn }

    func allows(_ point: ConversationBoardPosition) -> Bool {
        canPlace && point.fits(size: scene.size) && !pieces.contains(where: { $0.position == point })
    }

    func validate(for id: String) throws {
        guard schemaVersion == 1, boardId == id, scene.valid, pieces.count <= scene.size * scene.size,
              revision == (status == .waiting ? 1 : 2 + pieces.count),
              Set(pieces.map(\.position)).count == pieces.count,
              pieces.enumerated().allSatisfy({ index, piece in
                  piece.position.fits(size: scene.size) && piece.color == (index.isMultiple(of: 2) ? .black : .white)
              }) else { throw ConversationBoardError.unavailable }
        let validStatus: Bool
        switch status {
        case .waiting: validStatus = pieces.isEmpty && seat != .white && turn == nil && winner == nil
        case .playing:
            validStatus = turn == (pieces.count.isMultiple(of: 2) ? .black : .white)
                && winner == nil && pieces.count < scene.size * scene.size
        case .won: validStatus = pieces.count >= 9 && turn == nil && winner == pieces.last?.color
        case .draw: validStatus = pieces.count == scene.size * scene.size && turn == nil && winner == nil
        }
        guard validStatus else { throw ConversationBoardError.unavailable }
    }
}

enum ConversationBoardCommand: Equatable {
    static let createPrompt = "创建联机棋盘"
    static let openPrompt = "打开联机棋盘"
    case create, open(String)

    static func parse(_ prompt: String) throws -> Self? {
        if prompt == createPrompt { return .create }
        if prompt == openPrompt || prompt.hasPrefix(openPrompt + " ") {
            let id = String(prompt.dropFirst(openPrompt.count)).trimmingCharacters(in: .whitespaces).lowercased()
            guard ConversationCard.validInstanceID(id) else { throw ConversationBoardError.invalidCommand }
            return .open(id)
        }
        return nil
    }
}

struct ConversationBoardLink: Hashable {
    let boardID: String

    init?(boardID: String) {
        guard ConversationCard.validInstanceID(boardID) else { return nil }
        self.boardID = boardID
    }

    var url: URL {
        CatalogService.productionOrigin.appendingPathComponent("boards").appendingPathComponent(boardID)
    }

    static func parse(_ url: URL) -> Self? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { return nil }
        let prefix: String
        switch (parts.scheme?.lowercased(), parts.host?.lowercased(), parts.port) {
        case ("https", "apps.yunle.fun", nil), ("https", "apps.yunle.fun", 443): prefix = "/boards/"
        case ("yunlefun", "board", nil): prefix = "/"
        default: return nil
        }
        let path = parts.percentEncodedPath
        guard path.hasPrefix(prefix) else { return nil }
        return Self(boardID: String(path.dropFirst(prefix.count)))
    }
}

enum ConversationBoardAction: Equatable, Sendable, Encodable {
    case join
    case place(ConversationBoardPosition, revision: Int, id: String)

    func encode(to encoder: Encoder) throws {
        enum Key: String, CodingKey { case action, row, column, expectedRevision, actionId }
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .join:
            try container.encode("join", forKey: .action)
        case .place(let point, let revision, let id):
            try container.encode(ConversationBoardScene.Interaction.Action.place.rawValue, forKey: .action)
            try container.encode(point.row, forKey: .row)
            try container.encode(point.column, forKey: .column)
            try container.encode(revision, forKey: .expectedRevision)
            try container.encode(id, forKey: .actionId)
        }
    }
}

enum ConversationBoardError: LocalizedError, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, identityChanged, missing, conflict, unavailable, invalidCommand
    var isUnauthorized: Bool { self == .unauthorized }
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录。"
        case .forbidden: return "当前账号无法进行此操作。"
        case .identityChanged: return "账号已切换，请重新打开棋盘。"
        case .missing: return "找不到这局五子棋。"
        case .conflict: return "棋局已变化，请根据最新棋盘再试。"
        case .unavailable: return "暂时无法同步棋局。"
        case .invalidCommand: return "请发送「创建联机棋盘」，或复制分享中的完整打开指令。"
        }
    }
}
