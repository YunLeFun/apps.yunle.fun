import SwiftUI

struct WebBuildView: View {
    @EnvironmentObject private var accounts: AccountStore
    var service: WebBuildServing = WebBuildService()

    var body: some View {
        WebBuildList(accounts: accounts, service: service)
            .id(accounts.identityGeneration)
            .navigationTitle("AI 制作网页")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebBuildList: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var store: WebBuildStore
    @State private var showLogin = false
    let service: WebBuildServing

    init(accounts: AccountStore, service: WebBuildServing) {
        self.accounts = accounts
        self.service = service
        _store = StateObject(wrappedValue: WebBuildStore(accounts: accounts, service: service))
    }

    var body: some View {
        List {
            if accounts.user == nil {
                ContentStateView(title: "用 AI 制作网页", systemImage: "sparkles",
                                 message: "有效会员登录并验证手机号后，可生成、修改和分享网页。",
                                 actionTitle: "登录云乐坊", action: { showLogin = true })
            } else {
                if store.canCreate {
                    Section {
                        NavigationLink {
                            WebBuildEditorView(service: service)
                        } label: {
                            Label("新建网页", systemImage: "plus")
                        }
                        .accessibilityIdentifier("webBuild.create")
                    }
                }
                Section("我的网页") {
                    if store.isWorking { ProgressView("载入网页") }
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        Button("重试") { Task { await store.loadList() } }
                    } else if store.canCreate && !store.isWorking && store.projects.isEmpty {
                        Text("用一句话描述你的第一个网页。").foregroundStyle(.secondary)
                    }
                    ForEach(store.projects) { project in
                        NavigationLink {
                            WebBuildEditorView(projectID: project.id, service: service)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: project.title)
                                Text(project.shareUrl == nil ? "私有草稿" : "已发布")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task { if accounts.user != nil { await store.loadList() } }
        .refreshable { await store.loadList() }
        .sheet(isPresented: $showLogin) {
            LoginView(continuationMessage: "创作需要有效会员和已验证手机号的正式账号。")
                .environmentObject(accounts)
        }
    }
}

struct WebBuildEditorView: View {
    @EnvironmentObject private var accounts: AccountStore
    var projectID: String?
    var initialPrompt = ""
    var service: WebBuildServing = WebBuildService()

    var body: some View {
        WebBuildEditorContent(accounts: accounts, projectID: projectID, initialPrompt: initialPrompt, service: service)
            .id(accounts.identityGeneration)
            .navigationTitle("制作网页")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebBuildEditorContent: View {
    @StateObject private var store: WebBuildStore
    @ObservedObject private var accounts: AccountStore
    @State private var prompt = ""
    @State private var shortName = ""
    @State private var confirmation: Confirmation?
    @FocusState private var promptFocused: Bool
    private let projectID: String?

    private enum Confirmation: Equatable {
        case publish, withdraw, submit
        var title: String {
            switch self {
            case .publish: return "发布网页？"
            case .withdraw: return "停用网页？"
            case .submit: return "投稿当前版本？"
            }
        }
        var message: String {
            switch self {
            case .publish: return "获得链接的人可以在浏览器直接查看。"
            case .withdraw: return "分享链接和此前送审的版本链接将暂时无法打开。"
            case .submit: return "云乐坊将审核这一版网页。已上架的旧版在审核期间仍然可用。"
            }
        }
    }

    init(accounts: AccountStore, projectID: String?, initialPrompt: String, service: WebBuildServing) {
        self.accounts = accounts
        self.projectID = projectID
        _prompt = State(initialValue: initialPrompt)
        _store = StateObject(wrappedValue: WebBuildStore(accounts: accounts, service: service))
    }

    var body: some View {
        Form {
            if accounts.user == nil {
                Text("请登录后从工坊重新打开创作。").foregroundStyle(.secondary)
            } else {
                if let project = store.project {
                    Section("修改记录") {
                        ForEach(Array(project.prompts.enumerated()), id: \.offset) { _, message in
                            Text(verbatim: message).textSelection(.enabled)
                        }
                    }
                    Section {
                        NavigationLink {
                            WebBuildPreview(page: project.page)
                        } label: {
                            Label("预览网页", systemImage: "eye")
                        }
                        .accessibilityIdentifier("webBuild.preview")
                    }
                }
                if !store.membershipRequired && (projectID == nil || store.project != nil) { composer }
                if let project = store.project { publication(project) }
                if store.isWorking { ProgressView("正在处理网页") }
                if let error = store.error {
                    Text(error).foregroundStyle(.red)
                        .accessibilityIdentifier("webBuild.error")
                    if let id = store.project?.id ?? projectID {
                        Button("刷新网页") { Task { await store.loadProject(id: id) } }
                    }
                }
            }
        }
        .task {
            if let projectID { await store.loadProject(id: projectID) }
        }
        .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible, presenting: confirmation) { action in
            Button("确认", role: action == .withdraw ? .destructive : nil) {
                Task {
                    switch action {
                    case .publish: await store.update(.publish)
                    case .withdraw: await store.update(.withdraw)
                    case .submit: await store.submit(shortName: shortName.trimmed.lowercased())
                    }
                }
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var composer: some View {
        Section {
            TextField(store.project == nil ? "例如，做一个周末读书会邀请页" : "例如，把配色改成海蓝色",
                      text: $prompt, axis: .vertical)
                .lineLimit(3...6)
                .focused($promptFocused)
                .disabled(store.isWorking)
                .accessibilityLabel(store.project == nil ? "描述你的网页" : "描述你希望的修改")
                .accessibilityIdentifier("webBuild.prompt")
            Button(store.project == nil ? "生成网页" : "应用修改") {
                let request = prompt
                promptFocused = false
                Task {
                    if await store.update(.generate(request)) { prompt = "" }
                }
            }
            .disabled(store.isWorking || !WebBuildValue.text(prompt, limit: 1000))
            .accessibilityIdentifier("webBuild.generate")
        } header: {
            Text(store.project == nil ? "你想做什么网页？" : "想怎么修改？")
        } footer: {
            Text(prompt.utf16.count > 1000 ? "描述不能超过 1000 字。" : "AI 会处理你的描述，请勿填写个人隐私。")
        }
    }

    @ViewBuilder
    private func publication(_ project: WebBuildProject) -> some View {
        Section("发布与分享") {
            if !project.isCurrentPublished {
                Button(project.shareUrl == nil ? "发布网页" : "发布新版") { confirmation = .publish }
                    .disabled(store.isWorking)
            }
            if let url = project.shareUrl {
                ShareLink(item: url) { Label("分享网页链接", systemImage: "square.and.arrow.up") }
                Link("在浏览器打开", destination: url)
                Button("停用网页", role: .destructive) { confirmation = .withdraw }
                    .disabled(store.isWorking)
            }
        }
        if project.isCurrentPublished {
            Section {
                if store.submitted {
                    Label("已提交云乐坊审核", systemImage: "checkmark.circle")
                    NavigationLink("查看我的应用") { MyApplicationsView() }
                } else {
                    TextField("市场短名", text: $shortName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("投稿云乐坊") { confirmation = .submit }
                        .disabled(store.isWorking || (!shortName.trimmed.isEmpty && !PublishingValue.slug(shortName.trimmed.lowercased())))
                }
            } header: {
                Text("云乐坊投稿")
            } footer: {
                Text("首次投稿填写市场短名，审核通过后展示本次送审版本。")
            }
        }
    }
}

struct WebBuildPreview: View {
    let page: WebBuildPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: page.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(verbatim: page.description).font(.body)
                }
                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                    Group {
                        if section.expandable {
                            DisclosureGroup {
                                Text(verbatim: section.text).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            } label: {
                                Text(verbatim: section.title).font(.headline)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: section.title).font(.headline).accessibilityAddTraits(.isHeader)
                                Text(verbatim: section.text)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                }
                Text("用户使用云乐坊 AI 制作").font(.footnote)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.18))
        .tint(Color(red: 0.1, green: 0.25, blue: 0.35))
        .background(background.ignoresSafeArea())
        .navigationTitle("网页预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var background: Color {
        switch page.palette {
        case .indigo: return Color(red: 0.96, green: 0.95, blue: 1)
        case .moss: return Color(red: 0.92, green: 0.95, blue: 0.91)
        case .clay: return Color(red: 1, green: 0.95, blue: 0.91)
        case .ocean: return Color(red: 0.93, green: 0.96, blue: 0.98)
        }
    }
}
