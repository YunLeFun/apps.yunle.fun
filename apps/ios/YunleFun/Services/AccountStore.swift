import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var overview = AccountOverview()
    @Published private(set) var isRestoring = false
    @Published private(set) var notice: String?
    @Published private(set) var identityGeneration = UUID()
    @Published private(set) var selectionOperationGeneration = UUID()
    private let session: AccountSession
    private let signInOverview: @Sendable (AccountSession, AccountSignInCommit) async throws -> AccountOverview
    private let identityDidChange: (String?) -> Void
    private var selectionOperationEpoch = 0
    private var activeSignInAttemptID: UUID?
    private var lastProvenSuccess: AccountSignInSuccess?

    init(session: AccountSession = AccountSession(),
         signInOverview: (@Sendable (AccountSession, AccountSignInCommit) async throws -> AccountOverview)? = nil,
         identityDidChange: @escaping (String?) -> Void = { _ in }) {
        self.session = session
        self.signInOverview = signInOverview ?? { session, commit in
            try await session.overview(matching: commit)
        }
        self.identityDidChange = identityDidChange
    }

    var user: AccountUser? { overview.activeUser }

    func isCurrent(_ success: AccountSignInSuccess) -> Bool {
        lastProvenSuccess == success && user?.isUsable == true
            && success.target == AccountRequestBoundary(uid: user?.id, generation: identityGeneration)
    }

    func restore() async {
        guard !isRestoring else { return }
        // An initial restore can choose a saved identity, so it expires guest
        // continuation proofs. It must not reject an ordinary login whose
        // accepted identity is merely being published/refreshed by this restore.
        if user == nil { _ = beginSelectionOperation(advancingSelectionEpoch: false) }
        isRestoring = true
        defer { isRestoring = false }
        await publish()
        do {
            try await session.restore()
            notice = nil
        } catch is CancellationError { return }
        catch AccountError.sessionChanged { return }
        catch { notice = AccountError.message(for: error) }
        await publish()
    }

    func passwordSignIn(identifier: String, password: String, captcha: String?,
                        continuation: AccountSignInContinuation? = nil,
                        onCommitted: ((AccountSignInSuccess) -> Void)? = nil,
                        attemptID: UUID? = nil, onAuthenticated: (() -> Void)? = nil) async throws {
        try checkContinuation(continuation)
        let epoch = beginSelectionOperation()
        let attempt = attemptID ?? UUID()
        activeSignInAttemptID = attempt
        let continuationGeneration = selectionOperationGeneration
        let commit = try await session.passwordSignIn(identifier: identifier, password: password, captcha: captcha,
                                                       attemptID: attempt)
        try await publishSignIn(commit, epoch: epoch, continuationGeneration: continuationGeneration,
                                continuation: continuation, onCommitted: onCommitted, onAuthenticated: onAuthenticated)
    }

    func sendVerification(address: VerificationAddress, captcha: String?) async throws -> VerificationChallenge {
        try await session.sendVerification(address: address, captcha: captcha)
    }

    func verify(_ challenge: VerificationChallenge, code: String, captcha: String?,
                continuation: AccountSignInContinuation? = nil,
                onCommitted: ((AccountSignInSuccess) -> Void)? = nil,
                attemptID: UUID? = nil, onAuthenticated: (() -> Void)? = nil) async throws {
        try checkContinuation(continuation)
        let epoch = beginSelectionOperation()
        let attempt = attemptID ?? UUID()
        activeSignInAttemptID = attempt
        let continuationGeneration = selectionOperationGeneration
        let commit = try await session.verify(challenge, code: code, captcha: captcha, attemptID: attempt)
        try await publishSignIn(commit, epoch: epoch, continuationGeneration: continuationGeneration,
                                continuation: continuation, onCommitted: onCommitted, onAuthenticated: onAuthenticated)
    }

    func cancelSignIn(attemptID: UUID? = nil) async {
        if let attemptID, activeSignInAttemptID != attemptID { return }
        _ = beginSelectionOperation()
        // The actor checks again: another login may start while this call waits
        // to enter AccountSession after the Store-side check has succeeded.
        await session.cancelSignIn(attemptID: attemptID)
    }

    func authorization(forceRefresh: Bool = false) async throws -> AuthorizedAccount {
        do {
            let identity = try await session.authorization(forceRefresh: forceRefresh)
            await publish()
            guard user?.id == identity.userID else { throw AccountError.sessionChanged }
            return identity
        } catch {
            await publish()
            throw error
        }
    }

    func select(_ id: String) async throws {
        _ = beginSelectionOperation()
        try await session.select(id)
        await publish()
        await restore()
    }

    func remove(_ id: String) async throws {
        _ = beginSelectionOperation()
        let revocation = try await session.remove(id)
        // Clear private data and close identity-bound WebViews immediately;
        // a slow/offline remote sign-out must not delay the local transition.
        await publish()
        let revoked = await revocation.value
        notice = revoked ? nil : "已在此设备退出，暂时未能同步退出状态。"
    }

    func updateProfile(name: String, description: String) async throws {
        do {
            try await session.updateProfile(name: name, description: description)
            await publish()
        } catch {
            await publish()
            throw error
        }
    }

    func captcha() async throws -> CaptchaImage { try await session.captcha() }
    func verifyCaptcha(token: String, text: String) async throws -> String {
        try await session.verifyCaptcha(token: token, text: text)
    }

    private func publish() async {
        do {
            let next = try await session.overview()
            apply(next)
        } catch { notice = AccountError.message(for: error) }
    }

    private func publishSignIn(_ commit: AccountSignInCommit, epoch: Int, continuationGeneration: UUID,
                               continuation: AccountSignInContinuation?,
                               onCommitted: ((AccountSignInSuccess) -> Void)?,
                               onAuthenticated: (() -> Void)?) async throws {
        do {
            let next = try await signInOverview(session, commit)
            try checkContinuation(continuation)
            guard epoch == selectionOperationEpoch, activeSignInAttemptID == commit.attemptID,
                  next.activeID == commit.userID,
                  next.activeUser?.isUsable == true,
                  continuation == nil || continuationGeneration == selectionOperationGeneration else {
                throw AccountError.sessionChanged
            }
            // Keep publication and the continuation result in one MainActor turn.
            // A view rebuilt for this identity cannot substitute a later user.
            if next.revision >= overview.revision {
                apply(next)
            } else {
                // A newer profile for the same identity may already be visible.
                // Do not replace it with this earlier, matching login snapshot.
                guard overview.activeID == commit.userID, user?.isUsable == true else {
                    throw AccountError.sessionChanged
                }
            }
            notice = nil
            try Task.checkCancellation()
            onAuthenticated?()
            if let continuation {
                let success = AccountSignInSuccess(requestID: continuation.requestID, attemptID: commit.attemptID,
                    origin: continuation.origin,
                    target: AccountRequestBoundary(uid: commit.userID, generation: identityGeneration))
                lastProvenSuccess = success
                onCommitted?(success)
            }
        } catch {
            // Cancellation or an expired continuation does not roll back a login
            // already committed by the session. Publish its latest state only.
            await publish()
            throw error
        }
    }

    private func checkContinuation(_ continuation: AccountSignInContinuation?) throws {
        try Task.checkCancellation()
        guard let continuation else { return }
        guard continuation.origin.uid == nil, user == nil,
              continuation.origin == AccountRequestBoundary(uid: user?.id, generation: identityGeneration) else {
            throw AccountError.sessionChanged
        }
    }

    private func beginSelectionOperation(advancingSelectionEpoch: Bool = true) -> Int {
        if advancingSelectionEpoch {
            selectionOperationEpoch += 1
            activeSignInAttemptID = nil
        }
        lastProvenSuccess = nil
        selectionOperationGeneration = UUID()
        return selectionOperationEpoch
    }

    private func apply(_ next: AccountOverview) {
        guard next.revision >= overview.revision else { return }
        if next.activeID != overview.activeID {
            identityGeneration = UUID()
            identityDidChange(next.activeID)
        }
        overview = next
    }
}
