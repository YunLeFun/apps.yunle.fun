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

    func testPasswordVisibilityPreservesInputAndKeyboardFocus() throws {
        let app = try openPasswordLogin()
        let username = app.textFields["login.username"]
        username.tap(); username.typeText("ui-canary\n")
        // Tap a real software key without tapping the password field: Next must have moved focus.
        let first = try tapLetterKey(app)
        let visibility = app.buttons["login.password-visibility"]
        XCTAssertEqual(visibility.label, "显示密码")
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertGreaterThanOrEqual(visibility.frame.width, 44)
        XCTAssertGreaterThanOrEqual(visibility.frame.height, 44)
        visibility.tap()
        let revealed = app.textFields["login.password"]
        XCTAssertTrue(revealed.waitForExistence(timeout: 5))
        XCTAssertEqual(revealed.value as? String, first)
        XCTAssertEqual(visibility.label, "隐藏密码")
        let second = try tapLetterKey(app)
        XCTAssertEqual(revealed.value as? String, first + second, "Revealing must retain keyboard focus")
        visibility.tap()
        XCTAssertTrue(app.secureTextFields["login.password"].waitForExistence(timeout: 5))
        let third = try tapLetterKey(app)
        visibility.tap()
        XCTAssertEqual(revealed.value as? String, first + second + third, "Hiding must not clear or replace existing input")
        XCTAssertEqual(username.value as? String, "ui-canary")
        capturePasswordLogin(app, "password-visible-keyboard")

        let dismiss = app.buttons["login.dismiss-keyboard"]
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 10))
        visibility.tap()
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertFalse(dismiss.exists, "Revealing or hiding an unfocused field must not reopen the keyboard")
        XCTAssertTrue(app.keyboards.allElementsBoundByIndex.allSatisfy { !$0.isHittable })
        visibility.tap()
        XCTAssertEqual(revealed.value as? String, first + second + third)
        capturePasswordLogin(app, "password-visible-keyboard-dismissed")
        app.buttons["取消"].tap()
    }

    func testPasswordLoginOffersVerificationAndResetsVisibility() throws {
        let app = try openPasswordLogin()
        let visibility = app.buttons["login.password-visibility"]
        app.secureTextFields["login.password"].tap()
        _ = try tapLetterKey(app)
        visibility.tap()
        app.buttons["login.dismiss-keyboard"].tap()
        let phoneLink = app.buttons["login.use-phone-code"]
        XCTAssertTrue(phoneLink.isHittable)
        XCTAssertTrue(app.buttons["login.use-email-code"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["login.submit"].frame.height, 44)
        capturePasswordLogin(app, "password-login-actions")
        phoneLink.tap()
        let phone = app.textFields["login.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        let numberKey = app.keys["1"]
        XCTAssertTrue(numberKey.waitForExistence(timeout: 5)); numberKey.tap()
        XCTAssertEqual(phone.value as? String, "1", "The phone route must show a working number pad")
        app.buttons["login.dismiss-keyboard"].tap()
        app.segmentedControls.buttons["密码"].tap()
        let secure = app.secureTextFields["login.password"]
        XCTAssertTrue(secure.waitForExistence(timeout: 5))
        XCTAssertEqual(visibility.label, "显示密码")
        visibility.tap()
        let revealed = app.textFields["login.password"]
        XCTAssertTrue(revealed.waitForExistence(timeout: 5))
        XCTAssertEqual(revealed.value as? String, "密码", "Switching methods must clear the prior password")
        app.buttons["login.use-email-code"].tap()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("ui-canary@example.invalid")
        XCTAssertEqual(email.value as? String, "ui-canary@example.invalid")
        app.buttons["login.dismiss-keyboard"].tap()
        app.segmentedControls.buttons["密码"].tap()
        XCTAssertTrue(secure.waitForExistence(timeout: 5))
        XCTAssertEqual(visibility.label, "显示密码")
        app.buttons["取消"].tap()
    }

    func testPasswordVisibilityPreservesCaretAndRefocusedInput() throws {
        let app = try openPasswordLogin()
        let secure = app.secureTextFields["login.password"]
        let visibility = app.buttons["login.password-visibility"]
        secure.tap(); secure.typeText("leftRIGHT")
        visibility.tap()
        let revealed = app.textFields["login.password"]
        XCTAssertTrue(revealed.waitForExistence(timeout: 5))
        XCTAssertEqual(revealed.value as? String, "leftRIGHT")
        // Actual arrow-key events move the insertion point five characters from the end.
        for _ in 0..<5 { app.typeKey(.leftArrow, modifierFlags: []) }
        visibility.tap()
        let inserted = try tapLetterKey(app)
        visibility.tap()
        let edited = "left" + inserted + "RIGHT"
        XCTAssertEqual(revealed.value as? String, edited, "Revealing and hiding must preserve the insertion point")
        capturePasswordLogin(app, "password-middle-insertion")

        visibility.tap()
        app.buttons["login.dismiss-keyboard"].tap()
        XCTAssertTrue(app.buttons["login.dismiss-keyboard"].waitForNonExistence(timeout: 10))
        secure.tap()
        let appended = try tapLetterKey(app)
        visibility.tap()
        XCTAssertEqual(revealed.value as? String, edited + appended, "Refocusing a hidden password must append without clearing it")
        capturePasswordLogin(app, "password-refocused-input")
        app.buttons["取消"].tap()
    }

    private func openPasswordLogin() throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A prior journey may have launched at an accessibility text size, where the
        // login method uses a menu. Relaunch with an explicit standard size for this journey.
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        guard app.buttons["me.login"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator; never signs out an existing account")
        }
        app.buttons["me.login"].tap()
        XCTAssertTrue(app.navigationBars["账号"].waitForExistence(timeout: 5))
        let password = app.segmentedControls.buttons["密码"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        XCTAssertTrue(app.secureTextFields["login.password"].waitForExistence(timeout: 5))
        return app
    }

    @discardableResult private func tapLetterKey(_ app: XCUIApplication) throws -> String {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let key = app.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertTrue(key.isHittable)
        XCTAssertTrue(app.frame.contains(keyboard.frame), "The actual software keyboard must be onscreen")
        XCTAssertTrue(keyboard.frame.contains(key.frame))
        let letter = key.label
        key.tap()
        return letter
    }

    private func capturePasswordLogin(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func checkLoginKeyboardDismissal(large: Bool, passwordMethod: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName",
                               large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
        let login = app.buttons["me.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertTrue(login.label.hasPrefix("登录云乐坊"))
        login.tap()
        XCTAssertTrue(app.navigationBars["账号"].waitForExistence(timeout: 5))
        if passwordMethod {
            let method = app.segmentedControls.buttons["密码"]
            XCTAssertTrue(method.waitForExistence(timeout: 5))
            method.tap()
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
        let fieldIdentifier = field.identifier
        let insertion = typingKey.label
        typingKey.tap()
        // Match the current snapshot without repeatedly resolving the old
        // element inside a predicate. CI observed the inserted value while
        // that nested resolution was still retrying after its five-second wait.
        // Secure fields expose a localized count/mask, so only their value
        // change is observable; ordinary fields must contain the exact input.
        let valuePredicate = fieldType == .secureTextField
            ? NSPredicate(format: "value != %@", before)
            : NSPredicate(format: "value == %@", before + insertion)
        let fields = fieldType == .secureTextField ? app.secureTextFields : app.textFields
        let entered = fields.matching(identifier: fieldIdentifier).matching(valuePredicate).firstMatch
        let entry = entered.waitForExistence(timeout: 5)
        if !entry {
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
        XCTAssertTrue(entry, "Tapping the software keyboard must actually enter a character")
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
        XCTAssertTrue(app.staticTexts["iCloud 同步已关闭"].exists)
        XCTAssertTrue(app.switches["home.sync.icloud"].exists)
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
