import SwiftUI

struct HomeBackupsView: View {
    @StateObject private var store: HomeBackupStore
    init(library: HomeLibrary, accounts: IdentityScopedAccountAuthorizing) {
        _store = StateObject(wrappedValue: HomeBackupStore(library: library, accounts: accounts))
    }
    init(store: HomeBackupStore) { _store = StateObject(wrappedValue: store) }

    var body: some View {
        List {
            Section { LabeledContent("当前云居", value: store.targetLabel) }
            if store.needsRecovery {
                Section { Label("当前云居暂时无法读取。恢复前会保留原文件。", systemImage: "exclamationmark.triangle") }
            }
            if store.isLoading { ProgressView("正在读取备份") }
            if let error = store.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await store.load() } }
                }
            }
            Section {
                if store.isLoaded && store.visibleItems.isEmpty && !store.isLoading && store.error == nil {
                    Label("还没有云居备份", systemImage: "archivebox")
                    Text("导入旧版数据、选择云端版本或恢复备份前，会在此设备保留当前版本。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.visibleItems) { item in
                    NavigationLink {
                        HomeBackupDetailView(store: store, backupID: item.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.kind.label).font(.headline)
                            Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? "日期未知")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .accessibilityIdentifier("home.backup." + item.id)
                }
            } footer: { Text("只显示当前账号或访客云居在此设备的备份。恢复前可以查看内容，再决定是否替换。") }
        }
        .navigationTitle("云居备份")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }
}

#if DEBUG
#Preview("样例 · 备份预览") { HomeBackupsPreview(detail: true) }
#Preview("样例 · 无备份") { HomeBackupsPreview(detail: false) }
private struct HomeBackupsPreview: View {
    @StateObject private var store: HomeBackupStore
    let detail: Bool
    init(detail: Bool) {
        self.detail = detail
        let library = HomeLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("BackupPreview-" + UUID().uuidString))
        _store = StateObject(wrappedValue: HomeBackupStore(library: library, accounts: HomeBackupsPreviewAccounts(), reader: HomeBackupsPreviewReader(hasRecord: detail)))
    }
    var body: some View {
        NavigationStack {
            if detail { HomeBackupDetailView(store: store, backupID: "guest.before-legacy-" + String(repeating: "a", count: 64) + ".json") }
            else { HomeBackupsView(store: store) }
        }.allowsHitTesting(false)
    }
}
@MainActor private final class HomeBackupsPreviewAccounts: IdentityScopedAccountAuthorizing {
    let user: AccountUser? = nil
    let identityGeneration = UUID()
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount { throw AccountError.signedOut }
}
private struct HomeBackupsPreviewReader: HomeBackupReading {
    let hasRecord: Bool
    func list(ownerFileName: String) async throws -> [HomeBackupItem] {
        hasRecord ? [.init(id: "guest.before-legacy-" + String(repeating: "a", count: 64) + ".json", kind: .legacy, date: Date(timeIntervalSince1970: 1_790_000_000), byteCount: 1280)] : []
    }
    func preview(id: String, ownerFileName: String) async throws -> HomeBackupPreview {
        var snapshot = HomeLibrarySnapshot(); snapshot.configuration.installedApps = [.init(appId: "sample")]
        snapshot.cachedApplications = [CloudApplication(id: "sample", name: "样例应用")]
        return HomeBackupPreview(item: .init(id: id, kind: .legacy, date: Date(timeIntervalSince1970: 1_790_000_000), byteCount: 1280), snapshot: snapshot, digest: String(repeating: "a", count: 64))
    }
}
#endif

struct HomeBackupDetailView: View {
    @ObservedObject var store: HomeBackupStore
    let backupID: String
    @State private var restoreSettings = true
    @State private var confirmation: HomeBackupRestoreConfirmation?

    var body: some View {
        Form {
            if store.isLoadingPreview { ProgressView("正在打开备份") }
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("重新打开") { Task { await store.select(backupID, force: true) } }
                }
            }
            if let preview = store.visiblePreview, preview.item.id == backupID {
                Section {
                    LabeledContent("备份来源", value: preview.item.kind.label)
                    if let date = preview.item.date { LabeledContent("保存时间", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    LabeledContent("恢复位置", value: store.targetLabel)
                    LabeledContent("应用", value: "\(preview.snapshot.configuration.installedApps.count)")
                    LabeledContent("常用应用", value: "\(preview.snapshot.configuration.dockApps.count)")
                    LabeledContent("最近使用", value: "\(preview.snapshot.configuration.recentApps.count)")
                    NavigationLink("查看应用与顺序") {
                        HomeConfigurationView(title: "备份内容", configuration: preview.snapshot.configuration, snapshot: preview.snapshot)
                    }
                }
                Section {
                    Toggle("同时恢复云居设置", isOn: $restoreSettings).disabled(store.isRestoring)
                    if restoreSettings {
                        LabeledContent("云同步", value: preview.snapshot.syncEnabled ? "开启" : "关闭")
                        LabeledContent("自动同步", value: preview.snapshot.autoSyncEnabled ? "开启" : "关闭")
                        LabeledContent("常用应用显示", value: preview.snapshot.dockVisible ? "显示" : "隐藏")
                    }
                } footer: { Text("恢复的是云居布局、作者来源、最近使用及选中的云居设置。当前云端版本会继续参与同步检查。") }
                Section {
                    if store.didRestore { Label("已恢复云居", systemImage: "checkmark.circle") }
                    if store.isRestoring { ProgressView("正在恢复云居") }
                    Button("恢复此备份", role: .destructive) { confirmation = store.confirmation(restoreSettings: restoreSettings) }
                        .disabled(store.isRestoring)
                } footer: {
                    Text(store.needsRecovery ? "无法读取的原文件会单独保留在此设备，以便后续检查。登录账号和购买权益以当前账号记录为准。"
                         : "替换前会保留当前版本，之后也能从备份页找回。登录账号和购买权益以当前账号记录为准。")
                }
            } else if !store.isLoadingPreview && store.error == nil {
                Section {
                    if store.hasOpenedPreview {
                        Label("请重新打开这份备份", systemImage: "arrow.clockwise")
                        Button("重新打开") { Task { await store.select(backupID, force: true) } }
                    } else { ProgressView("正在打开备份") }
                }
            }
        }
        .navigationTitle("备份详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: backupID) { await store.select(backupID) }
        .confirmationDialog("恢复此备份？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible, presenting: confirmation) { value in
            Button("确认恢复", role: .destructive) { Task { await store.restore(value) } }
        } message: { _ in Text("将替换\(store.targetLabel)的云居。恢复前会保留当前版本；如果原文件已损坏，会保留其原始文件。") }
    }
}
