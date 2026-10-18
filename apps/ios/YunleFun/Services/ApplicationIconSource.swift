import Foundation

enum ApplicationIconRolePresentation: String, Hashable, Sendable { case appIcon, mark, legacy }
struct ApplicationIconCandidate: Hashable, Sendable {
    let url: URL
    let role: ApplicationIconRolePresentation
}

enum PublicMediaURL {
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
    func iconCandidates(dark: Bool) -> [ApplicationIconCandidate] {
        var candidates: [ApplicationIconCandidate] = []
        func append(_ source: String?, role: ApplicationIconRolePresentation) {
            guard let source, let url = PublicMediaURL.resolve(source),
                  !candidates.contains(where: { $0.url == url }) else { return }
            candidates.append(ApplicationIconCandidate(url: url, role: role))
        }
        func append(_ value: IconAssets.Variants?, role: ApplicationIconRolePresentation) {
            if dark { append(value?.darkSrc, role: role) }
            append(value?.png, role: role); append(value?.webp, role: role); append(value?.src, role: role)
        }
        append(iconAssets?.appIcon, role: .appIcon)
        append(iconAssets?.mark, role: .mark)
        append(logo, role: .legacy)
        return candidates
    }
}
