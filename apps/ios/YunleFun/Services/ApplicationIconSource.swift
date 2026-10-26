import Foundation

enum ApplicationIconRolePresentation: String, Hashable, Sendable { case appIcon, mark, legacy }
struct ApplicationIconCandidate: Hashable, Sendable {
    let url: URL
    let role: ApplicationIconRolePresentation
    var revision: String? = nil
}

enum PublicMediaURL {
    static func origin(of url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return "https://" + host
    }
    // Explicitly matches apps/mobile/app/constants/cloudbase.ts and its public media path policy.
    static let environment = "yunlefun-8g7ybcxc7345c490"
    static let bucket = "7975-yunlefun-8g7ybcxc7345c490-1325586649"
    static let origin = "https://" + bucket + ".tcb.qcloud.la"

    static func resolve(_ source: String) -> URL? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: source), parts.user == nil, parts.password == nil else { return nil }
        if parts.scheme?.lowercased() == "cloud" {
            guard parts.host == environment + "." + bucket, parts.port == nil,
                  parts.query == nil, parts.fragment == nil, isPublicPath(parts.percentEncodedPath)
            else { return nil }
            return URL(string: origin + parts.percentEncodedPath)
        }
        guard parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false else { return nil }
        var result = parts
        if parts.host == bucket + ".tcb.qcloud.la", (parts.port == nil || parts.port == 443), isPublicPath(parts.percentEncodedPath) {
            result.query = nil; result.fragment = nil
        }
        return result.url
    }

    private static func isPublicPath(_ path: String) -> Bool {
        guard let decoded = path.removingPercentEncoding, !decoded.contains("\\"), !decoded.contains("/../") else { return false }
        return decoded.range(of: #"^/avatars/[^/]+\.(?:jpe?g|png|webp)$"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            decoded.range(of: #"^/app-icons/[a-f0-9]{16}/[a-f0-9-]{36}\.png$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension CloudApplication {
    func iconCandidates(dark: Bool, downloaded: [String: CatalogIconAssets.Asset] = [:],
                        websites: [String: CatalogIconAssets.WebsiteAsset] = [:]) -> [ApplicationIconCandidate] {
        // A private/author revision can reuse a public slug without adopting its brand.
        let isPublicCatalog = accessWorkshopID == nil && accessOwnerID == nil && personalMarketOwnerLogin == nil
            && isPublic != false && (audience == nil || audience == "public")
        let slug = marketShortName ?? slug ?? id
        let live = isPublicCatalog ? downloaded[slug] : nil
        let bundled = isPublicCatalog ? CatalogIconAssets.bySlug[slug] : nil
        let curated = live ?? bundled
        var candidates: [ApplicationIconCandidate] = []
        func append(_ source: String?, role: ApplicationIconRolePresentation, revision: String? = nil) {
            guard let source else { return }
            // These exact published legacy URLs are gone. Preserve any newly supplied custom URL.
            let obsolete = ["https://play.yunle.fun/games/paper-star/icon.png", "https://smap.yunle.fun/smap-logo.svg"]
            let replacement = curated?.official != nil && obsolete.contains(source) ? curated?.official : source
            guard let replacement, let url = PublicMediaURL.resolve(replacement),
                  !candidates.contains(where: { $0.url == url }) else { return }
            candidates.append(ApplicationIconCandidate(url: url, role: role, revision: revision))
        }
        func append(_ value: IconAssets.Variants?, role: ApplicationIconRolePresentation) {
            if dark { append(value?.darkSrc, role: role) }
            append(value?.png, role: role); append(value?.webp, role: role); append(value?.src, role: role)
        }
        // A downloaded formal brand is authoritative over stale public application metadata.
        // Explicit dark artwork stays first; all original and bundled sources remain available on failure.
        if dark { append(iconAssets?.appIcon?.darkSrc, role: .appIcon) }
        append(live?.official, role: .appIcon, revision: live?.revision)
        if live?.official != nil { append(live?.thumbnail, role: .appIcon, revision: live?.revision) }
        append(iconAssets?.appIcon, role: .appIcon)
        if live == nil { append(bundled?.official, role: .appIcon) }
        append(iconAssets?.mark, role: .mark)
        append(logo, role: .legacy)
        append(live?.thumbnail, role: .appIcon, revision: live?.revision)
        append(bundled?.official, role: .appIcon)
        append(bundled?.thumbnail, role: .appIcon)
        // Website bindings are registered online, independently of public slugs.
        if let origin = PublicMediaURL.origin(of: launchURL), let asset = websites[origin] ?? CatalogIconAssets.byOrigin[origin] {
            append(asset.url, role: asset.role, revision: asset.revision)
        }
        return candidates
    }
}
