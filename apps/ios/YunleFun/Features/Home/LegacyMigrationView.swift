import SwiftUI

struct LegacyMigrationView: View {
    @StateObject private var store: LegacyImportStore
    @State private var confirmation: LegacyImportConfirmation?

    init(library: HomeLibrary, accounts: IdentityScopedAccountAuthorizing) {
        _store = StateObject(wrappedValue: LegacyImportStore(library: library, accounts: accounts))
    }
    init(store: LegacyImportStore) { _store = StateObject(wrappedValue: store) }

    var body: some View {
        Form {
            if store.isLoading { Section { ProgressView("正在读取旧版记录") } }
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("重新读取") { Task { await store.load(retry: true) } }
                }
            }
            if let archive = store.visibleArchive {
                recordSections(archive)
            } else if store.archive != nil {
                Section {
                    Label("旧版记录已为另一个云居保留", systemImage: "person.crop.circle.badge.exclamationmark")
                    Text("请回到原来的云居后查看或继续导入。").foregroundStyle(.secondary)
                }
            } else if store.isLoaded {
                Section {
                    Label("未发现旧版记录", systemImage: "checkmark.circle")
                    Text("旧版数据需要保留在同一设备、同一应用的存储中。删除应用后重新安装，或单独安装的开发版，可能没有这些记录。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("账号与权益") {
                Text("旧版账号需要重新登录。会员、云币与已购权益会从云乐坊账号重新核对。")
                NavigationLink("登录或管理账号") { AccountManagementView() }
            }
        }
        .navigationTitle("旧版数据导入")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .confirmationDialog("导入旧版云居？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible, presenting: confirmation) { value in
            Button("确认导入", role: .destructive) { store.apply(value) }
        } message: { _ in
            Text("将导入到\(store.targetLabel)。原有云居会先保存一份本机备份，再替换布局和对应设置。旧版原记录继续保留。")
        }
    }

    @ViewBuilder private func recordSections(_ archive: LegacyImportArchive) -> some View {
        Section {
            if archive.claim?.completed == true {
                Label("旧版数据已导入", systemImage: "checkmark.circle")
            } else {
                LabeledContent("导入位置", value: store.targetLabel)
            }
        } footer: {
            Text("旧版的本机记录没有可靠的账号归属。请确认导入位置，不会根据旧记录自动登录或合并其他账号。")
        }
        if let configuration = archive.record.configuration {
            Section("旧版云居") {
                LabeledContent("应用", value: "\(configuration.installedApps.count)")
                LabeledContent("常用应用", value: "\(configuration.dockApps.count)")
                LabeledContent("最近使用", value: "\(configuration.recentApps.count)")
                Text("保留应用顺序和最近使用时间。暂时找不到资料的应用仍会保留位置，联网更新后再打开。")
                    .foregroundStyle(.secondary)
            }
        }
        Section("设置") {
            if let appearance = archive.record.appearance.flatMap(AppAppearance.init(rawValue:)) { LabeledContent("显示模式", value: appearance.label) }
            if let enabled = archive.record.syncEnabled { LabeledContent("云同步", value: enabled ? "开启" : "关闭") }
            if let enabled = archive.record.autoSyncEnabled { LabeledContent("自动同步", value: enabled ? "开启" : "关闭") }
            if let visible = archive.record.dockVisible { LabeledContent("常用应用", value: visible ? "显示" : "隐藏") }
            if archive.record.hasOtherSettings { Text("浏览器、图标等其他设置的旧记录也会保留在此设备。") .foregroundStyle(.secondary) }
        }
        if !archive.record.accounts.isEmpty {
            Section("旧版账号记录") {
                ForEach(archive.record.accounts) { Text($0.label) }
            }
        }
        if archive.claim?.completed != true {
            Section {
                Button("导入到当前云居") { confirmation = store.confirmation() }
                    .disabled(store.isLoading || !store.isLoaded || !store.belongsToCurrentTarget)
            } footer: { Text("这里只导入本机记录，云同步仍按当前账号的版本检查执行。") }
        }
    }
}

#if DEBUG
#Preview("样例 · 导入前") { LegacyMigrationPreview(hasRecord: true) }
#Preview("样例 · 无旧版记录") { LegacyMigrationPreview(hasRecord: false) }

private struct LegacyMigrationPreview: View {
    @StateObject private var store: LegacyImportStore
    init(hasRecord: Bool) {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyPreview-" + id)
        _store = StateObject(wrappedValue: LegacyImportStore(library: HomeLibrary(directory: directory.appendingPathComponent("home")),
            accounts: LegacyPreviewAccounts(), reader: LegacyPreviewReader(hasRecord: hasRecord),
            archiveURL: directory.appendingPathComponent("record.json"), preferences: UserDefaults(suiteName: "LegacyPreview-" + id)!))
    }
    var body: some View {
        NavigationStack { LegacyMigrationView(store: store) }.allowsHitTesting(false)
    }
}
@MainActor
private final class LegacyPreviewAccounts: IdentityScopedAccountAuthorizing {
    let user: AccountUser? = nil
    let identityGeneration = UUID()
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount { throw AccountError.signedOut }
}
private struct LegacyPreviewReader: LegacyLocalDataReading {
    let hasRecord: Bool
    func read() async throws -> [String: String] {
        hasRecord ? ["ylf:homescreen-apps": #"[{"appId":"air-conditioner"}]"#, "ylf_theme_mode": "system"] : [:]
    }
}
#endif
