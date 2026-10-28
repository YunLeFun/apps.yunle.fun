import XCTest

/// Opt-in UI acceptance using only synthetic screenshots already in the shared QA photo library.
@MainActor
final class ScreenshotPreviewOrientationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SCREENSHOT_ROTATION_QA"] == "1" else {
            throw XCTSkip("Requires the prepared synthetic photo library on the reserved shared simulator")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testDraftPreviewRotatesBothWaysAndPreservesDraftOnClose() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 20)); app.tabBars.buttons["我"].tap()
        let entry = app.buttons["me.feedback"]; reveal(entry, in: app); entry.tap()
        let field = app.textViews["feedback.description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Synthetic landscape preview draft")
        app.buttons["feedback.dismiss-keyboard"].tap()
        app.buttons["feedback.screenshot.add"].tap()
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        let item = picker.images.matching(NSPredicate(format: "label CONTAINS '截屏' OR label CONTAINS[c] 'screenshot'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let confirm = picker.buttons.matching(NSPredicate(format: "label == '完成' OR label BEGINSWITH[c] 'Done' OR label BEGINSWITH '添加' OR label BEGINSWITH[c] 'Add'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        app.activate()
        let preview = app.buttons["feedback.screenshot.preview.0"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15)); preview.tap()
        XCTAssertTrue(app.images["feedback.preview.image"].waitForExistence(timeout: 5))
        captureScreenshotPreviewEvidence(app, "draft-preview-portrait")
        verifyScreenshotPreviewRotations(in: app, namePrefix: "draft-preview")
        app.buttons["feedback.preview.close"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Synthetic landscape preview draft")
        app.buttons["feedback.screenshot.remove.0"].tap()
        XCTAssertFalse(preview.exists)
        captureScreenshotPreviewEvidence(app, "draft-preserved-and-image-removed")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTFail("Cannot reach expected feedback entry")
    }
}

@MainActor
extension XCTestCase {
    func verifyScreenshotPreviewRotations(in app: XCUIApplication, namePrefix: String) {
        let image = app.images["feedback.preview.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let aspectRatio = image.frame.width / image.frame.height
        verifyRotation(in: app, orientation: .landscapeLeft, name: namePrefix + "-landscape-left", aspectRatio: aspectRatio)
        let width = image.frame.width
        image.doubleTap()
        let zoomed = NSPredicate { _, _ in image.frame.width > width * 1.5 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: zoomed, object: nil)], timeout: 5), .completed)
        captureScreenshotPreviewEvidence(app, namePrefix + "-landscape-zoomed")
        // Rotate while zoomed: a changed viewport must restore aspect-fit instead of cropping the screenshot.
        verifyRotation(in: app, orientation: .portrait, name: namePrefix + "-portrait-after-zoom", aspectRatio: aspectRatio)
        verifyRotation(in: app, orientation: .landscapeRight, name: namePrefix + "-landscape-right", aspectRatio: aspectRatio)
        verifyRotation(in: app, orientation: .portrait, name: namePrefix + "-restored-portrait", aspectRatio: aspectRatio)
    }

    private func verifyRotation(in app: XCUIApplication, orientation: UIDeviceOrientation, name: String, aspectRatio: CGFloat) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let rotated = NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10)
        captureScreenshotPreviewEvidence(app, name)
        XCTAssertEqual(result, .completed, "The actual App window must complete rotation")
        let image = app.images["feedback.preview.image"]
        XCTAssertTrue(image.exists)
        let frame = image.frame
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(frame.width / frame.height, aspectRatio, accuracy: 0.005, "Rotation must preserve the image aspect ratio")
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame), "The complete fitted screenshot must remain inside the window")
        XCTAssertEqual(frame.midX, window.midX, accuracy: 2, "The fitted screenshot must stay centered")
        XCTAssertTrue(app.buttons["feedback.preview.close"].isHittable)
        XCTAssertEqual(app.webViews.count, 0)
    }

    func captureScreenshotPreviewEvidence(_ app: XCUIApplication, _ name: String) {
        // App-scoped screenshot cropping can retain the old coordinate space during rotation.
        // Capture the physical screen; use the App window's geometry for orientation assertions.
        let screenshot = XCUIScreen.main.screenshot()
        let value = XCTAttachment(screenshot: screenshot); value.name = name; value.lifetime = .keepAlways; add(value)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenshotRotationQA")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        let image = app.images["feedback.preview.image"]
        let geometry: [String: Any] = ["window": String(describing: app.windows.firstMatch.frame),
            "image": image.exists ? String(describing: image.frame) : "not-present",
            "deviceOrientation": XCUIDevice.shared.orientation.rawValue,
            "screenImageSize": String(describing: screenshot.image.size),
            "screenImageOrientation": screenshot.image.imageOrientation.rawValue]
        if let data = try? JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]) {
            let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            metadata.name = name + "-geometry"; metadata.lifetime = .keepAlways; add(metadata)
        }
    }
}
