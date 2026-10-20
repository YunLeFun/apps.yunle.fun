import Foundation
import Combine

@MainActor
final class AssistantStore: ObservableObject {
    enum Access { case unknown, ready, membershipRequired, restricted }
    static let examples = ["找一个适合写代码的开发工具", "推荐几个好玩的应用", "有没有适合整理灵感的工具"]
    private let access: AccountRequestAccess<AssistantError>
    private let service: AssistantServing
    private let wallet: WalletServing
    private let historyStore: AssistantHistory?
    /// The messages last written to history, so re-saving an unchanged conversation never reorders the list.
    private var savedMessages: [AssistantMessage]?
    private var boundary: AccountRequestBoundary?
    private var operation = UUID()
    private var task: Task<Void, Never>?
    private(set) var threadID = "thread_" + UUID().uuidString
    @Published private var rawMessages: [AssistantMessage] = []
    @Published private var rawError: String?
    @Published private var rawDraft = ""
    @Published private var rawRunning = false
    @Published private var rawAccess = Access.unknown
    @Published private var rawHistory: [AssistantConversation] = []
    @Published private var rawHistoryUnsaved = false
    @Published private(set) var scrollRevision = 0
    var messages: [AssistantMessage] { current ? rawMessages : [] }
    var error: String? { current ? rawError : nil }
    var running: Bool { current && rawRunning }
    var accessState: Access { current ? rawAccess : .unknown }
    /// Saved conversations of the current signed-in account; empty for guests and across identity changes.
    var history: [AssistantConversation] { current ? rawHistory : [] }
    /// The open conversation could not be written to history; it is retried at the next save point
    /// and is lost only if the user starts a new conversation anyway.
    var historyUnsaved: Bool { current && rawHistoryUnsaved }
    var draft: String {
        get { current ? rawDraft : "" }
        set { prepareIdentity(); rawDraft = newValue }
    }
    var canSend: Bool { !running && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= 4000 }
    private var current: Bool { boundary == access.boundary }
    init(accounts: IdentityScopedAccountAuthorizing, service: AssistantServing = AssistantService(), wallet: WalletServing = WalletService(),
         history: AssistantHistory? = nil) {
        access = AccountRequestAccess(accounts: accounts); self.service = service; self.wallet = wallet; historyStore = history
        boundary = access.boundary
        loadHistory()
    }
    func identityChanged() { prepareIdentity() }
    private func prepareIdentity() {
        guard !current else { return }
        task?.cancel(); task = nil; operation = UUID(); boundary = access.boundary
        rawMessages = []; rawError = nil; rawDraft = ""; rawRunning = false; rawAccess = .unknown
        threadID = "thread_" + UUID().uuidString; savedMessages = nil; rawHistoryUnsaved = false
        loadHistory()
    }
    func refreshAccess() async {
        prepareIdentity()
        guard !running, access.boundary.uid != nil else { return }
        let captured = access.boundary
        let currentOperation = operation
        do {
            let value = try await account(boundary: captured)
            guard access.isCurrent(captured), operation == currentOperation, !running else { return }
            rawAccess = value.membership.isActive ? .ready : .membershipRequired
            rawError = nil
        } catch {
            guard access.isCurrent(captured), operation == currentOperation, !running, !Task.isCancelled else { return }
            setError(error)
        }
    }
    @discardableResult func send() -> Task<Void, Never>? {
        prepareIdentity()
        guard canSend else { return nil }
        return begin(prompt: draft.trimmingCharacters(in: .whitespacesAndNewlines), retry: false)
    }
    @discardableResult func retry() -> Task<Void, Never>? {
        prepareIdentity()
        guard !running, let user = rawMessages.last(where: { $0.role == .user }) else { return nil }
        return begin(prompt: user.content, retry: true)
    }
    func stop() {
        guard current else { prepareIdentity(); return }
        operation = UUID(); task?.cancel(); task = nil; rawRunning = false
        for index in rawMessages.indices where rawMessages[index].status == .streaming {
            rawMessages[index].status = .stopped; rawMessages[index].toolStatus = nil
        }
        persist()
    }
    func reset() {
        stop(); rawMessages = []; rawError = nil; savedMessages = nil; rawHistoryUnsaved = false
        rawDraft = ""; threadID = "thread_" + UUID().uuidString; scrollRevision += 1
    }
    /// Continues a saved conversation in the same Agent thread.
    func open(_ id: String) {
        guard current, let selected = rawHistory.first(where: { $0.id == id }) else { return }
        // Stopping saves a running thread, which can push the selection past the limit;
        // prefer the freshly saved copy when it is still there.
        stop()
        let conversation = rawHistory.first(where: { $0.id == id }) ?? selected
        rawMessages = conversation.messages; savedMessages = conversation.messages; rawHistoryUnsaved = false
        threadID = conversation.id; rawError = nil; rawDraft = ""; scrollRevision += 1
    }
    func delete(_ id: String) {
        guard current, let store = historyStore, let uid = historyAccountID else { return }
        // Finish an active reply first, so its final snapshot cannot save the deleted thread again.
        if id == threadID && rawRunning { stop() }
        rawHistory = store.delete(id, accountID: uid)
        // A deleted open conversation is only saved again if it gets new messages.
        if id == threadID { savedMessages = rawMessages }
    }
    func deleteAll() {
        guard current, let store = historyStore, let uid = historyAccountID else { return }
        if rawRunning { stop() }
        store.deleteAll(accountID: uid); rawHistory = []; savedMessages = rawMessages
    }
    private var historyAccountID: String? {
        guard historyStore != nil, let uid = access.boundary.uid, access.accounts.user?.isUsable == true else { return nil }
        return uid
    }
    private func loadHistory() {
        rawHistory = historyAccountID.flatMap { uid in historyStore?.load(accountID: uid) } ?? []
    }
    /// Saves the current conversation for the current account only, once it has changed.
    private func persist() {
        guard current, !rawRunning, rawMessages != savedMessages, let store = historyStore, let uid = historyAccountID,
              let conversation = AssistantHistory.conversation(id: threadID, messages: rawMessages) else { return }
        let result = store.save(conversation, accountID: uid)
        rawHistory = result.conversations
        rawHistoryUnsaved = !result.saved
        if result.saved { savedMessages = rawMessages }
    }
    private func begin(prompt: String, retry: Bool) -> Task<Void, Never>? {
        guard access.boundary.uid != nil, access.accounts.user?.isUsable == true else {
            rawError = AssistantError.unauthorized.message; return nil
        }
        guard rawMessages.count < 200, rawMessages.reduce(0, { $0 + $1.content.utf8.count }) < 512 * 1024 else {
            rawError = AssistantError.tooLong.message; return nil
        }
        let captured = access.boundary, id = UUID(), assistantID = "msg_" + UUID().uuidString
        operation = id; rawRunning = true; rawError = nil
        let worker = Task {
            defer { if self.operation == id { self.rawRunning = false; self.task = nil } }
            @MainActor func valid() -> Bool { !Task.isCancelled && self.operation == id && self.access.isCurrent(captured) }
            do {
                let snapshot = try await self.account(boundary: captured)
                guard valid() else { return }
                guard snapshot.membership.isActive else { throw AssistantError.membershipRequired }
                self.rawAccess = .ready
                if retry, let index = self.rawMessages.lastIndex(where: { $0.role == .user }) {
                    self.rawMessages = Array(self.rawMessages.prefix(index + 1))
                } else {
                    self.rawMessages.append(AssistantMessage(id: "msg_" + UUID().uuidString, role: .user, content: prompt))
                    self.rawDraft = ""
                }
                self.rawMessages.append(AssistantMessage(id: assistantID, role: .assistant, content: "", status: .streaming, toolStatus: "正在连接"))
                self.scrollRevision += 1
                let history = self.rawMessages.filter { !$0.content.isEmpty && $0.status != .failed }.suffix(32).map {
                    AssistantRunInput.Message(id: $0.id, role: $0.role, content: String($0.content.unicodeScalars.prefix(4000)))
                }
                let input = AssistantRunInput(botId: AssistantService.botID, threadId: self.threadID, runId: "run_" + UUID().uuidString, messages: history)
                let stream = try await self.access.perform(boundary: captured) { try await self.service.events(input: input, identity: $0) }
                var accumulator = AssistantRunAccumulator(threadID: input.threadId, runID: input.runId)
                for try await event in stream {
                    guard valid() else { return }
                    try accumulator.apply(event)
                    self.update(assistantID) {
                        $0.content = accumulator.content; $0.cards = accumulator.cards; $0.toolStatus = accumulator.status
                    }
                    self.scrollRevision += 1
                    if accumulator.finished { break }
                }
                guard valid() else { return }
                guard accumulator.finished else { throw AssistantError.interrupted }
                if accumulator.cards.isEmpty {
                    self.update(assistantID) { $0.toolStatus = "正在匹配应用" }
                    do {
                        let cards = try await self.access.perform(boundary: captured) { try await self.service.search(query: prompt, identity: $0) }
                        guard valid() else { return }
                        self.update(assistantID) { $0.cards = cards }
                    } catch { /* A card lookup failure does not replace a completed reply. */ }
                }
                guard valid() else { return }
                if let reply = self.rawMessages.first(where: { $0.id == assistantID }), reply.content.isEmpty && reply.cards.isEmpty {
                    throw AssistantError.invalidResponse
                }
                self.update(assistantID) { $0.status = .done; $0.toolStatus = nil }
                self.scrollRevision += 1
                self.rawRunning = false; self.persist()
            } catch {
                guard valid() else { return }
                self.setError(error)
                self.update(assistantID) { $0.status = .failed; $0.toolStatus = nil }
                self.rawRunning = false; self.persist()
            }
        }
        task = worker
        return worker
    }
    private func account(boundary: AccountRequestBoundary) async throws -> WalletSnapshot {
        try await access.perform(boundary: boundary) { identity in
            do { return try await wallet.account(identity: identity) }
            catch let error as WalletError {
                switch error {
                case .unauthorized: throw AssistantError.unauthorized
                case .forbidden: throw AssistantError.forbidden
                default: throw AssistantError.unavailable
                }
            }
        }
    }
    private func update(_ id: String, action: (inout AssistantMessage) -> Void) {
        guard let index = rawMessages.firstIndex(where: { $0.id == id }) else { return }
        action(&rawMessages[index])
    }
    private func setError(_ error: Error) {
        let issue = error as? AssistantError ?? .unavailable
        rawError = issue.message
        if issue == .membershipRequired { rawAccess = .membershipRequired }
        if issue == .forbidden { rawAccess = .restricted }
    }
}
