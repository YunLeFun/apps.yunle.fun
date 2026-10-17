import Foundation

enum CommunityError: Error, Equatable {
    case invalidInput, invalidResponse, unauthorized, forbidden, notFound, duplicate, throttled, unavailable, identityChanged
    var message: String {
        switch self {
        case .invalidInput: return "请检查评分、内容和字数后再试。"
        case .invalidResponse: return "服务返回的数据暂时无法读取，请刷新后重试。"
        case .unauthorized: return "登录状态已失效，请重新登录。"
        case .forbidden: return "当前账号不能执行此操作。"
        case .notFound: return "应用或评价已不可用，请刷新查看。"
        case .duplicate: return "你已举报过该内容，可在“我的举报”查看状态。"
        case .throttled: return "操作较频繁，请稍后再试。"
        case .unavailable: return "暂时无法连接服务，请稍后重试。"
        case .identityChanged: return "账号已变化，请重新打开此页面。"
        }
    }
}

enum ReviewStatus: String, Codable, Sendable {
    case published, pending, rejected
    var label: String {
        switch self { case .published: return "已发布"; case .pending: return "待审核"; case .rejected: return "未通过审核" }
    }
    var message: String {
        switch self {
        case .published: return "评价已发布"
        case .pending: return "评价已提交，审核通过后展示"
        case .rejected: return "评价未通过审核，可修改后重新提交"
        }
    }
}
struct AppReview: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let appKey: String
    let authorName: String
    let rating: Int
    let title: String?
    let content: String
    let createdAt: Double
    let updatedAt: Double
    let uid: String?
    let status: ReviewStatus?
    let rejectedReason: String?
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case appKey, authorName, rating, title, content, createdAt, updatedAt, uid, status, rejectedReason
    }
    var date: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    func validate(appKey: String, owner: String? = nil) throws {
        guard CommunityValue.identifier(id), self.appKey == appKey, !authorName.isEmpty,
              (1...5).contains(rating), !content.isEmpty, content.utf16.count <= 1000,
              (title?.utf16.count ?? 0) <= 100,
              CommunityValue.timestamp(createdAt), CommunityValue.timestamp(updatedAt),
              owner == nil || (uid == owner && status != nil)
        else { throw CommunityError.invalidResponse }
    }
}
struct ReviewSummary: Codable, Equatable, Sendable {
    let average: Double
    let count: Int
    let distribution: [String: Int]
    func validate() throws {
        guard (0...1_000_000_000).contains(count), average.isFinite, (0...5).contains(average),
              Set(distribution.keys) == Set(["1", "2", "3", "4", "5"]),
              distribution.values.allSatisfy({ (0...1_000_000_000).contains($0) }),
              distribution.values.reduce(0, +) == count else { throw CommunityError.invalidResponse }
        let total = distribution.reduce(0) { $0 + (Int($1.key) ?? 0) * $1.value }
        let expected = count == 0 ? 0 : (Double(total) / Double(count) * 10).rounded() / 10
        guard abs(expected - average) < 0.001 else { throw CommunityError.invalidResponse }
    }
}
struct ReviewList: Decodable, Sendable {
    let summary: ReviewSummary
    let reviews: [AppReview]
    let myReview: AppReview?
    func validate(appKey: String, owner: String?) throws {
        try summary.validate()
        guard reviews.count <= 50, reviews.count <= summary.count,
              Set(reviews.map(\.id)).count == reviews.count else { throw CommunityError.invalidResponse }
        for review in reviews {
            try review.validate(appKey: appKey)
            guard review.status == nil || review.status == .published else { throw CommunityError.invalidResponse }
        }
        if let myReview {
            guard let owner else { throw CommunityError.invalidResponse }
            try myReview.validate(appKey: appKey, owner: owner)
        }
    }
}
struct ReviewDraft: Equatable, Sendable {
    var rating = 5
    var title = ""
    var content = ""
    init(review: AppReview? = nil) {
        rating = review?.rating ?? 5; title = review?.title ?? ""; content = review?.content ?? ""
    }
    var isValid: Bool {
        (1...5).contains(rating) && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && content.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 1000
        && title.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 100
    }
}
struct ReviewSubmission: Decodable, Sendable {
    let status: ReviewStatus
    let review: AppReview
}
enum ReportReason: String, CaseIterable, Codable, Identifiable, Sendable {
    case illegal, porn, abuse, spam, privacy, other
    var id: Self { self }
    var label: String {
        switch self {
        case .illegal: return "违法违规"; case .porn: return "色情低俗"; case .abuse: return "人身攻击"
        case .spam: return "垃圾营销"; case .privacy: return "隐私泄露"; case .other: return "其他"
        }
    }
}
enum ReportTargetType: String, Codable, Sendable { case app, review }
struct ReportTarget: Identifiable, Sendable {
    let type: ReportTargetType
    let id: String
    let appKey: String
    let label: String
}
enum ReportStatus: String, Codable, Sendable {
    case open, resolved, dismissed
    var label: String {
        switch self { case .open: return "待处理"; case .resolved: return "已处理"; case .dismissed: return "已忽略" }
    }
}
struct MyReport: Decodable, Identifiable, Sendable {
    let id: String
    let targetType: ReportTargetType
    let targetId: String
    let appKey: String?
    let appName: String?
    let reason: ReportReason
    let detail: String?
    let status: ReportStatus
    let createdAt: Double
    let handledAt: Double?
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case targetType, targetId, appKey, appName, reason, detail, status, createdAt, handledAt
    }
    func validate() throws {
        guard CommunityValue.identifier(id), !targetId.isEmpty, CommunityValue.timestamp(createdAt),
              (detail?.utf16.count ?? 0) <= 500,
              handledAt.map({ $0 == 0 || CommunityValue.timestamp($0) }) ?? true
        else { throw CommunityError.invalidResponse }
    }
}
enum CommunityValue {
    static func identifier(_ value: String) -> Bool {
        (1...256).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    static func timestamp(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value <= 253_402_300_799_999 && value.rounded() == value
    }
}
