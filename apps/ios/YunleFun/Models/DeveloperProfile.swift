import Foundation

enum DeveloperProfileError: Error, Equatable {
    case invalidLogin, notFound, throttled, unavailable, invalidResponse, restricted

    var message: String {
        switch self {
        case .invalidLogin: return "作者标识无效，请从应用菜单重新打开。"
        case .notFound: return "未找到这个作者主页。作者可能已更改标识或停止公开作品。"
        case .throttled: return "访问有些频繁，请稍后重试。"
        case .restricted: return "此作者版本需要进一步确认使用权限。请查看云乐坊版本或联系作者。"
        default: return "暂时无法读取作者主页，请检查网络后重试。"
        }
    }
}

struct DeveloperProfile: Decodable, Equatable {
    let ownerLogin: String
    let items: [CloudApplication]

    var displayName: String {
        items.compactMap { $0.developerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.first ?? ownerLogin
    }

    static func normalizedLogin(_ value: String) -> String? {
        let login = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard login != ".", login != "..", login.range(of: #"^[A-Za-z0-9_.-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return login
    }

    var shareURL: URL { CatalogService.productionOrigin.appendingPathComponent("developer").appendingPathComponent(ownerLogin) }
    var githubURL: URL { URL(string: "https://github.com")!.appendingPathComponent(ownerLogin) }

    func validated(for requestedLogin: String) throws -> Self {
        guard Self.normalizedLogin(ownerLogin) == ownerLogin,
              ownerLogin.lowercased() == requestedLogin.lowercased(), items.count <= 1000,
              Set(items.map(\.id)).count == items.count else { throw DeveloperProfileError.invalidResponse }
        for app in items {
            // The server resolves the login to a UID, then aggregates that UID's
            // public publications. Individual records may retain an old alias
            // or no login; they are not a second identity or permission proof.
            guard NativeLink.validAppKey(app.id), !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  app.audience == "public", app.isPublic == true,
                  app.accessOwnerID == nil, app.accessWorkshopID == nil, app.personalMarketOwnerLogin == nil,
                  app.isUnavailable != true,
                  app.coinCost.map({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }) ?? true else { throw DeveloperProfileError.invalidResponse }
        }
        return Self(ownerLogin: ownerLogin, items: items.map { app in
            var current = app
            current.personalMarketOwnerLogin = ownerLogin
            return current
        })
    }
}
