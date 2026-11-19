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
    private let access: AccountRequestAccess<PublishingError>
    private let service: WebBuildServing

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
            self.project = $0
        }
    }

    @discardableResult
    func update(_ action: WebBuildEdit) async -> Bool {
        let current = project
        return await perform(operation: { try await self.service.update(action, project: current, identity: $0) }) {
            self.project = $0
            switch action {
            case .generate, .withdraw: self.submitted = false
            case .publish: break
            }
        }
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
            if (error as? PublishingError) == .membershipRequired {
                membershipRequired = true
                canCreate = false
                projects = []
                project = nil
                submitted = false
            }
            self.error = PublishingError.message(for: error)
            return false
        }
    }
}
