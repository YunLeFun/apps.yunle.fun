import SwiftUI

struct SupportCenterView: View {
    @ObservedObject private var accounts: AccountStore
    @StateObject private var model: SupportCenterStore
    @State private var destination: SupportDestination
    @State private var description: String
    @State private var screenshots: [FeedbackScreenshot]
    @State private var isImportingScreenshots = false
    @State private var pendingSubmission: SubmissionDraft?
    @State private var product = "www"
    @State private var managedProduct: String?
    @State private var category = "problem"
    @State private var browser: SupportBrowserPage?
    @State private var nativeTicket: SupportTicketPage?
    @State private var screenshotPreview: FeedbackScreenshot?
    @State private var showLogin = false
    @State private var confirmSubmit = false
    private let onDescriptionChanged: (String) -> Void
    private let onScreenshotsChanged: ([FeedbackScreenshot]) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var descriptionFocused: Bool

    private struct SubmissionDraft {
        let product: String
        let category: String
        let description: String
        let screenshots: [FeedbackScreenshot]
    }

    init(accounts: AccountStore, destination: SupportDestination = .compose, initialDescription: String = "",
         initialScreenshots: [FeedbackScreenshot] = [], service: SupportCenterServing = SupportCenterService(),
         onDescriptionChanged: @escaping (String) -> Void = { _ in },
         onScreenshotsChanged: @escaping ([FeedbackScreenshot]) -> Void = { _ in }) {
        self.accounts = accounts
        self.onDescriptionChanged = onDescriptionChanged
        self.onScreenshotsChanged = onScreenshotsChanged
        _destination = State(initialValue: destination)
        _description = State(initialValue: initialDescription)
        _screenshots = State(initialValue: initialScreenshots)
        _model = StateObject(wrappedValue: SupportCenterStore(accounts: accounts, service: service))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("支持中心", selection: $destination) {
                        ForEach(SupportDestination.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("support.center.destination")
                }
                if model.isLoading { ProgressView("正在连接支持中心") }
                if let error = model.error {
                    Section {
                        Text(error).accessibilityIdentifier("support.center.error")
                        if model.needsConsent {
                            Button("允许使用当前账号") { Task { await model.load(destination, product: managedProduct, consent: true) } }
                        } else {
                            Button("重试连接") { Task { await model.load(destination, product: managedProduct) } }
                        }
                    }
                }
                switch destination {
                case .compose: compose
                case .board: board
                case .manage: management
                }
                Section {
                    Button { open(path: "") } label: { Label("打开完整支持中心", systemImage: "globe") }
                        .disabled(model.isSubmitting)
                        .accessibilityIdentifier("support.center.website")
                }
            }
            .navigationTitle(destination.title)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(model.isSubmitting) }
                if descriptionFocused {
                    ToolbarItem(placement: .keyboard) { Button("完成输入") { descriptionFocused = false } }
                }
            }
            .task(id: loadID) { await model.load(destination, product: managedProduct) }
            .refreshable { await model.load(destination, product: managedProduct) }
            .onChange(of: accounts.identityGeneration) { _ in
                browser = nil; nativeTicket = nil; confirmSubmit = false; description = ""; managedProduct = nil
                screenshotPreview = nil
                screenshots = []
                model.identityChanged()
            }
            .onChange(of: destination) { _ in browser = nil; confirmSubmit = false; descriptionFocused = false }
            .onChange(of: description) { onDescriptionChanged($0) }
            .onChange(of: screenshots) { onScreenshotsChanged($0) }
            .sheet(item: $browser) { page in
                SupportBrowserView(page: page).id(accounts.identityGeneration)
            }
            .sheet(item: $nativeTicket) { page in
                SupportTicketView(page: page).id(accounts.identityGeneration)
            }
            .sheet(item: $screenshotPreview) { screenshot in
                NavigationStack { ScreenshotPreview(data: screenshot.data, imageLabel: "待提交的截图预览") }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(continuationMessage: "登录后，支持中心会使用当前账号查看你的工单和管理权限。")
                    .environmentObject(accounts)
            }
            .confirmationDialog("提交这条私密反馈？", isPresented: $confirmSubmit, titleVisibility: .visible,
                                presenting: pendingSubmission) { draft in
                Button("提交反馈") {
                    Task { await model.submit(product: draft.product, category: draft.category,
                                              description: draft.description, screenshots: draft.screenshots) }
                }
                Button("取消", role: .cancel) { }
            } message: { draft in
                Text("问题描述\(draft.screenshots.isEmpty ? "" : "和 \(draft.screenshots.count) 张截图")将发送给\(SupportProduct.title(draft.product))的支持人员。不会自动附带诊断日志。")
            }
            .onChange(of: model.receipt?.id) { if $0 != nil { screenshots = [] } }
            .onChange(of: confirmSubmit) { if !$0 { pendingSubmission = nil } }
        }
        .id(accounts.identityGeneration)
        .interactiveDismissDisabled(model.isSubmitting)
        .onDisappear { model.close() }
    }

    private var loadID: String { "\(accounts.identityGeneration)|\(destination.rawValue)|\(managedProduct ?? "")" }

    @ViewBuilder private var compose: some View {
        if let receipt = model.receipt {
            Section {
                Label("反馈已收到", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(receipt.id).font(.footnote.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("support.center.receipt")
                if let url = SupportCenterService.ticketURL(receipt) {
                    Button("查看工单与回复") { nativeTicket = SupportTicketPage(receipt: receipt, access: model.access) }
                    if accounts.user == nil {
                        ShareLink("保存工单访问链接", item: url)
                        Text("此链接包含访客访问凭证，请保存到自己的备忘录，不要转发给他人。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: { Text("反馈内容仅支持人员可见。请在工单中查看后续回复。") }
        } else {
            FeedbackScreenshotSection(screenshots: $screenshots, onPreview: { descriptionFocused = false; screenshotPreview = $0 },
                                      onImportingChanged: { isImportingScreenshots = $0 })
                .disabled(model.isSubmitting)
            Section {
                Picker("相关产品", selection: $product) {
                    ForEach(SupportProduct.submissionIDs, id: \.self) { Text(SupportProduct.title($0)).tag($0) }
                }
                Picker("反馈类型", selection: $category) {
                    Text("遇到问题").tag("problem")
                    Text("功能建议").tag("suggestion")
                    Text("其他").tag("other")
                }
                TextEditor(text: $description).frame(minHeight: 150).focused($descriptionFocused)
                    .accessibilityLabel("在线反馈描述").accessibilityIdentifier("support.center.description")
                Text("\(description.utf16.count) / 4000").font(.caption).foregroundStyle(.secondary)
                if let user = accounts.user {
                    Label(user.displayName, systemImage: "person.crop.circle")
                    Text("使用当前云乐坊账号，后续可在“我的工单”查看进度。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("以访客身份提交。提交后请保留当前工单页面，或先登录以便以后找回。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("登录云乐坊") { showLogin = true }
                }
                Button {
                    descriptionFocused = false
                    pendingSubmission = SubmissionDraft(product: product, category: category,
                                                        description: description, screenshots: screenshots)
                    confirmSubmit = true
                } label: {
                    Label(model.isSubmitting ? "正在提交" : "提交私密反馈", systemImage: "paperplane")
                }
                .disabled(model.access == nil || model.isLoading || model.isSubmitting || isImportingScreenshots
                          || !(5...4000).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count))
                .accessibilityIdentifier("support.center.submit")
                if model.isSubmitting { ProgressView() }
            } header: { Text("告诉我们发生了什么") }
            footer: { Text("可以写下操作步骤、预期和实际结果。请勿填写密码或验证码。反馈不会发布到公开需求墙。") }
            .disabled(model.isSubmitting)
        }
        if accounts.user != nil {
            Section { Button("我的工单") { open(path: "tickets") }.disabled(model.access == nil) }
        }
    }

    @ViewBuilder private var board: some View {
        Section {
            if model.hasLoaded && model.board.isEmpty { Text("暂时没有公开需求。").foregroundStyle(.secondary) }
            ForEach(model.board) { item in
                NavigationLink {
                    SupportBoardDetail(item: item, access: model.access)
                } label: { boardRow(item) }
            }
            if model.boardCursor != nil {
                Button("加载更多需求") { Task { await model.load(.board, more: true) } }.disabled(model.isLoading)
            }
        } header: { Text("公开需求与产品进展") }
        footer: { Text("查看大家关心的问题。投票与完整路线图可在支持中心网页中继续。") }
        Section { Button("查看路线图") { open(path: "roadmap") } }
    }

    @ViewBuilder private var management: some View {
        if accounts.user == nil {
            Section {
                Label("登录后验证管理权限", systemImage: "person.badge.key")
                Button("登录云乐坊") { showLogin = true }
            }
        } else if let dashboard = model.dashboard {
            Section {
                Picker("管理产品", selection: Binding(get: { managedProduct ?? dashboard.productId }, set: { managedProduct = $0 })) {
                    ForEach(dashboard.productIds, id: \.self) { Text(SupportProduct.title($0)).tag($0) }
                }
            }
            Section("私密反馈") {
                if dashboard.privateFeedback.items.isEmpty { Text("当前没有私密反馈。").foregroundStyle(.secondary) }
                ForEach(dashboard.privateFeedback.items) { item in
                    NavigationLink {
                        SupportPrivateDetail(item: item, access: model.access)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.description).lineLimit(3)
                            Text("\(item.sourceSummary) · \(item.statusTitle)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if dashboard.privateFeedback.nextCursor != nil {
                    Button("下一页私密反馈") { Task { await model.load(.manage, product: dashboard.productId, more: true) } }
                        .disabled(model.isLoading)
                }
            }
            Section("公开需求") {
                ForEach(dashboard.feedback.items) { item in
                    NavigationLink { SupportBoardDetail(item: item, access: model.access) } label: { boardRow(item) }
                }
                Button("打开完整反馈管理") { open(path: "manage") }
            }
        }
    }

    private func boardRow(_ item: SupportBoardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.headline)
            Text("\(SupportProduct.title(item.productId)) · \(item.statusTitle) · \(item.voteCount) 票")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func open(path: String) { browser = SupportBrowserPage(url: SupportCenterService.pageURL(path: path), access: model.access) }
}

private struct SupportBoardDetail: View {
    let item: SupportBoardItem
    let access: SupportAccess?
    @State private var browser: SupportBrowserPage?
    var body: some View {
        List {
            Section {
                Text(item.title).font(.title2.bold())
                LabeledContent("状态", value: item.statusTitle)
                LabeledContent("支持票数", value: String(item.voteCount))
                Text(item.publicContent).textSelection(.enabled)
            }
            if let response = item.officialResponse, !response.isEmpty { Section("官方回复") { Text(response).textSelection(.enabled) } }
            Section {
                Button("在支持中心继续") {
                    browser = SupportBrowserPage(url: SupportCenterService.pageURL(path: "feedback/" + item.id), access: access)
                }
            }
        }
        .navigationTitle("需求详情").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browser) { SupportBrowserView(page: $0) }
    }
}

private struct SupportPrivateDetail: View {
    let item: SupportPrivateItem
    let access: SupportAccess?
    @State private var browser: SupportBrowserPage?
    var body: some View {
        List {
            Section {
                LabeledContent("产品", value: SupportProduct.title(item.productId))
                LabeledContent("来源平台", value: item.sourceTitle)
                if let version = item.context?.version, !version.isEmpty {
                    LabeledContent("客户端版本", value: version)
                }
                LabeledContent("状态", value: item.statusTitle)
                Text(item.description).textSelection(.enabled)
                Text(item.id).font(.caption.monospaced()).textSelection(.enabled)
            }
            Section {
                Button("处理工单与回复") {
                    let path = item.ticketId.map { "manage/tickets/" + $0 } ?? "manage"
                    browser = SupportBrowserPage(url: SupportCenterService.pageURL(path: path), access: access)
                }
            }
        }
        .navigationTitle("私密反馈").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browser) { SupportBrowserView(page: $0) }
    }
}
