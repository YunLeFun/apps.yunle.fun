import Foundation

/// Proof of the particular interactive login accepted by AccountSession.
/// This contains no credentials and is not an authorization to make requests.
struct AccountSignInCommit: Equatable, Sendable {
    let attemptID: UUID
    let userID: String
    let selectionGeneration: Int
}

struct AccountSignInContinuation: Equatable {
    let requestID: UUID
    let origin: AccountRequestBoundary
}

struct AccountSignInSuccess: Equatable {
    let requestID: UUID
    let attemptID: UUID
    let origin: AccountRequestBoundary
    let target: AccountRequestBoundary
}
