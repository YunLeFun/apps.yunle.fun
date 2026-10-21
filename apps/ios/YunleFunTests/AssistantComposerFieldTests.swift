import UIKit
import XCTest
@testable import YunleFun

@MainActor
final class AssistantComposerFieldTests: XCTestCase {
    private var submissions = 0
    private func makeView(_ text: String = "") -> AssistantComposerTextView {
        submissions = 0
        let view = AssistantComposerTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 44), textContainer: nil)
        view.text = text
        view.onSubmit = { [unowned self] in submissions += 1 }
        return view
    }
    private func replaceAll(_ view: AssistantComposerTextView, with text: String) throws {
        view.replace(try XCTUnwrap(view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)), withText: text)
    }

    func testKeyboardReturnSendsWithoutChangingTheDraft() {
        let view = makeView("记账")
        view.insertText("\n")
        XCTAssertEqual(submissions, 1)
        XCTAssertEqual(view.text, "记账")
    }
    func testTypingStillInsertsText() {
        let view = makeView()
        view.insertText("a"); view.insertText("b")
        XCTAssertEqual(view.text, "ab"); XCTAssertEqual(submissions, 0)
    }
    func testPastedOrReplacedNewlinesStayInTheDraft() throws {
        let view = makeView("问题")
        view.replace(try XCTUnwrap(view.textRange(from: view.endOfDocument, to: view.endOfDocument)), withText: "\n")
        XCTAssertEqual(view.text, "问题\n")
        try replaceAll(view, with: "粘贴的问题\n")
        XCTAssertEqual(view.text, "粘贴的问题\n")
        XCTAssertEqual(submissions, 0, "Pastes, drops and dictation replace text without the keyboard and never send")
    }
    func testShiftReturnAddsALineAndCommandReturnSends() throws {
        let view = makeView("第一行")
        view.selectedRange = NSRange(location: 3, length: 0)
        view.insertNewline()
        XCTAssertEqual(view.text, "第一行\n"); XCTAssertEqual(submissions, 0)
        view.submitFromKeyboard()
        XCTAssertEqual(submissions, 1)
        let commands = try XCTUnwrap(view.keyCommands).filter { $0.input == "\r" }
        XCTAssertEqual(Set(commands.map(\.modifierFlags.rawValue)), [UIKeyModifierFlags.shift.rawValue, UIKeyModifierFlags.command.rawValue])
    }
    func testReturnWhileAnInputMethodIsComposingOnlyConfirmsTheCandidate() {
        let view = makeView()
        view.setMarkedText("ji", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        view.insertText("\n")
        XCTAssertEqual(submissions, 0)
        XCTAssertNil(view.markedTextRange)
        XCTAssertEqual(view.text, "ji", "Confirming the candidate must not add a newline")
    }
}
