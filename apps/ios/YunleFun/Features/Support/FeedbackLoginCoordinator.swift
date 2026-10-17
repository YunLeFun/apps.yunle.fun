import SwiftUI

struct FeedbackLoginIntent: Identifiable, Equatable {
    let id: UUID
    let origin: AccountRequestBoundary
    let text: String

    var continuation: AccountSignInContinuation { .init(requestID: id, origin: origin) }
}

struct FeedbackResumeRoute: Hashable { let id: UUID }

/// Lives above Me's identity reset. Only an explicit, matching login commit
/// can move the user's text into a fresh account-scoped feedback destination.
@MainActor
final class FeedbackLoginCoordinator: ObservableObject {
    private struct Draft {
        let id: UUID
        let success: AccountSignInSuccess
        let text: String
        var target: AccountRequestBoundary { success.target }
    }
    private enum State {
        case idle, pending(FeedbackLoginIntent), ready(Draft), active(Draft)
    }
    private var state = State.idle
    private var presentedID: UUID?
    @Published private(set) var login: FeedbackLoginIntent?
    @Published private var resumePath: [FeedbackResumeRoute] = []

    var success: AccountSignInSuccess? {
        switch state { case .ready(let draft), .active(let draft): return draft.success; default: return nil }
    }

    @discardableResult
    func begin(text: String, origin: AccountRequestBoundary, isRestoring: Bool) -> Bool {
        guard case .idle = state, presentedID == nil, origin.uid == nil, !isRestoring else { return false }
        let intent = FeedbackLoginIntent(id: UUID(), origin: origin, text: text)
        state = .pending(intent); login = intent
        return true
    }

    func didPresent(_ id: UUID) {
        guard login?.id == id else { return }
        presentedID = id
    }

    @discardableResult
    func committed(_ success: AccountSignInSuccess, current: AccountRequestBoundary, isUsable: Bool,
                   proofIsCurrent: Bool) -> Bool {
        guard case .pending(let intent) = state, login?.id == intent.id, presentedID == intent.id,
              success.requestID == intent.id, success.origin == intent.origin,
              success.origin.uid == nil, success.target.uid != nil,
              success.target.generation != success.origin.generation,
              success.target == current, isUsable, proofIsCurrent else { return false }
        state = .ready(Draft(id: intent.id, success: success, text: intent.text))
        return true
    }

    // A system swipe or LoginView.dismiss changes the item before onDismiss.
    // Only a committed result survives that presentation change.
    func presentationEnded() {
        login = nil
        if case .pending = state { state = .idle }
    }

    @discardableResult
    func didDismiss(current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) -> Bool {
        guard let dismissedID = presentedID else { return false }
        presentedID = nil
        presentationEnded()
        guard case .ready(let draft) = state, draft.id == dismissedID else { return false }
        guard draft.target == current, isUsable, proofIsCurrent else { cancel(); return false }
        // Consume before changing the path: duplicate dismiss/callback events
        // cannot create another destination or revive this draft after Back.
        state = .active(draft)
        resumePath = [FeedbackResumeRoute(id: draft.id)]
        return true
    }

    func identityChanged(to current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) {
        switch state {
        case .idle: break
        case .pending(let intent): if intent.origin != current { cancel() }
        case .ready(let draft), .active(let draft):
            if draft.target != current || !isUsable || !proofIsCurrent { cancel() }
        }
    }

    func path(current: AccountRequestBoundary, isUsable: Bool, proofIsCurrent: Bool) -> [FeedbackResumeRoute] {
        guard case .active(let draft) = state, draft.target == current, isUsable, proofIsCurrent else { return [] }
        return resumePath
    }

    func updatePath(_ path: [FeedbackResumeRoute], stack: AccountRequestBoundary, current: AccountRequestBoundary,
                    isUsable: Bool, proofIsCurrent: Bool) {
        // An old NavigationStack can emit its final empty path during .id reset.
        guard stack == current, case .active(let draft) = state else { return }
        guard draft.target == current, isUsable, proofIsCurrent else { cancel(); return }
        if path.isEmpty { cancel() }
        // The continuation creates one known route; arbitrary paths are ignored.
    }

    func text(for route: FeedbackResumeRoute, current: AccountRequestBoundary, isUsable: Bool,
              proofIsCurrent: Bool) -> String? {
        guard case .active(let draft) = state, draft.id == route.id,
              draft.target == current, isUsable, proofIsCurrent, resumePath.contains(route) else { return nil }
        return draft.text
    }

    func cancel() {
        state = .idle; login = nil; resumePath = []
    }
}

private struct FeedbackLoginRequestKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var requestFeedbackLogin: ((String) -> Void)? {
        get { self[FeedbackLoginRequestKey.self] }
        set { self[FeedbackLoginRequestKey.self] = newValue }
    }
}
