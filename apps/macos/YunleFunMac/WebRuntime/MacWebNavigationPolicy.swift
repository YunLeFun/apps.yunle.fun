import Foundation

/// Navigation and native authorization use separate permissions. HTTPS pages can
/// navigate in their isolated profile; only trusted main documents get SSO.
enum MacWebNavigationPolicy {
    enum Decision: Equatable { case allow, openExternally, cancel }

    static func launchURL(for application: CloudApplication) -> URL? {
        guard !application.id.isEmpty,
              application.runtimeScope == "public",
              application.audience == nil || application.audience == "public",
              application.canOpenAsGuest,
              let url = application.launchURL,
              isSecureWebURL(url) else { return nil }
        return url
    }

    static func decision(for url: URL?, isMainFrame: Bool, userInitiated: Bool,
                         allowsBlank: Bool = false) -> Decision {
        guard let url else { return .cancel }
        if isSecureWebURL(url) { return .allow }
        if url.absoluteString == "about:blank", !isMainFrame || allowsBlank { return .allow }
        if ["mailto", "tel"].contains(url.scheme?.lowercased() ?? ""), isMainFrame, userInitiated {
            return .openExternally
        }
        return .cancel
    }

    static func isSecureWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    static func origin(of url: URL?) -> String? {
        guard let url, isSecureWebURL(url), let host = url.host?.lowercased(), !host.hasSuffix(".") else { return nil }
        let port = url.port ?? 443
        guard (1...65535).contains(port) else { return nil }
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "https://\(authority)\(port == 443 ? "" : ":\(port)")"
    }

    static func sameDocumentIgnoringFragment(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second, isSecureWebURL(first), isSecureWebURL(second),
              var left = URLComponents(url: first, resolvingAgainstBaseURL: false),
              var right = URLComponents(url: second, resolvingAgainstBaseURL: false) else { return false }
        left.fragment = nil
        right.fragment = nil
        return left.url == right.url
    }

    static func isFragmentNavigation(from current: URL?, to destination: URL?, isReload: Bool) -> Bool {
        !isReload && (current?.fragment != nil || destination?.fragment != nil)
            && sameDocumentIgnoringFragment(current, destination)
    }

    static func isTrustedForAuthorization(_ url: URL, application: CloudApplication) -> Bool {
        guard origin(of: url) != nil, let host = url.host?.lowercased() else { return false }
        let domains = ["yunle.fun", "yunyoujun.cn"] + application.runtimeTrustedHosts
        return domains.contains { raw in
            let domain = raw.lowercased()
            guard !domain.isEmpty, domain == domain.trimmingCharacters(in: .whitespacesAndNewlines),
                  !domain.hasPrefix("."), !domain.hasSuffix("."),
                  domain.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 })
            else { return false }
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
