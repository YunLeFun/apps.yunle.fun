import Combine
import Foundation

@MainActor
final class HomeBackupStore: ObservableObject {
    @Published private var items: [HomeBackupItem] = []
    @Published private var selected: HomeBackupPreview?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var isRestoring = false
    @Published private(set) var error: String?
    @Published private var restored = false
    private let library: HomeLibrary
    private let accounts: IdentityScopedAccountAuthorizing
    private let reader: HomeBackupReading
    private var listBoundary: HomeBackupBoundary?
    private var previewBoundary: HomeBackupBoundary?
    private var listOperation = UUID(), previewOperation = UUID()

    init(library: HomeLibrary, accounts: IdentityScopedAccountAuthorizing, reader: HomeBackupReading? = nil) {
        self.library = library; self.accounts = accounts
        self.reader = reader ?? HomeBackupRepository(directory: library.fileURL.deletingLastPathComponent())
    }
    var visibleItems: [HomeBackupItem] { listBoundary.map(isCurrent) == true ? items : [] }
    var visiblePreview: HomeBackupPreview? { previewBoundary.map(isCurrent) == true ? selected : nil }
    var hasOpenedPreview: Bool { previewBoundary != nil }
    var didRestore: Bool { restored && previewBoundary.map(isCurrent) == true }
    var needsRecovery: Bool { library.needsRecovery }
    var targetLabel: String { accounts.user.map { "当前账号：" + $0.displayName } ?? "本机访客云居" }

    func load() async {
        let operation = UUID(); listOperation = operation
        isLoading = true; isLoaded = false; error = nil
        defer { if listOperation == operation { isLoading = false } }
        do {
            let boundary = try captureBoundary()
            if listBoundary != boundary { items = [] }
            listBoundary = boundary
            let result = try await reader.list(ownerFileName: boundary.ownerFileName)
            try Task.checkCancellation()
            guard listOperation == operation, isCurrent(boundary) else { throw HomeBackupError.identityChanged }
            items = result; isLoaded = true
        } catch is CancellationError { }
        catch { if listOperation == operation { self.error = message(error) } }
    }

    func select(_ id: String, force: Bool = false) async {
        guard !isRestoring else { return }
        if !force, let visiblePreview, visiblePreview.item.id == id { return }
        let operation = UUID(); previewOperation = operation
        selected = nil; restored = false; isLoadingPreview = true; error = nil
        defer { if previewOperation == operation { isLoadingPreview = false } }
        do {
            let boundary = try captureBoundary(); previewBoundary = boundary
            let result = try await reader.preview(id: id, ownerFileName: boundary.ownerFileName)
            try Task.checkCancellation()
            guard previewOperation == operation, isCurrent(boundary) else { throw HomeBackupError.identityChanged }
            selected = result
        } catch is CancellationError { }
        catch { if previewOperation == operation { self.error = message(error) } }
    }

    func confirmation(restoreSettings: Bool) -> HomeBackupRestoreConfirmation? {
        do {
            guard !isRestoring, let selected = visiblePreview else { throw HomeBackupError.identityChanged }
            let boundary = try captureBoundary()
            error = nil
            return HomeBackupRestoreConfirmation(backupID: selected.item.id, backupDigest: selected.digest, boundary: boundary,
                                                  baseline: library.restoreBaseline, restoreSettings: restoreSettings)
        } catch { self.error = message(error); return nil }
    }

    func restore(_ confirmation: HomeBackupRestoreConfirmation) async {
        guard !isRestoring else { return }
        isRestoring = true; error = nil
        defer { isRestoring = false }
        do {
            guard isCurrentAccount(confirmation.boundary) else { throw HomeBackupError.identityChanged }
            if library.snapshot.lastRestoreID != confirmation.id.uuidString {
                guard isCurrent(confirmation.boundary) else { throw HomeBackupError.identityChanged }
                let candidate = try await reader.preview(id: confirmation.backupID, ownerFileName: confirmation.boundary.ownerFileName)
                try Task.checkCancellation()
                guard isCurrent(confirmation.boundary) else { throw HomeBackupError.identityChanged }
                guard candidate.digest == confirmation.backupDigest else { throw HomeBackupError.backupChanged }
                try library.restoreBackup(candidate.snapshot, confirmation: confirmation)
            }
            let current = try captureBoundary()
            listBoundary = current; previewBoundary = current; restored = true
            await load()
        } catch is CancellationError { }
        catch { self.error = message(error) }
    }

    private func captureBoundary() throws -> HomeBackupBoundary {
        guard accounts.user?.id == library.accountID, accounts.user == nil || accounts.user?.isUsable == true else { throw HomeBackupError.identityChanged }
        return HomeBackupBoundary(accountID: library.accountID, accountGeneration: accounts.identityGeneration,
                                  libraryGeneration: library.generation, ownerFileName: library.fileURL.lastPathComponent)
    }
    private func isCurrentAccount(_ boundary: HomeBackupBoundary) -> Bool {
        accounts.user?.id == boundary.accountID && accounts.identityGeneration == boundary.accountGeneration
            && library.accountID == boundary.accountID && library.fileURL.lastPathComponent == boundary.ownerFileName
    }
    private func isCurrent(_ boundary: HomeBackupBoundary) -> Bool { isCurrentAccount(boundary) && library.generation == boundary.libraryGeneration }
    private func message(_ error: Error) -> String { (error as? HomeBackupError)?.localizedDescription ?? HomeBackupError.unreadable.localizedDescription }
}
