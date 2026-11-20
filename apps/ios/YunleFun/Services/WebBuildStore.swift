import Combine
import Foundation

@MainActor
final class WebBuildStore: ObservableObject {
    @Published private(set) var projects: [WebBuildSummary] = []
    @Published private(set) var project: WebBuildProject?
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var canCreate = false
    @Published private(set) var membershipRequired = false
    @Published private(set) var submitted = false
    @Published private(set) var inviteCode: String?
    private let access: AccountRequestAccess<PublishingError>
    private let service: WebBuildServing
    private var operationGeneration = 0
    private var refreshingRoom = false

    init(accounts: IdentityScopedAccountAuthorizing, service: WebBuildServing) {
        access = AccountRequestAccess(accounts: accounts)
        self.service = service
    }

    func loadList() async {
        await perform(operation: { try await self.service.projects(identity: $0) }) {
            self.projects = $0
            self.canCreate = true
        }
    }

    func loadProject(id: String) async {
        await perform(operation: { try await self.service.project(id: id, identity: $0) }) {
            self.applyProject($0)
        }
    }

    func observeRoom(id: String) async {
        while !Task.isCancelled {
            await refreshRoom(id: id)
            guard project?.id == id || isWorking else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }
    }

    private func refreshRoom(id: String) async {
        guard project?.id == id, !isWorking, !refreshingRoom else { return }
        refreshingRoom = true
        defer { refreshingRoom = false }
        let boundary = access.boundary
        let generation = operationGeneration
        do {
            let current = try await access.perform(boundary: boundary) { try await service.project(id: id, identity: $0) }
            guard !Task.isCancelled, access.isCurrent(boundary), operationGeneration == generation else { return }
            applyProject(current)
        } catch {
            guard !Task.isCancelled, access.isCurrent(boundary), operationGeneration == generation else { return }
            if let error = error as? PublishingError, [.notFound, .forbidden, .membershipRequired].contains(error) {
                applyError(error)
            }
        }
    }

    @discardableResult
    func changeRoom(_ action: WebBuildRoomAction) async -> Bool {
        let id = project?.id
        return await perform(operation: { try await self.service.room(action, projectID: id, identity: $0) }) { receipt in
            self.applyProject(receipt.project)
            if case .invite = action { self.inviteCode = receipt.inviteCode }
        }
    }

    @discardableResult
    func update(_ action: WebBuildEdit) async -> Bool {
        let current = project
        return await perform(operation: { try await self.service.update(action, project: current, identity: $0) }) {
            self.applyProject($0)
            switch action {
            case .generate, .withdraw: self.submitted = false
            case .publish: break
            }
        }
    }

    private func applyProject(_ current: WebBuildProject?) {
        if project?.id != current?.id || project?.room?.inviteExpiresAt != current?.room?.inviteExpiresAt {
            inviteCode = nil
        }
        if project?.revision != current?.revision { submitted = false }
        project = current
    }

    private func applyError(_ error: Error) {
        if let accessError = error as? PublishingError {
            if accessError == .membershipRequired || accessError == .forbidden {
                membershipRequired = true
                canCreate = false
                projects = []
            }
            if [.membershipRequired, .forbidden, .notFound].contains(accessError) {
                applyProject(nil)
            }
        }
        self.error = (error as? PublishingError) == .conflict
            ? "网页已有更新，请刷新后再试。"
            : PublishingError.message(for: error)
    }

    func submit(shortName: String) async {
        guard let project else { return }
        await perform(operation: { try await self.service.submit(project: project, shortName: shortName, identity: $0) }) { _ in
            self.submitted = true
        }
    }

    @discardableResult
    private func perform<Result>(
        operation: (AuthorizedAccount) async throws -> Result,
        apply: (Result) -> Void = { _ in }
    ) async -> Bool {
        guard !Task.isCancelled, !isWorking else { return false }
        let boundary = access.boundary
        guard boundary.uid != nil else { return false }
        operationGeneration &+= 1
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let result = try await access.perform(boundary: boundary, action: operation)
            guard access.isCurrent(boundary), !Task.isCancelled else { return false }
            membershipRequired = false
            apply(result)
            return true
        } catch {
            guard access.isCurrent(boundary), !Task.isCancelled else { return false }
            applyError(error)
            return false
        }
    }
}
