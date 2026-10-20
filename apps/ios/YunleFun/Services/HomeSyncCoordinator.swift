import Combine
import Foundation
import Network

@MainActor
protocol AccountAuthorizing: AnyObject {
    var user: AccountUser? { get }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount
}
extension AccountStore: AccountAuthorizing {}

struct HomeSyncConflict: Equatable, Identifiable {
    let id = UUID()
    let remote: RemoteHomeScreen
    let localMutationId: String
    /// nil for the guest Home Screen synced through iCloud.
    let accountID: String?
    let generation: UUID
}

@MainActor
final class HomeSyncCoordinator: ObservableObject {
    enum Phase: Equatable { case idle, syncing, failed(String), conflict(HomeSyncConflict) }
    @Published private(set) var phase = Phase.idle
    private let accounts: AccountAuthorizing
    private let library: HomeLibrary
    private let service: HomeSyncServing
    private let iCloud: HomeICloudSync?
    private let monitor: NWPathMonitor?
    private var operation: Task<Void, Never>?
    private var scheduled: Task<Void, Never>?
    private var flightID: UUID?
    private var repeatRequested = false
    private var observedLibraryGeneration: UUID

    init(accounts: AccountAuthorizing, library: HomeLibrary, service: HomeSyncServing = HomeSyncService(),
         iCloud: HomeICloudSync? = nil, monitorNetwork: Bool = true) {
        self.accounts = accounts
        self.library = library
        self.service = service
        self.iCloud = iCloud
        observedLibraryGeneration = library.generation
        monitor = monitorNetwork ? NWPathMonitor() : nil
        library.onUserChange = { [weak self] in
            guard let self else { return }
            if self.observedLibraryGeneration != self.library.generation { self.identityChanged() }
            else { self.schedule() }
        }
        iCloud?.onExternalChange = { [weak self] in self?.schedule() }
        monitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.schedule() } }
        }
        monitor?.start(queue: DispatchQueue(label: "fun.yunle.apps.home-network"))
    }
    deinit { monitor?.cancel(); operation?.cancel(); scheduled?.cancel() }

    var isSyncing: Bool { phase == .syncing }
    /// Guests can sync their Home Screen through iCloud on this build.
    var supportsICloud: Bool { iCloud != nil }
    var iCloudEnabled: Bool { iCloud?.isEnabled == true }
    /// Whether the visible Home Screen currently syncs, by account or by iCloud.
    var isActive: Bool {
        guard library.snapshot.syncEnabled else { return false }
        if let user = accounts.user { return user.id == library.accountID }
        return library.accountID == nil && iCloudEnabled
    }
    func setICloudEnabled(_ enabled: Bool) {
        guard let iCloud, iCloud.isEnabled != enabled else { return }
        objectWillChange.send()
        iCloud.isEnabled = enabled
        if enabled && !library.snapshot.syncEnabled { library.setSyncEnabled(true) }
        if case .conflict = phase { phase = .idle }
        schedule()
    }
    var message: String {
        if accounts.user == nil {
            guard supportsICloud else { return "登录后可同步云居" }
            guard isActive else { return "iCloud 同步已关闭" }
        }
        if !library.snapshot.syncEnabled { return "云同步已关闭" }
        switch phase {
        case .syncing: return "正在同步云居"
        case .failed(let message): return message
        case .conflict: return "另一台设备更新了云居"
        case .idle:
            if library.snapshot.hasPendingChanges { return "更改已保存，等待同步" }
            return library.snapshot.base == nil ? "尚未同步" : "云居已是最新"
        }
    }
    func identityChanged() {
        observedLibraryGeneration = library.generation
        scheduled?.cancel()
        operation?.cancel()
        scheduled = nil
        operation = nil
        flightID = nil
        repeatRequested = false
        phase = .idle
        schedule()
    }
    func schedule() {
        scheduled?.cancel()
        guard isActive else {
            operation?.cancel()
            operation = nil
            flightID = nil
            phase = .idle
            return
        }
        guard library.snapshot.autoSyncEnabled else { return }
        if case .conflict = phase { return }
        if operation != nil { repeatRequested = true; return }
        scheduled = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            await self?.synchronize()
        }
    }
    func synchronize() async {
        guard isActive else { return }
        let uid = accounts.user?.id
        if let operation { await operation.value; return }
        if case .conflict = phase { return }
        guard library.storageError == nil else { phase = .failed(HomeSyncError.storage.localizedDescription); return }
        if uid == nil, let iCloud {
            guard iCloud.isAvailable else { phase = .failed(HomeSyncError.iCloudUnavailable.localizedDescription); return }
            if iCloud.consumeIdentityChange() {
                do { try library.detachCloudBase() }
                catch { phase = .failed(message(for: error)); return }
            }
        }
        let generation = library.generation
        let flight = UUID()
        flightID = flight
        phase = .syncing
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.run(uid: uid, generation: generation)
        }
        operation = task
        await task.value
        guard flightID == flight else { return }
        operation = nil
        flightID = nil
        if repeatRequested { repeatRequested = false; schedule() }
    }

    func recheck() async {
        if case .conflict = phase { phase = .idle }
        await synchronize()
    }

    enum Resolution { case device, cloud }
    func resolve(_ choice: Resolution, conflict: HomeSyncConflict) async {
        guard case .conflict(let visible) = phase, visible.id == conflict.id,
              isCurrent(uid: conflict.accountID, generation: conflict.generation) else { return }
        // A form elsewhere may have added an app since the comparison opened.
        guard library.snapshot.mutationId == conflict.localMutationId else {
            showConflict(conflict.remote, uid: conflict.accountID, generation: conflict.generation)
            return
        }
        do {
            if choice == .device { try library.keepDevice(using: conflict.remote) }
            else { try library.keepCloud(conflict.remote) }
            phase = .idle
            if choice == .device { await synchronize() }
        } catch { phase = .failed(message(for: error)) }
    }

    private func run(uid: String?, generation: UUID) async {
        do {
            let remote = try await load(uid: uid, generation: generation)
            try ensureCurrent(uid: uid, generation: generation)
            let current = library.snapshot
            if uid == nil, !current.configuration.hasSameContent(as: HomeConfiguration()),
               (current.base == nil && !current.hasPendingChanges) || (remote.revision == nil && current.base?.revision != nil) {
                // An iCloud copy never silently replaces a guest layout it was
                // not compared with, and an empty or reset record never erases it.
                try library.detachCloudBase()
            }
            let local = library.snapshot
            if !local.hasPendingChanges || (remote.carriesSources && local.configuration.matches(remote)) {
                try library.adopt(remote)
            } else if local.base?.revision == remote.revision {
                guard remote.carriesSources else { throw HomeSyncError.unsupportedSchema }
                let write = HomeScreenWrite(baseRevision: remote.revision, mutationId: local.mutationId, configuration: local.configuration)
                let saved = try await save(write, uid: uid, generation: generation)
                try ensureCurrent(uid: uid, generation: generation)
                try library.acknowledge(saved, uploadedMutationId: write.mutationId)
            } else {
                showConflict(remote, uid: uid, generation: generation)
                return
            }
            phase = .idle
        } catch HomeSyncError.conflict(let remote) {
            if isCurrent(uid: uid, generation: generation) { showConflict(remote, uid: uid, generation: generation) }
        } catch {
            guard isCurrent(uid: uid, generation: generation), !Task.isCancelled else { return }
            phase = .failed(message(for: error))
        }
    }
    private func load(uid: String?, generation: UUID) async throws -> RemoteHomeScreen {
        guard let uid else {
            guard let iCloud else { throw HomeSyncError.identityChanged }
            return try iCloud.load()
        }
        return try await authorized(uid: uid, generation: generation) { identity in
            try await self.service.load(identity: identity)
        }
    }
    private func save(_ write: HomeScreenWrite, uid: String?, generation: UUID) async throws -> RemoteHomeScreen {
        guard let uid else {
            guard let iCloud else { throw HomeSyncError.identityChanged }
            return try iCloud.save(write)
        }
        return try await authorized(uid: uid, generation: generation) { identity in
            try await self.service.save(write, identity: identity)
        }
    }
    private func authorized<T>(uid: String, generation: UUID,
                               action: (AuthorizedAccount) async throws -> T) async throws -> T {
        var identity = try await accounts.authorization(forceRefresh: false)
        try ensureCurrent(uid: uid, generation: generation)
        guard identity.userID == uid else { throw HomeSyncError.identityChanged }
        do { return try await action(identity) }
        catch HomeSyncError.unauthorized {
            try ensureCurrent(uid: uid, generation: generation)
            identity = try await accounts.authorization(forceRefresh: true)
            try ensureCurrent(uid: uid, generation: generation)
            guard identity.userID == uid else { throw HomeSyncError.identityChanged }
            return try await action(identity)
        }
    }
    private func isCurrent(uid: String?, generation: UUID) -> Bool {
        accounts.user?.id == uid && library.accountID == uid && library.generation == generation && isActive
    }
    private func ensureCurrent(uid: String?, generation: UUID) throws {
        try Task.checkCancellation()
        guard isCurrent(uid: uid, generation: generation) else { throw HomeSyncError.identityChanged }
    }
    private func showConflict(_ remote: RemoteHomeScreen, uid: String?, generation: UUID) {
        phase = .conflict(HomeSyncConflict(remote: remote, localMutationId: library.snapshot.mutationId,
                                           accountID: uid, generation: generation))
    }
    private func message(for error: Error) -> String {
        if let error = error as? HomeSyncError { return error.localizedDescription }
        if error is AccountError { return AccountError.message(for: error) }
        return "网络暂时无法连接，更改已保存在此设备。"
    }
}
