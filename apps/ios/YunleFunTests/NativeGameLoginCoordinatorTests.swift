import XCTest
@testable import YunleFun

@MainActor
final class NativeGameLoginCoordinatorTests: XCTestCase {
    func testCommittedLoginPreservesExactIntentAndConsumesOnlyOnceAfterDismissal() throws {
        let flow = NativeGameLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        let proof = success(intent, target: target)
        flow.committed(proof, current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertEqual(flow.success, proof)
        flow.identityChanged(to: target, isUsable: true, proofIsCurrent: true)
        flow.presentationEnded()
        XCTAssertNil(flow.login)
        XCTAssertEqual(flow.consume(current: target, isUsable: true, proofIsCurrent: true), intent.action)
        XCTAssertNil(flow.consume(current: target, isUsable: true, proofIsCurrent: true))
        XCTAssertNil(flow.success)
    }

    func testCancelAndInteractiveDismissRejectLateSuccessAndOldIntent() throws {
        for cancel in [true, false] {
            let flow = NativeGameLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
            let old = try begin(flow, origin: origin)
            if cancel { flow.cancel() } else { flow.presentationEnded() }
            flow.committed(success(old, target: target), current: target, isUsable: true, proofIsCurrent: true)
            XCTAssertNil(flow.success)
            XCTAssertNil(flow.consume(current: target, isUsable: true, proofIsCurrent: true))
            let next = try begin(flow, origin: origin)
            XCTAssertNotEqual(old.id, next.id)
            flow.committed(success(old, target: target), current: target, isUsable: true, proofIsCurrent: true)
            XCTAssertNil(flow.success)
            flow.committed(success(next, target: target), current: target, isUsable: true, proofIsCurrent: true)
            flow.presentationEnded()
            XCTAssertEqual(flow.consume(current: target, isUsable: true, proofIsCurrent: true), next.action)
        }
    }

    func testCancelledPresentedSheetCannotBeReplacedBeforeDismissal() throws {
        let flow = NativeGameLoginCoordinator(), origin = boundary(nil)
        _ = try begin(flow, origin: origin)
        flow.cancel()
        flow.begin(try action(), origin: origin, isRestoring: false)
        XCTAssertNil(flow.login)
        XCTAssertNil(flow.consume(current: origin, isUsable: false, proofIsCurrent: false))
        flow.begin(try action(), origin: origin, isRestoring: false)
        XCTAssertNotNil(flow.login)
    }

    func testCancellationBeforePresentationDoesNotReserveModalOrAcceptOldDidPresent() throws {
        let flow = NativeGameLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        flow.begin(try action(), origin: origin, isRestoring: false)
        let old = try XCTUnwrap(flow.login)
        flow.cancel()
        flow.begin(try action(), origin: origin, isRestoring: false)
        let next = try XCTUnwrap(flow.login)
        flow.didPresent(old.id)
        flow.committed(success(next, target: target), current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertNil(flow.success)
        flow.didPresent(next.id)
        flow.committed(success(next, target: target), current: target, isUsable: true, proofIsCurrent: true)
        flow.presentationEnded()
        XCTAssertEqual(flow.consume(current: target, isUsable: true, proofIsCurrent: true), next.action)
    }

    func testUnrelatedRequestOriginTargetAndExpiredProofCannotCommit() throws {
        let flow = NativeGameLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        let wrongRequest = AccountSignInSuccess(requestID: UUID(), attemptID: UUID(), origin: origin, target: target)
        let wrongOrigin = AccountSignInSuccess(requestID: intent.id, attemptID: UUID(), origin: boundary(nil), target: target)
        let sameGeneration = AccountRequestBoundary(uid: "alice", generation: origin.generation)
        for candidate in [wrongRequest, wrongOrigin, success(intent, target: sameGeneration)] {
            flow.committed(candidate, current: candidate.target, isUsable: true, proofIsCurrent: true)
            XCTAssertNil(flow.success)
        }
        let proof = success(intent, target: target)
        flow.committed(proof, current: boundary("bob"), isUsable: true, proofIsCurrent: true)
        XCTAssertNil(flow.success)
        flow.committed(proof, current: target, isUsable: false, proofIsCurrent: true)
        XCTAssertNil(flow.success)
        flow.committed(proof, current: target, isUsable: true, proofIsCurrent: false)
        XCTAssertNil(flow.success)
        flow.committed(proof, current: target, isUsable: true, proofIsCurrent: true)
        flow.presentationEnded()
        XCTAssertNil(flow.consume(current: target, isUsable: true, proofIsCurrent: false))
    }

    func testAccountRoundTripAndExternalRestoreCannotReplayIntent() throws {
        let flow = NativeGameLoginCoordinator(), origin = boundary(nil), alice = boundary("alice")
        let intent = try begin(flow, origin: origin)
        flow.committed(success(intent, target: alice), current: alice, isUsable: true, proofIsCurrent: true)
        let bob = boundary("bob")
        flow.identityChanged(to: bob, isUsable: true, proofIsCurrent: false)
        let returnedAlice = boundary("alice")
        flow.identityChanged(to: returnedAlice, isUsable: true, proofIsCurrent: true)
        flow.presentationEnded()
        XCTAssertNil(flow.consume(current: returnedAlice, isUsable: true, proofIsCurrent: true))
        let restored = NativeGameLoginCoordinator()
        let guest = boundary(nil)
        let pending = try begin(restored, origin: guest)
        restored.identityChanged(to: alice, isUsable: true, proofIsCurrent: false)
        restored.committed(success(pending, target: alice), current: alice, isUsable: true, proofIsCurrent: true)
        restored.presentationEnded()
        XCTAssertNil(restored.consume(current: alice, isUsable: true, proofIsCurrent: true))
    }

    func testCancelAfterCommitAndSameUIDNewGenerationPreventContinuation() throws {
        for cancel in [true, false] {
            let flow = NativeGameLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
            let intent = try begin(flow, origin: origin)
            flow.committed(success(intent, target: target), current: target, isUsable: true, proofIsCurrent: true)
            if cancel { flow.cancel() }
            flow.presentationEnded()
            XCTAssertNil(flow.consume(current: cancel ? target : boundary("alice"), isUsable: true, proofIsCurrent: true))
        }
    }

    func testSignedInAndRestoringOriginsDoNotCreateGuestLogin() throws {
        let flow = NativeGameLoginCoordinator()
        flow.begin(try action(), origin: boundary("alice"), isRestoring: false)
        XCTAssertNil(flow.login)
        flow.begin(try action(), origin: boundary(nil), isRestoring: true)
        XCTAssertNil(flow.login)
    }

    private func boundary(_ uid: String?) -> AccountRequestBoundary { .init(uid: uid, generation: UUID()) }
    private func action() throws -> NativeGameLaunchIntent { .room(try NativeGameRoomIntent(input: "AB23CD", role: .spectator)) }
    private func begin(_ flow: NativeGameLoginCoordinator, origin: AccountRequestBoundary) throws -> NativeGameLoginIntent {
        flow.begin(try action(), origin: origin, isRestoring: false)
        let intent = try XCTUnwrap(flow.login)
        flow.didPresent(intent.id)
        return intent
    }
    private func success(_ intent: NativeGameLoginIntent, target: AccountRequestBoundary) -> AccountSignInSuccess {
        .init(requestID: intent.id, attemptID: UUID(), origin: intent.origin, target: target)
    }
}
