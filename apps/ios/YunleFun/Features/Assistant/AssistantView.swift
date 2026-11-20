import SwiftUI

struct AssistantView: View {
    private enum Modal: String, Identifiable {
        case login, membership, history, webBuild, webBuildHistory
        var id: Self { self }
    }
    private static let end = "assistant-end"
    private static let draftLimit = 4000
    private static let contentWidth: CGFloat = 640
    /// Famicom-inspired red, lifted in dark appearances to keep the thin symbol strokes legible.
    private static let gameSuggestionColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 232.0 / 255, green: 120.0 / 255, blue: 128.0 / 255, alpha: 1) // #E87880
            : UIColor(red: 166.0 / 255, green: 43.0 / 255, blue: 50.0 / 255, alpha: 1) // #A62B32
    })
    @EnvironmentObject private var chat: AssistantStore
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lifetime = AssistantScreenLifetime()
    @ScaledMetric(relativeTo: .body) private var actionSize: CGFloat = 30
    @State private var focused = false
    @State private var modal: Modal?
    @State private var pendingGuestPrompt: String?
    @State private var webBuildAccess: AccountRequestBoundary?
    @State private var webBuildPrompt = ""
    @State private var followLatest = true
    @State private var endVisible = true
    @State private var confirmReset = false
    @State private var confirmDiscard = false
    @State private var isVisible = false

    private var roomWatchID: String? {
        guard isVisible, scenePhase == .active,
              chat.messages.contains(where: { $0.conversationCards?.contains(where: { $0.publicRoomCode != nil }) == true })
        else { return nil }
        return accounts.identityGeneration.uuidString + chat.threadID
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if chat.messages.isEmpty { welcome }
                    ForEach(chat.messages) { message in
                        if message.role == .user {
                            AssistantUserBubble(message: message) { fillDraft($0); focused = true }
                        } else {
                            AssistantReply(message: message, isLatest: message.id == chat.messages.last?.id, canRegenerate: !chat.running) {
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
                .frame(maxWidth: Self.contentWidth)
                .frame(maxWidth: .infinity)
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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if focused {
                    Button { focused = false } label: {
                        Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                    }
                    .accessibilityIdentifier("assistant.dismiss-keyboard")
                }
                if accounts.user?.isUsable == true {
                    Button { focused = false; modal = .history } label: {
                        Label("历史对话", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("assistant.history")
                }
                Button {
                    focused = false
                    if chat.messages.isEmpty { chat.reset() } else { confirmReset = true }
                } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                }
                .disabled(chat.messages.isEmpty && chat.draft.isEmpty)
            }
        }
        .confirmationDialog("开始新对话？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("开始新对话", role: .destructive) { focused = false; if !chat.reset() { confirmDiscard = true } }
        } message: {
            Text(accounts.user?.isUsable == true && !chat.historyUnsaved ? "当前对话已保存到历史对话。" : "当前对话未保存到历史对话，开始新对话后不能找回。")
        }
        .confirmationDialog("当前对话未能保存", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃并开始新对话", role: .destructive) { chat.reset(discardUnsaved: true) }
        } message: { Text("保存到这台设备失败，可以稍后再试。开始新对话会丢失当前对话的内容。") }
        .sheet(item: $modal, onDismiss: { if accounts.user == nil { pendingGuestPrompt = nil } }) { item in
            switch item {
            case .login: LoginView(continuationMessage: "登录后继续使用 AI 助手，发送前会核对会员状态。")
            case .membership: NavigationStack { MembershipView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { modal = nil } } } }
            case .history:
                AssistantHistoryView { id, discard in
                    guard chat.open(id, discardUnsaved: discard) else { return false }
                    modal = nil; followLatest = true
                    return true
                }
            case .webBuild:
                webBuildSheet {
                    WebBuildEditorView(initialPrompt: webBuildPrompt)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                NavigationLink("我的网页") { WebBuildView() }
                            }
                        }
                }
            case .webBuildHistory:
                webBuildSheet { WebBuildView() }
            }
        }
        .task(id: accounts.identityGeneration) { await chat.refreshAccess() }
        .task(id: accounts.identityGeneration) {
            let boundary = await WebBuildService().availableBoundary(for: accounts)
            guard !Task.isCancelled else { return }
            webBuildAccess = boundary
        }
        .task(id: roomWatchID) {
            guard roomWatchID != nil else { return }
            await chat.roomFeed.watch()
        }
        .onChange(of: accounts.identityGeneration) { _ in
            modal = nil
            webBuildPrompt = ""
            if let prompt = pendingGuestPrompt, accounts.user?.isUsable == true {
                chat.identityChanged(); fillDraft(prompt); pendingGuestPrompt = nil
            }
        }
        .onChange(of: scenePhase) { if $0 != .active { chat.stop() } }
        // Pushing a card's detail page keeps the reply streaming; leaving the assistant stops it (see AssistantScreenLifetime).
        .onAppear { lifetime.chat = chat; isVisible = true }
        .onDisappear { isVisible = false }
        .haptic(.impact, trigger: chat.messages.count) { old, new in new > old }
        .environmentObject(chat.roomFeed)
        .environment(\.openURL, OpenURLAction { url in AssistantMarkdown.safeLink(url) ? .systemAction : .discarded })
    }

    private var canUseWebBuild: Bool {
        accounts.user?.isUsable == true && webBuildAccess?.generation == accounts.identityGeneration
    }

    @ViewBuilder
    private func webBuildSheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if canUseWebBuild {
            NavigationStack {
                content()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { modal = nil }
                        }
                    }
            }
        }
    }

    private var webBuildActions: some View {
        ViewThatFits {
            HStack(spacing: 16) { webBuildButtons }
            VStack(alignment: .leading) { webBuildButtons }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var webBuildButtons: some View {
        Button {
            focused = false
            webBuildPrompt = chat.draft
            modal = .webBuild
        } label: {
            Label("制作网页", systemImage: "sparkle.magnifyingglass").frame(minHeight: 44)
        }
        .accessibilityIdentifier("assistant.web-build.create")
        Button("我的网页") {
            focused = false
            webBuildPrompt = ""
            modal = .webBuildHistory
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("assistant.web-build.history")
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.largeTitle).foregroundStyle(Color.accentColor)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityHidden(true)
                Text("想找什么应用？").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("说说想做的事，帮你找到合适的云应用。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 10) {
                Text("试试这样问")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                suggestions
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
    private func errorNotice(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(verbatim: error).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { errorActions }
                VStack(alignment: .leading, spacing: 8) { errorActions }
            }
            .buttonBorderShape(.capsule)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    @ViewBuilder private var errorActions: some View {
        if !chat.messages.isEmpty {
            Button("重试上次问题") { focused = false; chat.retry() }.buttonStyle(.borderedProminent).disabled(chat.running)
        }
        Button("重新核对会员") { Task { await chat.refreshAccess() } }.buttonStyle(.bordered).disabled(chat.running)
    }
    private var draftLength: Int { chat.draft.utf16.count }
    private func composer(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if draftLength > Self.draftLimit - 400 {
                Text(verbatim: draftLength > Self.draftLimit ? "问题过长，请缩短后发送（\(draftLength)/\(Self.draftLimit)）" : "\(draftLength)/\(Self.draftLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(draftLength > Self.draftLimit ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(alignment: .bottom, spacing: 4) {
                // Keyboard 发送 / Return sends, Shift+Return adds a line, pastes and dictation stay in the draft.
                AssistantComposerField(text: $chat.draft, isFocused: $focused,
                                       placeholder: "想找什么应用？", onSubmit: send)
                composerAction.padding(.trailing, 4).padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            // Taps on the padding around the text still focus the field.
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { focused = true } }
            .modifier(AssistantFieldBackground())
            if canUseWebBuild { webBuildActions }
            accessLine
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity)
        .modifier(AssistantComposerChrome())
        .overlay(alignment: .top) {
            // Appearance of the lazy end marker is only a hint, so recovery stays available whenever following is paused.
            if (!endVisible || !followLatest) && !chat.messages.isEmpty {
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
        .animation(Motion.fade, value: followLatest)
    }
    /// Keep every example readable in the scrollable content, including at accessibility text sizes.
    /// Choosing one fills an editable draft; it never sends a request.
    private var suggestions: some View {
        let icons: [(symbol: String, color: Color)] = [
            ("chevron.left.forwardslash.chevron.right", .blue),
            ("gamecontroller", Self.gameSuggestionColor),
            ("lightbulb", .orange),
            ("person.2", Self.gameSuggestionColor),
            ("person.2.badge.plus", .blue),
            ("square.grid.3x3", Self.gameSuggestionColor)
        ]
        return VStack(spacing: 0) {
            ForEach(Array(AssistantStore.examples.enumerated()), id: \.element) { index, prompt in
                if index > 0 { Divider().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 16 : 52) }
                Button { fillDraft(prompt); focused = true } label: {
                    HStack(spacing: 12) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: icons[index % icons.count].symbol)
                                .font(.body).foregroundStyle(icons[index % icons.count].color)
                                .frame(width: 24).accessibilityHidden(true)
                        }
                        Text(prompt)
                            .font(.subheadline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "arrow.up.left")
                                .font(.footnote.weight(.medium)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prompt)
                .accessibilityIdentifier("assistant.suggestion.\(index)")
                .accessibilityHint("填入输入框，可修改后发送")
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    /// One quiet line instead of a card: guests can type first and sign in when they send.
    @ViewBuilder private var accessLine: some View {
        if accounts.user == nil {
            accessHint("AI 助手为会员功能", action: "登录") { focused = false; pendingGuestPrompt = chat.draft; modal = .login }
        } else if chat.accessState == .membershipRequired {
            accessHint("需要有效会员", action: "查看会员") { focused = false; modal = .membership }
        } else if chat.accessState == .unknown && chat.error == nil {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("正在核对会员状态") }
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
        }
    }
    private func accessHint(_ message: String, action: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(verbatim: message + " ·").foregroundStyle(.secondary)
                    Text(verbatim: action).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                }
                VStack(spacing: 4) {
                    Text(verbatim: message).foregroundStyle(.secondary)
                    Text(verbatim: action).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message + "，" + action)
    }
    private var sendHint: String {
        if accounts.user == nil { return "登录后发送" }
        return chat.accessState == .membershipRequired ? "开通会员后发送" : ""
    }
    @ViewBuilder private var composerAction: some View {
        if chat.running {
            Button { chat.stop() } label: {
                Image(systemName: "stop.circle.fill").font(.system(size: min(actionSize, 40)))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(Color.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("停止生成")
            .accessibilityIdentifier("assistant.stop")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: min(actionSize, 40)))
                    .foregroundStyle(chat.canSend ? Color.white : Color(uiColor: .secondaryLabel),
                                     chat.canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!chat.canSend)
            .accessibilityLabel("发送问题")
            .accessibilityHint(sendHint)
            .accessibilityIdentifier("assistant.send")
        }
    }
    /// Programmatic draft changes (examples, editing an earlier question, a restored guest prompt) never pass
    /// through the keyboard, so `AssistantComposerField` cannot mistake them for the 发送 key.
    private func fillDraft(_ text: String) { chat.draft = text }
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
    /// Tool states during which the Agent is looking up applications.
    private static let searchStates: Set<String> = ["正在检索应用", "正在确认条件", "正在整理结果", "正在匹配应用"]
    let message: AssistantMessage
    let isLatest: Bool
    let canRegenerate: Bool
    let regenerate: () -> Void
    @State private var copied = false
    private var streaming: Bool { message.status == .streaming }
    private var searching: Bool { streaming && message.cards.isEmpty && Self.searchStates.contains(message.toolStatus ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("云乐坊助手", systemImage: "sparkles")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if !message.content.isEmpty {
                // Markdown renders while streaming too, so headings and emphasis never jump when the reply ends.
                AssistantMarkdown(text: message.content)
                    .modifier(AssistantReplyMenu(content: message.content, enabled: !isLatest))
            } else if streaming && !searching {
                AssistantTypingIndicator(status: message.toolStatus)
            }
            if searching || !message.cards.isEmpty {
                AssistantRecommendations(cards: message.cards, searchStatus: searching ? message.toolStatus : nil)
            } else if streaming, !message.content.isEmpty, let status = message.toolStatus {
                HStack(spacing: 8) { ProgressView(); Text(verbatim: status).foregroundStyle(.secondary) }
                    .font(.subheadline).accessibilityElement(children: .combine)
            }
            if let cards = message.conversationCards {
                ForEach(cards) { card in
                    if let code = card.publicRoomCode { AssistantRoomCardView(code: code) }
                    else if let reference = card.reference { NativeConversationCardView(reference: reference, fallback: card.fallbackText) }
                    else { Text(verbatim: card.fallbackText).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            if message.status == .stopped {
                Label("已停止", systemImage: "stop.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            if message.status == .failed {
                Label("未能完成回复", systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            // Regenerate stays available for a reply that failed or stopped before any text; copy and share need text.
            if isLatest && !streaming && (!message.content.isEmpty || canRegenerate) { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .haptic(.success, trigger: copied) { _, new in new }
    }
    private var actions: some View {
        HStack(spacing: 4) {
            if !message.content.isEmpty {
                Button(action: copy) {
                    if copied { Label("已复制", systemImage: "checkmark").frame(minWidth: 36, minHeight: 32) }
                    else { Label("复制回复", systemImage: "doc.on.doc").frame(minWidth: 36, minHeight: 32) }
                }
                ShareLink(item: message.content) { Label("分享回复", systemImage: "square.and.arrow.up").frame(minWidth: 36, minHeight: 32) }
            }
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

private struct AssistantRecommendations: View {
    let cards: [AssistantAppCard]
    let searchStatus: String?
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let first = cards.first {
                VStack(spacing: 0) {
                    cardRow(first)
                    if cards.count > 1 {
                        divider
                        disclosure
                        if expanded {
                            VStack(spacing: 0) {
                                ForEach(cards.dropFirst()) { card in
                                    divider
                                    cardRow(card)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            } else {
                skeleton.transition(.opacity)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(reduceMotion ? nil : Motion.fade, value: cards.isEmpty)
    }

    private var divider: some View { Divider().padding(.leading, 16) }

    private var disclosure: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.fade) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(expanded ? "收起其他推荐" : "展开其余 \(cards.count - 1) 个结果")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityIdentifier("assistant.recommendations.disclosure")
    }

    @ViewBuilder private func cardRow(_ card: AssistantAppCard) -> some View {
        if let app = card.resolve(in: catalog.applications) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                // Keep details on the same navigation stack as the assistant.
                NavigationLink {
                    ApplicationDetailView(application: app)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ApplicationRow(application: app)
                        if let reason = card.reason {
                            Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                AssistantRecommendationAction(application: app)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        } else {
            Label("\(card.name)暂不可用", systemImage: "app.badge").foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var skeleton: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            if let searchStatus {
                HStack(spacing: 8) {
                    if reduceMotion { Image(systemName: "magnifyingglass").accessibilityHidden(true) }
                    else { ProgressView() }
                    Text(verbatim: searchStatus)
                }
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            layout {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.2)).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text("应用名称").font(.headline)
                    Text("一句话介绍这个应用的用途").font(.subheadline)
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantRecommendationAction: View {
    let application: CloudApplication
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var additions = 0
    @State private var showAddError = false

    var body: some View {
        let installed = library.contains(application)
        let directAdd = application.canOpenAsGuest
        let title: LocalizedStringKey = installed ? "打开" : (directAdd ? "添加" : "获取")
        Button {
            if library.contains(application) {
                runtime.open(application, catalog: catalog, library: library)
            } else if directAdd {
                library.add(application)
                if library.contains(application) { additions += 1 }
                else { showAddError = true }
            } else {
                runtime.acquire(application, intent: .install, catalog: catalog, library: library)
            }
        } label: {
            Label(title, systemImage: installed ? "checkmark" : "plus")
                .contentTransition(.opacity)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 36)
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(installed ? "打开\(application.name)" : (directAdd ? "添加\(application.name)到云居" : "获取\(application.name)"))
        .accessibilityIdentifier("assistant.recommendation.action.\(application.id)")
        .animation(reduceMotion ? nil : Motion.fade, value: installed)
        .haptic(.success, trigger: additions)
        .alert("暂未添加到云居", isPresented: $showAddError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(library.storageError ?? "请检查云居中的应用数量后重试。")
        }
    }
}

/// Stops generation once the assistant screen leaves the navigation stack. `onDisappear` also fires when a
/// card's detail page is pushed on top, and `isPresented` still reads true while the screen is popped, so the
/// end of the screen's own state is the reliable signal.
@MainActor private final class AssistantScreenLifetime: ObservableObject {
    weak var chat: AssistantStore?
    deinit {
        let chat = chat
        Task { @MainActor in chat?.stop() }
    }
}

/// Earlier replies keep copy and share in a context menu instead of a visible action row.
private struct AssistantReplyMenu: ViewModifier {
    let content: String
    let enabled: Bool
    @ViewBuilder func body(content view: Content) -> some View {
        if enabled {
            view.contextMenu {
                Button { UIPasteboard.general.string = content } label: { Label("复制回复", systemImage: "doc.on.doc") }
                ShareLink(item: content) { Label("分享回复", systemImage: "square.and.arrow.up") }
            }
        } else {
            view
        }
    }
}

/// Three dots before the first words arrive; they hold still under Reduce Motion.
private struct AssistantTypingIndicator: View {
    let status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(Color.secondary).frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 0.6 : (phase == index ? 1 : 0.3))
                }
            }
            if let status { Text(verbatim: status).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status ?? "正在回复"))
    }
}

/// Saved conversations of the current account on this device.
struct AssistantHistoryView: View {
    /// Opens a conversation; false when the current one could not be saved and was kept.
    let open: (_ id: String, _ discardUnsaved: Bool) -> Bool
    @EnvironmentObject private var chat: AssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var pendingOpen: String?
    var body: some View {
        NavigationStack {
            Group {
                if chat.history.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text("还没有历史对话").font(.headline)
                        Text("对话保存在这台设备上，仅当前账号可见。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if chat.historyUnsaved {
                            Section {
                                Label("当前对话暂时未能保存，会在下次回复结束时重试；打开其他对话会放弃它。", systemImage: "exclamationmark.triangle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            ForEach(chat.history) { conversation in
                                Button { if !open(conversation.id, false) { pendingOpen = conversation.id } } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: conversation.title).lineLimit(2).foregroundStyle(.primary)
                                        Text(conversation.updatedAt, format: .relative(presentation: .named))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("打开这段对话，可继续提问")
                            }
                            .onDelete { offsets in offsets.map { chat.history[$0].id }.forEach(chat.delete) }
                        } footer: {
                            Text("对话只保存在这台设备上，最多保留 \(AssistantHistory.limit) 个，退出账号时一并删除。")
                        }
                    }
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清除全部", role: .destructive) { confirmClear = true }
                        .disabled(chat.history.isEmpty)
                }
            }
            .confirmationDialog("当前对话未能保存", isPresented: Binding(get: { pendingOpen != nil }, set: { if !$0 { pendingOpen = nil } }),
                                titleVisibility: .visible) {
                Button("放弃当前对话并打开", role: .destructive) { if let id = pendingOpen { _ = open(id, true) }; pendingOpen = nil }
            } message: { Text("保存到这台设备失败。打开其他对话会丢失当前对话的内容。") }
            .confirmationDialog("清除全部历史对话？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除全部", role: .destructive) { chat.deleteAll() }
            } message: { Text("只删除这台设备上当前账号的对话，删除后不能恢复。") }
        }
    }
}

/// iOS 26 floats the composer as a bar with a hard scroll edge so content
/// scrolling beneath stays legible; earlier systems inset the content above it.
private struct AssistantBottomBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.hard, for: .bottom).safeAreaBar(edge: .bottom) {
                GlassEffectContainer(spacing: 12, content: bar)
            }
        } else { content.safeAreaInset(edge: .bottom, spacing: 0, content: bar) }
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
