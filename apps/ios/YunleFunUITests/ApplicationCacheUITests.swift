import XCTest

@MainActor
final class ApplicationCacheUITests: XCTestCase {
    // Simulator WebContent/Network extension bootstrap can outlast app launch.
    // Rendering and the downloader's bounded startup/navigation budgets differ.
    private let runtimePageTimeout: TimeInterval = 120

    func testDownloadUpdateOpenAndClear() throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_UI_TEST"] == "1" else {
            throw XCTSkip("Opt in on an empty guest simulator with YLF_CACHE_UI_TEST=1")
        }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        selectTab("我", in: app)
        XCTAssertTrue(app.buttons["me.login"].waitForExistence(timeout: 5), "Use an isolated guest simulator")
        app.buttons["设置"].tap(); app.buttons["应用下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["0 个应用已下载"].waitForExistence(timeout: 5), "Do not modify preexisting downloads")
        let automatic = app.switches["cache.auto-update"]
        let wifi = app.switches["cache.wifi-only"]
        XCTAssertEqual(automatic.value as? String, "0")
        XCTAssertEqual(wifi.value as? String, "1")
        setSwitch(automatic, enabled: true)
        XCTAssertTrue(wifi.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        app.terminate(); app.launch()
        selectTab("我", in: app)
        app.buttons["设置"].tap(); app.buttons["应用下载缓存"].tap()
        XCTAssertEqual(automatic.value as? String, "1", "Automatic update preference persists")
        XCTAssertEqual(wifi.value as? String, "1")
        setSwitch(automatic, enabled: false)
        selectTab("工坊", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("云空调")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "云空调")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        app.buttons["应用下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["尚未下载缓存"].waitForExistence(timeout: 5))
        app.buttons["cache.download"].tap()
        waitForSavedCache(app, operation: "首次下载")
        capture(app, "cache-downloaded")
        app.buttons["cache.download"].tap()
        waitForSavedCache(app, operation: "更新")
        app.navigationBars["应用下载缓存"].buttons.firstMatch.tap()
        openCloudAir(app, expecting: "便携小空调")
        capture(app, "cache-runtime-cloud-air")
        app.buttons["更多操作"].tap()
        app.buttons["runtime.menu.cache"].tap()
        XCTAssertTrue(app.buttons["cache.clear"].waitForExistence(timeout: 5))
        app.buttons["cache.clear"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["cache.clear"].exists)
        app.navigationBars.buttons["完成"].tap()
        app.buttons["更多操作"].tap(); app.buttons["结束"].tap()
        selectTab("我", in: app)
        XCTAssertTrue(app.staticTexts["1 个应用已下载"].waitForExistence(timeout: 5))
        app.buttons["cache.clear-all"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["清理全部"].tap()
        XCTAssertTrue(app.staticTexts["0 个应用已下载"].waitForExistence(timeout: 5))
        capture(app, "cache-cleared")
    }

    func testAutomaticUpdateKeepsRunningCacheUntilReopened() throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_UI_AUTOMATIC"] == "1" else {
            throw XCTSkip("Requires the expired public Cloud Air fixture on a guest simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 15))
        selectTab("我", in: app)
        XCTAssertTrue(app.buttons["me.login"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap(); app.buttons["应用下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["1 个应用已下载"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["cache.auto-update"].value as? String, "0")
        XCTAssertEqual(app.switches["cache.wifi-only"].value as? String, "1")

        selectTab("工坊", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("云空调")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "云空调")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        openCloudAir(app, expecting: "自动更新旧版本")
        capture(app, "automatic-old-cache-running")
        app.buttons["收起应用"].tap()

        selectTab("我", in: app)
        setSwitch(app.switches["cache.auto-update"], enabled: true)
        let downloaded = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "云空调")).firstMatch
        XCTAssertTrue(downloaded.waitForExistence(timeout: 5)); downloaded.tap()
        XCTAssertTrue(app.staticTexts["自动更新已就绪，下次重新打开应用时生效。"].waitForExistence(timeout: 145))
        capture(app, "automatic-update-ready")

        selectTab("工坊", in: app)
        openCloudAir(app, expecting: "自动更新旧版本", timeout: 10)
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.staticTexts["更新已就绪，下次重新打开生效"].waitForExistence(timeout: 5))
        app.buttons["结束"].tap()
        openCloudAir(app, expecting: "便携小空调")
        XCTAssertFalse(app.webViews.staticTexts["自动更新旧版本"].exists)
        capture(app, "automatic-new-cache-after-reopen")

        app.buttons["更多操作"].tap(); app.buttons["runtime.menu.cache"].tap()
        app.buttons["cache.clear"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["清理下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["尚未下载缓存"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["完成"].tap()
        app.buttons["更多操作"].tap(); app.buttons["结束"].tap()
        selectTab("我", in: app)
        app.navigationBars["应用下载缓存"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["0 个应用已下载"].waitForExistence(timeout: 5))
        setSwitch(app.switches["cache.auto-update"], enabled: false)
        capture(app, "automatic-cache-cleared")
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.wait(for: \.isHittable, toEqual: true, timeout: 10))
        // UIKit may still be dismissing the runtime when its underlying tab bar
        // becomes visible. Require the actual selection before continuing.
        for _ in 0..<3 {
            if tab.isSelected { return }
            tab.tap()
            if tab.wait(for: \.isSelected, toEqual: true, timeout: 2) { return }
        }
        XCTFail("Tab did not become selected: \(title)")
    }

    private func openCloudAir(_ app: XCUIApplication, expecting title: String, timeout: TimeInterval? = nil) {
        let operation = UUID()
        // Emit before any accessibility call: even resolving/tapping the launch
        // button can block while XCTest waits for the application to become idle.
        print("CACHE_UI_PROBE opening operation=\(operation)")
        // Resolve the available action after a runtime dismissal, rather than
        // choosing a missing button while the detail page is still reappearing.
        let launch = app.buttons.matching(NSPredicate(format: "label IN %@", ["试用", "打开"])).firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        XCTAssertTrue(launch.wait(for: \.isHittable, toEqual: true, timeout: 5))
        launch.tap()
        let rendered = app.webViews.staticTexts[title].firstMatch.waitForExistence(timeout: timeout ?? runtimePageTimeout)
        print("CACHE_UI_PROBE \(rendered ? "rendered" : "failed") operation=\(operation)")
        XCTAssertTrue(rendered, "Expected cached page did not become accessible")
    }

    private func setSwitch(_ control: XCUIElement, enabled: Bool) {
        XCTAssertTrue(control.wait(for: \.isHittable, toEqual: true, timeout: 10))
        // SwiftUI exposes the entire labeled row as the switch. Hit its trailing
        // control rather than the label, then wait for the observable state.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    func testClearConfirmationsWithLocalFixtures() throws {
        guard ProcessInfo.processInfo.environment["YLF_CACHE_UI_FIXTURES"] == "1" else {
            throw XCTSkip("Requires two explicitly seeded cache-confirm fixtures on a guest simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 15))
        selectTab("我", in: app)
        XCTAssertTrue(app.buttons["me.login"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap(); app.buttons["应用下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["2 个应用已下载"].waitForExistence(timeout: 5))
        let fixture = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "缓存确认测试一")).firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 5)); fixture.tap()
        app.buttons["cache.clear"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "cache-single-confirmation")
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["cache.clear"].exists)
        app.buttons["cache.clear"].tap(); app.alerts.buttons["清理下载缓存"].tap()
        XCTAssertTrue(app.staticTexts["尚未下载缓存"].waitForExistence(timeout: 5))
        app.navigationBars["应用下载缓存"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 个应用已下载"].waitForExistence(timeout: 5))
        app.buttons["cache.clear-all"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["1 个应用已下载"].exists)
        app.buttons["cache.clear-all"].tap(); app.alerts.buttons["清理全部"].tap()
        XCTAssertTrue(app.staticTexts["0 个应用已下载"].waitForExistence(timeout: 5))
        capture(app, "cache-fixtures-cleared")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func waitForSavedCache(_ app: XCUIApplication, operation: String) {
        // Wait for this operation to settle, not just a success message left by
        // the previous download. Surface an error immediately instead of spending
        // the whole UI timeout waiting for a button that cannot appear.
        let button = app.buttons["cache.download"]
        let message = app.staticTexts["cache.message"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.progressIndicators["cache.progress"].exists && button.exists && button.isEnabled
                && message.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 140), .completed, "\(operation)没有结束")
        XCTAssertEqual(message.label, "缓存已保存。下次重新打开应用时使用新缓存。", "\(operation)失败")
        XCTAssertEqual(button.label, "更新缓存")
    }
}
