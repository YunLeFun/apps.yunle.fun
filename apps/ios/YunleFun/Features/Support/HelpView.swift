import SwiftUI

struct HelpView: View {
    let logs: DiagnosticLogStore
    let accounts: AccountStore
    let navigateTab: (AppTab) -> Void
    @State private var document: Document?

    private struct Document: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    init(logs: DiagnosticLogStore, accounts: AccountStore, navigateTab: @escaping (AppTab) -> Void) {
        self.logs = logs
        self.accounts = accounts
        self.navigateTab = navigateTab
    }

    var body: some View {
        List {
            Section("新手引导") {
                DisclosureGroup {
                    explanation("在寻乐查看推荐，在工坊搜索工具并了解应用详情。")
                    Button("前往寻乐") { navigateTab(.discovery) }
                        .frame(minHeight: 44).accessibilityIdentifier("help.guide.discovery")
                    Button("前往工坊") { navigateTab(.workshop) }
                        .frame(minHeight: 44).accessibilityIdentifier("help.guide.workshop")
                } label: { Text("发现喜欢的云应用").accessibilityIdentifier("help.guide.discover") }
                DisclosureGroup {
                    explanation("在应用详情中选择“获取”。公开的免登录应用可直接添加，需要账号或权益的应用会先显示确认说明。获取后可从云居打开。")
                    Button("前往云居") { navigateTab(.home) }
                        .frame(minHeight: 44).accessibilityIdentifier("help.guide.home")
                } label: { Text("把应用带回云居").accessibilityIdentifier("help.guide.install") }
                DisclosureGroup {
                    explanation("使用云应用时，点“收起应用”返回云乐坊。在云居的“正在运行”中恢复会话；在应用的“更多操作”中选择“结束”，或在运行列表中滑动结束。")
                } label: { Text("恢复或结束运行中的应用").accessibilityIdentifier("help.guide.runtime") }
                DisclosureGroup {
                    explanation("设置支持浅色、深色或跟随系统，也可管理最近使用、常用应用、云居同步和本机备份。")
                    NavigationLink { SettingsView() } label: { Text("前往设置").frame(minHeight: 44) }
                        .accessibilityIdentifier("help.settings")
                } label: { Text("设置外观与云居").accessibilityIdentifier("help.guide.settings") }
            }
            Section("常见问题") {
                faq("what", question: "云乐坊是什么？", answer: "云乐坊汇集各类云应用和实用工具。你可以在工坊发现应用，在云居保存入口，打开后直接使用。")
                faq("account", question: "需要登录才能使用吗？", answer: "部分公开应用无需登录。访客云居保存在本机；账号同步、个人工坊、会员和部分应用能力需要登录。每个账号的云居分别保存。")
                faq("login", question: "支持哪些登录方式？", answer: "登录页面提供手机号验证码、邮箱验证码，以及用户名或手机号加密码。请以当前登录页面为准。")
                faq("remove", question: "从云居移除会结束应用吗？", answer: "从云居移除只移除保存的入口。已收起的会话仍可从“正在运行”恢复；需要关闭会话时，请选择“结束”。")
                faq("appearance", question: "如何切换深色模式？", answer: "进入“我”中的“设置”，在“外观”选择浅色、深色或跟随系统。")
                faq("feedback", question: "遇到问题如何反馈？", answer: "进入“反馈与建议”填写问题，可通过邮件或微信客服联系我们。没有登录、没有本地日志或未配置系统邮件时，也能复制邮箱和分享反馈内容。")
            }
            Section {
                NavigationLink { FeedbackView(logs: logs, accounts: accounts) } label: {
                    Label("反馈与建议", systemImage: "bubble.left.and.bubble.right")
                        .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                }
                .accessibilityIdentifier("help.feedback")
            }
            Section("文档与条款") {
                documentButton("更多帮助文档", url: SupportContactLinks.documents, id: "documents")
                documentButton("隐私政策", url: SupportContactLinks.privacy, id: "privacy")
                documentButton("服务条款", url: SupportContactLinks.terms, id: "terms")
            }
        }
        .navigationTitle("帮助")
        .sheet(item: $document) { SafariView(url: $0.url) }
    }

    private func explanation(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func faq(_ id: String, question: String, answer: String) -> some View {
        DisclosureGroup {
            explanation(answer)
        } label: { Text(question).fixedSize(horizontal: false, vertical: true) }
        .accessibilityIdentifier("help.faq." + id)
    }

    private func documentButton(_ title: String, url: URL, id: String) -> some View {
        Button { document = Document(url: url) } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .accessibilityIdentifier("help." + id)
    }
}
