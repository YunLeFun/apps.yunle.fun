import Combine
import Foundation

@MainActor
final class SupportCenterStore: ObservableObject {
    @Published private(set) var board: [SupportBoardItem] = []
    @Published private(set) var boardCursor: String?
    @Published private var savedDashboard: SupportDashboard?
    @Published private var savedReceipt: SupportFeedbackReceipt?
    @Published private var connected: SupportAccess?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var error: String?
    @Published private(set) var needsConsent = false
    private let accountAccess: AccountRequestAccess<SupportCenterError>
    private let service: SupportCenterServing
    private var scope: AccountRequestBoundary
    private var operationID = UUID()
    private var lastSubmission: [String] = []
    private var submissionKey = UUID().uuidString

    init(accounts: IdentityScopedAccountAuthorizing, service: SupportCenterServing = SupportCenterService()) {
        accountAccess = AccountRequestAccess(accounts: accounts)
        scope = accountAccess.boundary
        self.service = service
    }

    var isCurrent: Bool { accountAccess.isCurrent(scope) }
    var access: SupportAccess? { isCurrent ? connected : nil }
    var dashboard: SupportDashboard? { isCurrent ? savedDashboard : nil }
    var receipt: SupportFeedbackReceipt? { isCurrent ? savedReceipt : nil }

    func identityChanged() {
        close()
        operationID = UUID(); scope = accountAccess.boundary
        connected = nil; savedDashboard = nil; savedReceipt = nil
        error = nil; needsConsent = false; isLoading = false; isSubmitting = false; hasLoaded = false
        lastSubmission = []; submissionKey = UUID().uuidString
    }

    func close() {
        operationID = UUID()
        if let connected { revoke(connected) }
        connected = nil; savedDashboard = nil; savedReceipt = nil
        isLoading = false; isSubmitting = false
    }

    func load(_ destination: SupportDestination, product: String? = nil, more: Bool = false, consent: Bool = false) async {
        if !isCurrent { identityChanged() }
        guard !isSubmitting else { return }
        let boundary = scope, operation = UUID()
        operationID = operation; isLoading = true; error = nil; needsConsent = false
        if !more { hasLoaded = false; savedDashboard = nil }
        defer { if operationID == operation { isLoading = false } }
        do {
            switch destination {
            case .board:
                if !more { board = []; boardCursor = nil }
                let page = try await service.board(cursor: more ? boardCursor : nil)
                try check(boundary, operation)
                let previousIDs = Set(board.map(\.id))
                board = more ? board + page.items.filter { !previousIDs.contains($0.id) } : page.items
                boardCursor = page.nextCursor
                if boundary.uid != nil {
                    let access = try await connection(boundary: boundary, operation: operation, consent: consent)
                    try check(boundary, operation)
                    connected = access
                }
            case .compose:
                let access = try await connection(boundary: boundary, operation: operation, consent: consent)
                try check(boundary, operation)
                connected = access
            case .manage:
                guard boundary.uid != nil else { throw SupportCenterError.unauthorized }
                let access = try await connection(boundary: boundary, operation: operation, consent: consent)
                try check(boundary, operation)
                connected = access
                let page = try await service.dashboard(product: product,
                    cursor: more ? savedDashboard?.privateFeedback.nextCursor : nil, access: access)
                try check(boundary, operation)
                savedDashboard = page; connected = access
            }
            hasLoaded = true
        } catch {
            guard operationID == operation, accountAccess.isCurrent(boundary), !Task.isCancelled else { return }
            if error as? SupportCenterError == .unauthorized { connected = nil }
            needsConsent = error as? SupportCenterError == .consentRequired
            self.error = (error as? SupportCenterError)?.message ?? SupportCenterError.unavailable.message
        }
    }

    func submit(product: String, category: String, description: String) async {
        guard isCurrent, let connected, !isLoading, !isSubmitting, savedReceipt == nil else { return }
        let boundary = scope, operation = UUID()
        operationID = operation; isSubmitting = true; error = nil
        let input = [product, category, description.trimmingCharacters(in: .whitespacesAndNewlines)]
        if input != lastSubmission { lastSubmission = input; submissionKey = UUID().uuidString }
        defer { if operationID == operation { isSubmitting = false } }
        do {
            let receipt = try await service.submit(product: product, category: category, description: input[2],
                                                   key: submissionKey, access: connected)
            try check(boundary, operation)
            savedReceipt = receipt
        } catch {
            guard operationID == operation, accountAccess.isCurrent(boundary), !Task.isCancelled else { return }
            if error as? SupportCenterError == .unauthorized { self.connected = nil }
            self.error = (error as? SupportCenterError)?.message
                ?? "提交结果尚未确认。请重试，未修改的内容会使用同一提交编号，避免重复反馈。"
        }
    }

    private func connection(boundary: AccountRequestBoundary, operation: UUID, consent: Bool) async throws -> SupportAccess {
        if let connected, accountAccess.isCurrent(boundary), scope == boundary { return connected }
        let value: SupportAccess
        if boundary.uid != nil {
            var issued: SupportAccess?
            do {
                value = try await accountAccess.perform(boundary: boundary) { identity in
                    let result = try await service.connect(identity: identity, consent: consent)
                    issued = result
                    return result
                }
            } catch {
                if let issued { revoke(issued) }
                throw error
            }
        } else { value = try await service.connect(identity: nil, consent: false) }
        guard accountAccess.isCurrent(boundary), operationID == operation, !Task.isCancelled else {
            revoke(value)
            throw SupportCenterError.identityChanged
        }
        return value
    }

    private func revoke(_ access: SupportAccess) {
        guard access.userID != nil else { return }
        let service = service
        Task { try? await service.disconnect(access) }
    }

    private func check(_ boundary: AccountRequestBoundary, _ operation: UUID) throws {
        guard operationID == operation, accountAccess.isCurrent(boundary), !Task.isCancelled else { throw SupportCenterError.identityChanged }
    }
}
