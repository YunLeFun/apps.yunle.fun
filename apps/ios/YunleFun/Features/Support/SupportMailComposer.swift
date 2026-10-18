import Foundation
import MessageUI
import SwiftUI
import UIKit

struct SupportMailContext: Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let systemVersion: String

    @MainActor static var current: Self {
        Self(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知",
             buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知",
             systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
    }

    var text: String { "App 版本：\(appVersion)（\(buildNumber)）\n系统版本：\(systemVersion)" }
}

struct SupportMailDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String

    var shareText: String { "收件人：\(recipient)\n主题：\(subject)\n\n\(body)" }

    static func feedback(issueDescription: String, supportCode: String?, context: SupportMailContext) -> Self {
        let issue = issueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = supportCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let validCode = code.range(of: #"^[A-Z0-9]{12}$"#, options: .regularExpression) != nil
        return Self(recipient: SupportContactLinks.supportEmail, subject: "【问题反馈】来自云乐坊用户", body: """
            您好，

            我在使用云乐坊时遇到了以下问题：

            问题描述：\(issue)
            操作步骤：
            期望结果：
            实际结果：

            支持编号：\(validCode ? code : "未提供")
            \(context.text)

            ---
            发送自 云乐坊 (yunle.fun)
            """)
    }

    static func business(context: SupportMailContext) -> Self {
        Self(recipient: SupportContactLinks.businessEmail, subject: "【业务合作】来自云乐坊用户", body: """
            您好，

            我对云乐坊的业务合作感兴趣：

            公司/个人名称：
            联系方式：
            合作意向：

            \(context.text)

            ---
            发送自 云乐坊 (yunle.fun)
            """)
    }
}

enum SupportMailOutcome: Sendable {
    case cancelled, saved, queued, failed

    var message: String? {
        switch self {
        case .cancelled: return nil
        case .saved: return "草稿已保存在系统邮件中。"
        case .queued: return "已交给系统邮件发送，请在邮件 App 中查看发送状态。"
        case .failed: return "系统邮件未能完成操作。你仍可复制邮箱或分享反馈内容。"
        }
    }
}

@MainActor
struct SupportMailComposer: View {
    let draft: SupportMailDraft
    let onResult: (SupportMailOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(draft: SupportMailDraft, onResult: @escaping (SupportMailOutcome) -> Void) {
        self.draft = draft
        self.onResult = onResult
    }

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            SupportMailController(draft: draft) { result in
                onResult(result)
                dismiss()
            }
            .ignoresSafeArea()
        } else {
            SupportMailUnavailableView(draft: draft)
        }
    }
}

@MainActor
private struct SupportMailController: UIViewControllerRepresentable {
    let draft: SupportMailDraft
    let onFinish: (SupportMailOutcome) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (SupportMailOutcome) -> Void
        init(onFinish: @escaping (SupportMailOutcome) -> Void) { self.onFinish = onFinish }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                               didFinishWith result: MFMailComposeResult, error: Error?) {
            let outcome: SupportMailOutcome
            if error != nil { outcome = .failed }
            else {
                switch result {
                case .cancelled: outcome = .cancelled
                case .saved: outcome = .saved
                case .sent: outcome = .queued
                case .failed: outcome = .failed
                @unknown default: outcome = .failed
                }
            }
            Task { @MainActor [weak self] in self?.onFinish(outcome) }
        }
    }
}

@MainActor
struct SupportMailFallbackActions: View {
    let draft: SupportMailDraft
    let identifierPrefix: String
    let contentName: String
    @State private var copied: CopyKind?
    @AccessibilityFocusState(for: .voiceOver) private var noticeFocused: Bool

    private enum CopyKind { case email, content }

    init(draft: SupportMailDraft, identifierPrefix: String, contentName: String = "反馈内容") {
        self.draft = draft
        self.identifierPrefix = identifierPrefix
        self.contentName = contentName
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = draft.recipient
            copied = .email
        } label: { Label("复制邮箱", systemImage: "doc.on.doc").frame(minHeight: 44) }
            .accessibilityLabel("复制邮箱，\(draft.recipient)")
            .accessibilityIdentifier(identifierPrefix + ".copy-email")
        if copied == .email { notice("邮箱已复制。") }
        Button {
            UIPasteboard.general.string = draft.shareText
            copied = .content
        } label: { Label("复制\(contentName)", systemImage: "doc.on.doc").frame(minHeight: 44) }
            .accessibilityIdentifier(identifierPrefix + ".copy-content")
        if copied == .content { notice("\(contentName)已复制。") }
        ShareLink(item: draft.shareText) {
            Label("分享\(contentName)", systemImage: "square.and.arrow.up").frame(minHeight: 44)
        }
        .accessibilityIdentifier(identifierPrefix + ".share-content")
    }

    private func notice(_ message: String) -> some View {
        Text(message).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifierPrefix + ".notice")
            .accessibilityFocused($noticeFocused)
            .onAppear { noticeFocused = true }
    }
}

@MainActor
private struct SupportMailUnavailableView: View {
    let draft: SupportMailDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("此设备未配置系统邮件。你仍可复制邮箱或分享反馈内容。")
                        .accessibilityIdentifier("support.mail.unavailable")
                    SupportMailFallbackActions(draft: draft, identifierPrefix: "support.mail.fallback")
                }
            }
            .navigationTitle("邮件不可用")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}
