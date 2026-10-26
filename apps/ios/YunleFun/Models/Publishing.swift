import Foundation

enum PublishingError: Error, Equatable, AccountRequestFailure {
    case invalidInput, invalidResponse, unauthorized, forbidden, notFound, conflict, throttled, unavailable, identityChanged, storage, unsupportedServer
    var isUnauthorized: Bool { self == .unauthorized }
    var message: String {
        switch self {
        case .invalidInput: return "请检查名称、标识、网址与内容长度。"
        case .invalidResponse: return "服务返回的作品信息不完整，请刷新后核对。"
        case .unauthorized: return "登录状态已失效，请重新登录。"
        case .forbidden: return "请使用已验证手机号且状态正常的作品所有者账号操作。"
        case .notFound: return "作品已不存在或当前账号无权管理。"
        case .conflict: return "作品、市场短名或审核状态已变化，请刷新后核对。"
        case .throttled: return "操作较频繁，请稍后重试。作品保存还有每日次数限制。"
        case .unavailable: return "暂时无法连接作品服务，请检查网络后重试。"
        case .identityChanged: return "账号已变化，请重新打开作品。"
        case .unsupportedServer: return "服务暂未支持安全保存。请稍后刷新重试，本机草稿可以继续保留。"
        case .storage: return "无法保存本机草稿，原有文件已保留。"
        }
    }
    static func message(for error: Error) -> String {
        if let known = error as? PublishingError { return known.message }
        if let known = error as? AccountError { return AccountError.message(for: known) }
        return PublishingError.unavailable.message
    }
}
enum ApplicationAudience: String, Codable, CaseIterable, Identifiable {
    case `public`, workshop, owner
    var id: String { rawValue }
    var label: String { switch self { case .public: return "公开作品"; case .workshop: return "工坊坊客"; case .owner: return "仅本人" } }
}
enum ApplicationAccessMode: String, Codable, CaseIterable, Identifiable {
    case `public`, loginRequired = "login_required", inviteOnly = "invite_only"
    var id: String { rawValue }
    var label: String { switch self { case .public: return "直接访问"; case .loginRequired: return "需要登录"; case .inviteOnly: return "需要邀请" } }
}
enum ApplicationReleaseStage: String, Codable, CaseIterable, Identifiable {
    case stable, beta
    var id: String { rawValue }
    var label: String { self == .stable ? "正式版" : "测试版" }
}
enum ApplicationReviewStatus: String, Codable { case draft, pending, inReview = "in_review", changesRequested = "changes_requested", approved, rejected, withdrawn }
enum ApplicationPublicationStatus: String, Codable {
    case unpublished, published, suspended, delisted
    var label: String { switch self { case .unpublished: return "尚未发布"; case .published: return "当前版本已发布"; case .suspended: return "作品已暂停"; case .delisted: return "作品已下架" } }
}
struct ApplicationDraft: Codable, Equatable {
    var name = "", slug = "", description = "", githubRepo = "", websiteUrl = "", privacyPolicyUrl = "", supportUrl = ""
    var trustedHosts: [String] = []
    var backupUrl = "", logo = "", emoji = "📱", themeColor = "#007AFF", category = "其他"
    var iconAssets: CloudApplication.IconAssets?
    var tags: [String] = []
    var audience = ApplicationAudience.public
    var accessMode = ApplicationAccessMode.public
    var releaseStage = ApplicationReleaseStage.stable
    init() {}
    enum CodingKeys: String, CodingKey {
        case name, slug, description, githubRepo, websiteUrl, privacyPolicyUrl, supportUrl, trustedHosts, backupUrl, logo, emoji
        case themeColor, category, iconAssets, tags, audience, accessMode, releaseStage, isPublic
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); slug = try c.decode(String.self, forKey: .slug)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        githubRepo = try c.decodeIfPresent(String.self, forKey: .githubRepo) ?? ""
        websiteUrl = try c.decodeIfPresent(String.self, forKey: .websiteUrl) ?? ""
        privacyPolicyUrl = try c.decodeIfPresent(String.self, forKey: .privacyPolicyUrl) ?? ""
        supportUrl = try c.decodeIfPresent(String.self, forKey: .supportUrl) ?? ""
        trustedHosts = try c.decodeIfPresent([String].self, forKey: .trustedHosts) ?? []
        backupUrl = try c.decodeIfPresent(String.self, forKey: .backupUrl) ?? ""
        logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "📱"
        themeColor = try c.decodeIfPresent(String.self, forKey: .themeColor) ?? "#007AFF"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "其他"
        iconAssets = try c.decodeIfPresent(CloudApplication.IconAssets.self, forKey: .iconAssets)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        audience = try c.decodeIfPresent(ApplicationAudience.self, forKey: .audience) ?? ((try c.decodeIfPresent(Bool.self, forKey: .isPublic)) == true ? .public : .owner)
        accessMode = try c.decodeIfPresent(ApplicationAccessMode.self, forKey: .accessMode) ?? .public
        releaseStage = try c.decodeIfPresent(ApplicationReleaseStage.self, forKey: .releaseStage) ?? .stable
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(slug, forKey: .slug); try c.encode(description, forKey: .description)
        try c.encode(githubRepo, forKey: .githubRepo); try c.encode(websiteUrl, forKey: .websiteUrl)
        try c.encode(privacyPolicyUrl, forKey: .privacyPolicyUrl); try c.encode(supportUrl, forKey: .supportUrl)
        try c.encode(trustedHosts, forKey: .trustedHosts); try c.encode(backupUrl, forKey: .backupUrl)
        try c.encode(logo, forKey: .logo); try c.encode(emoji, forKey: .emoji); try c.encode(themeColor, forKey: .themeColor)
        try c.encode(category, forKey: .category); try c.encodeIfPresent(iconAssets, forKey: .iconAssets); try c.encode(tags, forKey: .tags)
        try c.encode(audience, forKey: .audience); try c.encode(accessMode, forKey: .accessMode); try c.encode(releaseStage, forKey: .releaseStage)
        try c.encode(audience == .public, forKey: .isPublic)
    }
    var validationIssue: String? {
        if name.trimmed.isEmpty || name.trimmed.utf16.count > 50 { return "应用名称必填，最多 50 字。" }
        if !PublishingValue.slug(slug.trimmed) { return "应用标识须为 2–50 个小写字母、数字或连字符，并以字母开头。" }
        if description.trimmed.utf16.count > 300 { return "简介最多 300 字。" }
        for (label, value) in [("应用网址", websiteUrl), ("隐私政策", privacyPolicyUrl), ("支持链接", supportUrl)] {
            if !PublishingValue.https(value) { return "\(label)须为不含账号密码的 HTTPS 网址。" }
        }
        if audience == .public, let host = URL(string: websiteUrl.trimmed)?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
           host != "yunle.fun" && !host.hasSuffix(".yunle.fun") { return "公开作品的应用网址需属于 yunle.fun；外部站点可用于仅本人或工坊可见的作品。" }
        if !backupUrl.trimmed.isEmpty && !PublishingValue.https(backupUrl) { return "备用链接须为 HTTPS 网址。" }
        if !githubRepo.trimmed.isEmpty && githubRepo.trimmed.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) == nil { return "GitHub 仓库格式为 owner/repo。" }
        if themeColor.trimmed.range(of: "^#[A-Fa-f0-9]{6}$", options: .regularExpression) == nil { return "主题色格式为 #RRGGBB。" }
        if emoji.trimmed.utf16.count > 16 || category.trimmed.utf16.count > 40 { return "图标文字或分类过长。" }
        let actualTags = tags.map(\.trimmed).filter { !$0.isEmpty }
        let actualHosts = trustedHosts.map(\.trimmed).filter { !$0.isEmpty }
        if actualTags.count > 10 || actualTags.contains(where: { $0.utf16.count > 24 }) { return "标签最多 10 个，每个最多 24 字。" }
        if actualHosts.count > 10 || actualHosts.contains(where: { !PublishingValue.host($0) }) { return "授信域名最多 10 个，请仅输入域名。" }
        let sources = [logo] + [iconAssets?.appIcon?.src, iconAssets?.appIcon?.darkSrc, iconAssets?.mark?.src, iconAssets?.mark?.darkSrc].compactMap { $0 }
        if sources.contains(where: { !$0.trimmed.isEmpty && !PublishingValue.iconSource($0) }) { return "图标须为 HTTPS 图片地址或上传生成的云图标标识。" }
        if (iconAssets?.appIcon?.src?.isEmpty ?? true) && iconAssets?.appIcon?.darkSrc?.isEmpty == false { return "请先设置默认完整图标。" }
        if (iconAssets?.mark?.src?.isEmpty ?? true) && iconAssets?.mark?.darkSrc?.isEmpty == false { return "请先设置默认主体图标。" }
        return nil
    }
    var isValid: Bool { validationIssue == nil }
    var preview: CloudApplication {
        CloudApplication(id: "draft", name: name.nilIfEmpty ?? "应用预览", slug: slug, description: description, websiteUrl: websiteUrl,
                         logo: logo, emoji: emoji, themeColor: themeColor, category: category, tags: tags, iconAssets: iconAssets,
                         accessMode: accessMode.rawValue, trustedHosts: trustedHosts, audience: audience.rawValue, isPublic: audience == .public)
    }
}
struct PublishingAccess: Decodable {
    let writePreconditionVersion: Int?
    let canSubmitFirstParty: Bool
    let thirdPartyEnabled: Bool
    let thirdPartyMessage: String
}
struct ApplicationSubmission: Decodable {
    let id: String, appId: String, submitterUid: String
    let revision: Int
    let reviewStatus: ApplicationReviewStatus
    let snapshot: ApplicationDraft
    let reviewNote: String?
    enum CodingKeys: String, CodingKey { case id = "_id"; case appId, submitterUid, revision, reviewStatus, snapshot, reviewNote }
}
struct ApplicationListing: Decodable {
    let appId: String
    let shortName: String?
    let status: String
    let approvedRevisionId: String?
    let activeSubmissionId: String?
    let reason: String?
}
struct ManagedApplication: Decodable, Identifiable {
    let id: String
    var application: CloudApplication
    var draft: ApplicationDraft
    let ownerUid: String?
    let legacyOwner: String?
    var publicationStatus: ApplicationPublicationStatus?
    let ownerMetadataRevisionId: String?
    let writeVersion: String?
    let currentRevisionId: String?
    let publishedSubmissionId: String?
    let activeSubmissionId: String?
    let latestSubmission: ApplicationSubmission?
    var listing: ApplicationListing?
    let updatedAt: Double
    enum CodingKeys: String, CodingKey {
        case id = "_id", legacyOwner = "_openid", listing = "yunlefunListing"
        case ownerUid, publicationStatus, ownerMetadataRevisionId, writeVersion, currentRevisionId, publishedSubmissionId, activeSubmissionId, latestSubmission, updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); application = try CloudApplication(from: decoder); draft = try ApplicationDraft(from: decoder)
        ownerUid = try c.decodeIfPresent(String.self, forKey: .ownerUid); legacyOwner = try c.decodeIfPresent(String.self, forKey: .legacyOwner)
        publicationStatus = try c.decodeIfPresent(ApplicationPublicationStatus.self, forKey: .publicationStatus)
        writeVersion = try c.decodeIfPresent(String.self, forKey: .writeVersion)
        ownerMetadataRevisionId = try c.decodeIfPresent(String.self, forKey: .ownerMetadataRevisionId)
        currentRevisionId = try c.decodeIfPresent(String.self, forKey: .currentRevisionId)
        publishedSubmissionId = try c.decodeIfPresent(String.self, forKey: .publishedSubmissionId)
        activeSubmissionId = try c.decodeIfPresent(String.self, forKey: .activeSubmissionId)
        latestSubmission = try c.decodeIfPresent(ApplicationSubmission.self, forKey: .latestSubmission)
        listing = try c.decodeIfPresent(ApplicationListing.self, forKey: .listing)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
    }
    func validate(owner: String, id: String? = nil) throws {
        if let writeVersion, !PublishingValue.writeVersion(writeVersion) { throw PublishingError.invalidResponse }
        guard PublishingValue.identifier(self.id), id == nil || self.id == id,
              ownerUid?.nilIfEmpty == owner || (ownerUid?.nilIfEmpty == nil && legacyOwner == owner),
              !application.name.isEmpty, CommunityValue.timestamp(updatedAt) else { throw PublishingError.invalidResponse }
        if let listing { guard listing.appId == self.id, ["unlisted", "listed", "suspended", "delisted"].contains(listing.status) else { throw PublishingError.invalidResponse } }
        if let submission = latestSubmission {
            // Historical versions may come from an administrator or a previous owner.
            // Ownership is checked on the application; submitterUid records authorship.
            guard submission.appId == self.id, PublishingValue.identifier(submission.id), submission.revision > 0,
                  !submission.submitterUid.trimmed.isEmpty else { throw PublishingError.invalidResponse }
        }
    }
    var revisionID: String? { currentRevisionId?.nilIfEmpty ?? publishedSubmissionId?.nilIfEmpty }
    var hasCurrentMetadata: Bool {
        guard let current = revisionID else { return true }
        if let ownerMetadataRevisionId { return ownerMetadataRevisionId == current }
        return latestSubmission == nil || latestSubmission?.id == current
    }
    var marketState: PublicationPresentation {
        if publicationStatus == .delisted { return .init(label: "作品已下架", detail: "可编辑并保存新版本后重新发布。提交与审核记录仍保留。", action: nil) }
        if publicationStatus == .suspended { return .init(label: "作品已暂停", detail: "请查看处理意见，再决定是否修改。", action: nil) }
        if draft.audience != .public { return .init(label: draft.audience == .owner ? "仅本人可见" : "工坊坊客可见", detail: "投稿云乐坊会创建公开版本，网站本身的访问保护仍保留。", action: .makePublic) }
        let currentListed = revisionID != nil && listing?.approvedRevisionId == revisionID
        if currentListed && listing?.status == "listed" { return .init(label: "已上架云乐坊", detail: "当前版本正在云乐坊公开展示。", action: nil) }
        if currentListed && ["suspended", "delisted"].contains(listing?.status ?? "") {
            return .init(label: listing?.status == "suspended" ? "云乐坊展示已暂停" : "已从云乐坊下架", detail: listing?.reason ?? "请查看处理意见。", action: nil)
        }
        let olderListed = listing?.status == "listed" && listing?.approvedRevisionId?.nilIfEmpty != nil && !currentListed
        if let current = revisionID, let latest = latestSubmission, latest.id != current {
            let reviewing = latest.reviewStatus == .pending || latest.reviewStatus == .inReview
            return .init(label: "新版未投稿", detail: reviewing ? "另一个版本仍在审核；当前版本尚未投稿。" : "这里的审核意见属于另一个版本，当前版本尚未投稿。", action: .submit)
        }
        if let status = latestSubmission?.reviewStatus {
            switch status {
            case .pending, .inReview: return .init(label: status == .pending ? "等待审核" : "审核中", detail: olderListed ? "新版正在审核，云乐坊继续展示上一批准版本。" : "投稿已进入审核流程。", action: nil)
            case .approved where revisionID != nil && (listing?.activeSubmissionId ?? activeSubmissionId) == revisionID:
                return .init(label: "审核通过", detail: "等待管理员上架到云乐坊。", action: nil)
            case .changesRequested, .rejected: return .init(label: status == .rejected ? "审核未通过" : "需要修改", detail: latestSubmission?.reviewNote ?? "请修改后重新投稿。", action: .submit)
            default: break
            }
        }
        return .init(label: olderListed ? "新版未投稿" : "尚未投稿", detail: olderListed ? "云乐坊仍展示上一批准版本，可投稿当前新版。" : "保存当前版本不会自动投稿云乐坊。", action: .submit)
    }
}
enum PublicationAction { case submit, makePublic }
struct PublicationPresentation { let label: String; let detail: String; let action: PublicationAction? }
struct ApplicationSaveReceipt: Decodable { let app: ManagedApplication; let submission: ApplicationSubmission }
struct MarketSubmissionReceipt: Decodable { let appId: String; let submissionId: String; let reviewStatus: ApplicationReviewStatus }
enum PublishingValue {
    static func writeVersion(_ value: String) -> Bool { value.utf8.count == 64 && value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func identifier(_ value: String) -> Bool { CommunityValue.identifier(value) && value != "." && value != ".." }
    static func slug(_ value: String) -> Bool { value.range(of: "^[a-z][a-z0-9-]{1,49}$", options: .regularExpression) != nil }
    static func https(_ value: String) -> Bool {
        let value = value.trimmed
        guard value.utf16.count <= 2048, let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, !value.contains("\n"), !value.contains("\r") else { return false }
        return true
    }
    static func host(_ value: String) -> Bool {
        let value = value.trimmed
        return !value.isEmpty && value.utf16.count <= 253 && !value.contains("/") && !value.contains(":")
            && !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
    }
    static func iconSource(_ value: String) -> Bool {
        if https(value) { return true }
        guard value.utf16.count <= 2048, let parts = URLComponents(string: value.trimmed), parts.scheme == "cloud", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return false }
        return parts.path.range(of: "^/app-icons/[a-fA-F0-9]{16}/[a-fA-F0-9-]{36}\\.png$", options: .regularExpression) != nil
    }
}
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
