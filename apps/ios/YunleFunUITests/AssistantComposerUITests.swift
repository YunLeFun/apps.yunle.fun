import XCTest

/// The composer sends only on the keyboard's 发送 / Return; examples and pastes stay editable drafts.
@MainActor
final class AssistantComposerUITests: XCTestCase {
    private let example = "找一个适合写代码的开发工具"

    private func openAssistant() throws -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The entry is members-only by default; open it to guests for this run only.
        app.launchArguments += ["-assistantRolloutAudience", "everyone", "-assistantRolloutPercent", "100"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        guard app.buttons["me.login"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator; never signs out a real account")
        }
        app.tabBars.buttons["云居"].tap()
        XCTAssertTrue(app.buttons["home.assistant"].waitForExistence(timeout: 5))
        app.buttons["home.assistant"].tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 5))
        let input = app.textViews["assistant.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        return (app, input)
    }
    private func assertStillDraft(_ app: XCUIApplication, _ message: String) {
        XCTAssertFalse(app.navigationBars["登录并继续"].waitForExistence(timeout: 2), message)
    }

    func testExampleFillsTheDraftAndReturnSends() throws {
        let (app, input) = try openAssistant()
        app.buttons[example].tap()
        XCTAssertEqual(input.value as? String, example)
        assertStillDraft(app, "Tapping an example only fills the draft")
        input.typeText("\n")
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5), "Return sends; a guest is asked to sign in")
        app.navigationBars["登录并继续"].buttons["取消"].tap()
        XCTAssertEqual(input.value as? String, example, "The draft is kept without a stray newline")
    }

    func testPastedNewlinesStayInTheDraft() throws {
        executionTimeAllowance = 180 // Two pastes through the edit menu, each possibly retried.
        let (app, input) = try openAssistant()
        // A paste ending in a newline, into an empty draft.
        paste("问题\n", into: input, app: app)
        assertStillDraft(app, "Pasting text that ends in a newline must not send")
        XCTAssertEqual(input.value as? String, "问题\n")
        // A lone pasted newline into a non-empty draft looks exactly like Return to a plain text field.
        app.navigationBars["AI 助手"].buttons["新对话"].tap()
        app.buttons[example].tap()
        paste("\n", into: input, app: app)
        assertStillDraft(app, "Pasting a lone newline must not send")
        let value = try XCTUnwrap(input.value as? String)
        XCTAssertEqual(value.count, example.count + 1)
        XCTAssertEqual(value.replacingOccurrences(of: "\n", with: ""), example)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "assistant-composer-pasted-newline"
        shot.lifetime = .keepAlways; add(shot)
    }
    private func paste(_ text: String, into input: XCUIElement, app: XCUIApplication) {
        let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", ["粘贴", "Paste"])).firstMatch
        // A slow runner can miss the first long press, or show the edit menu before the pasteboard
        // write arrives; alternate a long press with a tap on the caret, which also opens the menu.
        for attempt in 0..<4 where !paste.exists {
            UIPasteboard.general.string = text
            input.tap()
            if attempt.isMultiple(of: 2) { input.press(forDuration: 1.2) } else { input.tap() }
            _ = paste.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(paste.exists, "The edit menu never offered 粘贴 (pasteboard holds the text: \(UIPasteboard.general.string == text))")
        paste.tap()
    }
}
