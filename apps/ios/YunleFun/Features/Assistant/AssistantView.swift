import SwiftUI

struct AssistantView: View {
    private enum Modal: String, Identifiable { case login, membership; var id: Self { self } }
    private static let end = "assistant-end"
    private static let draftLimit = 4000
    @EnvironmentObject private var chat: AssistantStore
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var actionSize: CGFloat = 30
    @FocusState private var focused: Bool
    @State private var modal: Modal?
    @State private var pendingGuestPrompt: String?
    @State private var followLatest = true
    @State private var endVisible = true
    @State private var confirmReset = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // The sign-in / membership notice leads so it never starts hidden behind the composer.
                    accessNotice
                    if chat.messages.isEmpty { welcome }
                    ForEach(chat.messages) { message in
                        if message.role == .user {
                            AssistantUserBubble(message: message) { chat.draft = $0; focused = true }
                        } else {
                            AssistantReply(message: message, canRegenerate: message.id == chat.messages.last?.id && !chat.running) {
                                focused = false; chat.retry()
                            }
                        }
                    }
                    if let error = chat.error { errorNotice(error) }
                    Color.clear.frame(height: 1).id(Self.end)
                        .onAppear { endVisible = true; followLatest = true }
                        .onDisappear { endVisible = false }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // Only scrolling back through history pauses auto-follow; the end marker resumes it.
            .simultaneousGesture(DragGesture().onChanged { if $0.translation.height > 0 { followLatest = false } })
            .modifier(AssistantBottomBar { composer(proxy) })
            .onChange(of: chat.messages.count) { _ in
                followLatest = true
                scrollToEnd(proxy, animated: true)
            }
            .onChange(of: chat.scrollRevision) { _ in
                if followLatest { scrollToEnd(proxy, animated: false) }
            }
            .onChange(of: focused) { isFocused in
                guard isFocused, followLatest, !chat.messages.isEmpty else { return }
                Task { try? await Task.sleep(nanoseconds: 300_000_000); scrollToEnd(proxy, animated: true) }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { if chat.messages.isEmpty { chat.reset() } else { confirmReset = true } } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                }
                .disabled(chat.messages.isEmpty && chat.draft.isEmpty)
            }
        }
        .confirmationDialog("开始新对话？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("开始新对话", role: .destructive) { focused = false; chat.reset() }
        } message: { Text("当前对话只保留在本机内存中，开始新对话后不能找回。") }
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
        // A vertical TextField inserts a newline for Return instead of calling onSubmit, so the 发送 key is handled here.
        .onChange(of: chat.draft) { value in
            guard value.hasSuffix("\n") else { return }
            chat.draft = String(value.dropLast())
            send()
        }
        .onChange(of: scenePhase) { if $0 != .active { chat.stop() } }
        .onDisappear { chat.stop() }
        .haptic(.impact, trigger: chat.messages.count) { old, new in new > old }
        .environment(\.openURL, OpenURLAction { url in AssistantMarkdown.safeLink(url) ? .systemAction : .discarded })
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text("想找什么应用？").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("说说想做的事，助手会检索云乐坊的公开应用。").foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(AssistantStore.examples, id: \.self) { prompt in
                    Button { chat.draft = prompt; focused = true } label: {
                        HStack(spacing: 12) {
                            Text(prompt).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("填入输入框，可修改后发送")
                }
            }
            if !catalog.applications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("浏览公开应用").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader).padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(catalog.applications.prefix(3).enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().padding(.leading, 16) }
                            NavigationLink(value: app) { AssistantLinkRow { ApplicationRow(application: app) } }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
    @ViewBuilder private var accessNotice: some View {
        if accounts.user == nil {
            notice(title: "登录后使用", systemImage: "person.crop.circle",
                   message: "AI 助手是会员功能。登录后可核对当前账号的会员状态。") {
                Button("登录云乐坊") { focused = false; pendingGuestPrompt = chat.draft; modal = .login }
                    .buttonStyle(.borderedProminent)
            }
        } else if chat.accessState == .membershipRequired {
            notice(title: "需要有效会员", systemImage: "crown", message: "开通或续费会员后即可继续提问。") {
                Button("查看会员") { focused = false; modal = .membership }.buttonStyle(.borderedProminent)
            }
        } else if chat.accessState == .unknown && chat.error == nil {
            HStack(spacing: 8) { ProgressView(); Text("正在核对会员状态").foregroundStyle(.secondary) }
                .font(.subheadline).frame(maxWidth: .infinity).accessibilityElement(children: .combine)
        }
    }
    private func errorNotice(_ error: String) -> some View {
        notice(title: error, systemImage: "exclamationmark.triangle.fill", tint: .orange, message: nil) {
            if !chat.messages.isEmpty {
                Button("重试上次问题") { focused = false; chat.retry() }.buttonStyle(.borderedProminent).disabled(chat.running)
            }
            Button("重新核对会员") { Task { await chat.refreshAccess() } }.buttonStyle(.bordered).disabled(chat.running)
        }
    }
    private func notice<Actions: View>(title: String, systemImage: String, tint: Color = .accentColor, message: String?,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(verbatim: title).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .font(.headline)
            if let message { Text(verbatim: message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions() }
                VStack(alignment: .leading, spacing: 8) { actions() }
            }
            .buttonBorderShape(.capsule)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var draftLength: Int { chat.draft.utf16.count }
    private func composer(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if draftLength > Self.draftLimit - 400 {
                Text(verbatim: draftLength > Self.draftLimit ? "问题过长，请缩短后发送（\(draftLength)/\(Self.draftLimit)）" : "\(draftLength)/\(Self.draftLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(draftLength > Self.draftLimit ? Color.red : Color.secondary)
            }
            HStack(alignment: .bottom, spacing: 4) {
                TextField("想找什么应用？", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.leading, 16).padding(.vertical, 11)
                    .accessibilityIdentifier("assistant.input")
                composerAction.padding(.trailing, 2).padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Taps on the padding around the text still focus the field.
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { focused = true } }
            .modifier(AssistantFieldBackground())
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .modifier(AssistantComposerChrome())
        .overlay(alignment: .top) {
            if !endVisible && !chat.messages.isEmpty {
                Button { followLatest = true; scrollToEnd(proxy, animated: true) } label: {
                    Image(systemName: "arrow.down").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .modifier(AssistantFloatingBackground())
                .accessibilityLabel("查看最新回复")
                .alignmentGuide(.top) { $0[.bottom] + 8 }
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: chat.running)
        .animation(Motion.fade, value: endVisible)
    }
    @ViewBuilder private var composerAction: some View {
        if chat.running {
            Button { chat.stop() } label: {
                Image(systemName: "stop.circle.fill").font(.system(size: actionSize))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(Color.primary)
                    .frame(minWidth: 40, minHeight: 40)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("停止生成")
            .accessibilityIdentifier("assistant.stop")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: actionSize))
                    .foregroundStyle(Color.white, chat.canSend ? Color.accentColor : Color(uiColor: .systemGray3))
                    .frame(minWidth: 40, minHeight: 40)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!chat.canSend)
            .accessibilityLabel("发送问题")
            .accessibilityIdentifier("assistant.send")
        }
    }
    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion { withAnimation(Motion.spring) { proxy.scrollTo(Self.end, anchor: .bottom) } }
        else { proxy.scrollTo(Self.end, anchor: .bottom) }
    }
    private func send() {
        guard chat.canSend else { return }
        focused = false
        if accounts.user == nil { pendingGuestPrompt = chat.draft; modal = .login }
        else if chat.accessState == .membershipRequired { modal = .membership }
        else { chat.send() }
    }
}

private struct AssistantUserBubble: View {
    let message: AssistantMessage
    let edit: (String) -> Void
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(verbatim: message.content)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu {
                    Button { UIPasteboard.general.string = message.content } label: { Label("复制", systemImage: "doc.on.doc") }
                    Button { edit(message.content) } label: { Label("修改后重新提问", systemImage: "pencil") }
                }
                .accessibilityLabel(Text(verbatim: "你：" + message.content))
        }
    }
}

private struct AssistantReply: View {
    let message: AssistantMessage
    let canRegenerate: Bool
    let regenerate: () -> Void
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("云乐坊助手", systemImage: "sparkles")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if !message.content.isEmpty {
                if message.status == .streaming { Text(verbatim: message.content).textSelection(.enabled) }
                else { AssistantMarkdown(text: message.content) }
            }
            if !message.cards.isEmpty { cards }
            if let status = message.toolStatus {
                HStack(spacing: 8) { ProgressView(); Text(verbatim: status).foregroundStyle(.secondary) }
                    .font(.subheadline).accessibilityElement(children: .combine)
            }
            if message.status == .stopped {
                Label("已停止", systemImage: "stop.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            if message.status != .streaming && !message.content.isEmpty { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .haptic(.success, trigger: copied) { _, new in new }
    }
    private var cards: some View {
        VStack(spacing: 0) {
            ForEach(Array(message.cards.enumerated()), id: \.element.id) { index, card in
                if index > 0 { Divider().padding(.leading, 16) }
                cardRow(card)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    @ViewBuilder private func cardRow(_ card: AssistantAppCard) -> some View {
        if let app = card.resolve(in: catalog.applications) {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink(value: app) {
                    AssistantLinkRow {
                        VStack(alignment: .leading, spacing: 6) {
                            ApplicationRow(application: app)
                            if let reason = card.reason {
                                Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Button("打开") { runtime.open(app, catalog: catalog, library: library) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("打开\(app.name)")
                    if !library.contains(app) {
                        Button("获取") {
                            if app.canOpenAsGuest { library.add(app) }
                            else { runtime.acquire(app, intent: .install, catalog: catalog, library: library) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("获取\(app.name)")
                    }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        } else {
            Label("\(card.name)暂不可用", systemImage: "app.badge").foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: copy) {
                if copied { Label("已复制", systemImage: "checkmark").frame(minWidth: 36, minHeight: 32) }
                else { Label("复制回复", systemImage: "doc.on.doc").frame(minWidth: 36, minHeight: 32) }
            }
            ShareLink(item: message.content) { Label("分享回复", systemImage: "square.and.arrow.up").frame(minWidth: 36, minHeight: 32) }
            if canRegenerate {
                Button(action: regenerate) { Label("重新生成", systemImage: "arrow.clockwise").frame(minWidth: 36, minHeight: 32) }
            }
        }
        .labelStyle(.iconOnly)
        .font(.subheadline)
        .buttonStyle(.borderless)
        .tint(Color.secondary)
    }
    private func copy() {
        UIPasteboard.general.string = message.content
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
    }
}

/// A tappable row inside a rounded group: content plus a trailing disclosure chevron.
private struct AssistantLinkRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            content()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// iOS 26 floats the composer as a bar with a hard scroll edge so content
/// scrolling beneath stays legible; earlier systems inset the content above it.
private struct AssistantBottomBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.scrollEdgeEffectStyle(.hard, for: .bottom).safeAreaBar(edge: .bottom, content: bar) }
        else { content.safeAreaInset(edge: .bottom, content: bar) }
    }
}

/// Liquid Glass input on iOS 26; a bordered field on the system bar before that.
private struct AssistantFieldBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(Color(uiColor: .systemBackground), in: shape)
                .overlay { shape.strokeBorder(Color(uiColor: .separator), lineWidth: 0.5) }
        }
    }
}

private struct AssistantComposerChrome: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) { content }
        else { content.background(.bar).overlay(alignment: .top) { Divider() } }
    }
}

private struct AssistantFloatingBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle()).shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }
}
