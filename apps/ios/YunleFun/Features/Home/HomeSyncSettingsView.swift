import SwiftUI

struct HomeSyncSettingsView: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var sync: HomeSyncCoordinator
    @State private var showLogin = false
    @State private var resolution: HomeSyncCoordinator.Resolution?

    var body: some View {
        Form {
            Section {
                Label(sync.message, systemImage: sync.isSyncing ? "arrow.triangle.2.circlepath" : "icloud")
                if sync.isSyncing { ProgressView() }
                if accounts.user == nil {
                    if sync.supportsICloud {
                        Toggle("iCloud 同步", isOn: Binding(get: { sync.isActive }, set: sync.setICloudEnabled))
                            .accessibilityIdentifier("home.sync.icloud")
                        if sync.isActive { syncControls }
                    }
                    Button("登录云乐坊") { showLogin = true }
                } else {
                    Toggle("云同步", isOn: Binding(get: { library.snapshot.syncEnabled }, set: library.setSyncEnabled))
                    if library.snapshot.syncEnabled { syncControls }
                }
            } footer: {
                Text(accounts.user != nil ? "同步安装顺序、文件夹、常用应用、最近使用和所选作者来源。关闭同步后，更改仍保存在此设备。"
                     : sync.supportsICloud ? "访客云居默认只保存在此设备。开启 iCloud 同步后，登录同一 Apple 账户的设备会同步安装顺序、文件夹、常用应用、最近使用和所选作者来源。登录云乐坊后使用账号独立的云居，两者互不影响。"
                     : "访客云居保存在此设备，登录后使用账号独立的云居。")
            }
            if case .conflict(let conflict) = sync.phase {
                Section("有两个不同版本") {
                    Text("两边都有更改。查看内容后，选择要继续使用的版本。")
                    NavigationLink("查看此设备版本") {
                        HomeConfigurationView(title: "此设备版本", configuration: library.snapshot.configuration, snapshot: library.snapshot)
                    }
                    NavigationLink("查看云端版本") {
                        HomeConfigurationView(title: "云端版本", configuration: library.snapshot.configuration.adopting(conflict.remote),
                                              snapshot: library.snapshot,
                                              sourceNotice: conflict.remote.carriesSources ? nil : "云端未记录应用来源，使用此版本时会保留此设备的来源选择。")
                    }
                    Button("保留此设备版本") { resolution = .device }
                    Button("使用云端版本") { resolution = .cloud }
                }
                .confirmationDialog(resolution == .device ? "用此设备版本更新云端？" : "用云端版本替换此设备的更改？",
                                    isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }),
                                    titleVisibility: .visible, presenting: resolution) { choice in
                    Button("确认使用此版本", role: .destructive) {
                        Task { await sync.resolve(choice, conflict: conflict) }
                    }
                } message: { _ in Text("选择云端版本时，会先保留此设备更改的恢复副本。") }
            }
        }
        .navigationTitle("云居同步")
        .sheet(isPresented: $showLogin) { LoginView() }
    }

    @ViewBuilder private var syncControls: some View {
        Toggle("自动同步", isOn: Binding(get: { library.snapshot.autoSyncEnabled }, set: library.setAutoSyncEnabled))
        Button("立即同步") { Task { await sync.recheck() } }
            .disabled(sync.isSyncing)
        if let date = library.snapshot.base?.configuration.updatedAt, date > 0 {
            LabeledContent("云端更新时间", value: Date(timeIntervalSince1970: Double(date) / 1000).formatted(date: .abbreviated, time: .shortened))
        }
    }
}

struct HomeConfigurationView: View {
    let title: String
    let configuration: HomeConfiguration
    let snapshot: HomeLibrarySnapshot
    var sourceNotice: String? = nil
    private var displayedSnapshot: HomeLibrarySnapshot {
        var value = snapshot
        value.configuration = configuration
        return value
    }
    var body: some View {
        List {
            if let sourceNotice { Section { Text(sourceNotice) } }
            section("我的应用", references: configuration.installedApps.map(\.appId))
            section("常用应用", references: configuration.dockApps.map(\.appId))
            section("最近使用", references: configuration.recentApps.map(\.appId))
        }
        .navigationTitle(title)
    }
    private func section(_ title: String, references: [String]) -> some View {
        Section(title) {
            if references.isEmpty { Text("没有应用").foregroundStyle(.secondary) }
            ForEach(references, id: \.self) { reference in
                let app = displayedSnapshot.application(reference: reference)
                VStack(alignment: .leading, spacing: 4) {
                    ApplicationRow(application: app)
                    if let source = configuration.applicationSources.first(where: { $0.appId == reference }) {
                        Text("作者版本 · \(source.ownerLogin)").font(.callout)
                    } else if app.accessOwnerID == nil, app.accessWorkshopID == nil {
                        Text("云乐坊版本").font(.callout)
                    }
                    if app.isUnavailable == true { Text(reference).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
        }
    }
}
