import Foundation

enum AssistantError: Error, Equatable, AccountRequestFailure {
    case unauthorized, forbidden, membershipRequired, quota, unavailable, invalidResponse, identityChanged, interrupted, tooLong
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录后再试。"
        case .forbidden: return "当前账号暂不能使用 AI 助手。"
        case .membershipRequired: return "AI 助手需要有效会员。"
        case .quota: return "今日 AI 助手使用次数已达上限，请明天再试。"
        case .identityChanged: return "账号已变化，请重新开始对话。"
        case .interrupted: return "连接已中断，已保留收到的内容。可以重试。"
        case .tooLong: return "对话内容过长，请缩短问题或开始新对话。"
        default: return "AI 助手暂时不可用，请稍后重试。"
        }
    }
    static func fromServerCode(_ code: String?) -> Self {
        switch code {
        case "UNAUTHENTICATED", "TOKEN_EXPIRED": return .unauthorized
        case "MEMBERSHIP_REQUIRED": return .membershipRequired
        case "ACCOUNT_RESTRICTED": return .forbidden
        case "DAILY_LIMIT_EXCEEDED": return .quota
        case "REQUEST_TOO_LARGE": return .tooLong
        default: return .unavailable
        }
    }
}
struct AssistantAppCard: Identifiable, Equatable, Codable, Sendable {
    let applicationID: String?
    let slug: String
    let name: String
    let reason: String?
    var id: String { applicationID ?? slug }
    func resolve(in catalog: [CloudApplication]) -> CloudApplication? {
        // Agent output never supplies executable URLs, prices, permissions, or a private edition.
        let candidates = catalog.filter { app in
            app.accessOwnerID == nil && app.accessWorkshopID == nil && app.isUnavailable != true
            && app.isPublic != false && (app.audience == nil || app.audience == "public")
            && (applicationID.map { app.id == $0 } ?? (app.marketShortName == slug || app.id == slug))
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
struct AssistantMessage: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum Status: String, Codable, Sendable { case streaming, done, stopped, failed }
    let id: String
    let role: Role
    var content: String
    var cards: [AssistantAppCard] = []
    var status: Status = .done
    var toolStatus: String?
}
struct AssistantRunInput: Encodable, Sendable {
    let botId: String
    let threadId: String
    let runId: String
    let messages: [Message]
    var tools: [Tool] = [.search]
    let context: [String] = []
    let state: [String: String] = [:]
    let forwardedProps = ["source": "apps.yunle.fun", "platform": "ios"]
    struct Message: Encodable, Sendable {
        let id: String
        let role: AssistantMessage.Role
        let content: String
    }
    struct Tool: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters
        struct Parameters: Encodable, Sendable {
            let type = "object"
            let properties: [String: Property]
            let required = ["query"]
        }
        struct Property: Encodable, Sendable { let type: String; let description: String }
        static let search = Tool(name: "search_apps", description: "Search public approved YunLeFun apps and return up to six application cards.",
            parameters: Parameters(properties: [
                "query": Property(type: "string", description: "User intent or keywords."),
                "category": Property(type: "string", description: "Optional application category."),
                "limit": Property(type: "number", description: "Maximum cards, at most six.")
            ]))
    }
}
struct AssistantEvent: Sendable {
    let type: String?
    let threadID: String?
    let runID: String?
    let messageID: String?
    let delta: String?
    let content: String?
    let toolCallID: String?
    let toolName: String?
    let cards: [AssistantAppCard]
    let code: String?
    let isReasoning: Bool
    init(data: Data) throws {
        guard data.count <= 512 * 1024 else { throw AssistantError.tooLong }
        if data == Data("[DONE]".utf8) {
            type = "_DONE"; threadID = nil; runID = nil; messageID = nil; delta = nil; content = nil
            toolCallID = nil; toolName = nil; cards = []; code = nil; isReasoning = false; return
        }
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssistantError.invalidResponse }
        type = fields["type"] as? String
        threadID = fields["threadId"] as? String; runID = fields["runId"] as? String; messageID = fields["messageId"] as? String
        delta = fields["delta"] as? String; content = fields["content"] as? String
        toolCallID = fields["toolCallId"] as? String; toolName = fields["toolCallName"] as? String
        code = fields["code"] as? String; isReasoning = (fields["reasoning_content"] as? String)?.isEmpty == false
        cards = type == "TOOL_CALL_RESULT" ? try Self.extractCards(fields["content"]) : []
    }
    static func extractCards(_ value: Any?, depth: Int = 0) throws -> [AssistantAppCard] {
        guard depth <= 3 else { return [] }
        if let string = value as? String, let data = string.data(using: .utf8) {
            guard data.count <= 512 * 1024 else { throw AssistantError.tooLong }
            guard let nested = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return try extractCards(nested, depth: depth + 1)
        }
        if let array = value as? [[String: Any]] {
            guard array.count <= 6 else { throw AssistantError.invalidResponse }
            return array.compactMap { item in
                func text(_ key: String) -> String? {
                    guard let value = item[key] as? String, !value.isEmpty, value.utf16.count <= 500 else { return nil }
                    return value
                }
                let id = text("id") ?? text("appId")
                guard let key = text("slug") ?? id, let name = text("name") ?? text("title") else { return nil }
                return AssistantAppCard(applicationID: id, slug: key, name: name, reason: text("reason"))
            }
        }
        if let object = value as? [String: Any] {
            for key in ["apps", "appCards", "cards", "items", "results", "data", "result", "payload"] {
                if let nested = object[key] {
                    let cards = try extractCards(nested, depth: depth + 1)
                    if !cards.isEmpty { return cards }
                }
            }
        }
        return []
    }
}

/// Incremental SSE framing. UTF-8 is decoded after an entire line, including CR, LF and CRLF boundaries.
struct AssistantSSEDecoder {
    private var line = Data(), data = Data()
    private var afterCR = false, firstLine = true
    mutating func append(_ byte: UInt8) throws -> Data? {
        if afterCR && byte == 10 { afterCR = false; return nil }
        afterCR = false
        if byte == 10 || byte == 13 {
            afterCR = byte == 13
            return try finishLine()
        }
        line.append(byte)
        guard line.count <= 512 * 1024 else { throw AssistantError.tooLong }
        return nil
    }
    private mutating func finishLine() throws -> Data? {
        defer { line.removeAll(keepingCapacity: true); firstLine = false }
        if firstLine && line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        guard String(data: line, encoding: .utf8) != nil else { throw AssistantError.invalidResponse }
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            data.removeLast()
            let payload = data; data = Data()
            return payload
        }
        if line.starts(with: Data("data:".utf8)) || line == Data("data".utf8) {
            var value = line.count > 4 ? line.dropFirst(5) : Data.SubSequence()
            if value.first == 32 { value = value.dropFirst() }
            data.append(contentsOf: value); data.append(10)
            guard data.count <= 512 * 1024 else { throw AssistantError.tooLong }
        }
        return nil
    }
}
struct AssistantRunAccumulator {
    let threadID: String
    let runID: String
    private(set) var finished = false
    private var started = false, legacyContent = false
    private var messages = Set<String>(), openMessages = Set<String>(), searches = Set<String>()
    private(set) var content = ""
    private(set) var cards: [AssistantAppCard] = []
    private(set) var status: String? = "正在连接"
    mutating func apply(_ event: AssistantEvent) throws {
        guard !finished else { throw AssistantError.invalidResponse }
        if let thread = event.threadID, thread != threadID { throw AssistantError.invalidResponse }
        if let run = event.runID, run != runID { throw AssistantError.invalidResponse }
        if event.type == "RUN_ERROR" { throw AssistantError.fromServerCode(event.code) }
        if event.isReasoning { status = "正在思考" }
        switch event.type {
        case "RUN_STARTED":
            guard !started, event.threadID == threadID, event.runID == runID else { throw AssistantError.invalidResponse }
            started = true
        case "TEXT_MESSAGE_START":
            guard started, let id = event.messageID, messages.count < 32, messages.insert(id).inserted else { throw AssistantError.invalidResponse }
            openMessages.insert(id)
        case "TEXT_MESSAGE_CONTENT":
            guard started, let id = event.messageID, openMessages.contains(id), let delta = event.delta else { throw AssistantError.invalidResponse }
            content += delta; status = nil
        case "TEXT_MESSAGE_END":
            guard let id = event.messageID, openMessages.remove(id) != nil else { throw AssistantError.invalidResponse }
        case "TOOL_CALL_START":
            guard started, let id = event.toolCallID, searches.count < 32 else { throw AssistantError.invalidResponse }
            if event.toolName == "search_apps" { searches.insert(id); status = "正在检索应用" }
        case "TOOL_CALL_ARGS": status = "正在确认条件"
        case "TOOL_CALL_END": status = "正在整理结果"
        case "TOOL_CALL_RESULT":
            if let id = event.toolCallID, searches.remove(id) != nil {
                for card in event.cards where !cards.contains(where: { $0.id == card.id }) { cards.append(card) }
                guard cards.count <= 6 else { throw AssistantError.invalidResponse }
            }
        case "RUN_FINISHED":
            guard started, openMessages.isEmpty, event.runID == runID, event.threadID == threadID else { throw AssistantError.invalidResponse }
            finished = true; status = nil
        case "_DONE":
            guard legacyContent && !started else { throw AssistantError.interrupted }
            finished = true; status = nil
        case nil:
            if let delta = event.content { content += delta; legacyContent = true; status = nil }
        default: break
        }
        guard content.utf8.count <= 64 * 1024 else { throw AssistantError.tooLong }
    }
}

/// Return handling for the multi-line composer, whose 发送 key inserts a newline instead of calling onSubmit.
enum AssistantComposer {
    /// The draft before a just-typed Return when `new` differs from `old` by exactly one inserted
    /// newline, at any caret position; nil for pastes and programmatic edits, which stay draft-only.
    static func submission(from old: String, to new: String) -> String? {
        guard new.count == old.count + 1 else { return nil }
        var o = old.startIndex, n = new.startIndex
        while o < old.endIndex, old[o] == new[n] { o = old.index(after: o); n = new.index(after: n) }
        guard new[n] == "\n", new[new.index(after: n)...] == old[o...] else { return nil }
        return old
    }
}
