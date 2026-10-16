import SwiftUI

struct MeView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var accounts: AccountStore
    @State private var showLogin = false

    var body: some View {
        List {
            Section {
                if let user = accounts.user {
                    NavigationLink { AccountProfileView() } label: { AccountIdentityLabel(user: user) }
                } else {
                    Button { showLogin = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("登录云乐坊").font(.headline)
                                Text("继续你的应用生活").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "person.crop.circle").font(.largeTitle) }
                        .padding(.vertical, 8)
                    }
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
                NavigationLink { WalletView() } label: { Label("钱包", systemImage: "wallet.pass") }
                NavigationLink { MembershipView() } label: { Label("云乐坊会员", systemImage: "crown") }
                NavigationLink { MyApplicationsView() } label: { Label("我的应用", systemImage: "square.and.pencil") }
                NavigationLink { MyWorkshopsView() } label: { Label("个人工坊", systemImage: "person.2.crop.square.stack") }
                NavigationLink { AccountManagementView() } label: { Label("账号管理", systemImage: "person.2") }
                NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
                NavigationLink { AboutView() } label: { Label("关于云乐坊", systemImage: "info.circle") }
            }
            Section("支持") {
                NavigationLink { MyReportsView() } label: { Label("我的举报", systemImage: "flag") }
                Link(destination: URL(string: "https://www.yunle.fun/docs")!) { Label("使用帮助", systemImage: "questionmark.circle") }
                Link(destination: URL(string: "https://github.com/YunLeFun/apps.yunle.fun/issues")!) {
                    Label("反馈与建议", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .navigationTitle("我")
        .sheet(isPresented: $showLogin) { LoginView() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: HomeLibrary
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
                Button("清空最近使用", role: .destructive) { confirmClear = true }
                    .disabled(library.snapshot.recentIDs.isEmpty)
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
