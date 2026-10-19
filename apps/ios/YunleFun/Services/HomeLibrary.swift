import Foundation
import Combine
import CryptoKit

@MainActor
final class HomeLibrary: ObservableObject {
    @Published private(set) var snapshot = HomeLibrarySnapshot()
    @Published private(set) var storageError: String?
    private(set) var fileURL: URL
    private(set) var accountID: String?
    private(set) var generation = UUID()
    private let directory: URL
    private var canWrite = true
    private var pendingMigrationBackup: Data?
    var onUserChange: (() -> Void)?
    var needsRecovery: Bool { !canWrite }
    var restoreBaseline: HomeRestoreBaseline { HomeRestoreBaseline(snapshot, needsRecovery: needsRecovery) }

    init(directory: URL? = nil, accountID: String? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeLibrary", isDirectory: true)
        fileURL = self.directory.appendingPathComponent("guest.json")
        activateAccount(accountID)
    }

    func activateAccount(_ accountID: String?) {
        self.accountID = accountID
        generation = UUID()
        snapshot = HomeLibrarySnapshot()
        storageError = nil
        canWrite = true
        pendingMigrationBackup = nil
        let name = accountID.map { Data($0.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-") } ?? "guest"
        fileURL = directory.appendingPathComponent(name).appendingPathExtension("json")
        do {
            let data = try Data(contentsOf: fileURL)
            snapshot = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
            struct Version: Decodable { let version: Int? }
            if (try JSONDecoder().decode(Version.self, from: data).version ?? 1) < 3 { pendingMigrationBackup = data }
        }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
        catch {
            canWrite = false
            storageError = "无法读取云居，原有数据已保留。请稍后重试。"
        }
    }

    func contains(_ app: CloudApplication) -> Bool {
        (snapshot.applications + snapshot.dockApplications).contains { $0.id == app.id || $0.homeKey == app.homeKey }
    }

    func add(_ app: CloudApplication) {
        let alreadyInstalled = contains(app)
        guard alreadyInstalled || snapshot.configuration.installedApps.count < 1000 else { return }
        edit { state in
            if !alreadyInstalled { state.configuration.installedApps.append(HomeAppReference(appId: app.id)) }
            selectSource(app, in: &state)
            cache(app, in: &state)
        }
    }

    func remove(_ app: CloudApplication) {
        let references = Set(app.homeReference.map { [$0] } ??
                             (snapshot.applications + snapshot.dockApplications).filter { $0.id == app.id }.map(\.homeKey))
        edit {
            $0.configuration.installedApps.removeAll { references.contains($0.appId) }
            $0.configuration.dockApps.removeAll { references.contains($0.appId) }
            $0.configuration.recentApps.removeAll { references.contains($0.appId) }
        }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        guard offsets.allSatisfy({ snapshot.configuration.installedApps.indices.contains($0) }),
              (0...snapshot.configuration.installedApps.count).contains(destination) else { return }
        edit { state in
            let moving = offsets.sorted().map { state.configuration.installedApps[$0] }
            let insertion = destination - offsets.filter { $0 < destination }.count
            for offset in offsets.sorted(by: >) { state.configuration.installedApps.remove(at: offset) }
            state.configuration.installedApps.insert(contentsOf: moving, at: insertion)
        }
    }

    /// Applies a reordered subset of installed (or dock) references in one write.
    /// The given keys take the slots they already occupy, so references the
    /// caller did not show — pinned apps hidden from 我的应用 — keep their place.
    /// Unknown or duplicate keys are ignored; an unchanged order writes nothing.
    func reorder(_ keys: [String], inDock: Bool) {
        edit { state in
            var references = inDock ? state.configuration.dockApps : state.configuration.installedApps
            let present = Set(references.map(\.appId))
            var seen = Set<String>()
            let ordered = keys.filter { present.contains($0) && seen.insert($0).inserted }
            let slots = references.indices.filter { seen.contains(references[$0].appId) }
            guard slots.count == ordered.count else { return }
            var byKey: [String: HomeAppReference] = [:]
            for slot in slots { byKey[references[slot].appId] = references[slot] }
            for (slot, key) in zip(slots, ordered) { if let reference = byKey[key] { references[slot] = reference } }
            if inDock { state.configuration.dockApps = references } else { state.configuration.installedApps = references }
        }
    }

    func recordUse(_ app: CloudApplication) {
        let reference = app.homeReference ?? (snapshot.applications + snapshot.dockApplications).first { $0.id == app.id }?.homeKey ?? app.id
        edit { state in
            state.configuration.recentApps.removeAll { $0.appId == reference }
            state.configuration.recentApps.insert(HomeRecentReference(appId: reference, usedAt: Int64(Date().timeIntervalSince1970 * 1000)), at: 0)
            state.configuration.recentApps = Array(state.configuration.recentApps.prefix(100))
            selectSource(app, in: &state)
            cache(app, in: &state)
        }
    }

    func clearRecent() { edit { $0.configuration.recentApps = [] } }
    func isPinned(_ app: CloudApplication) -> Bool { snapshot.configuration.dockApps.contains { $0.appId == app.homeKey } }
    func setPinned(_ app: CloudApplication, _ pinned: Bool) {
        guard !pinned || snapshot.configuration.dockApps.count < 4 else { return }
        edit { state in
            state.configuration.dockApps.removeAll { $0.appId == app.homeKey }
            if pinned {
                state.configuration.dockApps.append(HomeAppReference(appId: app.homeKey))
                selectSource(app, in: &state)
            }
            cache(app, in: &state)
        }
    }

    /// Pins or unpins several apps in one write (one sync). Pinning fails as a
    /// whole, changing nothing, when the dock can't take every app.
    @discardableResult
    func setPinned(_ apps: [CloudApplication], _ pinned: Bool) -> Bool {
        let keys = apps.map(\.homeKey)
        let docked = Set(snapshot.configuration.dockApps.map(\.appId))
        var seen = Set<String>()
        let adding = keys.filter { !docked.contains($0) && seen.insert($0).inserted }
        if pinned { guard snapshot.configuration.dockApps.count + adding.count <= 4 else { return false } }
        edit { state in
            if pinned {
                state.configuration.dockApps.append(contentsOf: adding.map(HomeAppReference.init))
                for app in apps { selectSource(app, in: &state); cache(app, in: &state) }
            } else {
                state.configuration.dockApps.removeAll { keys.contains($0.appId) }
            }
        }
        return true
    }

    // MARK: Folders

    /// Grid key for a folder tile; app tiles use the app's home key.
    nonisolated static func folderKey(_ id: String) -> String { "folder:\(id)" }

    /// Makes a folder from `keys` (in order) where `anchor` sits, as when one
    /// icon is dropped on another. Members leave any folder they were in.
    @discardableResult
    func createFolder(named name: String, with keys: [String], at anchor: String) -> String? {
        let installed = Set(snapshot.configuration.installedApps.map(\.appId))
        let members = keys.reduce(into: [String]()) { if installed.contains($1) && !$0.contains($1) { $0.append($1) } }
        guard !members.isEmpty, snapshot.configuration.folders.count < HomeFolder.limit else { return nil }
        let id = UUID().uuidString.lowercased()
        let name = Self.folderName(name)
        edit { state in
            for index in state.configuration.folders.indices {
                state.configuration.folders[index].appIds.removeAll { members.contains($0) }
            }
            state.configuration.dockApps.removeAll { members.contains($0.appId) }
            state.configuration.installedApps = Self.gathering(members, at: anchor, in: state.configuration.installedApps)
            state.configuration.folders.append(HomeFolder(id: id, name: name, appIds: members))
        }
        return snapshot.configuration.folders.contains { $0.id == id } ? id : nil
    }

    /// Adds apps to the end of a folder, moving them next to its members.
    func addToFolder(_ id: String, keys: [String]) {
        guard let folder = snapshot.configuration.folders.first(where: { $0.id == id }) else { return }
        let adding = keys.filter { !folder.appIds.contains($0) }
        guard !adding.isEmpty, let last = folder.appIds.last else { return }
        edit { state in
            for index in state.configuration.folders.indices where state.configuration.folders[index].id != id {
                state.configuration.folders[index].appIds.removeAll { adding.contains($0) }
            }
            state.configuration.dockApps.removeAll { adding.contains($0.appId) }
            state.configuration.installedApps = Self.gathering(folder.appIds + adding, at: last, in: state.configuration.installedApps)
            if let index = state.configuration.folders.firstIndex(where: { $0.id == id }) {
                state.configuration.folders[index].appIds += adding
            }
        }
    }

    /// Takes an app out of its folder; it lands right after the folder.
    func removeFromFolder(_ key: String) {
        guard let folder = snapshot.configuration.folder(containing: key) else { return }
        edit { state in
            guard let index = state.configuration.folders.firstIndex(where: { $0.id == folder.id }) else { return }
            state.configuration.folders[index].appIds.removeAll { $0 == key }
            let rest = state.configuration.folders[index].appIds
            var apps = state.configuration.installedApps
            guard let from = apps.firstIndex(where: { $0.appId == key }) else { return }
            let moving = apps.remove(at: from)
            let after = apps.lastIndex { rest.contains($0.appId) }.map { $0 + 1 } ?? from
            apps.insert(moving, at: min(after, apps.count))
            state.configuration.installedApps = apps
        }
    }

    func renameFolder(_ id: String, to name: String) {
        edit { state in
            if let index = state.configuration.folders.firstIndex(where: { $0.id == id }) {
                state.configuration.folders[index].name = Self.folderName(name)
            }
        }
    }

    /// Removes the folder; its apps stay on the Home Screen where they were.
    func dissolveFolder(_ id: String) {
        edit { $0.configuration.folders.removeAll { $0.id == id } }
    }

    func reorderFolder(_ id: String, appIds: [String]) {
        guard let folder = snapshot.configuration.folders.first(where: { $0.id == id }),
              Set(appIds) == Set(folder.appIds), appIds.count == folder.appIds.count else { return }
        edit { state in
            if let index = state.configuration.folders.firstIndex(where: { $0.id == id }) {
                state.configuration.folders[index].appIds = appIds
            }
            if let first = folder.appIds.first {
                state.configuration.installedApps = Self.gathering(appIds, at: first, in: state.configuration.installedApps)
            }
        }
    }

    /// Reorders grid items where folders appear as `folderKey(id)`: each folder
    /// expands to its members, kept together, in one write.
    func reorderItems(_ itemKeys: [String]) {
        let folders = Dictionary(snapshot.configuration.folders.map { (Self.folderKey($0.id), $0.appIds) },
                                 uniquingKeysWith: { first, _ in first })
        reorder(itemKeys.flatMap { folders[$0] ?? [$0] }, inDock: false)
    }

    /// A trimmed, length-limited name; blank becomes the generic "文件夹".
    static func folderName(_ name: String) -> String {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "文件夹" : String(cleaned.prefix(HomeFolder.nameLimit))
    }

    /// Moves `members` together, in order, to where `anchor` currently is.
    private static func gathering(_ members: [String], at anchor: String, in apps: [HomeAppReference]) -> [HomeAppReference] {
        guard let anchorIndex = apps.firstIndex(where: { $0.appId == anchor }) else { return apps }
        let set = Set(members)
        let before = apps[..<anchorIndex].filter { !set.contains($0.appId) }.count
        var rest = apps.filter { !set.contains($0.appId) }
        let moving = members.compactMap { key in apps.first { $0.appId == key } }
        rest.insert(contentsOf: moving, at: min(before, rest.count))
        return rest
    }

    func setSyncEnabled(_ enabled: Bool) { preference { $0.syncEnabled = enabled } }
    func setAutoSyncEnabled(_ enabled: Bool) { preference { $0.autoSyncEnabled = enabled } }
    func setDockVisible(_ visible: Bool) { preference { $0.dockVisible = visible } }

    func updateCatalog(_ applications: [CloudApplication]) {
        var next = snapshot
        for app in applications { cache(app, in: &next, preservingSavedSource: true) }
        if next.cachedApplications != snapshot.cachedApplications { _ = persist(next) }
    }

    func adopt(_ remote: RemoteHomeScreen) throws {
        try remote.validate()
        var next = snapshot
        next.configuration = snapshot.configuration.adopting(remote)
        next.base = remote
        next.hasPendingChanges = !remote.carriesSources && (!next.configuration.applicationSources.isEmpty || snapshot.hasPendingChanges)
        if next.hasPendingChanges && !next.configuration.hasSameContent(as: snapshot.configuration) {
            // A legacy cloud choice can preserve local sources while changing
            // the pending payload. Never reuse its previous retry identity.
            next.mutationId = UUID().uuidString
        }
        guard persist(next) else { throw HomeSyncError.storage }
    }

    func acknowledge(_ remote: RemoteHomeScreen, uploadedMutationId: String) throws {
        try remote.validate()
        guard remote.carriesSources else { throw HomeSyncError.unsupportedSchema }
        var next = snapshot
        next.base = remote
        if next.mutationId == uploadedMutationId {
            next.configuration = snapshot.configuration.adopting(remote)
            next.hasPendingChanges = false
        }
        guard persist(next) else { throw HomeSyncError.storage }
    }

    func keepDevice(using remote: RemoteHomeScreen) throws {
        try remote.validate()
        var next = snapshot
        next.base = remote
        next.hasPendingChanges = true
        next.mutationId = UUID().uuidString
        guard persist(next) else { throw HomeSyncError.storage }
    }

    /// Forgets the cloud copy this device last matched and keeps the layout as
    /// an unsynced change, so a different cloud (another iCloud account) is
    /// compared with it instead of replacing it.
    func detachCloudBase() throws {
        guard snapshot.base != nil || !snapshot.hasPendingChanges else { return }
        var next = snapshot
        next.base = nil
        next.hasPendingChanges = true
        next.mutationId = UUID().uuidString
        guard persist(next) else { throw HomeSyncError.storage }
    }

    func keepCloud(_ remote: RemoteHomeScreen) throws {
        guard canWrite else { throw HomeSyncError.storage }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
        do { try JSONEncoder().encode(snapshot).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { throw HomeSyncError.storage }
        try adopt(remote)
    }

    func importLegacy(_ record: LegacyLocalData, expectedGeneration: UUID) throws {
        guard generation == expectedGeneration else { throw LegacyImportError.identityChanged }
        guard canWrite else { throw LegacyImportError.storage }
        guard snapshot.legacyImportID != record.id else { return }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("before-legacy-\(record.id).json")
        do {
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen])
            } else { _ = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: backup)) }
        } catch { throw LegacyImportError.storage }
        var next = snapshot
        if let configuration = record.configuration, configuration != next.configuration {
            next.configuration = configuration; next.hasPendingChanges = true; next.mutationId = UUID().uuidString
        }
        next.syncEnabled = record.syncEnabled ?? next.syncEnabled
        next.autoSyncEnabled = record.autoSyncEnabled ?? next.autoSyncEnabled
        next.dockVisible = record.dockVisible ?? next.dockVisible
        next.legacyImportID = record.id
        guard persist(next) else { throw LegacyImportError.storage }
        onUserChange?()
    }

    func restoreBackup(_ candidate: HomeLibrarySnapshot, confirmation: HomeBackupRestoreConfirmation) throws {
        guard accountID == confirmation.boundary.accountID else { throw HomeBackupError.identityChanged }
        if snapshot.lastRestoreID == confirmation.id.uuidString { return }
        guard generation == confirmation.boundary.libraryGeneration else { throw HomeBackupError.identityChanged }
        guard confirmation.baseline.matches(snapshot, includingSettings: confirmation.restoreSettings),
              confirmation.baseline.needsRecovery == needsRecovery else { throw HomeBackupError.currentChanged }
        do { try candidate.configuration.validate() } catch { throw HomeBackupError.unreadable }
        try preserveBeforeRestore(confirmation)
        var next = snapshot
        next.configuration = candidate.configuration
        let currentCache = snapshot.cachedApplications
        next.cachedApplications = candidate.cachedApplications
        for app in currentCache { cache(app, in: &next, preservingSavedSource: true) }
        if confirmation.restoreSettings {
            next.syncEnabled = candidate.syncEnabled; next.autoSyncEnabled = candidate.autoSyncEnabled; next.dockVisible = candidate.dockVisible
        }
        next.legacyImportID = snapshot.legacyImportID ?? candidate.legacyImportID
        next.mutationId = UUID().uuidString; next.hasPendingChanges = true
        next.lastRestoreID = confirmation.id.uuidString
        guard persist(next, allowRecovery: true) else { throw HomeBackupError.storage }
        generation = UUID()
        onUserChange?()
    }

    private func preserveBeforeRestore(_ confirmation: HomeBackupRestoreConfirmation) throws {
        let suffix = (needsRecovery ? "before-repair-" : "before-restore-") + confirmation.id.uuidString
        let backup = fileURL.deletingPathExtension().appendingPathExtension(suffix).appendingPathExtension(needsRecovery ? "bin" : "json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if needsRecovery {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw HomeBackupError.storage }
                if FileManager.default.fileExists(atPath: backup.path) {
                    guard FileManager.default.contentsEqual(atPath: fileURL.path, andPath: backup.path) else { throw HomeBackupError.currentChanged }
                } else {
                    try FileManager.default.copyItem(at: fileURL, to: backup)
                }
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: backup.path)
            } else {
                var data: Data
                do {
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= HomeBackupRepository.maximumBytes else { throw HomeBackupError.storage }
                    data = try Data(contentsOf: fileURL)
                    let disk = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
                    guard restoreBaseline.matchesDiskContent(disk) else { throw HomeBackupError.currentChanged }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; data = try encoder.encode(snapshot)
                }
                if FileManager.default.fileExists(atPath: backup.path) {
                    guard try Data(contentsOf: backup) == data else { throw HomeBackupError.currentChanged }
                } else { try data.write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen]) }
            }
        } catch let error as HomeBackupError { throw error }
        catch { throw HomeBackupError.storage }
    }

    private func edit(_ update: (inout HomeLibrarySnapshot) -> Void) {
        var next = snapshot
        update(&next)
        // Removing or pinning an app takes it out of its folder; a folder left
        // empty disappears, as on the Home Screen.
        next.configuration = next.configuration.sanitizingFolders()
        guard next.configuration != snapshot.configuration else { return }
        next.hasPendingChanges = true
        next.mutationId = UUID().uuidString
        if persist(next) { onUserChange?() }
    }
    private func preference(_ update: (inout HomeLibrarySnapshot) -> Void) {
        var next = snapshot
        update(&next)
        if persist(next) { onUserChange?() }
    }
    private func selectSource(_ app: CloudApplication, in state: inout HomeLibrarySnapshot) {
        guard app.isUnavailable != true else { return }
        let references = Set(state.configuration.installedApps.map(\.appId) + state.configuration.dockApps.map(\.appId) + state.configuration.recentApps.map(\.appId))
        let selected = references.filter { $0 == app.id || $0 == app.homeKey || state.cachedApplication(reference: $0)?.id == app.id }
        state.configuration.applicationSources.removeAll { selected.contains($0.appId) }
        if let login = app.personalMarketOwnerLogin {
            // Validation in persist rejects malformed author identifiers without
            // writing any of the proposed selection or cache changes.
            state.configuration.applicationSources += selected.map { HomeApplicationSource(appId: $0, ownerLogin: login) }
        }
    }
    private func cache(_ app: CloudApplication, in state: inout HomeLibrarySnapshot, preservingSavedSource: Bool = false) {
        guard app.isUnavailable != true else { return }
        var app = app
        app.homeReference = nil
        if let index = state.cachedApplications.firstIndex(where: { $0.id == app.id }) {
            // Passive metadata merges must not erase the source needed for
            // the next launch. Explicit use or installation selects its source.
            if preservingSavedSource {
                let selected = state.configuration.applicationSources.first {
                    $0.appId == app.id || state.cachedApplication(reference: $0.appId)?.id == app.id
                }
                if let selected {
                    guard app.personalMarketOwnerLogin?.lowercased() == selected.ownerLogin.lowercased(),
                          app.accessWorkshopID == nil, app.accessOwnerID == nil else { return }
                } else if app.personalMarketOwnerLogin != nil {
                    return
                }
                guard (state.cachedApplications[index].accessWorkshopID == nil && state.cachedApplications[index].accessOwnerID == nil
                       && (state.cachedApplications[index].personalMarketOwnerLogin == nil || selected == nil))
                    || app.accessWorkshopID != nil || app.accessOwnerID != nil || app.personalMarketOwnerLogin != nil else { return }
            }
            state.cachedApplications[index] = app
        }
        else { state.cachedApplications.append(app) }
    }
    @discardableResult private func persist(_ proposed: HomeLibrarySnapshot, allowRecovery: Bool = false) -> Bool {
        guard canWrite || allowRecovery else { return false }
        do {
            try proposed.configuration.validate()
            let data = try JSONEncoder().encode(proposed)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let original = pendingMigrationBackup {
                guard try Data(contentsOf: fileURL) == original else { throw HomeSyncError.storage }
                let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
                let backup = fileURL.deletingPathExtension().appendingPathExtension("before-native-migration-" + digest).appendingPathExtension("json")
                if FileManager.default.fileExists(atPath: backup.path) {
                    guard try Data(contentsOf: backup) == original else { throw HomeSyncError.storage }
                } else { try original.write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen]) }
            }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            snapshot = proposed
            pendingMigrationBackup = nil
            canWrite = true
            storageError = nil
            return true
        } catch {
            storageError = "这次更改未能保存，请检查设备存储空间后重试。"
            return false
        }
    }
}
