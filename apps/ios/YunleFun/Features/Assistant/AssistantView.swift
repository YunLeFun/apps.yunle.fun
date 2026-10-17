import SwiftUI

struct AssistantView: View {
    private enum Modal: String, Identifiable { case login, membership; var id: Self { self } }
    @EnvironmentObject private var chat: AssistantStore
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var modal: Modal?
    @State private var pendingGuestPrompt: String?
    @State private var followLatest = true
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if chat.messages.isEmpty {
                    Section {
                        Label("想找什么应用？", systemImage: "sparkles").font(.title2.bold())
                        Text("说说想做的事，助手会检索云乐坊的公开应用。").foregroundStyle(.secondary)
                        ForEach(AssistantStore.examples, id: \.self) { prompt in
                            Button(prompt) { chat.draft = prompt; focused = true }
                        }
                    }
                    if !catalog.applications.isEmpty {
                        Section("浏览公开应用") {
                            ForEach(Array(catalog.applications.prefix(3))) { app in
                                NavigationLink(value: app) { ApplicationRow(application: app) }
                            }
                        }
                    }
                }
                accessSection
                ForEach(chat.messages) { message in
                    Section {
                        if !message.content.isEmpty {
                            if message.role == .user { Text(verbatim: message.content).textSelection(.enabled) }
                            else if message.status == .streaming { Text(verbatim: message.content).textSelection(.enabled) }
                            else { AssistantMarkdown(text: message.content) }
                        }
                        ForEach(message.cards) { card in
                            if let app = card.resolve(in: catalog.applications) {
                                NavigationLink(value: app) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ApplicationRow(application: app)
                                        if let reason = card.reason { Text(verbatim: reason).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                HStack {
                                    Button("打开\(app.name)") { runtime.open(app, catalog: catalog, library: library) }
                                    if !library.contains(app) {
                                        Button("获取\(app.name)") {
                                            if app.canOpenAsGuest { library.add(app) }
                                            else { runtime.acquire(app, intent: .install, catalog: catalog, library: library) }
                                        }
                                    }
                                }.buttonStyle(.bordered)
                            } else {
                                Label("\(card.name)暂不可用", systemImage: "app.badge").foregroundStyle(.secondary)
                            }
                        }
                        if let status = message.toolStatus { ProgressView(status).accessibilityLabel(status) }
                        if message.status == .stopped { Label("已停止", systemImage: "stop.circle").foregroundStyle(.secondary) }
                        if message.role == .assistant && !message.content.isEmpty {
                            Button { UIPasteboard.general.string = message.content } label: { Label("复制回复", systemImage: "doc.on.doc") }
                        }
                    } header: { Text(message.role == .user ? "你" : "云乐坊助手") }
                }
                if let error = chat.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                        if !chat.messages.isEmpty { Button("重试上次问题") { focused = false; chat.retry() }.disabled(chat.running) }
                        Button("重新核对会员") { Task { await chat.refreshAccess() } }.disabled(chat.running)
                    }
                }
                if !followLatest && !chat.messages.isEmpty {
                    Button("查看最新回复") { followLatest = true; proxy.scrollTo("assistant-end", anchor: .bottom) }
                }
                Color.clear.frame(height: 1).listRowBackground(Color.clear).id("assistant-end")
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture().onChanged { _ in followLatest = false })
            .onChange(of: chat.messages.count) { _ in
                followLatest = true
                if reduceMotion { proxy.scrollTo("assistant-end", anchor: .bottom) }
                else { withAnimation { proxy.scrollTo("assistant-end", anchor: .bottom) } }
            }
            .onChange(of: chat.scrollRevision) { _ in
                if followLatest { proxy.scrollTo("assistant-end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { chat.reset() } label: { Label("新对话", systemImage: "square.and.pencil") }
                    .disabled(chat.messages.isEmpty && chat.draft.isEmpty)
            }
        }
        .sheet(item: $modal, onDismiss: { if accounts.user == nil { pendingGuestPrompt = nil } }) { item in
            switch item {
            case .login: LoginView(continuationMessage: "登录后继续使用 AI 助手，发送前会核对会员状态。")
            case .membership: NavigationStack { MembershipView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { modal = nil } } } }
            }
        }
        .task(id: accounts.identityGeneration) { await chat.refreshAccess() }
        .onChange(of: accounts.identityGeneration) { _ in
            modal = nil
            if let prompt = pendingGuestPrompt, accounts.user?.isUsable == true {
                chat.identityChanged(); chat.draft = prompt; pendingGuestPrompt = nil
            }
        }
        .onChange(of: scenePhase) { if $0 != .active { chat.stop() } }
        .onDisappear { chat.stop() }
        .environment(\.openURL, OpenURLAction { url in AssistantMarkdown.safeLink(url) ? .systemAction : .discarded })
    }
    @ViewBuilder private var accessSection: some View {
        if accounts.user == nil {
            Section {
                Text("AI 助手是会员功能。登录后可核对当前账号的会员状态。").foregroundStyle(.secondary)
                Button("登录云乐坊") { pendingGuestPrompt = chat.draft; modal = .login }
            }
        } else if chat.accessState == .membershipRequired {
            Section {
                Label("需要有效会员", systemImage: "crown")
                Button("查看会员") { focused = false; modal = .membership }
            }
        } else if chat.accessState == .unknown && chat.error == nil {
            Section { ProgressView("正在核对会员状态") }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chat.draft.utf16.count > 4000 { Text("问题过长，请缩短后发送。").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("想找什么应用？", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder).focused($focused)
                    .submitLabel(.send).onSubmit(send)
                    .accessibilityIdentifier("assistant.input")
                if chat.running {
                    Button { chat.stop() } label: { Label("停止生成", systemImage: "stop.fill").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.bordered)
                } else {
                    Button(action: send) { Label("发送问题", systemImage: "arrow.up").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.borderedProminent).disabled(!chat.canSend)
                }
            }
        }.padding().background(.bar)
    }
    private func send() {
        guard chat.canSend else { return }
        focused = false
        if accounts.user == nil { pendingGuestPrompt = chat.draft; modal = .login }
        else if chat.accessState == .membershipRequired { modal = .membership }
        else { chat.send() }
    }
}
