import XCTest

@MainActor
final class FeedbackScreenshotUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The isolated QA simulator's library contains one synthetic screenshot.
    func testScreenshotSelectionPreviewRemovalAndOnlineDraftRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["FEEDBACK_SCREENSHOT_QA_SEEDED"] == "1" else {
            throw XCTSkip("Requires an isolated simulator containing the synthetic screenshot fixture")
        }
        let app = XCUIApplication(); app.launch()
        openFeedback(app)
        let field = app.textViews["feedback.description"]
        field.tap(); field.typeText("Synthetic screenshot feedback")
        app.buttons["feedback.dismiss-keyboard"].tap()
        let add = app.buttons["feedback.screenshot.add"]
        reveal(add, in: app); add.tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo' OR label BEGINSWITH '照片'")).firstMatch
        if !photo.waitForExistence(timeout: 10) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "screenshot-picker-tree"; tree.lifetime = .keepAlways; self.add(tree)
        }
        XCTAssertTrue(photo.exists); photo.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Add' OR label BEGINSWITH '添加'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let preview = app.buttons["feedback.screenshot.preview.0"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); preview.tap()
        XCTAssertTrue(app.navigationBars["截图预览"].waitForExistence(timeout: 5))
        capture(app, "native-feedback-screenshot-preview")
        app.navigationBars["截图预览"].buttons["完成"].tap()
        let online = app.buttons["feedback.support-center"]
        reveal(online, in: app); online.tap()
        XCTAssertTrue(app.navigationBars["在线反馈"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedback.screenshot.preview.0"].exists)
        XCTAssertEqual(app.textViews["support.center.description"].value as? String, "Synthetic screenshot feedback")
        app.navigationBars["在线反馈"].buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5))
        let remove = app.buttons["feedback.screenshot.remove.0"]
        reveal(remove, in: app, upward: false); remove.tap()
        XCTAssertFalse(app.buttons["feedback.screenshot.preview.0"].exists)
        XCTAssertTrue(app.buttons["feedback.screenshot.add"].label.contains("0/3"))
        capture(app, "native-feedback-screenshot-removed")
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
