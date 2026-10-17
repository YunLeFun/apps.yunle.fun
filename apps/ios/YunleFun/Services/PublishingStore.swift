import Combine
import Foundation

struct ApplicationEditBase: Equatable {
    let id: String
    let revision: String?
    let writeVersion: String?
    let updatedAt: Double
    init(_ app: ManagedApplication) { id = app.id; revision = app.revisionID; updatedAt = app.updatedAt; writeVersion = app.writeVersion }
}
struct PendingPublicationReload { let name: String; let madePublic: Bool }
@MainActor
final class PublishingStore: ObservableObject {
    @Published private var records: [ManagedApplication] = []
    @Published private var accessRecord: PublishingAccess?
    @Published private var pendingRecords: [String: PendingPublicationReload] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    private let access: AccountRequestAccess<PublishingError>
    private let service: PublishingServing
    private let workshops: WorkshopServing
    private var loadedBoundary: AccountRequestBoundary?
    private var loadID = UUID()
    private var writeID: UUID?
    init(accounts: IdentityScopedAccountAuthorizing, service: PublishingServing = PublishingService(), workshops: WorkshopServing = WorkshopService()) {
        access = AccountRequestAccess(accounts: accounts); self.service = service; self.workshops = workshops
    }
    var hasLoaded: Bool { loadedBoundary.map(access.isCurrent) ?? false }
    var applications: [ManagedApplication] { hasLoaded ? records : [] }
    var publishingAccess: PublishingAccess? { hasLoaded ? accessRecord : nil }
    var canSubmit: Bool { publishingAccess?.canSubmitFirstParty == true }
    func application(id: String) -> ManagedApplication? { applications.first { $0.id == id } }
    func pending(id: String) -> PendingPublicationReload? { hasLoaded ? pendingRecords[id] : nil }
    func refresh() async {
        guard !isWriting else { return }
        let boundary = access.boundary, requestID = UUID(); loadID = requestID; isLoading = true; error = nil
        defer { if loadID == requestID { isLoading = false } }
        guard boundary.uid != nil else { records = []; accessRecord = nil; pendingRecords = [:]; loadedBoundary = nil; return }
        do {
            let result = try await access.perform(boundary: boundary) { identity in
                async let apps = self.service.applications(identity: identity)
                async let access = self.service.access(identity: identity)
                return try await (apps, access)
            }
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            records = result.0; accessRecord = result.1; loadedBoundary = boundary; pendingRecords = [:]
        } catch {
            guard loadID == requestID, access.isCurrent(boundary), !Task.isCancelled else { return }
            self.error = PublishingError.message(for: error)
        }
    }
    func save(_ draft: ApplicationDraft, base: ApplicationEditBase?, generation: UUID) async throws -> ManagedApplication {
        let result = try await write(generation: generation) { identity in
            try await self.checkRemote(base, identity: identity)
            try self.checkGeneration(generation)
            if draft.audience == .workshop {
                let workshop = try await self.workshops.mine(identity: identity)
                try self.checkGeneration(generation)
                guard workshop != nil else { throw PublishingError.invalidInput }
            }
            return try await self.service.save(id: base?.id, draft: draft, writeVersion: base?.writeVersion, identity: identity)
        }
        records.removeAll { $0.id == result.id }; records.insert(result, at: 0); loadedBoundary = access.boundary
        notice = "当前版本已保存。投稿云乐坊需要另外确认。"
        return result
    }
    func submit(base: ApplicationEditBase, makePublic: Bool, shortName: String, generation: UUID) async throws {
        guard let current = application(id: base.id), current.marketState.action != nil else { throw PublishingError.conflict }
        _ = try await write(generation: generation) { identity in
            try await self.checkRemote(base, identity: identity)
            try self.checkGeneration(generation)
            return try await self.service.submit(id: base.id, makePublic: makePublic, shortName: shortName, writeVersion: base.writeVersion!, identity: identity)
        }
        records.removeAll { $0.id == base.id }
        pendingRecords[base.id] = PendingPublicationReload(name: current.application.name, madePublic: makePublic)
        notice = makePublic ? "已设为公开并投稿云乐坊，等待审核。" : "已投稿云乐坊，等待审核。"
        await refresh()
    }
    func delist(base: ApplicationEditBase, generation: UUID) async throws {
        try await write(generation: generation) { identity in
            try await self.checkRemote(base, identity: identity)
            try self.checkGeneration(generation)
            try await self.service.delist(id: base.id, writeVersion: base.writeVersion!, identity: identity)
        }
        records.removeAll { $0.id == base.id }
        notice = "作品已下架，提交与审核记录仍保留。"
    }
    func upload(png: Data, role: ApplicationIconRole, generation: UUID) async throws -> String {
        try await write(generation: generation) { try await self.service.upload(png: png, role: role, identity: $0) }
    }
    private func checkGeneration(_ generation: UUID) throws {
        guard access.boundary.generation == generation, !Task.isCancelled else { throw PublishingError.identityChanged }
    }
    private func checkRemote(_ base: ApplicationEditBase?, identity: AuthorizedAccount) async throws {
        guard let base else { return }
        guard let version = base.writeVersion, PublishingValue.writeVersion(version) else { throw PublishingError.unsupportedServer }
        guard let current = try await service.applications(identity: identity).first(where: { $0.id == base.id }),
              current.hasCurrentMetadata, ApplicationEditBase(current) == base else { throw PublishingError.conflict }
    }
    private func write<Result>(generation: UUID, operation: (AuthorizedAccount) async throws -> Result) async throws -> Result {
        guard access.boundary.generation == generation else { throw PublishingError.identityChanged }
        guard canSubmit else { throw PublishingError.forbidden }
        guard publishingAccess?.writePreconditionVersion == 1 else { throw PublishingError.unsupportedServer }
        guard !isWriting else { throw PublishingError.throttled }
        let boundary = access.boundary, requestID = UUID()
        loadID = UUID(); isLoading = false; writeID = requestID; isWriting = true; error = nil; notice = nil
        defer { if writeID == requestID { isWriting = false; writeID = nil } }
        let result = try await access.perform(boundary: boundary, action: operation)
        guard writeID == requestID else { throw PublishingError.identityChanged }
        return result
    }
}
