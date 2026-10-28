import Combine
import Foundation

@MainActor
final class MyWorkshopsStore: ObservableObject {
    @Published private var owned: WorkshopManagement?
    @Published private var joinedRecords: [PersonalWorkshop] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    private let access: AccountRequestAccess<WorkshopError>
    private let service: WorkshopServing
    private var loadedBoundary: AccountRequestBoundary?
    private var loadID = UUID()
    private var writeID: UUID?
    init(accounts: IdentityScopedAccountAuthorizing, service: WorkshopServing = WorkshopService()) {
        access = AccountRequestAccess(accounts: accounts); self.service = service
    }
    var hasLoaded: Bool { loadedBoundary.map(access.isCurrent) ?? false }
    var management: WorkshopManagement? { hasLoaded ? owned : nil }
    var joined: [PersonalWorkshop] { hasLoaded ? joinedRecords : [] }
    var switchableWorkshops: [PersonalWorkshop] {
        var seen = Set<String>()
        return ([management?.workshop].compactMap { $0 } + joined).filter { seen.insert($0.id).inserted }
    }
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await refresh()
    }
    func refresh() async {
        guard !isWriting else { return }
        let boundary = access.boundary, requestID = UUID()
        loadID = requestID; isLoading = true; error = nil
        defer { if loadID == requestID { isLoading = false } }
        guard boundary.uid != nil else { owned = nil; joinedRecords = []; loadedBoundary = nil; return }
        do {
            let result = try await access.perform(boundary: boundary) { identity in
                async let mine = self.service.mine(identity: identity)
                async let joined = self.service.joined(identity: identity)
                return try await (mine, joined)
            }
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            owned = result.0; joinedRecords = result.1; loadedBoundary = boundary
        } catch {
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            self.error = WorkshopError.message(for: error)
        }
    }
    func save(_ draft: WorkshopDraft, expectedID: String?, generation: UUID) async throws {
        guard access.boundary.generation == generation else { throw WorkshopError.identityChanged }
        guard draft.isValid, management?.workshop.id == expectedID, expectedID != nil || hasLoaded else { throw WorkshopError.conflict }
        let workshop = try await write(generation: generation) { identity in
            if let id = expectedID { return try await self.service.update(id: id, draft: draft, identity: identity) }
            return try await self.service.create(draft: draft, identity: identity)
        }
        if var owned, owned.workshop.id == workshop.id { owned.workshop = workshop; self.owned = owned }
        else { owned = WorkshopManagement(workshop: workshop, pending: [], guests: [], blocked: []) }
        loadedBoundary = access.boundary
        notice = expectedID == nil ? "个人工坊已创建" : "工坊设置已保存"
    }

    func decide(member: WorkshopMembership, action: WorkshopDecision, generation: UUID) async throws {
        guard access.boundary.generation == generation else { throw WorkshopError.identityChanged }
        guard let management, management.workshop.id == member.workshopId,
              management.member(member.userUid) == member, action.allows(member.status) else { throw WorkshopError.conflict }
        let result = try await write(generation: generation) { identity in
            try await self.service.decide(id: member.workshopId, member: member, action: action, identity: identity)
        }
        owned?.apply(result); notice = action.label + "已完成"
    }
    private func write<Result>(generation: UUID, operation: (AuthorizedAccount) async throws -> Result) async throws -> Result {
        guard access.boundary.generation == generation else { throw WorkshopError.identityChanged }
        guard !isWriting else { throw WorkshopError.throttled }
        let boundary = access.boundary, requestID = UUID()
        loadID = UUID(); isLoading = false; writeID = requestID; isWriting = true; error = nil; notice = nil
        defer { if writeID == requestID { isWriting = false; writeID = nil } }
        let result = try await access.perform(boundary: boundary, action: operation)
        guard writeID == requestID else { throw WorkshopError.identityChanged }
        return result
    }
}

@MainActor
final class WorkshopPageStore: ObservableObject {
    let id: String
    @Published private var payload: WorkshopPage?
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    private let access: AccountRequestAccess<WorkshopError>
    private let service: WorkshopServing
    private var loadedBoundary: AccountRequestBoundary?
    private var loadID = UUID()
    private var writeID: UUID?
    init(id: String, accounts: IdentityScopedAccountAuthorizing, service: WorkshopServing = WorkshopService()) {
        self.id = id; access = AccountRequestAccess(accounts: accounts); self.service = service
    }
    var page: WorkshopPage? { loadedBoundary.map(access.isCurrent) == true ? payload : nil }
    func refresh() async {
        guard !isWriting else { return }
        let boundary = access.boundary, requestID = UUID()
        loadID = requestID; isLoading = true; error = nil
        defer { if loadID == requestID { isLoading = false } }
        do {
            let result: WorkshopPage
            if boundary.uid == nil { result = try await service.page(id: id, identity: nil) }
            else { result = try await access.perform(boundary: boundary) { try await self.service.page(id: self.id, identity: $0) } }
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            payload = result; loadedBoundary = boundary
        } catch {
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            self.error = WorkshopError.message(for: error)
        }
    }
    func join(generation: UUID) async throws {
        guard let page, page.workshop.status == .active, page.workshop.joinPolicy != .closed,
              page.access == .none || page.access == .anonymous else { throw WorkshopError.conflict }
        let result = try await write(generation: generation) { try await self.service.join(id: self.id, identity: $0) }
        payload = WorkshopPage(surface: "workshop", access: result.joined ? .active : .pending, workshop: page.workshop, apps: [])
        loadedBoundary = access.boundary
        notice = result.joined ? "已加入工坊" : "申请已提交，等待坊主审批"
        await refresh()
    }
    func leave(generation: UUID) async throws {
        guard let page, page.access == .active else { throw WorkshopError.conflict }
        _ = try await write(generation: generation) { try await self.service.leave(id: self.id, identity: $0) }
        payload = WorkshopPage(surface: "workshop", access: .none, workshop: page.workshop, apps: [])
        loadedBoundary = access.boundary; notice = "已离开工坊"
    }

    private func write<Result>(generation: UUID, operation: (AuthorizedAccount) async throws -> Result) async throws -> Result {
        guard access.boundary.generation == generation else { throw WorkshopError.identityChanged }
        guard !isWriting else { throw WorkshopError.throttled }
        let boundary = access.boundary, requestID = UUID()
        loadID = UUID(); isLoading = false; writeID = requestID; isWriting = true; error = nil; notice = nil
        defer { if writeID == requestID { isWriting = false; writeID = nil } }
        let result = try await access.perform(boundary: boundary, action: operation)
        guard writeID == requestID else { throw WorkshopError.identityChanged }
        return result
    }
}
