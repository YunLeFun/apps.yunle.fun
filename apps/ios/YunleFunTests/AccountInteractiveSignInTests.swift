import Foundation
import SwiftUI
import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

private let interactiveSignInNow = Date(timeIntervalSince1970: 1_800_000_000)

final class AccountInteractiveSignInTests: XCTestCase {
    func testAcceptedCommitIsRejectedAfterExternalAccountSelection() async throws {
        let session = try makeSession(ids: ["b"])
        let commit = try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        XCTAssertEqual(commit.userID, "a")
        try await session.select("b")
        await assertStale(commit, in: session)
    }

    func testReturningToTheSameUIDDoesNotReviveAnAcceptedCommit() async throws {
        let session = try makeSession(ids: ["b"])
        let commit = try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        try await session.select("b")
        try await session.select("a")
        await assertStale(commit, in: session)
    }

    func testNewLoginForTheSameUIDInvalidatesOnlyTheOldCommit() async throws {
        let session = try makeSession()
        let first = try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        let second = try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        XCTAssertNotEqual(first.attemptID, second.attemptID)
        XCTAssertGreaterThan(second.selectionGeneration, first.selectionGeneration)
        await assertStale(first, in: session)
        let current = try await session.overview(matching: second)
        XCTAssertEqual(current.activeID, "a")
    }

    func testProfileRefreshAndRestoreForTheSameUIDPreserveTheCommit() async throws {
        let session = try makeSession()
        let commit = try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        let accepted = try await session.overview(matching: commit)
        try await session.refreshProfile()
        try await session.restore()
        let refreshed = try await session.overview(matching: commit)
        XCTAssertEqual(refreshed.activeID, "a")
        XCTAssertGreaterThan(refreshed.revision, accepted.revision,
                             "Profile revisions do not represent a different interactive login")
    }

    @MainActor
    func testGuestPasswordContinuationReceivesThePublishedTargetSynchronously() async throws {
        let store = AccountStore(session: try makeSession())
        let continuation = guestContinuation(for: store)
        var successes: [AccountSignInSuccess] = []
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       continuation: continuation, onCommitted: { success in
            XCTAssertEqual(store.user?.id, "a")
            XCTAssertEqual(success.requestID, continuation.requestID)
            XCTAssertEqual(success.origin, continuation.origin)
            XCTAssertEqual(success.target, AccountRequestBoundary(uid: store.user?.id,
                                                                 generation: store.identityGeneration))
            XCTAssertTrue(store.isCurrent(success), "The synchronous callback receives an already valid proof")
            successes.append(success)
        })
        XCTAssertEqual(successes.count, 1)
        XCTAssertNotEqual(successes.first?.target.generation, continuation.origin.generation)
    }

    @MainActor
    func testGuestVerificationUsesTheSameContinuationContract() async throws {
        let store = AccountStore(session: try makeSession())
        let continuation = guestContinuation(for: store)
        let challenge = VerificationChallenge(address: .email("fixture@example.invalid"), id: "verified",
            isExistingUser: true, expiresAt: interactiveSignInNow.addingTimeInterval(60))
        var success: AccountSignInSuccess?
        try await store.verify(challenge, code: "123456", captcha: nil, continuation: continuation, onCommitted: { success = $0 })
        XCTAssertEqual(success?.requestID, continuation.requestID)
        XCTAssertEqual(success?.target.uid, "verified")
        XCTAssertEqual(store.user?.id, "verified")
    }

    @MainActor
    func testExpiredGuestOriginIsRejectedBeforeStartingAuthentication() async throws {
        let api = InteractiveSignInAPI()
        let store = AccountStore(session: try makeSession(api: api))
        let expired = AccountSignInContinuation(requestID: UUID(),
            origin: AccountRequestBoundary(uid: nil, generation: UUID()))
        var completed = false
        do {
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: expired, onCommitted: { _ in completed = true })
            XCTFail("An obsolete guest generation cannot start a continuation")
        } catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let count = await api.passwordSignInCount
        XCTAssertEqual(count, 0)
        XCTAssertFalse(completed)
        XCTAssertNil(store.user)
    }

    @MainActor
    func testAuthenticatedOriginCannotBeUsedAsAGuestContinuation() async throws {
        let api = InteractiveSignInAPI()
        let store = AccountStore(session: try makeSession(ids: ["a"], activeID: "a", api: api))
        await store.restore()
        let continuation = AccountSignInContinuation(requestID: UUID(),
            origin: AccountRequestBoundary(uid: "a", generation: store.identityGeneration))
        do {
            try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                           continuation: continuation)
            XCTFail("An account draft must not travel through the guest continuation")
        } catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let count = await api.passwordSignInCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.user?.id, "a")
    }

    @MainActor
    func testRestoreDoesNotCompleteGuestContinuationAndInvalidatesItsOrigin() async throws {
        let gate = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: gate, gatedToken: "login-a")
        let store = AccountStore(session: try makeSession(ids: ["b"], activeID: "b", api: api))
        let continuation = guestContinuation(for: store)
        var successes: [AccountSignInSuccess] = []
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { successes.append($0) })
        }
        await gate.waitUntilEntered()
        await store.restore()
        XCTAssertEqual(store.user?.id, "b")
        XCTAssertTrue(successes.isEmpty, "Restoring a saved account is not this login's success")
        await gate.open()
        do { try await login.value; XCTFail("The restored identity expired the guest origin") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertTrue(successes.isEmpty)
        XCTAssertEqual(store.user?.id, "a", "An expired continuation does not undo a committed login")
    }

    @MainActor
    func testCancelledLoginCannotCompleteFromALateUserResponse() async throws {
        let gate = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: gate, gatedToken: "login-a")
        let store = AccountStore(session: try makeSession(api: api))
        let continuation = guestContinuation(for: store)
        var completed = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await gate.waitUntilEntered()
        login.cancel()
        await store.cancelSignIn()
        await gate.open()
        do { try await login.value; XCTFail("A cancelled operation cannot issue a success receipt") }
        catch { XCTAssertTrue(error is CancellationError || error as? AccountError == .sessionChanged) }
        XCTAssertFalse(completed)
        XCTAssertNil(store.user)
    }

    @MainActor
    func testLateLoginCannotCompleteAfterAnotherInteractiveLoginWins() async throws {
        let gate = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: gate, gatedToken: "login-a")
        let store = AccountStore(session: try makeSession(api: api))
        let continuation = guestContinuation(for: store)
        var completed = false
        let oldLogin = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await gate.waitUntilEntered()
        try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil)
        await gate.open()
        do { try await oldLogin.value; XCTFail("An older login response cannot complete a newer identity") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(completed)
        XCTAssertEqual(store.user?.id, "b")
    }

    @MainActor
    func testOrdinaryLoginDoesNotMintAContinuationReceipt() async throws {
        let store = AccountStore(session: try makeSession())
        var completed = false
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       onCommitted: { _ in completed = true })
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertFalse(completed)
    }

    @MainActor
    func testAnotherLoginStartedAfterSnapshotReadExpiresTheOldContinuationBeforeEitherPublishes() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let secondUser = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: secondUser, gatedToken: "login-b")
        let store = AccountStore(session: try makeSession(api: api), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let continuation = guestContinuation(for: store)
        var completed = false
        let first = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await snapshots.gate.waitUntilEntered()
        let second = Task { @MainActor in
            try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil)
        }
        await secondUser.waitUntilEntered()
        XCTAssertNil(store.user, "Neither operation has published; the guest boundary still matches")
        XCTAssertEqual(store.identityGeneration, continuation.origin.generation)
        await snapshots.gate.open()
        do { try await first.value; XCTFail("Starting another login must revoke the earlier snapshot") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(completed)
        await secondUser.open()
        try await second.value
        XCTAssertEqual(store.user?.id, "b")
    }

    @MainActor
    func testStartingAccountSelectionExpiresAReadSnapshotEvenBeforeAnIdentityChangeIsPublished() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let continuation = guestContinuation(for: store)
        var completed = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await snapshots.gate.waitUntilEntered()
        do { try await store.select("unavailable"); XCTFail("This account is not stored") }
        catch { XCTAssertEqual(error as? AccountError, .signedOut) }
        XCTAssertNil(store.user)
        XCTAssertEqual(store.identityGeneration, continuation.origin.generation)
        await snapshots.gate.open()
        do { try await login.value; XCTFail("A newer selection intent must expire the prior continuation") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(completed)
    }

    @MainActor
    func testCancelAfterCommitDoesNotCompleteFromAnAlreadyReadSnapshot() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let continuation = guestContinuation(for: store)
        var completed = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await snapshots.gate.waitUntilEntered()
        await store.cancelSignIn()
        await snapshots.gate.open()
        do { try await login.value; XCTFail("A cancelled intent cannot complete a committed login") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(completed)
        XCTAssertEqual(store.user?.id, "a", "Cancelling the continuation cannot roll back the accepted session")
    }

    @MainActor
    func testTaskCancellationAfterCommitDoesNotIssueAContinuationReceipt() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let continuation = guestContinuation(for: store)
        var completed = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await snapshots.gate.waitUntilEntered()
        login.cancel()
        await snapshots.gate.open()
        do { try await login.value; XCTFail("Task cancellation must be checked after reading the snapshot") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(completed)
        XCTAssertEqual(store.user?.id, "a")
    }

    @MainActor
    func testKnownIdentityProfileRestoreDoesNotExpireAnOrdinaryMatchingLogin() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(ids: ["a"], activeID: "a"), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        await store.restore()
        let generation = store.identityGeneration
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        }
        await snapshots.gate.waitUntilEntered()
        await store.restore()
        await snapshots.gate.open()
        try await login.value
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(store.identityGeneration, generation)
    }

    @MainActor
    func testInitialRestoreOfAnAcceptedOrdinaryLoginDoesNotRejectThatLogin() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        }
        await snapshots.gate.waitUntilEntered()
        XCTAssertNil(store.user, "The first accepted login has not yet been published")
        let operationGeneration = store.selectionOperationGeneration
        await store.restore()
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertNotEqual(store.selectionOperationGeneration, operationGeneration,
                          "An unknown-identity restore still expires guest continuation proofs")
        await snapshots.gate.open()
        try await login.value
        XCTAssertEqual(store.user?.id, "a")
    }

    @MainActor
    func testInitialRestoreOfAnAcceptedLoginStillExpiresItsGuestContinuation() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let continuation = guestContinuation(for: store)
        var completed = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           continuation: continuation, onCommitted: { _ in completed = true })
        }
        await snapshots.gate.waitUntilEntered()
        XCTAssertNil(store.user)
        await store.restore()
        await snapshots.gate.open()
        do { try await login.value; XCTFail("Restoring the identity does not prove this guest continuation") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(completed)
        XCTAssertEqual(store.user?.id, "a")
    }

    @MainActor
    func testStartingSameUIDLoginImmediatelyExpiresAPreviousSuccessProof() async throws {
        let gate = InteractiveSignInGate()
        let api = InteractiveSignInAPI()
        let store = AccountStore(session: try makeSession(api: api))
        var proven: AccountSignInSuccess?
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       continuation: guestContinuation(for: store), onCommitted: { proven = $0 })
        let success = try XCTUnwrap(proven)
        XCTAssertTrue(store.isCurrent(success))
        let identityGeneration = store.identityGeneration
        let operationGeneration = store.selectionOperationGeneration
        await api.setUserGate(gate, token: "login-a")
        let second = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        }
        await gate.waitUntilEntered()
        XCTAssertEqual(store.identityGeneration, identityGeneration, "The UID has not changed")
        XCTAssertNotEqual(store.selectionOperationGeneration, operationGeneration)
        XCTAssertFalse(store.isCurrent(success), "A sheet dismissal cannot consume the old proof")
        await gate.open()
        try await second.value
        XCTAssertFalse(store.isCurrent(success))
    }

    @MainActor
    func testSameUIDProfileRestorePreservesTheSuccessProofAndOperationGeneration() async throws {
        let store = AccountStore(session: try makeSession())
        var proven: AccountSignInSuccess?
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       continuation: guestContinuation(for: store), onCommitted: { proven = $0 })
        let success = try XCTUnwrap(proven)
        let generation = store.selectionOperationGeneration
        await store.restore()
        XCTAssertEqual(store.selectionOperationGeneration, generation)
        XCTAssertTrue(store.isCurrent(success))
    }

    #if os(iOS)
    // Feedback navigation belongs to the iOS presentation layer. The account
    // continuation and cancellation contracts are tested above on both platforms.
    @MainActor
    func testRealStoreCommitRestoresFeedbackTextOnlyAfterActualSheetDismissal() async throws {
        let store = AccountStore(session: try makeSession())
        let flow = FeedbackLoginCoordinator()
        let origin = AccountRequestBoundary(uid: nil, generation: store.identityGeneration)
        let text = "问题 👩🏽‍💻\n步骤与实际结果\n" + String(repeating: "长", count: 510)
        XCTAssertTrue(flow.begin(text: text, origin: origin, isRestoring: store.isRestoring))
        let intent = try XCTUnwrap(flow.login)
        flow.didPresent(intent.id)
        var committed = false
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       continuation: intent.continuation, onCommitted: { success in
            let current = AccountRequestBoundary(uid: store.user?.id, generation: store.identityGeneration)
            committed = flow.committed(success, current: current, isUsable: store.user?.isUsable == true,
                                       proofIsCurrent: store.isCurrent(success))
            XCTAssertTrue(flow.path(current: current, isUsable: true,
                                    proofIsCurrent: store.isCurrent(success)).isEmpty,
                          "The synchronous authentication callback must not push beneath its sheet")
        })
        XCTAssertTrue(committed)
        let success = try XCTUnwrap(flow.success)
        let current = AccountRequestBoundary(uid: store.user?.id, generation: store.identityGeneration)
        flow.presentationEnded()
        XCTAssertTrue(flow.path(current: current, isUsable: true,
                                proofIsCurrent: store.isCurrent(success)).isEmpty)
        XCTAssertTrue(flow.didDismiss(current: current, isUsable: true, proofIsCurrent: store.isCurrent(success)))
        let route = try XCTUnwrap(flow.path(current: current, isUsable: true,
                                           proofIsCurrent: store.isCurrent(success)).first)
        XCTAssertEqual(flow.text(for: route, current: current, isUsable: true,
                                proofIsCurrent: store.isCurrent(success)), text)
        XCTAssertFalse(flow.didDismiss(current: current, isUsable: true, proofIsCurrent: store.isCurrent(success)))
    }

    @MainActor
    func testRealStoreSameUIDLoginHidesActiveFeedbackBeforeTheCoordinatorObserverRuns() async throws {
        let gate = InteractiveSignInGate()
        let api = InteractiveSignInAPI()
        let store = AccountStore(session: try makeSession(api: api))
        let flow = FeedbackLoginCoordinator()
        let origin = AccountRequestBoundary(uid: nil, generation: store.identityGeneration)
        XCTAssertTrue(flow.begin(text: "本次访客描述", origin: origin, isRestoring: false))
        let intent = try XCTUnwrap(flow.login)
        flow.didPresent(intent.id)
        try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                       continuation: intent.continuation, onCommitted: { success in
            let current = AccountRequestBoundary(uid: store.user?.id, generation: store.identityGeneration)
            XCTAssertTrue(flow.committed(success, current: current, isUsable: true,
                                         proofIsCurrent: store.isCurrent(success)))
        })
        let success = try XCTUnwrap(flow.success)
        let target = AccountRequestBoundary(uid: store.user?.id, generation: store.identityGeneration)
        XCTAssertTrue(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: store.isCurrent(success)))
        let route = try XCTUnwrap(flow.path(current: target, isUsable: true,
                                           proofIsCurrent: store.isCurrent(success)).first)
        await api.setUserGate(gate, token: "login-a")
        let next = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil)
        }
        await gate.waitUntilEntered()
        XCTAssertEqual(store.identityGeneration, target.generation)
        XCTAssertFalse(store.isCurrent(success))
        XCTAssertTrue(flow.path(current: target, isUsable: true,
                                proofIsCurrent: store.isCurrent(success)).isEmpty)
        XCTAssertNil(flow.text(for: route, current: target, isUsable: true,
                              proofIsCurrent: store.isCurrent(success)),
                     "The observer has not cancelled the coordinator, but its text is already inaccessible")
        await gate.open()
        try await next.value
        XCTAssertFalse(store.isCurrent(success))
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: false).isEmpty)
        flow.identityChanged(to: target, isUsable: true, proofIsCurrent: store.isCurrent(success))
        XCTAssertNil(flow.success)
    }
    #endif

    @MainActor
    func testOldStoreCancellationCannotInvalidateANewerAttemptOrItsSuccessProof() async throws {
        let oldUser = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: oldUser, gatedToken: "login-a")
        let store = AccountStore(session: try makeSession(api: api))
        let oldAttempt = UUID(), newAttempt = UUID()
        let oldLogin = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           attemptID: oldAttempt)
        }
        await oldUser.waitUntilEntered()
        var proven: AccountSignInSuccess?
        try await store.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                       continuation: guestContinuation(for: store), onCommitted: { proven = $0 },
                                       attemptID: newAttempt)
        let success = try XCTUnwrap(proven)
        XCTAssertEqual(success.attemptID, newAttempt)
        let generation = store.selectionOperationGeneration
        await store.cancelSignIn(attemptID: oldAttempt)
        XCTAssertEqual(store.selectionOperationGeneration, generation,
                       "An old view's delayed cancellation must not advance the new selection operation")
        XCTAssertTrue(store.isCurrent(success))
        await oldUser.open()
        do { try await oldLogin.value; XCTFail("The older login must remain superseded") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertEqual(store.user?.id, "b")
        XCTAssertTrue(store.isCurrent(success))
    }

    func testOldActorCancellationArrivingAfterNewUserRequestDoesNotCancelTheNewAttempt() async throws {
        let oldUser = InteractiveSignInGate(), newUser = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: oldUser, gatedToken: "login-a")
        let session = try makeSession(api: api)
        let oldAttempt = UUID(), newAttempt = UUID()
        let oldLogin = Task {
            try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                             attemptID: oldAttempt)
        }
        await oldUser.waitUntilEntered()
        await api.setUserGate(newUser, token: "login-b")
        let newLogin = Task {
            try await session.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                             attemptID: newAttempt)
        }
        await newUser.waitUntilEntered()
        // Model the Store check succeeding earlier, followed by a newer login
        // entering the actor before the delayed cancel message reaches it.
        await session.cancelSignIn(attemptID: oldAttempt)
        await newUser.open()
        let commit = try await newLogin.value
        XCTAssertEqual(commit.userID, "b")
        XCTAssertEqual(commit.attemptID, newAttempt)
        await oldUser.open()
        do { _ = try await oldLogin.value; XCTFail("The old response cannot replace the new login") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        let current = try await session.overview(matching: commit)
        XCTAssertEqual(current.activeID, "b")
    }

    @MainActor
    func testMatchingScopedStoreCancellationStillRejectsItsOwnLateResponse() async throws {
        let user = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: user, gatedToken: "login-a")
        let store = AccountStore(session: try makeSession(api: api))
        let attempt = UUID()
        var authenticated = false
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           attemptID: attempt, onAuthenticated: { authenticated = true })
        }
        await user.waitUntilEntered()
        let generation = store.selectionOperationGeneration
        await store.cancelSignIn(attemptID: attempt)
        XCTAssertNotEqual(store.selectionOperationGeneration, generation)
        await user.open()
        do { try await login.value; XCTFail("The matching attempt must be cancelled") }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged) }
        XCTAssertFalse(authenticated)
        XCTAssertNil(store.user)
    }

    @MainActor
    func testOrdinaryAuthenticationNotificationPrecedesCallerResumeAfterSnapshotAndRestore() async throws {
        let snapshots = InteractiveSignInSnapshotReader()
        let store = AccountStore(session: try makeSession(), signInOverview: { session, commit in
            try await snapshots.read(session, commit)
        })
        let origin = AccountRequestBoundary(uid: nil, generation: store.identityGeneration)
        let attempt = UUID()
        var callerResumed = false, continuationMinted = false
        var authenticatedCount = 0
        let login = Task { @MainActor in
            try await store.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                           onCommitted: { _ in continuationMinted = true }, attemptID: attempt,
                                           onAuthenticated: {
                XCTAssertFalse(callerResumed)
                XCTAssertEqual(store.user?.id, "a", "Notify for the actual accepted identity after publication")
                authenticatedCount += 1
            })
            callerResumed = true
        }
        await snapshots.gate.waitUntilEntered()
        XCTAssertEqual(authenticatedCount, 0)
        XCTAssertFalse(callerResumed)
        await store.restore()
        XCTAssertEqual(store.user?.id, "a")
        XCTAssertEqual(authenticatedCount, 0, "Restore itself cannot notify this interactive login's success")
        await snapshots.gate.open()
        try await login.value
        XCTAssertTrue(callerResumed)
        XCTAssertEqual(authenticatedCount, 1)
        XCTAssertFalse(continuationMinted)
        let unproven = AccountSignInSuccess(requestID: UUID(), attemptID: attempt, origin: origin,
            target: AccountRequestBoundary(uid: store.user?.id, generation: store.identityGeneration))
        XCTAssertFalse(store.isCurrent(unproven), "A normal login does not mint a feedback continuation proof")
    }

    @MainActor
    func testVerificationNotifiesAuthenticationBeforeTypedCommitUsingTheCallerAttempt() async throws {
        let store = AccountStore(session: try makeSession())
        let attempt = UUID()
        let continuation = guestContinuation(for: store)
        let challenge = VerificationChallenge(address: .email("fixture@example.invalid"), id: "verified",
            isExistingUser: true, expiresAt: interactiveSignInNow.addingTimeInterval(60))
        var events: [String] = []
        try await store.verify(challenge, code: "123456", captcha: nil, continuation: continuation,
                               onCommitted: { success in
            XCTAssertEqual(events, ["authenticated"])
            XCTAssertEqual(success.attemptID, attempt)
            XCTAssertTrue(store.isCurrent(success))
            events.append("committed")
        }, attemptID: attempt, onAuthenticated: {
            XCTAssertEqual(store.user?.id, "verified")
            events.append("authenticated")
        })
        XCTAssertEqual(events, ["authenticated", "committed"])
    }

    func testCancelledPasswordTaskEnteringTheActorLateCannotSupersedeANewerAttempt() async throws {
        let newUser = InteractiveSignInGate(), oldStart = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: newUser, gatedToken: "login-b")
        let session = try makeSession(api: api)
        let newAttempt = UUID()
        let newLogin = Task {
            try await session.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                             attemptID: newAttempt)
        }
        await newUser.waitUntilEntered()
        let oldLogin = Task {
            // This nonthrowing gate deliberately lets an already cancelled task
            // continue to the actor entry, rather than cancelling its wait.
            await oldStart.wait()
            return try await session.passwordSignIn(identifier: "a", password: "fixture", captcha: nil,
                                                    attemptID: UUID())
        }
        await oldStart.waitUntilEntered()
        oldLogin.cancel()
        await oldStart.open()
        do { _ = try await oldLogin.value; XCTFail("Cancellation must be checked before registering the old attempt") }
        catch { XCTAssertTrue(error is CancellationError) }
        let passwordCalls = await api.passwordSignInCount
        XCTAssertEqual(passwordCalls, 1, "The cancelled password request must not reach the authentication API")
        await newUser.open()
        let commit = try await newLogin.value
        XCTAssertEqual(commit.attemptID, newAttempt)
        let current = try await session.overview(matching: commit)
        XCTAssertEqual(current.activeID, "b")
    }

    func testCancelledVerificationTaskEnteringTheActorLateCannotSupersedeANewerAttempt() async throws {
        let newUser = InteractiveSignInGate(), oldStart = InteractiveSignInGate()
        let api = InteractiveSignInAPI(userGate: newUser, gatedToken: "login-b")
        let session = try makeSession(api: api)
        let newAttempt = UUID()
        let newLogin = Task {
            try await session.passwordSignIn(identifier: "b", password: "fixture", captcha: nil,
                                             attemptID: newAttempt)
        }
        await newUser.waitUntilEntered()
        let challenge = VerificationChallenge(address: .email("fixture@example.invalid"), id: "a",
            isExistingUser: true, expiresAt: interactiveSignInNow.addingTimeInterval(60))
        let oldLogin = Task {
            await oldStart.wait()
            return try await session.verify(challenge, code: "123456", captcha: nil, attemptID: UUID())
        }
        await oldStart.waitUntilEntered()
        oldLogin.cancel()
        await oldStart.open()
        do { _ = try await oldLogin.value; XCTFail("Cancellation must be checked before registering the old verification attempt") }
        catch { XCTAssertTrue(error is CancellationError) }
        let verificationCalls = await api.verificationCount
        XCTAssertEqual(verificationCalls, 0, "The cancelled verification must not reach the authentication API")
        await newUser.open()
        let commit = try await newLogin.value
        XCTAssertEqual(commit.attemptID, newAttempt)
        let current = try await session.overview(matching: commit)
        XCTAssertEqual(current.activeID, "b")
    }

    @MainActor
    private func guestContinuation(for store: AccountStore) -> AccountSignInContinuation {
        AccountSignInContinuation(requestID: UUID(),
            origin: AccountRequestBoundary(uid: nil, generation: store.identityGeneration))
    }

    private func assertStale(_ commit: AccountSignInCommit, in session: AccountSession,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await session.overview(matching: commit); XCTFail("A stale commit must be rejected", file: file, line: line) }
        catch { XCTAssertEqual(error as? AccountError, .sessionChanged, file: file, line: line) }
    }

    private func makeSession(ids: [String] = [], activeID: String? = nil,
                             api: InteractiveSignInAPI = InteractiveSignInAPI()) throws -> AccountSession {
        var state = AccountVaultState()
        state.activeID = activeID
        state.accounts = ids.map { id in
            SavedAccount(user: AccountUser(id: id), credential: AccountCredential(accessToken: "original-\(id)",
                refreshToken: "refresh-\(id)", expiresAt: interactiveSignInNow.addingTimeInterval(3600)))
        }
        let vault = InteractiveSignInVault(data: try JSONEncoder().encode(state))
        return AccountSession(api: api, vault: vault, now: { interactiveSignInNow })
    }
}

private final class InteractiveSignInVault: AccountVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    init(data: Data) { self.data = data }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ value: Data) throws { lock.lock(); defer { lock.unlock() }; data = value }
}

private actor InteractiveSignInGate {
    private var entered = false
    private var opened = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        entryWaiters.forEach { $0.resume() }; entryWaiters = []
        if !opened { await withCheckedContinuation { held.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func open() { opened = true; held.forEach { $0.resume() }; held = [] }
}

/// Holds only the first real matching snapshot before AccountStore resumes.
private actor InteractiveSignInSnapshotReader {
    let gate = InteractiveSignInGate()
    private var heldFirst = false
    func read(_ session: AccountSession, _ commit: AccountSignInCommit) async throws -> AccountOverview {
        let snapshot = try await session.overview(matching: commit)
        if !heldFirst {
            heldFirst = true
            await gate.wait()
        }
        return snapshot
    }
}

private actor InteractiveSignInAPI: AccountAuthenticating {
    private(set) var passwordSignInCount = 0
    private(set) var verificationCount = 0
    private var userGate: InteractiveSignInGate?
    private var gatedToken: String?
    init(userGate: InteractiveSignInGate? = nil, gatedToken: String? = nil) {
        self.userGate = userGate; self.gatedToken = gatedToken
    }
    func setUserGate(_ gate: InteractiveSignInGate, token: String) { userGate = gate; gatedToken = token }
    func passwordSignIn(identifier: String, password: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        passwordSignInCount += 1
        return tokens(for: identifier)
    }
    func verify(_ challenge: VerificationChallenge, code: String, deviceID: String, captcha: String?) async throws -> AuthTokenResponse {
        verificationCount += 1
        return tokens(for: challenge.id)
    }
    func user(accessToken: String, deviceID: String) async throws -> AccountUser {
        if accessToken == gatedToken { await userGate?.wait() }
        return AccountUser(id: String(accessToken.split(separator: "-").last!))
    }
    func refresh(_ refreshToken: String, deviceID: String) async throws -> AuthTokenResponse {
        tokens(for: String(refreshToken.split(separator: "-").last!))
    }
    func signOut(accessToken: String, deviceID: String) async throws { }
    func updateProfile(userID: String, name: String, description: String, accessToken: String, deviceID: String) async throws { }
    func sendVerification(address: VerificationAddress, deviceID: String, captcha: String?) async throws -> VerificationChallenge { throw AccountError.unavailable }
    func captcha(deviceID: String) async throws -> CaptchaImage { throw AccountError.unavailable }
    func verifyCaptcha(token: String, text: String, deviceID: String) async throws -> String { throw AccountError.unavailable }
    private func tokens(for id: String) -> AuthTokenResponse {
        AuthTokenResponse(accessToken: "login-\(id)", refreshToken: "refresh-\(id)", expiresIn: 3600, subject: id)
    }
}

#if os(iOS)
// This schedule is declared by the iOS LoginView, not the shared account layer.
final class VerificationResendTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testIdleLoginDoesNotScheduleRecurringRefreshes() {
        let schedule = VerificationResendTimeline(deadline: .distantPast)
        XCTAssertEqual(Array(schedule.entries(from: now, mode: .normal).prefix(10)), [now])
    }
    func testActiveCooldownIncludesItsExactExpiryAndThenStops() {
        let deadline = now.addingTimeInterval(2.5)
        let schedule = VerificationResendTimeline(deadline: deadline)
        let entries = Array(schedule.entries(from: now, mode: .normal).prefix(10))
        XCTAssertEqual(entries, [now, now.addingTimeInterval(1), now.addingTimeInterval(2), deadline])
        XCTAssertEqual(entries.map { max(0, Int(ceil(deadline.timeIntervalSince($0)))) }, [3, 2, 1, 0])
    }
    func testResumingAfterExpiryDoesNotRestartTheCountdown() {
        let deadline = now.addingTimeInterval(60), resumed = now.addingTimeInterval(65)
        let schedule = VerificationResendTimeline(deadline: deadline)
        XCTAssertEqual(Array(schedule.entries(from: resumed, mode: .lowFrequency).prefix(10)), [resumed])
    }
}
#endif
