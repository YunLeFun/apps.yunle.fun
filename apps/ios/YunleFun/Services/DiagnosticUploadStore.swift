import Combine
import CryptoKit
import Foundation

struct DiagnosticUploadConfirmation: Identifiable, Equatable {
    let id: UUID
    let payload: DiagnosticUploadPayload
    let boundary: AccountRequestBoundary
    let logScopeGeneration: UUID
    let sizeBytes: Int
}

@MainActor
final class DiagnosticUploadStore: ObservableObject {
    private struct Scoped<Value> { let boundary: AccountRequestBoundary; let value: Value }
    private final class Flight {
        let id = UUID()
        let confirmation: DiagnosticUploadConfirmation
        var requestStarted = false
        init(_ confirmation: DiagnosticUploadConfirmation) { self.confirmation = confirmation }
    }
    @Published private var flight: Flight?
    @Published private var failure: Scoped<DiagnosticError>?
    @Published private var savedReceipt: Scoped<DiagnosticUploadReceipt>?
    @Published private var persistenceNotice: Scoped<String>?
    private var prepared: DiagnosticUploadConfirmation?
    private var operation: Task<DiagnosticUploadReceipt, Error>?
    private var observation: AnyCancellable?
    private let access: AccountRequestAccess<DiagnosticError>
    private let logs: DiagnosticLogStore
    private let service: DiagnosticServing
    private let receipts: DiagnosticReceiptVault
    private let now: () -> Date

    init(accounts: IdentityScopedAccountAuthorizing, logs: DiagnosticLogStore,
         service: DiagnosticServing = DiagnosticService(), receiptDirectory: URL? = nil, now: @escaping () -> Date = Date.init) {
        access = AccountRequestAccess(accounts: accounts); self.logs = logs; self.service = service
        receipts = DiagnosticReceiptVault(directory: receiptDirectory); self.now = now
        loadReceipt()
        observation = logs.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.logScopeChanged() }
        }
    }

    var isUploading: Bool { flight.map { isCurrent($0.confirmation) } ?? false }
    var error: String? { failure.flatMap { access.isCurrent($0.boundary) ? $0.value.message : nil } }
    var storageNotice: String? { persistenceNotice.flatMap { access.isCurrent($0.boundary) ? $0.value : nil } }
    var receipt: DiagnosticUploadReceipt? {
        guard let savedReceipt, access.isCurrent(savedReceipt.boundary),
              savedReceipt.value.expiresAt > now().timeIntervalSince1970 * 1000 else { return nil }
        return savedReceipt.value
    }

    func prepare(start: Date, end: Date, issueDescription: String, client: DiagnosticClientContext) throws -> DiagnosticUploadConfirmation {
        guard flight == nil else { throw DiagnosticError.uploadInProgress }
        prepared = nil
        let boundary = access.boundary
        guard let uid = boundary.uid, access.accounts.user?.isUsable == true, logs.accountID == uid else {
            throw DiagnosticError.identityChanged
        }
        let startTime = (start.timeIntervalSince1970 * 1000).rounded(.towardZero)
        let endTime = (end.timeIntervalSince1970 * 1000).rounded(.towardZero)
        let payload = try DiagnosticUploadRules.normalize(DiagnosticUploadPayload(startTime: startTime, endTime: endTime,
            issueDescription: issueDescription, logs: logs.select(startTime: startTime, endTime: endTime), client: client),
            now: now().timeIntervalSince1970 * 1000)
        let confirmation = DiagnosticUploadConfirmation(id: UUID(), payload: payload, boundary: boundary,
            logScopeGeneration: logs.scopeGeneration, sizeBytes: try DiagnosticUploadRules.sizeBytes(payload))
        prepared = confirmation; failure = nil
        return confirmation
    }

    func isValid(_ confirmation: DiagnosticUploadConfirmation) -> Bool {
        prepared == confirmation && isCurrent(confirmation)
            && (try? DiagnosticUploadRules.normalize(confirmation.payload, now: now().timeIntervalSince1970 * 1000)) == confirmation.payload
    }

    @discardableResult
    func upload(_ confirmation: DiagnosticUploadConfirmation) async -> Bool {
        guard flight == nil else { return false }
        guard isValid(confirmation) else {
            if access.isCurrent(confirmation.boundary), error == nil {
                failure = Scoped(boundary: access.boundary, value: .confirmationExpired)
            }
            return false
        }
        prepared = nil
        let current = Flight(confirmation)
        flight = current; failure = nil
        let started = now().timeIntervalSince1970 * 1000
        let task = Task<DiagnosticUploadReceipt, Error> { @MainActor [self] in
            try await access.perform(boundary: confirmation.boundary) { identity in
                try self.check(current)
                current.requestStarted = true
                do {
                    let receipt = try await self.service.upload(confirmation.payload, identity: identity)
                    try self.check(current)
                    return receipt
                } catch {
                    try self.check(current)
                    throw error
                }
            }
        }
        operation = task
        defer {
            if flight?.id == current.id { flight = nil; operation = nil }
        }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                Task { @MainActor [weak self] in
                    if self?.flight?.id == current.id { self?.cancelUpload() }
                }
            }
            try check(current)
            try DiagnosticUploadRules.validate(value, count: confirmation.payload.logs.count,
                                               now: now().timeIntervalSince1970 * 1000, started: started)
            savedReceipt = Scoped(boundary: confirmation.boundary, value: value)
            do {
                try receipts.save(value, owner: confirmation.boundary.uid!, now: now().timeIntervalSince1970 * 1000)
                persistenceNotice = nil
            } catch { persistenceNotice = Scoped(boundary: confirmation.boundary, value: DiagnosticError.storage.message) }
            return true
        } catch {
            guard flight?.id == current.id, isCurrent(confirmation) else { return false }
            let safe = DiagnosticError.safe(error)
            failure = Scoped(boundary: confirmation.boundary,
                             value: !current.requestStarted && safe == .outcomeUnknown ? .unavailable : safe)
            return false
        }
    }

    func invalidateConfirmation() {
        prepared = nil
        if flight != nil { cancelUpload() }
    }
    func cancelUpload() {
        prepared = nil
        guard let current = flight else { return }
        operation?.cancel(); operation = nil; flight = nil
        if access.isCurrent(current.confirmation.boundary) {
            failure = Scoped(boundary: current.confirmation.boundary,
                             value: current.requestStarted ? .outcomeUnknown : .cancelled)
        }
    }
    func identityChanged() {
        prepared = nil; operation?.cancel(); operation = nil; flight = nil
        failure = nil; savedReceipt = nil; persistenceNotice = nil
        loadReceipt()
    }

    private func isCurrent(_ confirmation: DiagnosticUploadConfirmation) -> Bool {
        access.isCurrent(confirmation.boundary) && access.accounts.user?.isUsable == true
            && logs.accountID == confirmation.boundary.uid && logs.scopeGeneration == confirmation.logScopeGeneration
    }
    private func check(_ current: Flight) throws {
        guard !Task.isCancelled, flight?.id == current.id, isCurrent(current.confirmation) else { throw DiagnosticError.confirmationExpired }
    }
    private func logScopeChanged() {
        if let prepared, !isCurrent(prepared) { self.prepared = nil }
        if let flight, !isCurrent(flight.confirmation) { cancelUpload() }
    }
    private func loadReceipt() {
        let boundary = access.boundary
        guard let uid = boundary.uid, access.accounts.user?.isUsable == true else { return }
        do {
            if let value = try receipts.load(owner: uid, now: now().timeIntervalSince1970 * 1000) {
                savedReceipt = Scoped(boundary: boundary, value: value)
            }
        } catch { persistenceNotice = Scoped(boundary: boundary, value: "本机保存的支持编号暂时无法读取，请保留已复制的信息。") }
    }
}

private struct DiagnosticReceiptVault {
    let directory: URL
    init(directory: URL?) {
        self.directory = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiagnosticReceipts", isDirectory: true)).standardizedFileURL
    }
    func load(owner: String, now: Double) throws -> DiagnosticUploadReceipt? {
        let checked: URL
        do { checked = try checkedDirectory(create: false) }
        catch { if Self.isMissing(error) { return nil }; throw error }
        let url = file(owner, directory: checked)
        guard try inspectFile(url) else { return nil }
        let value = try readRecord(url, owner: owner, now: now)
        if value.receipt.expiresAt <= now {
            try? FileManager.default.removeItem(at: url); return nil
        }
        try DiagnosticUploadRules.validate(value.receipt, now: now)
        return value.receipt
    }
    func save(_ receipt: DiagnosticUploadReceipt, owner: String, now: Double) throws {
        let url = file(owner, directory: try checkedDirectory(create: true))
        // A new successful upload must not destroy a corrupt previous file.
        if try inspectFile(url) { _ = try readRecord(url, owner: owner, now: now) }
        let data = try JSONEncoder().encode(Record(version: 1, ownerKey: key(owner), savedAt: now.rounded(.towardZero), receipt: receipt))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func readRecord(_ url: URL, owner: String, now: Double) throws -> Record {
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard record.version == 1, record.ownerKey == key(owner), record.savedAt.isFinite,
              record.savedAt.rounded(.towardZero) == record.savedAt,
              record.savedAt > 0, record.savedAt <= now + DiagnosticUploadRules.clockSkew else { throw DiagnosticError.storage }
        // Validate expired records against their original save time before cleanup.
        try DiagnosticUploadRules.validate(record.receipt, now: record.savedAt, started: record.savedAt)
        return record
    }
    private func checkedDirectory(create: Bool) throws -> URL {
        let requested = directory.pathComponents
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        let homeParts = home.pathComponents
        let insideHome = requested.starts(with: homeParts)
        // Resolve only the system-owned home prefix; app-controlled descendants must be real directories.
        var current = insideHome ? home.resolvingSymlinksInPath() : URL(fileURLWithPath: "/", isDirectory: true)
        let parts = insideHome ? Array(requested.dropFirst(homeParts.count)) : Array(requested.dropFirst())
        for part in parts {
            current.appendPathComponent(part, isDirectory: true)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw DiagnosticError.storage }
            } catch {
                guard Self.isMissing(error), create else { throw error }
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
        }
        return current
    }
    private func inspectFile(_ url: URL) throws -> Bool {
        do {
            let values = try FileManager.default.attributesOfItem(atPath: url.path)
            guard values[.type] as? FileAttributeType == .typeRegular,
                  let size = values[.size] as? NSNumber, size.int64Value >= 0, size.int64Value <= 8192 else { throw DiagnosticError.storage }
            return true
        } catch { if Self.isMissing(error) { return false }; throw error }
    }
    private static func isMissing(_ error: Error) -> Bool {
        guard let error = error as? CocoaError else { return false }
        return error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }
    private func key(_ owner: String) -> String { SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func file(_ owner: String, directory: URL) -> URL { directory.appendingPathComponent(key(owner) + ".json") }
    private struct Record: Codable { let version: Int; let ownerKey: String; let savedAt: Double; let receipt: DiagnosticUploadReceipt }
}
