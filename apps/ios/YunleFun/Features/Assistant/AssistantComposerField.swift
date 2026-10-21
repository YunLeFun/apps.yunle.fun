import SwiftUI
import UIKit

/// The assistant's multi-line input. A SwiftUI vertical `TextField` turns the 发送 key into an inserted
/// newline that looks the same as a pasted one, so this wraps a `UITextView` whose keyboard Return is
/// told apart from pastes, dictation, drops and programmatic edits.
struct AssistantComposerField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    var maximumLines = 6
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AssistantComposerTextView {
        let view = AssistantComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = false
        view.accessibilityIdentifier = "assistant.input"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        view.onSubmit = { [weak coordinator] in coordinator?.parent.onSubmit() }
        return view
    }

    func updateUIView(_ view: AssistantComposerTextView, context: Context) {
        context.coordinator.parent = self
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize))
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        if view.font != font { view.font = font; view.placeholderLabel.font = font }
        if view.text != text {
            // Programmatic edits never pass through the keyboard, so they cannot send.
            view.text = text
            view.updatePlaceholder()
        }
        view.placeholderLabel.text = placeholder
        view.accessibilityLabel = placeholder
        if isFocused, !view.isFirstResponder, view.window != nil {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: AssistantComposerTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let lineHeight = (view.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let limit = ceil(lineHeight * CGFloat(maximumLines) + view.textContainerInset.top + view.textContainerInset.bottom)
        let scrolls = fitting > limit
        if view.isScrollEnabled != scrolls {
            DispatchQueue.main.async {
                view.isScrollEnabled = scrolls
                // Keep the caret in view once the field stops growing, for example after a long paste.
                if scrolls { view.scrollRangeToVisible(view.selectedRange) }
            }
        }
        return CGSize(width: width, height: min(ceil(fitting), limit))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AssistantComposerField
        init(_ parent: AssistantComposerField) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? AssistantComposerTextView)?.updatePlaceholder()
            if parent.text != textView.text { parent.text = textView.text }
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { DispatchQueue.main.async { self.parent.isFocused = true } }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { DispatchQueue.main.async { self.parent.isFocused = false } }
        }
    }
}

/// Keyboard Return (software 发送 key or a hardware Return / ⌘Return) submits; Shift+Return inserts a
/// newline. Only `insertText(_:)` from the keyboard counts: pastes, drops, dictation and autocorrection
/// replace text through other paths, so a pasted "\n" always stays in the draft.
final class AssistantComposerTextView: UITextView {
    var onSubmit: (() -> Void)?
    let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.adjustsFontForContentSizeCategory = false
        addSubview(placeholderLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        placeholderLabel.frame = CGRect(x: inset.left, y: inset.top,
                                        width: max(0, bounds.width - inset.left - inset.right), height: placeholderLabel.font.lineHeight)
    }
    func updatePlaceholder() { placeholderLabel.isHidden = !text.isEmpty }

    override func insertText(_ text: String) {
        if text == "\n" {
            // While an input method is composing, Return only confirms the candidate: no send, no newline.
            if markedTextRange != nil { unmarkText() } else { onSubmit?() }
            return
        }
        super.insertText(text)
    }

    override var keyCommands: [UIKeyCommand]? {
        let newline = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertNewline))
        newline.wantsPriorityOverSystemBehavior = true
        newline.discoverabilityTitle = "换行"
        let send = UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(submitFromKeyboard))
        send.wantsPriorityOverSystemBehavior = true
        send.discoverabilityTitle = "发送"
        return (super.keyCommands ?? []) + [newline, send]
    }
    @objc func insertNewline() {
        guard markedTextRange == nil else { return }
        super.insertText("\n")
    }
    @objc func submitFromKeyboard() {
        guard markedTextRange == nil else { return }
        onSubmit?()
    }
}
