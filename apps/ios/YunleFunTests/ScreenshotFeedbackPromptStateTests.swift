import XCTest
@testable import YunleFun

final class ScreenshotFeedbackPromptStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testDefaultWaitsForExplicitPresentationAndCountsOnlyVisibleTime() {
        var state = ScreenshotFeedbackPromptState()
        XCTAssertTrue(state.enabled)
        XCTAssertFalse(state.suppressedForSession)
        XCTAssertFalse(state.hasPending)
        XCTAssertEqual(state.visibleTimeRemaining(at: start), 0)

        state.receive(at: start)
        XCTAssertTrue(state.hasPending)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.visibleTimeRemaining(at: time(20)), 8)
        state.present(at: time(20))
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.visibleTimeRemaining(at: time(23)), 5)
    }

    func testRepeatedScreenshotsAndPresentationsDoNotExtendVisibleLifetime() {
        var state = visibleState()
        state.receive(at: time(4))
        state.present(at: time(5))
        XCTAssertEqual(state.visibleTimeRemaining(at: time(7)), 1)
        state.advance(at: time(8))
        XCTAssertFalse(state.hasPending)
        XCTAssertFalse(state.isVisible)
    }

    func testNaturalDismissalRequiresThirtySecondCooldown() {
        var state = visibleState()
        state.advance(at: time(8))
        state.receive(at: time(37.9))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(38))
        XCTAssertTrue(state.hasPending)
        XCTAssertFalse(state.isVisible)
    }

    func testConsumptionClearsPromptAndStartsCooldown() {
        var state = visibleState()
        state.consume(at: time(2))
        XCTAssertFalse(state.hasPending)
        XCTAssertFalse(state.suppressedForSession)
        state.receive(at: time(31.9))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(32))
        XCTAssertTrue(state.hasPending)
    }

    func testSuspensionPreservesRemainingTimeAcrossRepeatedSuspensions() {
        var state = visibleState()
        state.suspend(at: time(3))
        XCTAssertTrue(state.hasPending)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.visibleTimeRemaining(at: time(40)), 5)
        state.suspend(at: time(40))
        state.present(at: time(40))
        XCTAssertEqual(state.visibleTimeRemaining(at: time(42)), 3)
        state.suspend(at: time(42))
        state.present(at: time(50))
        state.advance(at: time(52.9))
        XCTAssertTrue(state.isVisible)
        state.advance(at: time(53))
        XCTAssertFalse(state.hasPending)
    }

    func testSuspendingAnAlreadyExpiredPromptDoesNotReviveIt() {
        var state = visibleState()
        state.suspend(at: time(8))
        state.present(at: time(9))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(37))
        XCTAssertFalse(state.hasPending)
    }

    func testUnpresentedPromptExpiresFromFirstScreenshotDespiteDuplicates() {
        var state = ScreenshotFeedbackPromptState()
        state.receive(at: start)
        state.receive(at: time(100))
        state.advance(at: time(119))
        XCTAssertTrue(state.hasPending)
        state.present(at: time(120))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(149))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(150))
        XCTAssertTrue(state.hasPending)
    }

    func testSuspendedPromptStillHasAbsoluteExpiry() {
        var state = visibleState()
        state.suspend(at: time(1))
        state.present(at: time(119))
        XCTAssertTrue(state.isVisible)
        state.advance(at: time(120))
        XCTAssertFalse(state.hasPending)
    }

    func testScreenshotAtExpiryCannotImmediatelyReplaceOldPrompt() {
        var state = ScreenshotFeedbackPromptState()
        state.receive(at: start)
        state.receive(at: time(120))
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(150))
        XCTAssertTrue(state.hasPending)
    }

    func testDisabledPreferenceRejectsScreenshotsAndDisablingClearsVisiblePrompt() {
        var state = ScreenshotFeedbackPromptState(enabled: false)
        state.receive(at: start)
        state.present(at: start)
        XCTAssertFalse(state.hasPending)
        state.setEnabled(true)
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(1))
        state.present(at: time(1))
        state.setEnabled(false)
        XCTAssertFalse(state.enabled)
        XCTAssertFalse(state.hasPending)
        XCTAssertFalse(state.isVisible)
    }

    func testManualCloseSuppressesSessionWithoutChangingPreference() {
        var state = visibleState()
        state.dismiss(at: time(1))
        XCTAssertTrue(state.enabled)
        XCTAssertTrue(state.suppressedForSession)
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(200))
        XCTAssertFalse(state.hasPending)
        state.setEnabled(true)
        state.receive(at: time(201))
        XCTAssertFalse(state.hasPending, "Writing the unchanged preference must not undo an explicit close")
    }

    func testExplicitDisableThenEnableAllowsNewPromptAfterManualClose() {
        var state = visibleState()
        state.dismiss(at: time(1))
        state.setEnabled(false)
        XCTAssertTrue(state.suppressedForSession)
        state.setEnabled(true)
        XCTAssertFalse(state.suppressedForSession)
        XCTAssertFalse(state.hasPending)
        state.receive(at: time(2))
        XCTAssertTrue(state.hasPending)
    }

    func testDiscardDropsPendingPromptWithoutSuppressingNextScreenshot() {
        var state = visibleState()
        state.discard()
        state.present(at: time(2))
        XCTAssertFalse(state.hasPending)
        XCTAssertFalse(state.suppressedForSession)
        state.receive(at: time(2))
        XCTAssertTrue(state.hasPending)
        XCTAssertEqual(state.visibleTimeRemaining(at: time(2)), 8)
    }

    func testDiscardPreservesSessionSuppressionAndExistingCooldown() {
        var suppressed = visibleState()
        suppressed.dismiss(at: time(1))
        suppressed.discard()
        suppressed.receive(at: time(200))
        XCTAssertTrue(suppressed.suppressedForSession)
        XCTAssertFalse(suppressed.hasPending)

        var cooling = visibleState()
        cooling.consume(at: time(1))
        cooling.discard()
        cooling.setEnabled(false)
        cooling.setEnabled(true)
        cooling.receive(at: time(30))
        XCTAssertFalse(cooling.hasPending)
        cooling.receive(at: time(31))
        XCTAssertTrue(cooling.hasPending)
    }

    func testRemainingTimeNeverGrowsForEarlierDateOrBecomesNegative() {
        let state = visibleState()
        XCTAssertEqual(state.visibleTimeRemaining(at: time(-2)), 8)
        XCTAssertEqual(state.visibleTimeRemaining(at: time(20)), 0)
    }

    private func time(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    private func visibleState() -> ScreenshotFeedbackPromptState {
        var state = ScreenshotFeedbackPromptState()
        state.receive(at: start)
        state.present(at: start)
        return state
    }
}
