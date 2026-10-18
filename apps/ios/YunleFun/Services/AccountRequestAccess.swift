import Foundation

@MainActor
protocol IdentityScopedAccountAuthorizing: AccountAuthorizing { var identityGeneration: UUID { get } }
extension AccountStore: IdentityScopedAccountAuthorizing {}

struct AccountRequestBoundary: Equatable {
    let uid: String?
    let generation: UUID
}
protocol AccountRequestFailure: Error {
    static var identityChanged: Self { get }
    var isUnauthorized: Bool { get }
}
extension CommunityError: AccountRequestFailure { var isUnauthorized: Bool { self == .unauthorized } }

// The generation detects A → B → A even if SwiftUI coalesces both identity updates.
@MainActor
final class AccountRequestAccess<Failure: AccountRequestFailure> {
    let accounts: IdentityScopedAccountAuthorizing
    init(accounts: IdentityScopedAccountAuthorizing) { self.accounts = accounts }
    var boundary: AccountRequestBoundary { AccountRequestBoundary(uid: accounts.user?.id, generation: accounts.identityGeneration) }
    func isCurrent(_ boundary: AccountRequestBoundary) -> Bool { self.boundary == boundary }
    func perform<T>(boundary: AccountRequestBoundary, action: (AuthorizedAccount) async throws -> T) async throws -> T {
        guard let uid = boundary.uid, accounts.user?.isUsable == true, isCurrent(boundary) else { throw Failure.identityChanged }
        var identity = try await accounts.authorization(forceRefresh: false)
        try check(boundary, identity: identity, uid: uid)
        let result: T
        do { result = try await action(identity) }
        catch let error as Failure where error.isUnauthorized {
            try check(boundary, identity: identity, uid: uid)
            identity = try await accounts.authorization(forceRefresh: true)
            try check(boundary, identity: identity, uid: uid)
            result = try await action(identity)
        }
        try check(boundary, identity: identity, uid: uid)
        return result
    }
    private func check(_ boundary: AccountRequestBoundary, identity: AuthorizedAccount, uid: String) throws {
        guard !Task.isCancelled, isCurrent(boundary), identity.userID == uid else { throw Failure.identityChanged }
    }
}
