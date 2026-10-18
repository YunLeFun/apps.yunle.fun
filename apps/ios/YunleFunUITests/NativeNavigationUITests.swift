import XCTest

@MainActor
final class NativeNavigationUITests: XCTestCase {
    func testGuestCanDismissPhoneKeyboardAtStandardTextSize() {
        checkLoginKeyboardDismissal(large: false)
    }

    func testGuestCanDismissPasswordKeyboardAtStandardTextSize() {
        checkLoginKeyboardDismissal(large: false, passwordMethod: true)
    }

    func testGuestCanDismissPhoneKeyboardAtLargestTextSize() {
        checkLoginKeyboardDismissal(large: true)
    }

    private func checkLoginKeyboardDismissal(large: Bool, passwordMethod: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
        let login = app.buttons["me.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertTrue(login.label.hasPrefix("登录云乐坊"))
        login.tap()
        if passwordMethod {
            app.segmentedControls.buttons["密码"].tap()
            let username = app.textFields["login.username"], password = app.secureTextFields["login.password"]
            XCTAssertTrue(username.waitForExistence(timeout: 5))
            XCTAssertEqual(username.label, "用户名、邮箱或手机号")
            XCTAssertEqual(password.label, "密码")
            checkDismissal(app, field: password, name: "password-standard")
        } else {
            let phone = app.textFields["login.phone"]
            XCTAssertTrue(phone.waitForExistence(timeout: 5))
            XCTAssertEqual(phone.label, "手机号")
            checkDismissal(app, field: phone, name: large ? "phone-largest" : "phone-standard")
        }
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
    }

    private func checkDismissal(_ app: XCUIApplication, field: XCUIElement, name: String) {
        field.tap()
        field.typeText("1")
        let keyboard = app.keyboards.firstMatch, dismiss = app.buttons["login.dismiss-keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let screen = app.frame
        // A Keyboard.firstMatch snapshot can have no descendants while the
        // application's current snapshot already exposes the visible keys.
        // Resolve keys from the app, then require them to be inside the keyboard.
        let typingKeys = app.keys.matching(NSPredicate(format: "label IN %@", ["1", "a", "A"]))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard keyboard.exists else { return false }
            let frame = keyboard.frame
            return frame.height > 100 && frame.minY < screen.maxY - 100
                && frame.maxY <= screen.maxY + 1 && typingKeys.allElementsBoundByIndex.contains { key in
                    key.isHittable && frame.contains(key.frame)
                }
        }, object: keyboard)
        // Keep the existing CI visibility allowance. The frame alone does not
        // prove usability; the software key must also enter a character below.
        let visibility = XCTWaiter.wait(for: [shown], timeout: 30)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "native-login-keyboard-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        if visibility != .completed {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "native-login-keyboard-tree-\(name)"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertEqual(visibility, .completed, "Software keyboard must be onscreen and usable: \(keyboard.frame)")
        guard let typingKey = typingKeys.allElementsBoundByIndex.first(where: { $0.isHittable && keyboard.frame.contains($0.frame) }),
              let before = field.value as? String else {
            XCTFail("A visible software key and the focused field value must be available")
            return
        }
        let fieldType = field.elementType
        typingKey.tap()
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = field.value as? String else { return false }
            // Secure fields expose an accessibility value, not the password.
            // A localized character-count description can change while its
            // string length stays constant. The selected software key above
            // is an insertion key, so require an observable value change.
            if fieldType == .secureTextField { return value != before }
            return value.utf16.count > before.utf16.count
        }, object: field)
        let entry = XCTWaiter.wait(for: [entered], timeout: 5)
        if entry != .completed {
            let value = field.value as? String
            let detail = XCTAttachment(string: """
                elementType=\(fieldType.rawValue)
                beforeUTF16Count=\(before.utf16.count)
                afterUTF16Count=\(value?.utf16.count.description ?? "unavailable")
                valueChanged=\(value.map { String($0 != before) } ?? "unavailable")
                beforeMatchesPlaceholder=\(field.placeholderValue == before)
                """)
            detail.name = "native-login-key-entry-\(name)"; detail.lifetime = .keepAlways; add(detail)
        }
        XCTAssertEqual(entry, .completed,
                       "Tapping the software keyboard must actually enter a character")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertLessThan(dismiss.frame.maxY, keyboard.frame.minY)
        dismiss.tap()
        // A count query can spend the whole predicate deadline retrying a
        // removed toolbar button. Use XCTest's absence wait before checking
        // any keyboard nodes that the accessibility service may retain.
        let focusDismissed = dismiss.waitForNonExistence(timeout: 10)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // Query current matches instead of re-resolving the old keyboard
            // node: XCTest retries a removed node, consuming this whole wait
            // even when the keyboard and focus action have already disappeared.
            // Retained keyboard nodes and typing keys must still be inert.
            return app.keyboards.allElementsBoundByIndex.allSatisfy { currentKeyboard in
                !currentKeyboard.isHittable
            } && typingKeys.allElementsBoundByIndex.allSatisfy { !$0.isHittable }
        }, object: nil)
        let dismissal = XCTWaiter.wait(for: [hidden], timeout: 10)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "native-login-after-dismiss-\(name)"; after.lifetime = .keepAlways; add(after)
        if !focusDismissed || dismissal != .completed {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "native-login-after-dismiss-tree-\(name)"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(focusDismissed, "The focus dismissal action must disappear")
        XCTAssertEqual(dismissal, .completed, "The keyboard and typing keys must no longer be interactive")
        XCTAssertFalse(dismiss.exists)
    }

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
        let timeoutMessage = "读取旧版记录用时较长，请重新读取。"
        let state = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["未发现旧版记录", timeoutMessage])).firstMatch
        let ready = state.waitForExistence(timeout: 25)
        if !ready || state.label == timeoutMessage {
            let issue = XCTAttachment(string: app.debugDescription)
            issue.name = "native-legacy-import-initial-state"; issue.lifetime = .keepAlways; add(issue)
        }
        XCTAssertTrue(ready, "The reader must finish with an empty result or an explicit timeout")
        if state.label == timeoutMessage {
            let retry = app.buttons["重新读取"]
            XCTAssertTrue(retry.isHittable); retry.tap()
        }
        let empty = app.staticTexts["未发现旧版记录"].waitForExistence(timeout: 25)
        if !empty {
            let issue = XCTAttachment(string: app.debugDescription)
            issue.name = "native-legacy-import-final-state"; issue.lifetime = .keepAlways; add(issue)
        }
        XCTAssertTrue(empty, "A timeout may be retried once; it must never count as empty data")
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
