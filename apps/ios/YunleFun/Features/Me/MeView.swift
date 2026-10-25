import SwiftUI

struct MeView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var diagnostics: DiagnosticLogStore
    let navigateTab: (AppTab) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showLogin = false
    @State private var returningEntry: Entry?
    @AccessibilityFocusState(for: .voiceOver) private var focusedEntry: Entry?

    private enum Entry: Hashable { case profile, login, wallet, membership, applications, workshops, accounts, settings, about, reports, help, feedback }

    var body: some View {
        List {
            Section {
                if let user = accounts.user {
                    NavigationLink { AccountProfileView().onAppear { returningEntry = .profile; focusedEntry = nil } } label: { AccountIdentityLabel(user: user) }
                        .accessibilityFocused($focusedEntry, equals: .profile)
                } else {
                    Button { showLogin = true } label: {
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 12) {
                                    loginIcon
                                    loginText
                                }
                            } else {
                                // Label centers a large icon in its narrow icon column, pushing it past the row margin.
                                HStack(spacing: 12) {
                                    loginIcon
                                    loginText
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("me.login")
                    .accessibilityFocused($focusedEntry, equals: .login)
                }
                LabeledContent("云居中的应用", value: "\(library.snapshot.applications.count)")
            }
            if accounts.isRestoring { ProgressView("正在检查登录状态") }
            if let notice = accounts.notice {
                Section {
                    Text(notice).foregroundStyle(.secondary)
                    Button("重试") { Task { await accounts.restore() } }
                }
            }
            Section {
                navigationRow("钱包", systemImage: "wallet.pass.fill", color: .green, entry: .wallet) { WalletView() }
                navigationRow("云乐坊会员", systemImage: "crown.fill", color: .orange, entry: .membership) { MembershipView() }
                navigationRow("我的应用", systemImage: "square.and.pencil", color: .blue, entry: .applications) { MyApplicationsView() }
                navigationRow("个人工坊", systemImage: "person.2.crop.square.stack.fill", color: .purple, entry: .workshops) { MyWorkshopsView() }
                navigationRow("账号管理", systemImage: "person.2.fill", color: .teal, entry: .accounts) { AccountManagementView() }
                navigationRow("设置", systemImage: "gearshape.fill", color: .gray, entry: .settings) { SettingsView() }
                navigationRow("关于云乐坊", systemImage: "info", color: .indigo, entry: .about) { AboutView() }
            }
            Section {
                Text("支持").font(.headline).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                navigationRow("我的举报", systemImage: "flag.fill", color: .red, entry: .reports) { MyReportsView() }
                navigationRow("使用帮助", systemImage: "questionmark", color: .blue, entry: .help) {
                    HelpView(logs: diagnostics, accounts: accounts, navigateTab: navigateTab)
                }
                .accessibilityIdentifier("me.help")
                navigationRow("反馈与建议", systemImage: "bubble.left.and.bubble.right", color: .green, entry: .feedback) {
                    FeedbackView(logs: diagnostics, accounts: accounts)
                }
                .accessibilityIdentifier("me.feedback")
            }
        }
        .navigationTitle("我")
        .onAppear {
            if let returningEntry { focusedEntry = returningEntry; self.returningEntry = nil }
        }
        .sheet(isPresented: $showLogin, onDismiss: { focusedEntry = accounts.user == nil ? .login : .profile }) {
            LoginView().onAppear { focusedEntry = nil }
        }
    }

    private func navigationRow<Destination: View>(_ title: String, systemImage: String, color: Color, entry: Entry,
                                                  @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination().onAppear { returningEntry = entry; focusedEntry = nil } } label: {
            navigationLabel(title, systemImage: systemImage, color: color)
        }
        .accessibilityFocused($focusedEntry, equals: entry)
    }

    @ViewBuilder private func navigationLabel(_ title: String, systemImage: String, color: Color) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text(title).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            } icon: {
                SettingsIcon(systemImage: systemImage, color: color)
            }
        }
    }

    private var loginIcon: some View {
        Image(systemName: "person.crop.circle").font(.largeTitle).accessibilityHidden(true)
    }

    private var loginText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("登录云乐坊").font(.headline).foregroundStyle(Color.primary)
            Text("继续你的应用生活").font(.subheadline).foregroundStyle(Color.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var accounts: AccountStore
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("home.showRecent") private var showRecent = true
    @AppStorage(ScreenshotFeedbackPromptState.preferenceKey) private var screenshotFeedbackEnabled = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("外观") {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                } label: { SettingsLabel("显示模式", systemImage: "circle.lefthalf.filled", color: .blue) }
            }
            Section("云居") {
                Toggle(isOn: $showRecent) { SettingsLabel("显示最近使用", systemImage: "clock.fill", color: .indigo) }
                Toggle(isOn: Binding(get: { library.snapshot.dockVisible }, set: library.setDockVisible)) {
                    SettingsLabel("显示常用应用", systemImage: "dock.rectangle", color: .orange)
                }
                NavigationLink { HomeSyncSettingsView() } label: { SettingsLabel("云居同步", systemImage: "icloud.fill", color: .cyan) }
                NavigationLink { HomeBackupsView(library: library, accounts: accounts) } label: {
                    SettingsLabel("云居备份", systemImage: "clock.arrow.circlepath", color: .green)
                }
                Button(role: .destructive) { confirmClear = true } label: {
                    SettingsLabel("清空最近使用", systemImage: "trash.fill", color: .red)
                }
                .disabled(library.snapshot.recentIDs.isEmpty)
            }
            Section {
                NavigationLink { ApplicationCacheSettingsView(store: runtime.applicationCache) } label: {
                    SettingsLabel("应用下载缓存", systemImage: "internaldrive.fill", color: .gray)
                }
                NavigationLink { LegacyMigrationView(library: library, accounts: accounts) } label: {
                    SettingsLabel("旧版数据导入", systemImage: "square.and.arrow.down.fill", color: .purple)
                }
            }
            Section {
                Toggle("截屏后显示反馈入口", isOn: $screenshotFeedbackEnabled)
                    .accessibilityIdentifier("settings.screenshot-feedback")
            } header: {
                Text("反馈")
            } footer: {
                Text("截屏后短暂显示反馈按钮，点按后进入反馈页。不会读取或上传截图。")
            }
        }
        .navigationTitle("设置")
        .confirmationDialog("清空最近使用记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) { library.clearRecent() }
        } message: { Text("云居里的应用会继续保留。") }
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                Text("云乐坊").font(.title.bold())
                Text("在工坊发现云应用，把喜欢的带回云居。").foregroundStyle(.secondary)
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
            Section {
                Link("隐私政策", destination: URL(string: "https://www.yunle.fun/docs/privacy-policy")!)
                Link("服务条款", destination: URL(string: "https://www.yunle.fun/docs/terms-of-service")!)
            }
        }
        .navigationTitle("关于")
    }
}
