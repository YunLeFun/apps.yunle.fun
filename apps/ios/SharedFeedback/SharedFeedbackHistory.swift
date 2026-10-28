import CryptoKit
import Foundation

struct SharedFeedbackContext: Codable, Equatable, Sendable {
    let epoch: UUID
    let channel: FeedbackChannel
}

struct SharedFeedbackRecord: Codable, Identifiable, Equatable, Sendable {
    let receipt: SupportFeedbackReceipt
    let createdAt: Date
    var id: String { receipt.id }
    var ticketURL: URL? { SupportFeedbackClient.ticketURL(receipt, requiringGuestAccess: true) }
}

/// The App Group stores only bounded guest-ticket receipts, never photos, drafts or App credentials.
/// Coordinated read/modify/write operations fence late extension results across account changes.
struct SharedFeedbackHistory: Sendable {
    static let maximumRecords = 20
    private let directory: URL?
    private struct State: Codable {
        var schemaVersion = 1
        var ownerKey: String?
        var context: SharedFeedbackContext
        var records: [SharedFeedbackRecord] = []
    }

    init(directory: URL? = nil, bundle: Bundle = .main) {
        if let directory { self.directory = directory }
        else if let group = bundle.object(forInfoDictionaryKey: "YunleFeedbackAppGroup") as? String,
                group.hasPrefix("group.fun.yunle.apps"), !group.contains("$") {
            self.directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("SupportShare", isDirectory: true)
        } else { self.directory = nil }
    }

    func rememberedContext() throws -> SharedFeedbackContext? {
        try coordinate(writing: false) { url in try read(url)?.context }
    }

    func prepareForShare(channel: FeedbackChannel) throws -> SharedFeedbackContext {
        try coordinate(writing: true) { url in
            var state = try read(url) ?? State(context: SharedFeedbackContext(epoch: UUID(), channel: channel))
            state.context = SharedFeedbackContext(epoch: state.context.epoch, channel: channel)
            try write(state, to: url)
            return state.context
        }
    }

    func activate(userID: String?, channel: FeedbackChannel) throws {
        let owner = SHA256.hash(data: Data((userID.map { "user:" + $0 } ?? "guest").utf8))
            .map { String(format: "%02x", $0) }.joined()
        try coordinate(writing: true) { url in
            var state = try read(url) ?? State(context: SharedFeedbackContext(epoch: UUID(), channel: channel))
            // A first share can happen before the containing App has ever launched.
            // Its unassigned receipt can be adopted once, after account restoration.
            if let previous = state.ownerKey, previous != owner {
                state.records = []
                state.context = SharedFeedbackContext(epoch: UUID(), channel: channel)
            }
            state.ownerKey = owner
            state.context = SharedFeedbackContext(epoch: state.context.epoch, channel: channel)
            try write(state, to: url)
        }
    }

    func isCurrent(_ context: SharedFeedbackContext) throws -> Bool {
        try rememberedContext()?.epoch == context.epoch
    }

    func records(expected context: SharedFeedbackContext) throws -> [SharedFeedbackRecord] {
        try coordinate(writing: false) { url in
            guard let state = try read(url), state.context.epoch == context.epoch else { throw SharedFeedbackHistoryError.scopeChanged }
            return state.records
        }
    }

    func save(_ record: SharedFeedbackRecord, expected context: SharedFeedbackContext) throws {
        guard valid(record) else { throw SharedFeedbackHistoryError.corrupt }
        try coordinate(writing: true) { url in
            guard var state = try read(url), state.context.epoch == context.epoch else { throw SharedFeedbackHistoryError.scopeChanged }
            state.records.removeAll { $0.id == record.id }
            state.records.insert(record, at: 0)
            state.records = Array(state.records.prefix(Self.maximumRecords))
            try write(state, to: url)
        }
    }

    func clear(expected context: SharedFeedbackContext) throws {
        try coordinate(writing: true) { url in
            guard var state = try read(url), state.context.epoch == context.epoch else { throw SharedFeedbackHistoryError.scopeChanged }
            state.records = []
            try write(state, to: url)
        }
    }

    private func coordinate<T>(writing: Bool, work: (URL) throws -> T) throws -> T {
        guard var directory else { throw SharedFeedbackHistoryError.unavailable }
        if FileManager.default.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw SharedFeedbackHistoryError.corrupt }
        }
        if writing {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } else if !FileManager.default.fileExists(atPath: directory.path) {
            return try work(directory.appendingPathComponent("receipts.json"))
        }
        let url = directory.appendingPathComponent("receipts.json")
        try rejectLink(at: url)
        if !writing && !FileManager.default.fileExists(atPath: url.path) { return try work(url) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
                result = Result { try work(coordinated) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                result = Result { try work(coordinated) }
            }
        }
        if coordinationError != nil { throw SharedFeedbackHistoryError.unavailable }
        guard let result else { throw SharedFeedbackHistoryError.unavailable }
        return try result.get()
    }

    private func read(_ url: URL) throws -> State? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let properties = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard properties.isSymbolicLink != true, (properties.fileSize ?? Int.max) <= 256 * 1024 else {
            throw SharedFeedbackHistoryError.corrupt
        }
        let data = try Data(contentsOf: url)
        guard let state = try? JSONDecoder().decode(State.self, from: data), state.schemaVersion == 1,
              state.ownerKey.map({ $0.count == 64 && $0.range(of: #"^[a-f0-9]{64}\z"#, options: .regularExpression) != nil }) ?? true,
              state.records.count <= Self.maximumRecords, state.records.allSatisfy(valid),
              Set(state.records.map(\.id)).count == state.records.count else { throw SharedFeedbackHistoryError.corrupt }
        return state
    }

    private func rejectLink(at url: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SharedFeedbackHistoryError.corrupt }
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return }
    }

    private func write(_ state: State, to url: URL) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= 256 * 1024 else { throw SharedFeedbackHistoryError.corrupt }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func valid(_ record: SharedFeedbackRecord) -> Bool {
        SupportFeedbackClient.identifier(record.id) && SupportProduct.submissionIDs.contains(record.receipt.productId)
            && record.ticketURL != nil && record.createdAt <= Date().addingTimeInterval(300)
    }
}

enum SharedFeedbackHistoryError: Error {
    case unavailable, corrupt, scopeChanged
    var message: String {
        switch self {
        case .unavailable: return "暂时无法读取分享反馈记录，请先打开一次云乐坊，再重试。"
        case .corrupt: return "分享反馈记录暂时无法读取，原记录已保留。"
        case .scopeChanged: return "云乐坊账号环境已变化，请重新打开反馈。"
        }
    }
}
