import XCTest

/// Explicitly opted-in, isolated-device acceptance against the loopback Support composition.
@MainActor
final class ShareFeedbackEndToEndUITests: XCTestCase {
    private let origin = URL(string: "https://127.0.0.1:18473")!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SHARE_FEEDBACK_LOCAL_QA"] == "1",
              ProcessInfo.processInfo.environment["SHARE_FEEDBACK_PRESENTED"] == "1" else {
            throw XCTSkip("Requires the explicit local-validation build, trusted loopback fixture and isolated photo library")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testNativeFeedbackScreenIsReadyForSystemShare() {
        let app = XCUIApplication()
        app.launch()
        openFeedback(app)
        XCTAssertTrue(app.buttons["feedback.screenshot.add"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        capture(app, "native-feedback-before-system-share")
    }

    func testNativeFeedbackDraftPreviewKeepsTheImageAndDescriptionUntilRemoval() async throws {
        let before = try await control("status")
        let app = XCUIApplication(); app.launch(); openFeedback(app)
        let description = app.textViews["feedback.description"]
        description.tap(); description.typeText("Synthetic native screenshot draft")
        app.buttons["feedback.dismiss-keyboard"].tap()
        let addImage = app.buttons["feedback.screenshot.add"]
        reveal(addImage, in: app); addImage.tap()
        // iOS 26's system picker is an ExtensionKit process. Query that process,
        // rather than the occluded host App's accessibility elements.
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        let image = picker.images.matching(NSPredicate(format: "label CONTAINS '截屏' OR label CONTAINS[c] 'screenshot'")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        captureTree(picker, "native-draft-system-picker-tree")
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        captureTree(picker, "native-draft-selected-picker-tree")
        let confirm = picker.buttons.matching(NSPredicate(format: "label == '完成' OR label BEGINSWITH[c] 'Done' OR label BEGINSWITH '添加' OR label BEGINSWITH[c] 'Add'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        let preview = app.buttons["feedback.screenshot.preview.0"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15)); preview.tap()
        XCTAssertTrue(app.images["feedback.preview.image"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.webViews.count, 0)
        capture(app, "native-draft-screenshot-preview")
        verifyNativeZoom(in: app)
        app.buttons["feedback.preview.close"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(description.value as? String, "Synthetic native screenshot draft")
        capture(app, "native-draft-preserved-after-preview")
        app.buttons["feedback.screenshot.remove.0"].tap()
        XCTAssertFalse(preview.exists)
        capture(app, "native-draft-screenshot-removed")
        let after = try await control("status")
        XCTAssertEqual((after["events"] as? [[String: Any]])?.count, (before["events"] as? [[String: Any]])?.count)
    }

    func testSystemShareRetryReceiptRelaunchAndPrivateScreenshot() async throws {
        _ = try await control("reset")
        let app = XCUIApplication()
        let extensionUI = XCUIApplication(bundleIdentifier: "fun.yunle.apps.native-dev.feedback-share")
        let preview = extensionUI.buttons["share.feedback.preview.0"]
        // The real system-menu entry may be selected while this wait keeps device accessibility active.
        XCTAssertTrue(preview.waitForExistence(timeout: 120))
        captureTree(extensionUI, "extension-process-tree")
        capture(extensionUI, "share-native-form"); preview.tap()
        XCTAssertTrue(extensionUI.navigationBars["截图预览"].waitForExistence(timeout: 5))
        capture(extensionUI, "share-image-preview")
        verifyNativeZoom(in: extensionUI)
        verifyScreenshotPreviewRotations(in: extensionUI, namePrefix: "extension-preview")
        extensionUI.buttons["feedback.preview.close"].tap()
        let description = "Synthetic system share acceptance screenshot"
        let field = extensionUI.textViews["share.feedback.description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(description)
        extensionUI.buttons["完成输入"].tap()
        let submit = extensionUI.buttons["share.feedback.submit"]
        reveal(submit, in: extensionUI); submit.tap()
        let confirm = extensionUI.buttons["确认提交"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture(extensionUI, "share-reviewed-confirmation")
        // Cancelling the system confirmation must not bootstrap or send anything.
        let cancel = extensionUI.buttons.matching(identifier: "取消")
        cancel.element(boundBy: cancel.count - 1).tap()
        let cancelled = try await control("status")
        XCTAssertEqual((cancelled["events"] as? [[String: Any]])?.count, 0)
        _ = try await control("fail-after-commit")
        submit.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(extensionUI.staticTexts["share.feedback.error"].waitForExistence(timeout: 35))
        XCTAssertEqual(field.value as? String, description)
        capture(extensionUI, "share-uncertain-result-retained")
        submit.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(extensionUI.staticTexts["share.feedback.receipt"].waitForExistence(timeout: 35))
        capture(extensionUI, "share-received")
        extensionUI.buttons["share.feedback.done"].firstMatch.tap()
        app.activate()
        openFeedback(app)
        let ticket = app.buttons["feedback.shared.ticket"].firstMatch
        reveal(ticket, in: app); XCTAssertTrue(ticket.exists)
        capture(app, "share-receipt-in-app")
        // The same receipt must survive termination and account restoration.
        app.terminate(); app.launch(); openFeedback(app)
        let restored = app.buttons["feedback.shared.ticket"].firstMatch
        reveal(restored, in: app); restored.tap()
        XCTAssertTrue(app.navigationBars["反馈工单"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", description)).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0, "Share-ticket readback must stay native")
        let screenshot = app.buttons["support.ticket.screenshot.0"]
        XCTAssertTrue(screenshot.waitForExistence(timeout: 20))
        capture(app, "share-native-ticket")
        reveal(screenshot, in: app); screenshot.tap()
        XCTAssertTrue(app.images["feedback.preview.image"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.webViews.count, 0)
        capture(app, "share-private-ticket-screenshot")
        verifyNativeZoom(in: app)
        verifyScreenshotPreviewRotations(in: app, namePrefix: "ticket-preview")
        app.buttons["feedback.preview.close"].tap()
        let status = try await control("status")
        XCTAssertEqual(status["records"] as? Int, 1)
        let events = try XCTUnwrap(status["events"] as? [[String: Any]])
        let submissions = events.filter { $0["kind"] as? String == "submit" }
        XCTAssertEqual(submissions.count, 2)
        XCTAssertEqual(submissions.first?["key"] as? String, submissions.last?["key"] as? String)
        XCTAssertEqual(submissions.first?["id"] as? String, submissions.last?["id"] as? String)
        XCTAssertEqual(submissions.last?["screenshots"] as? Int, 1)
        XCTAssertEqual(events.filter { $0["kind"] as? String == "guest" }.count, 1)
        XCTAssertTrue(events.contains { $0["kind"] as? String == "image-read" })
        app.buttons["support.ticket.close"].tap()
        let clear = app.buttons["feedback.shared.clear"]
        reveal(clear, in: app); clear.tap()
        XCTAssertTrue(app.buttons["清除本机记录"].waitForExistence(timeout: 5))
        app.buttons["清除本机记录"].tap()
        XCTAssertFalse(app.buttons["feedback.shared.ticket"].firstMatch.exists)
        let afterClear = try await control("status")
        XCTAssertEqual(afterClear["records"] as? Int, 1)
    }

    func testBetaGuidanceRequiresAnExplicitGeneralFeedbackChoice() async throws {
        guard ProcessInfo.processInfo.environment["SHARE_FEEDBACK_BETA_QA"] == "1" else {
            throw XCTSkip("Requires the fixture to seed only the isolated App Group's remembered channel")
        }
        let before = try await control("status")
        let count = (before["events"] as? [[String: Any]])?.count
        let extensionUI = XCUIApplication(bundleIdentifier: "fun.yunle.apps.native-dev.feedback-share")
        let official = extensionUI.buttons["share.feedback.testflight-done"]
        XCTAssertTrue(official.waitForExistence(timeout: 120))
        XCTAssertFalse(extensionUI.buttons["share.feedback.preview.0"].exists)
        capture(extensionUI, "share-beta-official-priority")
        let general = extensionUI.buttons["share.feedback.use-general"]
        XCTAssertTrue(general.waitForExistence(timeout: 15)); general.tap()
        let preview = extensionUI.buttons["share.feedback.preview.0"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        let remove = extensionUI.buttons["移除截图 1"]
        XCTAssertTrue(remove.exists); remove.tap(); XCTAssertFalse(preview.exists)
        capture(extensionUI, "share-beta-explicit-general-removed")
        extensionUI.buttons["share.feedback.cancel"].tap()
        let after = try await control("status")
        XCTAssertEqual((after["events"] as? [[String: Any]])?.count, count)
    }

    func testBetaOfficialChoiceClosesWithoutSubmitting() async throws {
        guard ProcessInfo.processInfo.environment["SHARE_FEEDBACK_BETA_QA"] == "1" else {
            throw XCTSkip("Requires the isolated remembered Beta channel")
        }
        let before = try await control("status")
        let extensionUI = XCUIApplication(bundleIdentifier: "fun.yunle.apps.native-dev.feedback-share")
        let official = extensionUI.buttons["share.feedback.testflight-done"]
        XCTAssertTrue(official.waitForExistence(timeout: 120))
        XCTAssertFalse(extensionUI.buttons["share.feedback.preview.0"].exists)
        capture(extensionUI, "share-beta-official-close")
        official.tap()
        XCTAssertFalse(extensionUI.buttons["share.feedback.use-general"].exists)
        let after = try await control("status")
        XCTAssertEqual((after["events"] as? [[String: Any]])?.count, (before["events"] as? [[String: Any]])?.count)
    }

    private func openFeedback(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 20)); app.tabBars.buttons["我"].tap()
        let entry = app.buttons["me.feedback"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5))
    }

    private func verifyNativeZoom(in app: XCUIApplication) {
        let image = app.images["feedback.preview.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let width = image.frame.width
        image.doubleTap()
        let enlarged = NSPredicate { _, _ in image.frame.width > width * 1.5 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enlarged, object: nil)], timeout: 5), .completed)
        capture(app, "native-preview-zoomed")
        image.doubleTap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        captureTree(app, "unreachable-element"); XCTFail("Element could not be reached: \(element)")
    }

    private func control(_ operation: String) async throws -> [String: Any] {
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["SHARE_FEEDBACK_VALIDATION_KEY"])
        var request = URLRequest(url: origin.appendingPathComponent("_validation/" + operation))
        request.httpMethod = "POST"; request.setValue(key, forHTTPHeaderField: "x-validation-key")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let value = XCTAttachment(screenshot: screenshot); value.name = name; value.lifetime = .keepAlways; add(value)
        // Keep synthetic QA evidence readable even if the test runner stalls during failure teardown.
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ShareFeedbackQA")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }
    private func captureTree(_ app: XCUIApplication, _ name: String) {
        let value = XCTAttachment(string: app.debugDescription); value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
