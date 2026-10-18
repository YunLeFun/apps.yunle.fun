import Combine
import Foundation

@MainActor
final class LegacyImportStore: ObservableObject {
    @Published private(set) var archive: LegacyImportArchive?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published private(set) var error: String?
    private let library: HomeLibrary
    private let accounts: IdentityScopedAccountAuthorizing
    private let reader: LegacyLocalDataReading
    private let archiveURL: URL
    private let preferences: UserDefaults

    init(library: HomeLibrary, accounts: IdentityScopedAccountAuthorizing,
         reader: LegacyLocalDataReading? = nil, archiveURL: URL? = nil, preferences: UserDefaults = .standard) {
        self.library = library; self.accounts = accounts; self.reader = reader ?? LegacyLocalDataReader(); self.preferences = preferences
        self.archiveURL = archiveURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegacyImport", isDirectory: true).appendingPathComponent("record-v1.json")
    }
    var targetLabel: String { accounts.user.map { "当前账号：" + $0.displayName } ?? "本机访客云居" }
    var belongsToCurrentTarget: Bool { archive?.claim.map { $0.accountID == library.accountID && $0.accountID == accounts.user?.id } ?? true }
    var visibleArchive: LegacyImportArchive? { belongsToCurrentTarget ? archive : nil }

    func load(retry: Bool = false) async {
        guard !isLoading, !isLoaded || retry else { return }
        isLoading = true; isLoaded = false; error = nil
        defer { isLoading = false }
        do {
            var stored: LegacyImportArchive
            do {
                stored = try readStoredArchive()
            } catch let issue as CocoaError where issue.code == .fileReadNoSuchFile {
                let values = try await reader.read()
                try Task.checkCancellation()
                // Another window may have staged or claimed the record while
                // WebKit was loading. Never replace that durable decision.
                do { stored = try readStoredArchive() }
                catch let issue as CocoaError where issue.code == .fileReadNoSuchFile {
                    let record = try LegacyLocalData(values: values)
                    if record.values.isEmpty { archive = nil; isLoaded = true; return }
                    stored = LegacyImportArchive(record: record)
                    try save(stored)
                }
            }
            try Task.checkCancellation()
            archive = stored; isLoaded = true
        } catch is CancellationError { }
        catch is DecodingError { self.error = LegacyImportError.invalidData.localizedDescription }
        catch { self.error = (error as? LegacyImportError)?.localizedDescription ?? LegacyImportError.unreadable.localizedDescription }
    }

    func confirmation() -> LegacyImportConfirmation? {
        do {
            guard let displayed = archive, isLoaded, !isLoading else { return nil }
            let archive = try refreshArchive(expectedID: displayed.record.id)
            guard belongsToCurrentTarget else { throw LegacyImportError.alreadyClaimed }
            guard archive.claim?.completed != true else { return nil }
            guard accounts.user?.id == library.accountID, accounts.user == nil || accounts.user?.isUsable == true else { throw LegacyImportError.identityChanged }
            error = nil
            return LegacyImportConfirmation(recordID: archive.record.id, accountID: library.accountID,
                                            accountGeneration: accounts.identityGeneration, libraryGeneration: library.generation)
        } catch { self.error = (error as? LegacyImportError)?.localizedDescription ?? LegacyImportError.storage.localizedDescription; return nil }
    }

    func apply(_ confirmation: LegacyImportConfirmation) {
        do {
            guard isLoaded, !isLoading, archive != nil,
                  confirmation.accountID == library.accountID, confirmation.accountID == accounts.user?.id,
                  confirmation.accountGeneration == accounts.identityGeneration, confirmation.libraryGeneration == library.generation,
                  accounts.user == nil || accounts.user?.isUsable == true else { throw LegacyImportError.identityChanged }
            var current = try refreshArchive(expectedID: confirmation.recordID)
            if let claim = current.claim, claim.accountID != confirmation.accountID { throw LegacyImportError.alreadyClaimed }
            guard current.claim?.completed != true else { return }
            // Claim the destination durably before changing its home. A crash or
            // failed write can only resume in this destination, never another uid.
            current.claim = .init(accountID: confirmation.accountID)
            try save(current); archive = current
            try library.importLegacy(current.record, expectedGeneration: confirmation.libraryGeneration)
            if let appearance = current.record.appearance { preferences.set(appearance, forKey: "appearance") }
            current.claim?.completed = true
            try save(current); archive = current; error = nil
        } catch { self.error = (error as? LegacyImportError)?.localizedDescription ?? LegacyImportError.storage.localizedDescription }
    }

    private func refreshArchive(expectedID: String) throws -> LegacyImportArchive {
        let current: LegacyImportArchive
        do { current = try readStoredArchive() }
        catch { isLoaded = false; throw error }
        archive = current
        guard current.record.id == expectedID else { isLoaded = false; throw LegacyImportError.recordChanged }
        return current
    }

    private func readStoredArchive() throws -> LegacyImportArchive {
        let data = try Data(contentsOf: archiveURL)
        guard data.count <= 1_048_576 else { throw LegacyImportError.invalidData }
        let stored: LegacyImportArchive
        do { stored = try JSONDecoder().decode(LegacyImportArchive.self, from: data) }
        catch is DecodingError { throw LegacyImportError.invalidData }
        guard stored.version == 1 else { throw LegacyImportError.invalidData }
        if let uid = stored.claim?.accountID {
            do { try HomeConfiguration(installedApps: [.init(appId: uid)]).validate() }
            catch { throw LegacyImportError.invalidData }
        }
        return stored
    }

    private func save(_ proposed: LegacyImportArchive) throws {
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(proposed).write(to: archiveURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { throw LegacyImportError.storage }
    }
}
