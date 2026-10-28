import Foundation

struct SupportTicketDetail: Decodable {
    struct Ticket: Decodable {
        let id: String
        let number: String
        let title: String
        let productId: String
        let status: String
        let createdAt: String
        let updatedAt: String
        var statusTitle: String {
            switch status {
            case "new", "open": return "待处理"
            case "triaged": return "已分流"
            case "in_progress": return "处理中"
            case "waiting_user": return "等待补充"
            case "resolved": return "已解决"
            case "closed": return "已关闭"
            default: return status
            }
        }
    }
    struct Message: Decodable, Identifiable {
        let id: String
        let content: String
        let createdAt: String
        let author: String
    }
    let ticket: Ticket
    let messages: [Message]
}

struct SupportTicketScreenshot: Decodable, Identifiable, Equatable {
    let id: String
    let mimeType: String
    let width: Int
    let height: Int
    let sizeBytes: Int
}

struct SupportTicketSnapshot {
    let detail: SupportTicketDetail
    let screenshots: [SupportTicketScreenshot]
    let cookies: [HTTPCookie]
}

enum SupportTicketError: Error, Equatable {
    case invalidResponse, unavailable, expired, notFound, throttled
    var message: String {
        switch self {
        case .invalidResponse: return "工单内容暂时无法读取，请稍后重试。"
        case .unavailable: return "暂时无法读取工单，请检查网络后重试。"
        case .expired: return "工单访问凭证已失效，请使用原账号或有效的私密工单链接查看。"
        case .notFound: return "工单或截图已不可用。"
        case .throttled: return "操作有些频繁，请稍后再试。"
        }
    }
}
