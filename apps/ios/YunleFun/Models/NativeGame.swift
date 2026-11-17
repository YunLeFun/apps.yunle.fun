import Foundation

/// The public Play catalog describes launch targets; it grants no account or room rights.
struct NativeGameCatalog: Codable, Equatable {
    let schemaVersion: Int
    let catalogVersion: String
    let generatedAt: String
    let games: [NativeGame]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw NativeGameError.invalidCatalog }
        let result = try JSONDecoder().decode(Self.self, from: data)
        try result.validate()
        return result
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw NativeGameError.unsupportedCatalog }
        guard !catalogVersion.isEmpty, catalogVersion.count <= 128, games.count <= 64,
              Self.date(generatedAt) != nil else { throw NativeGameError.invalidCatalog }
        var gameIDs = Set<String>()
        var appIDs = Set<String>()
        for game in games {
            guard gameIDs.insert(game.gameId).inserted, appIDs.insert(game.appId).inserted else {
                throw NativeGameError.invalidCatalog
            }
            try game.validate()
        }
    }

    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct NativeGame: Codable, Identifiable, Hashable {
    struct Players: Codable, Hashable {
        let min: Int
        let max: Int
        var label: String { min == max ? "\(min) 人" : "\(min)–\(max) 人" }
    }

    static let firstReleaseIDs: Set<String> = ["gomoku", "flight-chess", "paper-star"]
    let gameId: String
    let appId: String
    let name: String
    let description: String
    let iconURL: String?
    let lifecycle: String
    let launchModes: [NativeGameMode]
    let resourceManifestURL: String?
    let players: Players?
    let type: String?
    var fallbackURL: String? = nil
    var resourceVersion: String? = nil

    var id: String { gameId }
    var isPlayable: Bool { ["playable", "beta"].contains(lifecycle) }
    var availableModes: [NativeGameMode] { isPlayable ? launchModes.filter(\.available) : [] }
    var matchesFirstRelease: Bool { Self.firstReleaseIDs.contains(gameId) }
    var iconApplication: CloudApplication {
        CloudApplication(id: appId, name: name, logo: iconURL, category: "游戏")
    }

    func mode(id: String) -> NativeGameMode? { launchModes.first { $0.id == id } }

    func launchURL(for mode: NativeGameMode) throws -> URL {
        guard launchModes.contains(mode), isPlayable, mode.available else { throw NativeGameError.modeUnavailable }
        return try Self.validatedLaunchURL(mode.launchURL, gameID: gameId, modeID: mode.id)
    }

    func validate() throws {
        guard Self.validIdentifier(gameId), Self.validIdentifier(appId), !name.isEmpty, name.count <= 80,
              description.count <= 2_000, ["playable", "beta", "coming-soon", "retired"].contains(lifecycle),
              !launchModes.isEmpty, launchModes.count <= 8 else { throw NativeGameError.invalidCatalog }
        // First-release Play games have the same canonical game/app ID. A
        // mutable catalog cannot repurpose another market application's key.
        if Self.firstReleaseIDs.contains(gameId), appId != gameId { throw NativeGameError.invalidCatalog }
        if let players {
            guard players.min > 0, players.min <= players.max, players.max <= 16 else { throw NativeGameError.invalidCatalog }
        }
        if let iconURL {
            guard let url = URL(string: iconURL), Self.publicHTTPS(url) else { throw NativeGameError.invalidCatalog }
        }
        if let manifest = resourceManifestURL {
            guard let url = URL(string: manifest), Self.publicHTTPS(url),
                  url.host?.lowercased() == "play.yunle.fun",
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/native/resources/\(gameId)-v1.json",
                  url.query == nil, url.fragment == nil else { throw NativeGameError.invalidCatalog }
        }
        if let resourceVersion, resourceVersion.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) == nil {
            throw NativeGameError.invalidCatalog
        }
        if let fallbackURL {
            guard let url = URL(string: fallbackURL), Self.publicHTTPS(url), url.host?.lowercased() == "play.yunle.fun",
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.percentEncodedPath == "/games/\(gameId)", parts.query == nil, parts.fragment == nil else {
                throw NativeGameError.invalidCatalog
            }
        }
        var modes = Set<String>()
        for mode in launchModes {
            guard NativeGameMode.supportedIDs.contains(mode.id), modes.insert(mode.id).inserted,
                  !mode.title.isEmpty, mode.title.count <= 80,
                  (mode.unavailableReason?.count ?? 0) <= 240,
                  mode.orientation == nil || ["portrait", "landscape", "system"].contains(mode.orientation!)
            else { throw NativeGameError.invalidCatalog }
            _ = try Self.validatedLaunchURL(mode.launchURL, gameID: gameId, modeID: mode.id)
            if mode.id == "online", !mode.requiresLogin || !mode.requiresNetwork { throw NativeGameError.invalidCatalog }
            if !isPlayable, mode.available { throw NativeGameError.invalidCatalog }
        }
    }

    static func validatedLaunchURL(_ value: String, gameID: String, modeID: String) throws -> URL {
        guard validIdentifier(gameID), NativeGameMode.supportedIDs.contains(modeID),
              let url = URL(string: value), publicHTTPS(url), url.host?.lowercased() == "play.yunle.fun",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.percentEncodedPath == "/games/\(gameID)/\(modeID)",
              parts.query == nil, parts.fragment == nil else { throw NativeGameError.invalidLaunch }
        return url
    }

    static func publicHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
    }

    static func validIdentifier(_ value: String) -> Bool {
        value.range(of: "\\A[a-z][a-z0-9-]{0,63}\\z", options: .regularExpression) != nil
    }
}

struct NativeGameMode: Codable, Identifiable, Hashable {
    static let supportedIDs: Set<String> = ["computer", "local", "online", "tutorial", "pve"]
    let id: String
    let title: String
    let requiresLogin: Bool
    let requiresNetwork: Bool
    let launchURL: String
    let available: Bool
    let unavailableReason: String?
    let orientation: String?
}

struct NativeGameRoomIntent: Equatable, Identifiable {
    enum Role: String, CaseIterable, Identifiable { case player, spectator; var id: Self { self } }
    let inviteCode: String
    let role: Role
    var id: String { inviteCode + ":" + role.rawValue }

    init(input: String, role: Role = .player) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.scheme != nil {
            guard let parsed = Self.parse(url) else { throw NativeGameError.invalidInvitation }
            self = parsed
        } else {
            let code = value.uppercased()
            guard Self.validCode(code) else { throw NativeGameError.invalidInvitation }
            inviteCode = code
            self.role = role
        }
    }

    private init(code: String, role: Role) { inviteCode = code; self.role = role }

    static func parse(_ url: URL) -> Self? {
        guard NativeGame.publicHTTPS(url), url.host?.lowercased() == "play.yunle.fun",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil else { return nil }
        let path = parts.percentEncodedPath
        let prefix = "/room/"
        guard path.hasPrefix(prefix), Self.validCode(String(path.dropFirst(prefix.count))) else { return nil }
        let query = parts.queryItems ?? []
        guard query.count <= 1, query.allSatisfy({ $0.name == "role" && $0.value.flatMap(Role.init(rawValue:)) != nil }) else { return nil }
        return Self(code: String(path.dropFirst(prefix.count)), role: query.first?.value.flatMap(Role.init(rawValue:)) ?? .player)
    }

    var url: URL {
        var parts = URLComponents(string: "https://play.yunle.fun/room/\(inviteCode)")!
        if role == .spectator { parts.queryItems = [URLQueryItem(name: "role", value: role.rawValue)] }
        return parts.url!
    }

    private static func validCode(_ value: String) -> Bool {
        value.range(of: "\\A[A-Z0-9]{6}\\z", options: .regularExpression) != nil
    }
}

enum NativeGameError: LocalizedError {
    case invalidCatalog, unsupportedCatalog, invalidLaunch, modeUnavailable, invalidInvitation, hostUnavailable, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "暂时无法读取游戏列表，请稍后刷新。"
        case .unsupportedCatalog: return "游戏列表需要更新客户端后才能读取。"
        case .invalidLaunch: return "这个游戏入口暂不可用，请刷新后重试。"
        case .modeUnavailable: return "这个玩法暂未开放，请选择其他玩法。"
        case .invalidInvitation: return "请输入六位房间号或有效的云乐坊间邀请链接。"
        case .hostUnavailable: return "请先刷新工坊中的云乐坊间应用资料，再试一次。"
        case .http(429): return "访问有些频繁，请稍后再试。"
        case .http: return "游戏列表暂时无法更新，请稍后刷新。"
        }
    }
}
