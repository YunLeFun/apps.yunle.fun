import Foundation

struct HomeAppReference: Codable, Equatable, Hashable, Sendable {
    let appId: String
}
struct HomeRecentReference: Codable, Equatable, Sendable {
    let appId: String
    let usedAt: Int64
}
/// A Home Screen folder (sync schema 2). Members stay in `installedApps`, so
/// clients without folder support still show every app; the folder sits where
/// its first member is.
struct HomeFolder: Codable, Equatable, Hashable, Sendable, Identifiable {
    static let limit = 200
    static let nameLimit = 40
    let id: String
    var name: String
    var appIds: [String]

    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines) && name.count <= nameLimit
            && !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }
}

struct HomeConfiguration: Codable, Equatable, Sendable {
    var installedApps: [HomeAppReference] = []
    var dockApps: [HomeAppReference] = []
    var recentApps: [HomeRecentReference] = []
    var updatedAt: Int64 = 0
    var folders: [HomeFolder] = []

    func hasSameContent(as other: Self, includingFolders: Bool = true) -> Bool {
        installedApps == other.installedApps && dockApps == other.dockApps && recentApps == other.recentApps
            && (!includingFolders || folders == other.folders)
    }

    /// Compares with a server copy. A schema 1 server can't store folders, so
    /// they are left out of the comparison instead of looking like a change.
    func matches(_ remote: RemoteHomeScreen) -> Bool {
        hasSameContent(as: remote.configuration, includingFolders: remote.carriesFolders)
    }

    /// Takes a server copy. From a schema 1 server the local folders are kept
    /// (minus apps that are gone) rather than wiped.
    func adopting(_ remote: RemoteHomeScreen) -> HomeConfiguration {
        guard !remote.carriesFolders else { return remote.configuration }
        var next = remote.configuration
        next.folders = folders
        return next.sanitizingFolders()
    }

    /// Drops folder members that are no longer installed, pinned to the dock or
    /// already in an earlier folder, then folders left empty.
    func sanitizingFolders() -> HomeConfiguration {
        var next = self
        let installed = Set(installedApps.map(\.appId)), docked = Set(dockApps.map(\.appId))
        var seen = Set<String>()
        next.folders = folders.compactMap { folder in
            var folder = folder
            folder.appIds = folder.appIds.filter { installed.contains($0) && !docked.contains($0) && seen.insert($0).inserted }
            return folder.appIds.isEmpty ? nil : folder
        }
        return next
    }

    func folder(containing appId: String) -> HomeFolder? { folders.first { $0.appIds.contains(appId) } }

    func validate() throws {
        let groups = [installedApps.map(\.appId), dockApps.map(\.appId), recentApps.map(\.appId)]
        guard installedApps.count <= 1000, dockApps.count <= 4, recentApps.count <= 100, updatedAt >= 0, updatedAt <= 9_007_199_254_740_991,
              recentApps.allSatisfy({ $0.usedAt >= 0 && $0.usedAt <= 9_007_199_254_740_991 }),
              groups.allSatisfy({ ids in
                  Set(ids).count == ids.count && ids.allSatisfy {
                      !$0.isEmpty && $0.utf16.count <= 256 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
                  }
              }) else { throw HomeSyncError.invalidResponse }
        let installed = Set(installedApps.map(\.appId))
        var folderIDs = Set<String>(), members = Set<String>()
        guard folders.count <= HomeFolder.limit, folders.allSatisfy({ folder in
            folder.id.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
                && folderIDs.insert(folder.id).inserted && HomeFolder.isValidName(folder.name) && !folder.appIds.isEmpty
                && folder.appIds.allSatisfy { installed.contains($0) && members.insert($0).inserted }
        }) else { throw HomeSyncError.invalidResponse }
    }
}
extension HomeConfiguration {
    enum CodingKeys: String, CodingKey { case installedApps, dockApps, recentApps, updatedAt, folders }
    /// `folders` is absent from schema 1 data and from snapshots saved before folders.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installedApps = try c.decode([HomeAppReference].self, forKey: .installedApps)
        dockApps = try c.decode([HomeAppReference].self, forKey: .dockApps)
        recentApps = try c.decode([HomeRecentReference].self, forKey: .recentApps)
        updatedAt = try c.decode(Int64.self, forKey: .updatedAt)
        folders = try c.decodeIfPresent([HomeFolder].self, forKey: .folders) ?? []
    }
}
struct RemoteHomeScreen: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let revision: String?
    let configuration: HomeConfiguration
    enum CodingKeys: String, CodingKey { case schemaVersion, revision, configuration }
    /// Schema 2 servers store folders; schema 1 responses never mention them.
    var carriesFolders: Bool { schemaVersion >= 2 }
    func validate() throws {
        guard schemaVersion == 1 || schemaVersion == 2, schemaVersion == 2 || configuration.folders.isEmpty,
              revision == nil || (revision?.count == 64 && revision?.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) == true)
        else { throw HomeSyncError.invalidResponse }
        try configuration.validate()
        if revision == nil {
            guard configuration == HomeConfiguration() else { throw HomeSyncError.invalidResponse }
        }
    }
}
extension RemoteHomeScreen {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.revision) else { throw HomeSyncError.invalidResponse }
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        configuration = try c.decode(HomeConfiguration.self, forKey: .configuration)
        try validate()
    }
}
struct HomeScreenWrite: Codable, Sendable {
    static let schemaVersion = 2
    let baseRevision: String?
    let mutationId: String
    let configuration: HomeConfiguration
    enum CodingKeys: String, CodingKey { case schemaVersion, baseRevision, mutationId, configuration }
    init(baseRevision: String?, mutationId: String, configuration: HomeConfiguration) {
        self.baseRevision = baseRevision; self.mutationId = mutationId; self.configuration = configuration
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseRevision = try c.decodeIfPresent(String.self, forKey: .baseRevision)
        mutationId = try c.decode(String.self, forKey: .mutationId)
        configuration = try c.decode(HomeConfiguration.self, forKey: .configuration)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        if let baseRevision { try container.encode(baseRevision, forKey: .baseRevision) }
        else { try container.encodeNil(forKey: .baseRevision) }
        try container.encode(mutationId, forKey: .mutationId)
        try container.encode(configuration, forKey: .configuration)
    }
}

struct HomeLibrarySnapshot: Codable, Equatable {
    var version = 2
    var configuration = HomeConfiguration()
    var cachedApplications: [CloudApplication] = []
    var base: RemoteHomeScreen?
    var mutationId = UUID().uuidString
    var hasPendingChanges = false
    var syncEnabled = true
    var autoSyncEnabled = true
    var dockVisible = false
    var legacyImportID: String?
    var lastRestoreID: String?

    var applications: [CloudApplication] { configuration.installedApps.map { application(reference: $0.appId) } }
    var dockApplications: [CloudApplication] { configuration.dockApps.map { application(reference: $0.appId) } }
    var recentApplications: [CloudApplication] { configuration.recentApps.map { application(reference: $0.appId) } }
    var recentIDs: [String] { configuration.recentApps.map(\.appId) }

    func application(reference: String) -> CloudApplication {
        let exact = cachedApplications.first { $0.id == reference }
        let market = cachedApplications.filter { $0.marketShortName == reference }
        let legacy = cachedApplications.filter { $0.slug == reference }
        var app = exact ?? (market.count == 1 ? market[0] : nil) ?? (legacy.count == 1 ? legacy[0] : nil)
            ?? CloudApplication(id: reference, name: "暂不可用的应用", isUnavailable: true)
        app.homeReference = reference
        return app
    }

    init() {}
    enum CodingKeys: String, CodingKey {
        case version, configuration, cachedApplications, base, mutationId, hasPendingChanges
        case syncEnabled, autoSyncEnabled, dockVisible, applications, recentIDs, legacyImportID, lastRestoreID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard (1...2).contains(storedVersion) else { throw HomeSyncError.invalidResponse }
        if storedVersion == 1 {
            cachedApplications = try c.decode([CloudApplication].self, forKey: .applications)
            configuration.installedApps = cachedApplications.map { HomeAppReference(appId: $0.id) }
            let oldRecent = try c.decodeIfPresent([String].self, forKey: .recentIDs) ?? []
            // Version 1 stored order but no timestamps; do not invent recency.
            configuration.recentApps = oldRecent.map { HomeRecentReference(appId: $0, usedAt: 0) }
            hasPendingChanges = !configuration.installedApps.isEmpty || !oldRecent.isEmpty
        } else {
            configuration = try c.decode(HomeConfiguration.self, forKey: .configuration)
            cachedApplications = try c.decode([CloudApplication].self, forKey: .cachedApplications)
            base = try c.decodeIfPresent(RemoteHomeScreen.self, forKey: .base)
            mutationId = try c.decode(String.self, forKey: .mutationId)
            hasPendingChanges = try c.decode(Bool.self, forKey: .hasPendingChanges)
            syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? true
            autoSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
            dockVisible = try c.decodeIfPresent(Bool.self, forKey: .dockVisible) ?? false
            legacyImportID = try c.decodeIfPresent(String.self, forKey: .legacyImportID)
            lastRestoreID = try c.decodeIfPresent(String.self, forKey: .lastRestoreID)
        }
        guard UUID(uuidString: mutationId) != nil else { throw HomeSyncError.invalidResponse }
        if let legacyImportID, legacyImportID.count != 64 || !legacyImportID.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) { throw HomeSyncError.invalidResponse }
        if let lastRestoreID, UUID(uuidString: lastRestoreID) == nil { throw HomeSyncError.invalidResponse }
        try configuration.validate()
        try base?.validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(legacyImportID, forKey: .legacyImportID)
        try c.encodeIfPresent(lastRestoreID, forKey: .lastRestoreID)
        try c.encode(configuration, forKey: .configuration)
        try c.encode(cachedApplications, forKey: .cachedApplications)
        try c.encodeIfPresent(base, forKey: .base)
        try c.encode(mutationId, forKey: .mutationId)
        try c.encode(hasPendingChanges, forKey: .hasPendingChanges)
        try c.encode(syncEnabled, forKey: .syncEnabled)
        try c.encode(autoSyncEnabled, forKey: .autoSyncEnabled)
        try c.encode(dockVisible, forKey: .dockVisible)
    }
}

enum HomeSyncError: Error, LocalizedError {
    case unauthorized, forbidden, unavailable, invalidResponse, storage, conflict(RemoteHomeScreen), identityChanged
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录状态需要更新，请重新登录后同步。"
        case .forbidden: return "当前账号暂时无法同步云居，请检查账号状态。"
        case .unavailable: return "云同步暂时无法使用，更改已保存在此设备。"
        case .invalidResponse: return "云居数据暂时无法读取，现有内容已保留。"
        case .storage: return "无法保存云居，请检查设备存储空间后重试。"
        case .conflict: return "另一台设备更新了云居，请选择要保留的版本。"
        case .identityChanged: return "账号已发生变化，请重新操作。"
        }
    }
}
