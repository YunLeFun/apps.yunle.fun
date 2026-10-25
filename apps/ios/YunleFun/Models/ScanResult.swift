import Foundation

enum ScanPurpose { case general, workshop }
enum NativeDestination: Hashable {
    case workshop(String)
    case application(String)
    case developer(String)
}
enum ScanResult: Equatable {
    case destination(NativeDestination)
    case website(URL)
    case text(String)
    case unsupportedWorkshop
    case unsupportedLink
}
struct ScanCandidate: Identifiable, Equatable {
    let id = UUID()
    let payload: String
    let result: ScanResult
    var title: String {
        switch result {
        case .destination(.workshop): return "个人工坊"
        case .destination(.application): return "云应用"
        case .destination(.developer): return "作者主页"
        case .website(let url): return url.host ?? "网址"
        case .text: return "文本"
        case .unsupportedWorkshop: return "不是工坊二维码"
        case .unsupportedLink: return "无法打开此链接"
        }
    }
}
enum NativeLink {
    static func destination(_ url: URL) -> NativeDestination? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        let path: String
        if parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "apps.yunle.fun", parts.port == nil || parts.port == 443 {
            path = parts.path
        } else if parts.scheme?.lowercased() == "yunlefun", parts.port == nil,
                  let host = parts.host?.lowercased(), host == "w" || host == "workshop" || host == "app" || host == "developer" {
            path = "/" + (host == "workshop" ? "w" : host) + parts.path
        } else { return nil }
        var segments = path.split(separator: "/", omittingEmptySubsequences: false)
        if segments.last == "" { segments.removeLast() }
        guard segments.count == 3, segments[0] == "" else { return nil }
        let key = String(segments[2])
        if segments[1] == "w", let id = WorkshopLink.normalize(key) { return .workshop(id) }
        if segments[1] == "app", validAppKey(key) { return .application(key) }
        if segments[1] == "developer", DeveloperProfile.normalizedLogin(key) == key { return .developer(key) }
        return nil
    }
    static func validAppKey(_ key: String) -> Bool {
        key.utf8.count <= 256 && key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
    static func publicApplication(key: String, in applications: [CloudApplication]) -> CloudApplication? {
        // A publisher's legacy slug is not a globally unique public identifier.
        let exact = applications.filter { $0.id == key }
        if exact.count == 1 { return exact[0] }
        let market = applications.filter { $0.marketShortName?.lowercased() == key.lowercased() }
        return market.count == 1 ? market[0] : nil
    }
}
enum ScanParser {
    static func parse(_ payload: String, purpose: ScanPurpose) -> ScanResult {
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 10_000,
              !value.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 10 && $0.value != 13 && $0.value != 9 })
        else { return .unsupportedLink }
        if purpose == .workshop {
            return WorkshopLink.parse(value).map { .destination(.workshop($0)) } ?? .unsupportedWorkshop
        }
        if let url = URL(string: value), let destination = NativeLink.destination(url) { return .destination(destination) }
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased() else { return .text(value) }
        guard scheme == "https" || scheme == "http", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, !value.contains("\n"), !value.contains("\r"),
              let url = parts.url else { return .unsupportedLink }
        // Malformed first-party routes do not fall through into a browser that
        // could run account flows or interpret different path semantics.
        if host.lowercased() == "apps.yunle.fun" { return .unsupportedLink }
        return .website(url)
    }
}
enum ScanImageError: Error, Equatable {
    case invalidImage, tooLarge, noCode
    var message: String {
        switch self {
        case .invalidImage: return "图片无法读取，请选择另一张图片。"
        case .tooLarge: return "图片过大，请裁剪二维码区域后重试。"
        case .noCode: return "未识别到二维码，请选择更清晰的图片，或裁剪二维码区域后重试。"
        }
    }
}

enum WorkshopLink {
    static func normalize(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.range(of: "^[2-9A-HJKMNP-Z]{6}$", options: .regularExpression) != nil ? value : nil
    }
    static func parse(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = normalize(value) { return id }
        guard let url = URLComponents(string: value), url.scheme?.lowercased() == "https", url.host?.lowercased() == "apps.yunle.fun",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.query == nil, url.fragment == nil else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 3 || (segments.count == 4 && segments.last == ""),
              segments[0] == "", segments[1] == "w" else { return nil }
        return normalize(String(segments[2]))
    }
}
