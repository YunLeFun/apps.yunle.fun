import XCTest
@testable import YunleFun

@MainActor
final class FeedbackLoginCoordinatorTests: XCTestCase {
    func testExplicitCommitWaitsForActualDismissAndTransfersExactTextOnlyOnce() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let raw = "问题 👩🏽‍💻\n步骤与实际结果\n" + String(repeating: "长", count: 510)
        let intent = try begin(flow, origin: origin, text: raw)
        let result = success(intent, target: target)
        XCTAssertTrue(flow.committed(result, current: target, isUsable: true, proofIsCurrent: true))
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: true).isEmpty)
        flow.identityChanged(to: target, isUsable: true, proofIsCurrent: true)
        flow.presentationEnded()
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: true).isEmpty,
                      "Removing the sheet item is not the system's dismissal completion")
        XCTAssertTrue(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
        let route = try XCTUnwrap(flow.path(current: target, isUsable: true, proofIsCurrent: true).first)
        XCTAssertEqual(flow.text(for: route, current: target, isUsable: true, proofIsCurrent: true), raw,
                       "The upload length limit must not truncate a user's contact draft")
        XCTAssertFalse(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
        XCTAssertFalse(flow.committed(result, current: target, isUsable: true, proofIsCurrent: true))
        flow.updatePath([], stack: target, current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertNil(flow.text(for: route, current: target, isUsable: true, proofIsCurrent: true))
        XCTAssertFalse(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
    }

    func testCancelAndInteractiveDismissRejectLateSuccessAndOldIntentAfterRetry() throws {
        for cancel in [true, false] {
            let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
            let old = try begin(flow, origin: origin)
            if cancel { flow.cancel() } else { flow.presentationEnded() }
            XCTAssertFalse(flow.committed(success(old, target: target), current: target,
                                          isUsable: true, proofIsCurrent: true))
            XCTAssertFalse(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
            let next = try begin(flow, origin: origin, text: "第二次文字")
            XCTAssertNotEqual(old.id, next.id)
            XCTAssertFalse(flow.committed(success(old, target: target), current: target,
                                          isUsable: true, proofIsCurrent: true))
            XCTAssertTrue(flow.committed(success(next, target: target), current: target,
                                         isUsable: true, proofIsCurrent: true))
        }
    }

    func testCancelAfterCommitStillPreventsContinuationWithoutClaimingAuthenticationRollback() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: target), current: target,
                                     isUsable: true, proofIsCurrent: true))
        flow.cancel()
        XCTAssertFalse(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: true).isEmpty)
    }

    func testCancelledSheetCannotBeReplacedUntilItsActualDismissCompletion() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil)
        _ = try begin(flow, origin: origin)
        flow.cancel()
        XCTAssertFalse(flow.begin(text: "替换文字", origin: origin, isRestoring: false))
        XCTAssertFalse(flow.didDismiss(current: origin, isUsable: false, proofIsCurrent: false))
        XCTAssertTrue(flow.begin(text: "下一次文字", origin: origin, isRestoring: false))
    }

    func testCancellationBeforePresentationDoesNotLeaveAStuckModalReservation() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil)
        XCTAssertTrue(flow.begin(text: "尚未显示", origin: origin, isRestoring: false))
        let old = try XCTUnwrap(flow.login)
        flow.cancel()
        XCTAssertTrue(flow.begin(text: "新意图", origin: origin, isRestoring: false))
        let next = try XCTUnwrap(flow.login)
        let target = boundary("alice"), result = success(next, target: target)
        flow.didPresent(old.id)
        XCTAssertFalse(flow.committed(result, current: target, isUsable: true, proofIsCurrent: true))
        flow.didPresent(next.id)
        XCTAssertTrue(flow.committed(result, current: target, isUsable: true, proofIsCurrent: true))
    }

    func testRestoreOrExternalSelectionCannotStandInForThisLoginCommit() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), restored = boundary("alice")
        let intent = try begin(flow, origin: origin)
        flow.identityChanged(to: restored, isUsable: true, proofIsCurrent: false)
        XCTAssertNil(flow.login)
        XCTAssertFalse(flow.didDismiss(current: restored, isUsable: true, proofIsCurrent: true))
        XCTAssertFalse(flow.committed(success(intent, target: restored), current: restored,
                                      isUsable: true, proofIsCurrent: true))
    }

    func testRoundTripBackToSameUIDBeforeDismissCannotReuseAnOlderGeneration() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), first = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: first), current: first,
                                     isUsable: true, proofIsCurrent: true))
        let returned = boundary("alice")
        XCTAssertFalse(flow.didDismiss(current: returned, isUsable: true, proofIsCurrent: true))
        XCTAssertTrue(flow.path(current: returned, isUsable: true, proofIsCurrent: true).isEmpty)
    }

    func testNewLoginOfSameUIDInvalidatesReadyProofEvenWithoutAnIdentityChange() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: target), current: target,
                                     isUsable: true, proofIsCurrent: true))
        XCTAssertFalse(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: false))
        XCTAssertNil(flow.success)
    }

    func testActiveDraftIsHiddenImmediatelyWhenProofExpiresBeforeObserverRuns() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: target), current: target,
                                     isUsable: true, proofIsCurrent: true))
        XCTAssertTrue(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
        let route = try XCTUnwrap(flow.path(current: target, isUsable: true, proofIsCurrent: true).first)
        XCTAssertNil(flow.text(for: route, current: target, isUsable: true, proofIsCurrent: false))
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: false).isEmpty)
        XCTAssertNil(flow.text(for: route, current: boundary("bob"), isUsable: true, proofIsCurrent: true))
        flow.identityChanged(to: target, isUsable: true, proofIsCurrent: false)
        XCTAssertNil(flow.success)
    }

    func testSameUIDProfileRefreshRetainsAnOtherwiseCurrentContinuation() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: target), current: target,
                                     isUsable: true, proofIsCurrent: true))
        flow.identityChanged(to: target, isUsable: true, proofIsCurrent: true)
        XCTAssertTrue(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
    }

    func testOldNavigationStackCannotPopNewContinuationDuringIdentityReset() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        XCTAssertTrue(flow.committed(success(intent, target: target), current: target,
                                     isUsable: true, proofIsCurrent: true))
        flow.updatePath([], stack: origin, current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertTrue(flow.didDismiss(current: target, isUsable: true, proofIsCurrent: true))
        flow.updatePath([], stack: origin, current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertEqual(flow.path(current: target, isUsable: true, proofIsCurrent: true).count, 1)
        flow.updatePath([], stack: target, current: target, isUsable: true, proofIsCurrent: true)
        XCTAssertTrue(flow.path(current: target, isUsable: true, proofIsCurrent: true).isEmpty)
    }

    func testMismatchedRequestOriginTargetAndUnusableOrUnprovenSuccessAreRejected() throws {
        let flow = FeedbackLoginCoordinator(), origin = boundary(nil), target = boundary("alice")
        let intent = try begin(flow, origin: origin)
        let wrongID = AccountSignInSuccess(requestID: UUID(), attemptID: UUID(), origin: origin, target: target)
        let wrongOrigin = AccountSignInSuccess(requestID: intent.id, attemptID: UUID(), origin: boundary(nil), target: target)
        let sameGeneration = AccountRequestBoundary(uid: "alice", generation: origin.generation)
        for candidate in [wrongID, wrongOrigin, success(intent, target: sameGeneration)] {
            XCTAssertFalse(flow.committed(candidate, current: candidate.target, isUsable: true, proofIsCurrent: true))
        }
        let valid = success(intent, target: target)
        XCTAssertFalse(flow.committed(valid, current: boundary("bob"), isUsable: true, proofIsCurrent: true))
        XCTAssertFalse(flow.committed(valid, current: target, isUsable: false, proofIsCurrent: true))
        XCTAssertFalse(flow.committed(valid, current: target, isUsable: true, proofIsCurrent: false))
        XCTAssertTrue(flow.committed(valid, current: target, isUsable: true, proofIsCurrent: true))
    }

    func testSignedInAndRestoringOriginsCannotCreateAGuestContinuation() {
        let flow = FeedbackLoginCoordinator()
        XCTAssertFalse(flow.begin(text: "文字", origin: boundary("alice"), isRestoring: false))
        XCTAssertFalse(flow.begin(text: "文字", origin: boundary(nil), isRestoring: true))
        XCTAssertNil(flow.login)
        XCTAssertFalse(flow.didDismiss(current: boundary("alice"), isUsable: true, proofIsCurrent: true))
    }

    private func boundary(_ uid: String?) -> AccountRequestBoundary { .init(uid: uid, generation: UUID()) }
    private func begin(_ flow: FeedbackLoginCoordinator, origin: AccountRequestBoundary,
                       text: String = "本次访客文字") throws -> FeedbackLoginIntent {
        XCTAssertTrue(flow.begin(text: text, origin: origin, isRestoring: false))
        let intent = try XCTUnwrap(flow.login)
        flow.didPresent(intent.id)
        return intent
    }
    private func success(_ intent: FeedbackLoginIntent, target: AccountRequestBoundary) -> AccountSignInSuccess {
        .init(requestID: intent.id, attemptID: UUID(), origin: intent.origin, target: target)
    }
}
