import Foundation

/// A single opt-in loopback preview for local integration measurements. The
/// release application has no URL override and never trusts a preview origin.
enum NativeGameHostEnvironment {
    static let productionOrigin = URL(string: "https://play.yunle.fun/")!
    static var previewOrigin: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1" {
            return URL(string: "http://127.0.0.1:18146/")!
        }
        #endif
        return nil
    }

    static func transportURL(_ canonical: URL) -> URL {
        guard let origin = previewOrigin,
              let logical = URLComponents(url: canonical, resolvingAgainstBaseURL: false),
              logical.scheme == "https", logical.host?.lowercased() == "play.yunle.fun",
              logical.port == nil || logical.port == 443, logical.user == nil, logical.password == nil,
              var result = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return canonical }
        result.percentEncodedPath = logical.percentEncodedPath
        result.percentEncodedQuery = logical.percentEncodedQuery
        result.percentEncodedFragment = logical.percentEncodedFragment
        return result.url ?? canonical
    }

    static var previewProfileApplication: CloudApplication? {
        guard previewOrigin != nil else { return nil }
        return CloudApplication(id: "native-game-preview-18146", name: "本地游戏预览",
                                websiteUrl: "https://native-game-preview.invalid/")
    }
}
