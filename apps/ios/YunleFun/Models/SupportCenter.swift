import Foundation

enum SupportDestination: String, CaseIterable, Identifiable {
    case compose, board, manage
    var id: Self { self }
    var title: String {
        switch self { case .compose: return "在线反馈"; case .board: return "需求墙"; case .manage: return "反馈管理" }
    }
}

struct SupportPage<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

struct SupportBoardItem: Decodable, Identifiable {
    let id: String
    let productId: String
    let title: String
    let publicContent: String
    let publicStatus: String
    let voteCount: Int
    let officialResponse: String?
    var statusTitle: String {
        switch publicStatus {
        case "collecting": return "收集中"
        case "evaluating": return "评估中"
        case "planned": return "已计划"
        case "in_progress": return "进行中"
        case "shipped": return "已完成"
        case "declined": return "暂不采纳"
        default: return publicStatus
        }
    }
}

struct SupportPrivateItem: Decodable, Identifiable {
    struct Context: Decodable {
        let source: String?
        let version: String?
    }
    let id: String
    let productId: String
    let description: String
    let status: String
    let category: String
    let createdAt: String
    let ticketId: String?
    let context: Context?
    var sourceTitle: String {
        switch context?.source {
        case "cook-web": return "Web"
        case "cook-ios": return "iOS"
        case "apps-ios-share": return "iOS 系统分享"
        case .some(let source) where !source.isEmpty: return source
        default: return "未记录"
        }
    }
    var sourceSummary: String {
        guard let version = context?.version, !version.isEmpty else { return sourceTitle }
        return "\(sourceTitle) · \(version)"
    }
    var statusTitle: String {
        switch status { case "received": return "待处理"; case "reviewing": return "处理中"; case "resolved": return "已处理"; default: return status }
    }
}

struct SupportDashboard: Decodable {
    let productId: String
    let productIds: [String]
    let feedback: SupportPage<SupportBoardItem>
    let privateFeedback: SupportPage<SupportPrivateItem>
}

/// A short-lived Support session, kept in memory and scoped to one App identity.
/// Neither the App's access token nor its SSO assertion enters the WebView.
struct SupportAccess {
    let userID: String?
    let csrfToken: String
    let cookies: [HTTPCookie]
}

struct SupportBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
    let access: SupportAccess?
}

enum SupportCenterError: Error, Equatable, AccountRequestFailure {
    case identityChanged, unauthorized, forbidden, consentRequired, invalidResponse, unavailable, throttled, invalidInput, invalidScreenshot
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .identityChanged: return "账号已变化，请重新打开支持中心。"
        case .unauthorized: return "支持中心登录已失效，请重新连接。"
        case .forbidden: return "当前账号没有此项权限，或尚未完成手机号验证。请在账号中心核对。"
        case .consentRequired: return "请允许支持中心使用当前云乐坊账号。"
        case .invalidResponse: return "支持中心返回了无法识别的内容，请稍后重试。"
        case .unavailable: return "暂时无法连接支持中心，请稍后重试。"
        case .throttled: return "操作有些频繁，请稍后再试。"
        case .invalidScreenshot: return "截图未能提交。最多可添加 3 张、每张压缩后 1 MB 以内；请重新选择，或稍后重试。"
        case .invalidInput: return "请填写 5 至 4000 个字符的问题描述。"
        }
    }
}
