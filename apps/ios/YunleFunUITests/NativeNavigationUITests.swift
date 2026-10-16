import XCTest

@MainActor
final class NativeNavigationUITests: XCTestCase {
    func testGuestCanReachSyncSettingsAndCancelNativeLogin() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let me = app.tabBars.buttons["我"]
        XCTAssertTrue(me.waitForExistence(timeout: 10))
        me.tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["云居同步"].tap()
        XCTAssertTrue(app.navigationBars["云居同步"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录后可同步云居"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-sync-guest"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["登录云乐坊"].tap()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["云居同步"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }
}
