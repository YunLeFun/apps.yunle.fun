import Foundation

struct CloudApplication: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var slug: String?
    var marketShortName: String?
    var description: String?
    var websiteUrl: String?
    var logo: String?
    var emoji: String?
    var themeColor: String?
    var category: String?
    var tags: [String]?
    var ownerLogin: String?
    var developerName: String?
    var rating: Double?
    var ratingCount: Int?
    var screenshots: [String]?
    var iconAssets: IconAssets?
    var isOfficial: Bool?
    var accessMode: String?
    var coinCost: Int?
    var requiresMembership: Bool?
    var trustedHosts: [String]?
    var audience: String?
    var isPublic: Bool?
    var accessWorkshopID: String?
    var accessOwnerID: String?
    var homeReference: String?
    var isUnavailable: Bool?
    /// Metadata provenance, never an access or host-authorization grant.
    /// Home sync carries only the selected author, never this cached URL.
    var personalMarketOwnerLogin: String?

    var homeKey: String { homeReference ?? id }

    func refreshingPublicMetadata(with candidate: Self?) -> Self {
        guard accessWorkshopID == nil && accessOwnerID == nil && personalMarketOwnerLogin == nil else { return self }
        var current = candidate ?? self
        current.homeReference = homeReference
        return current
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, slug, marketShortName, description, websiteUrl, logo, emoji
        case themeColor, category, tags, ownerLogin, developerName, rating, ratingCount
        case screenshots, iconAssets, isOfficial, accessMode, coinCost, requiresMembership, trustedHosts
        case audience, isPublic, accessWorkshopID, accessOwnerID, homeReference, isUnavailable, personalMarketOwnerLogin
    }

    struct IconAssets: Codable, Hashable {
        var appIcon: Variants?
        var mark: Variants?
        struct Variants: Codable, Hashable {
            var src: String?
            var darkSrc: String?
            var png: String?
            var webp: String?
        }
    }

    var publicKey: String { marketShortName ?? id }
    var author: String { developerName?.nilIfEmpty ?? ownerLogin?.nilIfEmpty ?? "独立开发者" }
    var summary: String { description?.nilIfEmpty ?? "在云乐坊发现并使用这个应用。" }

    var iconURL: URL? {
        iconCandidates(dark: false).first?.url
    }

    var launchURL: URL? {
        let canonical: [String: String] = [
            "web-resume": "https://resume.yunle.fun/",
            "ai-sfc": "https://ai-sfc.yunle.fun/",
            "give-me-money": "https://gmm.yunle.fun/",
        ]
        guard let raw = accessWorkshopID == nil && accessOwnerID == nil && personalMarketOwnerLogin == nil ? (canonical[marketShortName ?? slug ?? id] ?? websiteUrl) : websiteUrl,
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    var launchRestriction: String? {
        if isUnavailable == true { return "暂不可用" }
        if let accessMode, accessMode != "public" { return accessMode == "login_required" ? "需要登录" : "需要邀请" }
        if requiresMembership == true { return "会员专属" }
        if let coinCost, coinCost > 0 { return "\(coinCost) 云币" }
        return nil
    }

    var accessLabel: String? {
        if let launchRestriction { return launchRestriction }
        if accessOwnerID != nil { return "作品所有者预览" }
        if audience == "owner" { return "仅本人可见" }
        return accessWorkshopID != nil || audience == "workshop" || isPublic == false ? "限工坊坊客使用" : nil
    }
    var canOpenAsGuest: Bool { accessLabel == nil && launchURL != nil }
    var ownerPreviewRestriction: String? {
        if isUnavailable == true { return "暂不可用" }
        if requiresMembership == true || (coinCost ?? 0) > 0 { return "需要先确认会员或购买权益" }
        return nil
    }
    var runtimeScope: String {
        accessOwnerID.map { "owner:" + $0 } ?? accessWorkshopID.map { "workshop:" + $0 }
            ?? personalMarketOwnerLogin.map { "personal:" + $0.lowercased() } ?? "public"
    }
    var runtimeTrustedHosts: [String] {
        // A public personal revision has not necessarily passed market review.
        // It cannot extend the bridge/SSO host allowlist using its own metadata.
        personalMarketOwnerLogin == nil ? trustedHosts ?? [] : []
    }
    var shareURL: URL {
        if let login = personalMarketOwnerLogin, DeveloperProfile.normalizedLogin(login) == login {
            return CatalogService.productionOrigin.appendingPathComponent("developer").appendingPathComponent(login)
        }
        return accessWorkshopID.map { CatalogService.productionOrigin.appendingPathComponent("w/\($0)") }
            ?? CatalogService.productionOrigin.appendingPathComponent("app/\(publicKey)")
    }
    var canRequestWorkshopLaunch: Bool { accessWorkshopID != nil && launchRestriction == nil && launchURL != nil }


    var displayRating: Double? {
        guard let count = ratingCount, count > 0, let rating, (0...5).contains(rating) else { return nil }
        return rating
    }

    // Mirrors packages/app-core/src/utils/appBrowseCategories.ts.
    var browseCategory: String {
        let raw = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = marketShortName ?? slug ?? id
        let overrides: [String: (String, [String])] = [
            "cook": ("生活方式", ["应用"]),
            "ai-sfc": ("AI", ["应用"]),
            "char-dust": ("创意设计", ["应用"]),
            "color-dust": ("创意设计", ["应用"]),
            "pixi-painter": ("创意设计", ["应用", "工具"]),
            "birthday": ("趣味娱乐", ["应用"]),
            "go-far-away": ("生活方式", ["应用"]),
            "fc": ("游戏", ["整活"]),
        ]
        if let (label, legacy) = overrides[key], legacy.contains(raw) { return label }
        let aliases = ["工具": "效率工具", "设计": "创意设计", "生活": "生活方式", "整活": "趣味娱乐",
                       "插件": "开发", "参与": "开发", "实验": "开发"]
        if raw.isEmpty || raw == "应用" || raw == "全部" { return "其他" }
        return aliases[raw] ?? raw
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [name, summary, browseCategory, author, (tags ?? []).joined(separator: " ")]
            .contains { $0.localizedStandardContains(query) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
