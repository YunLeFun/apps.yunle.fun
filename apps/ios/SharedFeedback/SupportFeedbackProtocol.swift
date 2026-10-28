import Foundation

enum SupportProduct {
    static func title(_ id: String) -> String {
        switch id {
        case "www": return "云乐坊账号与服务"
        case "cook": return "云食册 / 食用手册"
        case "play": return "Play 游戏"
        case "yunbox": return "云匣 YunBox"
        case "drive": return "Drive"
        case "cms": return "CMS"
        case "advjs": return "AdvJS"
        default: return id
        }
    }
    static let submissionIDs = ["www", "cook", "play", "yunbox", "drive", "cms", "advjs"]
}

struct SupportFeedbackReceipt: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let productId: String
    let ticketId: String?
    let ticketUrl: String?
}

struct SupportFeedbackAccess: Sendable {
    let csrfToken: String
    let cookies: [HTTPCookie]
}

/// An immutable, reviewed payload; no filenames, account credentials or photo metadata.
struct SupportFeedbackSubmission: Equatable, Sendable, Encodable {
    struct Context: Equatable, Sendable, Encodable { let source: String; let version: String }
    let productId: String
    let category: String
    let description: String
    let images: [Data]
    let context: Context?

    init(product: String, category: String, description: String, screenshots: [FeedbackScreenshot], context: Context? = nil) {
        productId = product; self.category = category
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        images = screenshots.map(\.data); self.context = context
    }

    func encode(to encoder: Encoder) throws {
        enum Keys: String, CodingKey { case productId, category, description, screenshots, context }
        struct ImageInput: Encodable { let mimeType = "image/jpeg"; let data: String }
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(productId, forKey: .productId)
        try values.encode(category, forKey: .category)
        try values.encode(description, forKey: .description)
        if !images.isEmpty { try values.encode(images.map { ImageInput(data: $0.base64EncodedString()) }, forKey: .screenshots) }
        try values.encodeIfPresent(context, forKey: .context)
    }

    func validate() throws {
        guard SupportProduct.submissionIDs.contains(productId), ["problem", "suggestion", "other"].contains(category),
              (5...4000).contains(description.utf16.count) else { throw SupportFeedbackError.invalidInput }
        guard images.count <= FeedbackScreenshot.maximumCount,
              images.allSatisfy({ !$0.isEmpty && $0.count <= FeedbackScreenshot.maximumBytes }) else {
            throw SupportFeedbackError.invalidScreenshot
        }
    }
}

protocol SupportFeedbackSubmitting: Sendable {
    func connectGuest() async throws -> SupportFeedbackAccess
    func submit(_ submission: SupportFeedbackSubmission, key: String, access: SupportFeedbackAccess) async throws -> SupportFeedbackReceipt
}

enum SupportFeedbackError: Error, Equatable {
    case invalidResponse, unavailable, throttled, unauthorized, forbidden, invalidInput, invalidScreenshot
    var message: String {
        switch self {
        case .invalidInput: return "请填写 5 至 4000 个字符的问题描述。"
        case .invalidScreenshot: return "截图未能提交。最多 3 张，压缩后每张不超过 1 MB，请检查后重试。"
        case .unauthorized, .forbidden: return "反馈会话校验失败，请稍后重新打开分享菜单。"
        case .throttled: return "操作有些频繁，请稍后再试。"
        case .invalidResponse: return "提交结果尚未确认。请重试，未修改的内容会使用同一提交编号。"
        case .unavailable: return "暂时无法连接支持中心。内容已保留，可以重试。"
        }
    }
}
