import MessageUI
import SwiftUI
import UIKit
import YunleSupportUI

enum SupportContactLinks {
    static let supportEmail = "kf@yunle.fun"
    static let businessEmail = "i@yunle.fun"
    static let wechat = URL(string: "https://work.weixin.qq.com/kfid/kfc9d4dcc4b6bd1c69e")!
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
                    SupportMenuLabel("撰写反馈邮件", icon: .system("envelope"))
                }
                .supportMenuRow()
                .disabled(!canSendMail)
                .accessibilityIdentifier("support.mail.feedback")
                if !canSendMail {
                    Text("此设备未配置系统邮件。你仍可复制邮箱或分享反馈内容。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("support.mail.unavailable")
                }
                SupportMailFallbackActions(draft: feedback, identifierPrefix: "support.feedback")
                DisclosureGroup {
                    Text(verbatim: feedback.shareText).font(.footnote).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    SupportMenuLabel("查看反馈内容", icon: .system("doc.text.magnifyingglass"))
                }
                .supportMenuRow()
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
                } label: { SupportMenuLabel("打开微信客服", icon: .brand(.wechat), external: true) }
                    .supportMenuRow()
                    .accessibilityIdentifier("support.wechat.open")
                Button {
                    UIPasteboard.general.string = SupportContactLinks.wechat.absoluteString
                    notice = "微信客服链接已复制。"
                } label: { SupportMenuLabel("复制客服链接", icon: .system("doc.on.doc")) }
                    .supportMenuRow()
                    .accessibilityIdentifier("support.wechat.copy")
                ShareLink(item: SupportContactLinks.wechat) {
                    SupportMenuLabel("分享客服链接", icon: .system("square.and.arrow.up"))
                }
                .supportMenuRow()
                .accessibilityIdentifier("support.wechat.share")
            }
            Section("业务合作") {
                DisclosureGroup {
                    Text(SupportContactLinks.businessEmail).textSelection(.enabled)
                    Button { compose(.business(context: .current)) } label: {
                        SupportMenuLabel("撰写合作邮件", icon: .system("envelope"))
                    }
                    .supportMenuRow()
                    .disabled(!canSendMail)
                    .accessibilityIdentifier("support.mail.business")
                    SupportMailFallbackActions(draft: .business(context: .current), identifierPrefix: "support.business", contentName: "合作内容")
                } label: {
                    SupportMenuLabel("联系业务合作", icon: .system("briefcase"))
                }
                .supportMenuRow()
            }
            Section("支持我们") {
                Button {
                    openURL(SupportContactLinks.appStore) { accepted in
                        if !accepted { notice = "暂时无法打开 App Store，请稍后重试。" }
                    }
                } label: { SupportMenuLabel("去 App Store 评分", icon: .system("star"), external: true) }
                    .supportMenuRow()
                    .accessibilityIdentifier("support.rating")
            }
            SupportSocialSection { url in
                sheet = .website(url)
            } copyOfficialAccount: { name in
                UIPasteboard.general.string = name
                notice = "公众号名称已复制，请在微信中搜索“\(name)”。"
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

}
