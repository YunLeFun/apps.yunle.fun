import SwiftUI

struct MeView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showLogin = false
    @State private var returningEntry: Entry?
    @AccessibilityFocusState(for: .voiceOver) private var focusedEntry: Entry?

    private enum Entry: Hashable { case profile, login, wallet, membership, applications, workshops, accounts, settings, about, reports }

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
                                Label { loginText } icon: { loginIcon }
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
                navigationRow("钱包", systemImage: "wallet.pass", entry: .wallet) { WalletView() }
                navigationRow("云乐坊会员", systemImage: "crown", entry: .membership) { MembershipView() }
                navigationRow("我的应用", systemImage: "square.and.pencil", entry: .applications) { MyApplicationsView() }
                navigationRow("个人工坊", systemImage: "person.2.crop.square.stack", entry: .workshops) { MyWorkshopsView() }
                navigationRow("账号管理", systemImage: "person.2", entry: .accounts) { AccountManagementView() }
                navigationRow("设置", systemImage: "gearshape", entry: .settings) { SettingsView() }
                navigationRow("关于云乐坊", systemImage: "info.circle", entry: .about) { AboutView() }
            }
            Section {
                Text("支持").font(.headline).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                navigationRow("我的举报", systemImage: "flag", entry: .reports) { MyReportsView() }
                Link(destination: URL(string: "https://www.yunle.fun/docs")!) { navigationLabel("使用帮助", systemImage: "questionmark.circle") }
                Link(destination: URL(string: "https://github.com/YunLeFun/apps.yunle.fun/issues")!) {
                    navigationLabel("反馈与建议", systemImage: "bubble.left.and.bubble.right")
                }
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

    private func navigationRow<Destination: View>(_ title: String, systemImage: String, entry: Entry,
                                                  @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination().onAppear { returningEntry = entry; focusedEntry = nil } } label: {
            navigationLabel(title, systemImage: systemImage)
        }
        .accessibilityFocused($focusedEntry, equals: entry)
    }

    @ViewBuilder private func navigationLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text(title).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage).font(.body).accessibilityHidden(true)
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
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var accounts: AccountStore
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("home.showRecent") private var showRecent = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("显示模式", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("云居") {
                Toggle("显示最近使用", isOn: $showRecent)
                Toggle("显示常用应用", isOn: Binding(get: { library.snapshot.dockVisible }, set: library.setDockVisible))
                NavigationLink("云居同步") { HomeSyncSettingsView() }
                NavigationLink("云居备份") { HomeBackupsView(library: library, accounts: accounts) }
                Button("清空最近使用", role: .destructive) { confirmClear = true }
                    .disabled(library.snapshot.recentIDs.isEmpty)
            }
            Section {
                NavigationLink("旧版数据导入") { LegacyMigrationView(library: library, accounts: accounts) }
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
