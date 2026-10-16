import XCTest

@MainActor
final class NativeNavigationUITests: XCTestCase {
    func testGuestCanUseHomeOptionsAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["云居"].waitForExistence(timeout: 10))
        let addApplication = app.buttons["home.add"], options = app.buttons["home.options"]
        XCTAssertTrue(addApplication.isHittable); XCTAssertTrue(options.isHittable)
        options.tap()
        XCTAssertTrue(app.navigationBars["云居选项"].waitForExistence(timeout: 5))
        let optionsAttachment = XCTAttachment(screenshot: app.screenshot())
        optionsAttachment.name = "native-home-options-largest-text"; optionsAttachment.lifetime = .keepAlways; add(optionsAttachment)
        let scan = app.buttons["home.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5)); scan.tap()
        XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-home-scanner-largest-text"; attachment.lifetime = .keepAlways; add(attachment)
        app.navigationBars.buttons["完成"].tap()
        app.navigationBars["云居选项"].buttons["云居"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        addApplication.tap()
        XCTAssertTrue(app.tabBars.buttons["工坊"].isSelected)
    }

    func testGuestCanReadEmptyHomeBackupsAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["云居"].waitForExistence(timeout: 10))
        let installed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).allElementsBoundByIndex.map(\.label)
        app.tabBars.buttons["我"].tap(); app.buttons["设置"].tap(); app.buttons["云居备份"].tap()
        XCTAssertTrue(app.navigationBars["云居备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["还没有云居备份"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "native-home-backups-empty"; attachment.lifetime = .keepAlways; add(attachment)
        app.tabBars.buttons["云居"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).allElementsBoundByIndex.map(\.label), installed)
    }

    func testGuestCanReadLegacyImportEmptyStateAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["云居"].waitForExistence(timeout: 10))
        let installed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).allElementsBoundByIndex.map(\.label)
        app.tabBars.buttons["我"].tap(); app.buttons["设置"].tap()
        app.buttons["旧版数据导入"].tap()
        XCTAssertTrue(app.navigationBars["旧版数据导入"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未发现旧版记录"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["导入到当前云居"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "native-legacy-import-empty"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["登录或管理账号"].tap()
        XCTAssertTrue(app.navigationBars["账号管理"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["旧版数据导入"].waitForExistence(timeout: 5))
        app.tabBars.buttons["云居"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).allElementsBoundByIndex.map(\.label), installed)
    }

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
