import XCTest
@testable import YunleFun

final class NativeGameDeferredLaunchTests: XCTestCase {
    func testInitialRestoreCanAdoptOneIdentityEvenWhenObserversCoalesce() throws {
        var flow = NativeGameDeferredLaunchCoordinator()
        let guest = boundary(nil), alice = boundary("alice"), selection = UUID(), action = try action()
        flow.enqueue(action, boundary: guest, selectionGeneration: selection, isRestoring: true)
        XCTAssertEqual(take(&flow, current: alice, selection: selection), .launch(action))
        XCTAssertEqual(take(&flow, current: alice, selection: selection), .waiting, "A delayed tap is consumed once")
    }

    func testRestoreAdoptionClosesAfterFirstIdentityAndAfterAnonymousCompletion() throws {
        for restored in [false, true] {
            var flow = NativeGameDeferredLaunchCoordinator()
            let guest = boundary(nil), alice = boundary("alice"), selection = UUID()
            flow.enqueue(try action(), boundary: guest, selectionGeneration: selection, isRestoring: true)
            let current = restored ? alice : guest
            XCTAssertEqual(take(&flow, current: current, selection: selection,
                                isRestoring: restored, hasPlay: false, catalogIsLoading: true), .waiting)
            XCTAssertEqual(take(&flow, current: boundary("bob"), selection: selection), .discarded)
        }
    }

    func testUserSelectionOperationAlwaysInvalidatesInitialRestoreException() throws {
        for current in [boundary(nil), boundary("alice")] {
            var flow = NativeGameDeferredLaunchCoordinator()
            flow.enqueue(try action(), boundary: boundary(nil), selectionGeneration: UUID(), isRestoring: true)
            XCTAssertEqual(take(&flow, current: current, selection: UUID()), .discarded)
        }
    }

    func testGuestTapOutsideRestoreCannotBeInheritedByLogin() throws {
        var flow = NativeGameDeferredLaunchCoordinator()
        let selection = UUID()
        flow.enqueue(try action(), boundary: boundary(nil), selectionGeneration: selection, isRestoring: false)
        XCTAssertEqual(take(&flow, current: boundary("alice"), selection: selection), .discarded)
    }

    func testAccountSwitchSameUIDNewGenerationAndSelectionRoundTripCannotReplayTap() throws {
        let alice = boundary("alice"), selection = UUID()
        for (current, nextSelection) in [(boundary("bob"), selection), (boundary("alice"), selection), (alice, UUID())] {
            var flow = NativeGameDeferredLaunchCoordinator()
            flow.enqueue(try action(), boundary: alice, selectionGeneration: selection, isRestoring: false)
            // No identity observer is required between enqueue and consume.
            XCTAssertEqual(take(&flow, current: current, selection: nextSelection), .discarded)
            XCTAssertEqual(take(&flow, current: alice, selection: selection), .waiting)
        }
    }

    func testCachedPlayRefreshDoesNotDelayDismissedPresentation() throws {
        var flow = NativeGameDeferredLaunchCoordinator()
        let alice = boundary("alice"), selection = UUID(), action = try action()
        flow.enqueue(action, boundary: alice, selectionGeneration: selection, isRestoring: false)
        XCTAssertEqual(take(&flow, current: alice, selection: selection, awaitingDismissal: true,
                            catalogIsLoading: true), .waiting)
        XCTAssertEqual(take(&flow, current: alice, selection: selection, catalogIsLoading: true), .launch(action))
        XCTAssertTrue(NativeGameDeferredLaunchCoordinator.waitsForCatalog(hasPlay: false, isLoading: true))
        XCTAssertFalse(NativeGameDeferredLaunchCoordinator.waitsForCatalog(hasPlay: false, isLoading: false))
    }

    func testMissingPlayWaitsAndNewTapReplacesOldRequestWithoutWeakeningIdentity() throws {
        var flow = NativeGameDeferredLaunchCoordinator()
        let alice = boundary("alice"), selection = UUID(), original = try action(), latest = try action("ZX98YU")
        flow.enqueue(original, boundary: alice, selectionGeneration: selection, isRestoring: false)
        XCTAssertEqual(take(&flow, current: alice, selection: selection, hasPlay: false, catalogIsLoading: true), .waiting)
        flow.enqueue(latest, boundary: alice, selectionGeneration: selection, isRestoring: false)
        XCTAssertEqual(take(&flow, current: alice, selection: selection), .launch(latest))
        flow.enqueue(original, boundary: alice, selectionGeneration: selection, isRestoring: false)
        flow.cancel()
        XCTAssertEqual(take(&flow, current: alice, selection: selection), .waiting)
    }

    private func boundary(_ uid: String?) -> AccountRequestBoundary { .init(uid: uid, generation: UUID()) }
    private func action(_ code: String = "AB23CD") throws -> NativeGameLaunchIntent {
        .room(try NativeGameRoomIntent(input: code, role: .spectator))
    }
    private func take(_ flow: inout NativeGameDeferredLaunchCoordinator, current: AccountRequestBoundary, selection: UUID,
                      isRestoring: Bool = false, awaitingDismissal: Bool = false, hasPlay: Bool = true,
                      catalogIsLoading: Bool = false) -> NativeGameDeferredLaunchCoordinator.Resolution {
        flow.take(current: current, selectionGeneration: selection, isRestoring: isRestoring,
                  awaitingPresentationDismissal: awaitingDismissal, hasPlay: hasPlay, catalogIsLoading: catalogIsLoading)
    }
}
