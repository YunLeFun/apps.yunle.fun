import Foundation
import Combine

@MainActor
final class HomeLibrary: ObservableObject {
    @Published private(set) var snapshot = HomeLibrarySnapshot()
    @Published private(set) var storageError: String?
    private(set) var fileURL: URL
    private(set) var accountID: String?
    private(set) var generation = UUID()
    private let directory: URL
    private var canWrite = true
    var onUserChange: (() -> Void)?

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
        let name = accountID.map { Data($0.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-") } ?? "guest"
        fileURL = directory.appendingPathComponent(name).appendingPathExtension("json")
        do { snapshot = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: Data(contentsOf: fileURL)) }
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
        guard !contains(app), snapshot.configuration.installedApps.count < 1000 else { return }
        edit { state in
            cache(app, in: &state)
            state.configuration.installedApps.append(HomeAppReference(appId: app.id))
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

    func recordUse(_ app: CloudApplication) {
        let reference = app.homeReference ?? (snapshot.applications + snapshot.dockApplications).first { $0.id == app.id }?.homeKey ?? app.id
        edit { state in
            cache(app, in: &state)
            state.configuration.recentApps.removeAll { $0.appId == reference }
            state.configuration.recentApps.insert(HomeRecentReference(appId: reference, usedAt: Int64(Date().timeIntervalSince1970 * 1000)), at: 0)
            state.configuration.recentApps = Array(state.configuration.recentApps.prefix(100))
        }
    }

    func clearRecent() { edit { $0.configuration.recentApps = [] } }
    func isPinned(_ app: CloudApplication) -> Bool { snapshot.configuration.dockApps.contains { $0.appId == app.homeKey } }
    func setPinned(_ app: CloudApplication, _ pinned: Bool) {
        guard !pinned || snapshot.configuration.dockApps.count < 4 else { return }
        edit { state in
            cache(app, in: &state)
            state.configuration.dockApps.removeAll { $0.appId == app.homeKey }
            if pinned { state.configuration.dockApps.append(HomeAppReference(appId: app.homeKey)) }
        }
    }

    func setSyncEnabled(_ enabled: Bool) { preference { $0.syncEnabled = enabled } }
    func setAutoSyncEnabled(_ enabled: Bool) { preference { $0.autoSyncEnabled = enabled } }
    func setDockVisible(_ visible: Bool) { preference { $0.dockVisible = visible } }

    func updateCatalog(_ applications: [CloudApplication]) {
        var next = snapshot
        for app in applications { cache(app, in: &next) }
        if next.cachedApplications != snapshot.cachedApplications { _ = persist(next) }
    }

    func adopt(_ remote: RemoteHomeScreen) throws {
        try remote.validate()
        var next = snapshot
        next.configuration = remote.configuration
        next.base = remote
        next.hasPendingChanges = false
        guard persist(next) else { throw HomeSyncError.storage }
    }

    func acknowledge(_ remote: RemoteHomeScreen, uploadedMutationId: String) throws {
        try remote.validate()
        var next = snapshot
        next.base = remote
        if next.mutationId == uploadedMutationId {
            next.configuration = remote.configuration
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

    func keepCloud(_ remote: RemoteHomeScreen) throws {
        guard canWrite else { throw HomeSyncError.storage }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString).json")
        do { try JSONEncoder().encode(snapshot).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { throw HomeSyncError.storage }
        try adopt(remote)
    }

    private func edit(_ update: (inout HomeLibrarySnapshot) -> Void) {
        var next = snapshot
        update(&next)
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
    private func cache(_ app: CloudApplication, in state: inout HomeLibrarySnapshot) {
        guard app.isUnavailable != true else { return }
        var app = app
        app.homeReference = nil
        if let index = state.cachedApplications.firstIndex(where: { $0.id == app.id }) {
            // Public discovery uses the approved market revision. It must not
            // replace a saved workshop edition or erase its revalidation scope.
            guard (state.cachedApplications[index].accessWorkshopID == nil && state.cachedApplications[index].accessOwnerID == nil)
                || app.accessWorkshopID != nil || app.accessOwnerID != nil else { return }
            state.cachedApplications[index] = app
        }
        else { state.cachedApplications.append(app) }
    }
    @discardableResult private func persist(_ proposed: HomeLibrarySnapshot) -> Bool {
        guard canWrite else { return false }
        do {
            try proposed.configuration.validate()
            let data = try JSONEncoder().encode(proposed)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            snapshot = proposed
            storageError = nil
            return true
        } catch {
            storageError = "这次更改未能保存，请检查设备存储空间后重试。"
            return false
        }
    }
}
