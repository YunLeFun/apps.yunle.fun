import MessageUI
import SwiftUI
import UIKit

enum SupportContactLinks {
    static let supportEmail = "kf@yunle.fun"
    static let businessEmail = "i@yunle.fun"
    static let wechat = URL(string: "https://work.weixin.qq.com/kfid/kfc9d4dcc4b6bd1c69e")!
    static let officialAccount = "云乐坊工作室"
    static let appStore = URL(string: "https://apps.apple.com/app/id6759859441")!
    static let documents = URL(string: "https://www.yunle.fun/docs")!
    static let privacy = URL(string: "https://www.yunle.fun/docs/privacy-policy")!
    static let terms = URL(string: "https://www.yunle.fun/docs/terms-of-service")!
}

@MainActor
struct SupportContactSection: View {
    let issueDescription: String
    let supportCode: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    @State private var notice: String?
    @State private var canSendMail = MFMailComposeViewController.canSendMail()
    @AccessibilityFocusState(for: .voiceOver) private var noticeFocused: Bool

    private enum Sheet: Identifiable {
        case mail(SupportMailDraft), website(URL)
        var id: String {
            switch self {
            case .mail(let draft): return draft.id.uuidString
            case .website(let url): return url.absoluteString
            }
        }
    }

    init(issueDescription: String, supportCode: String?) {
        self.issueDescription = issueDescription
        self.supportCode = supportCode
    }

    private var feedback: SupportMailDraft {
        .feedback(issueDescription: issueDescription, supportCode: supportCode, context: .current)
    }

    var body: some View {
        Group {
            Section {
                Text(SupportContactLinks.supportEmail).textSelection(.enabled)
                    .accessibilityLabel("问题反馈邮箱，\(SupportContactLinks.supportEmail)")
                Button { compose(feedback) } label: {
                    Label("撰写反馈邮件", systemImage: "envelope").frame(minHeight: 44)
                }
                .disabled(!canSendMail)
                .accessibilityIdentifier("support.mail.feedback")
                if !canSendMail {
                    Text("此设备未配置系统邮件。你仍可复制邮箱或分享反馈内容。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("support.mail.unavailable")
                }
                SupportMailFallbackActions(draft: feedback, identifierPrefix: "support.feedback")
                DisclosureGroup("查看反馈内容") {
                    Text(verbatim: feedback.shareText).font(.footnote).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("support.feedback.preview")
            } header: { Text("问题反馈") } footer: {
                Text("你可以在系统界面中核对和编辑内容，再决定是否发送。邮件与分享内容不会自动附带诊断日志。")
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .mail(let draft): SupportMailComposer(draft: draft) { result in notice = result.message }
                case .website(let url): SafariView(url: url)
                }
            }
            .onChange(of: scenePhase) { if $0 == .active { canSendMail = MFMailComposeViewController.canSendMail() } }
            .onChange(of: notice) { if $0 != nil { noticeFocused = true } }
            if let notice {
                Section {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                        .accessibilityFocused($noticeFocused)
                        .accessibilityIdentifier("support.notice")
                }
            }
            Section("微信客服") {
                Button {
                    openURL(SupportContactLinks.wechat) { accepted in
                        if !accepted { notice = "未能打开微信客服。可以复制或分享客服链接，稍后在浏览器中打开。" }
                    }
                } label: { Label("打开微信客服", systemImage: "bubble.left.and.bubble.right").frame(minHeight: 44) }
                    .accessibilityIdentifier("support.wechat.open")
                Button {
                    UIPasteboard.general.string = SupportContactLinks.wechat.absoluteString
                    notice = "微信客服链接已复制。"
                } label: { Label("复制客服链接", systemImage: "doc.on.doc").frame(minHeight: 44) }
                    .accessibilityIdentifier("support.wechat.copy")
                ShareLink(item: SupportContactLinks.wechat) {
                    Label("分享客服链接", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                }
                .accessibilityIdentifier("support.wechat.share")
            }
            Section("业务合作") {
                DisclosureGroup("联系业务合作") {
                    Text(SupportContactLinks.businessEmail).textSelection(.enabled)
                    Button { compose(.business(context: .current)) } label: {
                        Label("撰写合作邮件", systemImage: "envelope").frame(minHeight: 44)
                    }
                    .disabled(!canSendMail)
                    .accessibilityIdentifier("support.mail.business")
                    SupportMailFallbackActions(draft: .business(context: .current), identifierPrefix: "support.business", contentName: "合作内容")
                }
            }
            Section("支持我们") {
                Button {
                    openURL(SupportContactLinks.appStore) { accepted in
                        if !accepted { notice = "暂时无法打开 App Store，请稍后重试。" }
                    }
                } label: { Label("去 App Store 评分", systemImage: "star").frame(minHeight: 44) }
                    .accessibilityIdentifier("support.rating")
            }
            Section("社交媒体") {
                Button {
                    UIPasteboard.general.string = SupportContactLinks.officialAccount
                    notice = "公众号名称已复制，请在微信中搜索“云乐坊工作室”。"
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("复制微信公众号名称")
                        Text(SupportContactLinks.officialAccount).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                }
                .accessibilityIdentifier("support.wechat-official.copy")
                website("GitHub · YunLeFun", url: "https://github.com/yunlefun", id: "github")
                website("X · @yunlefun", url: "https://x.com/yunlefun", id: "x")
                website("Bilibili · 云乐坊工作室", url: "https://space.bilibili.com/yunlefun", id: "bilibili")
                website("云乐坊官网", url: "https://www.yunle.fun", id: "website")
                website("云乐坊工作室", url: "https://studio.yunle.fun", id: "studio")
            }
        }
    }

    private func compose(_ draft: SupportMailDraft) {
        canSendMail = MFMailComposeViewController.canSendMail()
        guard canSendMail else {
            notice = "此设备未配置系统邮件。你仍可复制邮箱或分享反馈内容。"
            return
        }
        sheet = .mail(draft)
    }

    private func website(_ title: String, url: String, id: String) -> some View {
        Button { if let url = URL(string: url) { sheet = .website(url) } } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .accessibilityIdentifier("support.social." + id)
    }
}
