import XCTest

@MainActor
final class NativeSupportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHelpExplainsRuntimeAndNavigatesToDiscovery() {
        let app = XCUIApplication(); app.launch()
        openMe(app)
        reveal(app.buttons["me.help"], in: app); app.buttons["me.help"].tap()
        XCTAssertTrue(app.navigationBars["帮助"].waitForExistence(timeout: 5))
        let runtime = app.buttons["help.guide.runtime"]
        reveal(runtime, in: app); runtime.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "在云居的“正在运行”中恢复会话")).firstMatch.exists)
        capture(app, "native-help-runtime")
        let discover = app.buttons["help.guide.discover"]
        reveal(discover, in: app, upward: false); discover.tap()
        let discovery = app.buttons["help.guide.discovery"]; reveal(discovery, in: app); discovery.tap()
        XCTAssertTrue(app.tabBars.buttons["寻乐"].isSelected)
        app.tabBars.buttons["我"].tap()
        XCTAssertTrue(app.navigationBars["帮助"].waitForExistence(timeout: 5))
        app.navigationBars["帮助"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
    }

    func testGuestFeedbackCanDismissKeyboardAndCancelLoginWithoutLosingDraft() {
        let app = XCUIApplication(); app.launch()
        openFeedback(app)
        let field = app.textViews["feedback.description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Native support draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let dismiss = app.buttons["feedback.dismiss-keyboard"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5)); XCTAssertTrue(dismiss.isHittable); dismiss.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        let copy = app.buttons["support.feedback.copy-content"]
        reveal(copy, in: app); copy.tap()
        reveal(app.staticTexts["support.feedback.notice"], in: app)
        XCTAssertTrue(app.staticTexts["support.feedback.notice"].label.contains("反馈内容已复制"))
        XCTAssertFalse(app.buttons["feedback.confirmation.upload"].exists)
        let login = app.buttons["feedback.login"]
        reveal(login, in: app); login.tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "上传前仍需重新预览并确认")).firstMatch.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5))
        reveal(field, in: app, upward: false)
        XCTAssertEqual(field.value as? String, "Native support draft")
        capture(app, "native-feedback-guest-draft")
    }

    func testFeedbackEmptyLogsAndMailFallbackAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openFeedback(app)
        let copyEmail = app.buttons["support.feedback.copy-email"]
        reveal(copyEmail, in: app); XCTAssertGreaterThanOrEqual(copyEmail.frame.height, 44); copyEmail.tap()
        reveal(app.staticTexts["support.feedback.notice"], in: app)
        XCTAssertTrue(app.staticTexts["support.feedback.notice"].label.contains("邮箱已复制"))
        capture(app, "native-feedback-largest-mail-fallback")
        let clear = app.buttons["feedback.logs.clear"]
        reveal(clear, in: app); XCTAssertTrue(clear.isEnabled); clear.tap()
        XCTAssertTrue(app.buttons["清除日志"].waitForExistence(timeout: 5))
        let cancel = app.buttons["取消"]
        if cancel.exists { cancel.tap() } else {
            // Current iOS adapts this native confirmation to an anchored
            // popover. Dismiss outside its observed bounds, away from actions.
            let dialog = app.sheets["清除当前本地日志？"]
            XCTAssertTrue(dialog.exists)
            XCTAssertGreaterThan(dialog.frame.minX, 10)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: dialog.frame.minX / 2, dy: dialog.frame.midY)).tap()
        }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["清除日志"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(clear.isEnabled); clear.tap(); app.buttons["清除日志"].tap()
        let empty = app.staticTexts["feedback.logs.empty"]
        reveal(empty, in: app, upward: false)
        XCTAssertTrue(empty.exists)
        XCTAssertFalse(clear.isEnabled)
        XCTAssertFalse(app.buttons["feedback.confirmation.upload"].exists)
        capture(app, "native-feedback-largest-empty-logs")
        let login = app.buttons["feedback.login"]
        reveal(login, in: app); XCTAssertGreaterThanOrEqual(login.frame.height, 44)
        XCTAssertTrue(login.isHittable)
    }

    private func openMe(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
    }
    private func openFeedback(_ app: XCUIApplication) {
        openMe(app)
        let entry = app.buttons["me.feedback"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<32 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "support-unreachable-element"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("Could not reach \(element)")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
