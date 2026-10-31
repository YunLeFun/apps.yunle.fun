import Foundation

/// The only page-originated data retained by the game host. This channel
/// carries presentation state, never credentials or authority over a room.
struct NativeGameLifecycleEvent: Decodable, Equatable {
    enum State: String, Decodable {
        case ready, failed, connecting
        case roomReady = "room-ready"
        case roomState = "room-state"
        case roomLeft = "room-left"
    }
    struct Room: Decodable, Equatable {
        let inviteCode: String
        let role: String
        let state: String?
        let gameId: String?
    }
    let schemaVersion: Int
    let launchId: String
    let gameId: String
    let modeId: String
    let state: State
    let room: Room?
    let elapsedMilliseconds: Double?

    static func parse(_ body: [String: Any], source: URL, launchID: UUID,
                      gameID: String, modeID: String, expectedOrigin: URL = NativeGameHostEnvironment.productionOrigin) -> Self? {
        guard let parts = URLComponents(url: source, resolvingAgainstBaseURL: false),
              sourceMatches(source, expectedOrigin: expectedOrigin), parts.user == nil, parts.password == nil,
              JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 8192,
              let event = try? JSONDecoder().decode(Self.self, from: data),
              event.schemaVersion == 1, UUID(uuidString: event.launchId) == launchID,
              event.gameId == gameID, event.modeId == modeID else { return nil }
        if let milliseconds = event.elapsedMilliseconds {
            guard milliseconds.isFinite, milliseconds >= 0, milliseconds <= 24 * 60 * 60 * 1000 else { return nil }
        }
        if let room = event.room {
            guard room.inviteCode.range(of: #"\A[A-Z0-9]{6}\z"#, options: .regularExpression) != nil,
                  ["player", "spectator"].contains(room.role),
                  room.state.map({ $0.utf8.count <= 64 && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }) ?? true else { return nil }
            if let game = room.gameId, !NativeGame.validIdentifier(game) { return nil }
        }
        return event
    }

    private static func sourceMatches(_ source: URL, expectedOrigin: URL) -> Bool {
        guard source.scheme == expectedOrigin.scheme, source.host?.lowercased() == expectedOrigin.host?.lowercased(),
              (source.port ?? (source.scheme == "https" ? 443 : 80)) == (expectedOrigin.port ?? (expectedOrigin.scheme == "https" ? 443 : 80)) else { return false }
        if expectedOrigin == NativeGameHostEnvironment.productionOrigin { return true }
        #if DEBUG
        return expectedOrigin == NativeGameHostEnvironment.previewOrigin
        #else
        return false
        #endif
    }
}

struct NativeGameSessionStatus: Equatable {
    let gameID: String
    let modeID: String
    let launchID: UUID
    let startedAt: TimeInterval
    var phase: NativeGameLifecycleEvent.State?
    var readyMilliseconds: Double?
    var roomReadyMilliseconds: Double?
    var recordedGameID: String?
    var room: NativeGameLifecycleEvent.Room?
}

enum NativeGameLaunchURL {
    /// Public links never export a host operation or a one-time login return.
    static func publicURL(_ source: URL) -> URL? {
        guard let parts = URLComponents(url: source, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        var trusted = parts.scheme == "https" && parts.host?.lowercased() == "play.yunle.fun"
            && (parts.port == nil || parts.port == 443)
        #if DEBUG
        trusted = trusted || (NativeGameHostEnvironment.previewOrigin != nil
            && parts.scheme == "http" && parts.host == "127.0.0.1" && parts.port == 18146)
        #endif
        guard trusted else { return nil }
        let room = parts.path.range(of: #"\A/room/[A-Z0-9]{6}\z"#, options: .regularExpression) != nil
        let game = parts.path.range(of: #"\A/games/[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)?\z"#, options: .regularExpression) != nil
        guard room || game else { return nil }
        var result = URLComponents()
        result.scheme = "https"; result.host = "play.yunle.fun"; result.path = parts.path
        if room, parts.queryItems?.contains(URLQueryItem(name: "role", value: "spectator")) == true {
            result.queryItems = [URLQueryItem(name: "role", value: "spectator")]
        }
        return result.url
    }

    static func addingContext(to url: URL, launchID: UUID, gameID: String, modeID: String) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.lowercased() == "play.yunle.fun",
              parts.port == nil || parts.port == 443, parts.user == nil, parts.password == nil,
              parts.fragment == nil,
              gameID.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil,
              modeID.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil else { return nil }
        let reserved = Set(["ylfLaunchId", "ylfGameId", "ylfMode"])
        guard !(parts.queryItems ?? []).contains(where: { reserved.contains($0.name) }) else { return nil }
        parts.queryItems = (parts.queryItems ?? []) + [
            URLQueryItem(name: "ylfLaunchId", value: launchID.uuidString),
            URLQueryItem(name: "ylfGameId", value: gameID),
            URLQueryItem(name: "ylfMode", value: modeID),
        ]
        return parts.url
    }
}
