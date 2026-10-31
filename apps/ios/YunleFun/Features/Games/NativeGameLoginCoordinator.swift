import Combine
import Foundation

enum NativeGameLaunchIntent: Equatable {
    case game(NativeGame, NativeGameMode)
    case room(NativeGameRoomIntent)
}

struct NativeGameLoginIntent: Identifiable {
    let id: UUID
    let origin: AccountRequestBoundary
    let action: NativeGameLaunchIntent
    var continuation: AccountSignInContinuation { .init(requestID: id, origin: origin) }
}

/// Login may finish after its sheet has been dismissed or the selected account
/// changed. Only the matching committed proof can consume the original intent.
@MainActor
final class NativeGameLoginCoordinator: ObservableObject {
    @Published private(set) var login: NativeGameLoginIntent?
    private var pending: NativeGameLoginIntent?
    private var presentedID: UUID?
    private(set) var success: AccountSignInSuccess?

    func begin(_ action: NativeGameLaunchIntent, origin: AccountRequestBoundary, isRestoring: Bool) {
        guard login == nil, presentedID == nil, origin.uid == nil, !isRestoring else { return }
        let request = NativeGameLoginIntent(id: UUID(), origin: origin, action: action)
        pending = request; login = request; success = nil
    }

    func didPresent(_ id: UUID) { if login?.id == id { presentedID = id } }

    func committed(_ proof: AccountSignInSuccess, current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) {
        guard let pending, pending.id == login?.id, presentedID == pending.id,
              proof.requestID == pending.id, proof.origin == pending.origin,
              proof.origin.uid == nil, proof.target.uid != nil, proof.target.generation != proof.origin.generation,
              current == proof.target, isUsable, proofIsCurrent else { return }
        success = proof
    }

    func presentationEnded() {
        login = nil
        if success == nil { pending = nil }
    }

    func consume(current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) -> NativeGameLaunchIntent? {
        defer { cancel(); presentedID = nil }
        guard let pending, presentedID == pending.id, let success,
              success.target == current, isUsable, proofIsCurrent else { return nil }
        return pending.action
    }

    func identityChanged(to current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) {
        if let success {
            if success.target != current || !isUsable || !proofIsCurrent { cancel() }
        } else if let pending, pending.origin != current { cancel() }
    }

    func cancel() { login = nil; pending = nil; success = nil }
}

/// A delayed tap belongs to the identity and selection operation that received
/// it. Only a reserved initial restore boundary may adopt one saved identity.
struct NativeGameDeferredLaunchCoordinator {
    enum Resolution: Equatable {
        case waiting, discarded
        case launch(NativeGameLaunchIntent)
    }
    private struct Pending {
        let action: NativeGameLaunchIntent
        var boundary: AccountRequestBoundary
        let selectionGeneration: UUID
        var mayAdoptRestoredIdentity: Bool
    }
    private var pending: Pending?

    static func waitsForCatalog(hasPlay: Bool, isLoading: Bool) -> Bool { !hasPlay && isLoading }

    mutating func enqueue(_ action: NativeGameLaunchIntent, boundary: AccountRequestBoundary,
                          selectionGeneration: UUID, isRestoring: Bool) {
        pending = Pending(action: action, boundary: boundary, selectionGeneration: selectionGeneration,
                          mayAdoptRestoredIdentity: boundary.uid == nil && isRestoring)
    }

    mutating func take(current: AccountRequestBoundary, selectionGeneration: UUID, isRestoring: Bool,
                       awaitingPresentationDismissal: Bool, hasPlay: Bool, catalogIsLoading: Bool) -> Resolution {
        guard var request = pending else { return .waiting }
        guard request.selectionGeneration == selectionGeneration else { cancel(); return .discarded }
        if request.boundary != current {
            guard request.mayAdoptRestoredIdentity, request.boundary.uid == nil, current.uid != nil,
                  request.boundary.generation != current.generation else { cancel(); return .discarded }
            request.boundary = current
            request.mayAdoptRestoredIdentity = false
        }
        // Close the exception even if restoring completed without selecting an
        // account. A later login cannot inherit an earlier anonymous tap.
        if !isRestoring { request.mayAdoptRestoredIdentity = false }
        pending = request
        guard !awaitingPresentationDismissal, !isRestoring,
              !Self.waitsForCatalog(hasPlay: hasPlay, isLoading: catalogIsLoading) else { return .waiting }
        cancel()
        return .launch(request.action)
    }

    mutating func cancel() { pending = nil }
}
