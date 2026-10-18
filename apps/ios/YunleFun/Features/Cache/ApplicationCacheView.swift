import SwiftUI

struct ApplicationCacheView: View {
    let application: CloudApplication
    @ObservedObject var store: ApplicationCacheStore
    @State private var confirmClear = false
    private var entry: ApplicationCacheEntry? { store.entry(for: application) }
    private var isDownloading: Bool { store.downloadingID == ApplicationCacheEntry.key(for: application) }

    var body: some View {
        List {
            Section {
                Label(application.name, systemImage: "app")
                if let entry {
                    LabeledContent("下载大小", value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                    LabeledContent("更新时间") { Text(entry.downloadedAt, format: .dateTime.year().month().day().hour().minute()) }
                    LabeledContent("已保存资源", value: "\(entry.resourceCount) 项")
                } else { Text("尚未下载缓存").foregroundStyle(.secondary) }
            } footer: {
                Text("保存首页及加载时取得的网页资源。登录、实时数据、视频和其他页面仍可能需要联网。缓存由系统按可用空间保留。")
            }
            Section {
                if store.updatesReady.contains(ApplicationCacheEntry.key(for: application)) {
                    Label("更新已就绪，下次重新打开生效", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                if isDownloading {
                    ProgressView(value: store.progress) { Text(entry == nil ? "正在下载" : "正在更新") }
                        .accessibilityIdentifier("cache.progress")
                    Button("取消下载") { store.cancelDownload() }.disabled(store.isClearing)
                } else {
                    Button { store.download(application) } label: {
                        Label(entry == nil ? "下载到本地" : "更新缓存", systemImage: entry == nil ? "arrow.down.circle" : "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isBusy || !ApplicationCacheEntry.supports(application))
                    .accessibilityIdentifier("cache.download")
                }
                if entry != nil {
                    Button("清理此应用下载缓存", role: .destructive) { confirmClear = true }
                        .disabled(store.isClearing).accessibilityIdentifier("cache.clear")
                }
            } footer: {
                Text(ApplicationCacheEntry.supports(application)
                     ? "更新会重新下载网页资源，失败时保留旧缓存。正在运行的应用需结束后重新打开，才会使用更新或清理后的内容。"
                     : "暂时只支持云乐坊中公开、免费的应用。需要登录、会员、购买或工坊权限的应用继续在线使用。")
            }
            if let message = store.message { Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("cache.message") } }
        }
        .navigationTitle("应用下载缓存")
        .navigationBarTitleDisplayMode(.inline)
        .runtimeMenuToolbar()
        .task { await store.refresh() }
        .alert("清理这个应用的下载缓存？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) { }
            Button("清理下载缓存", role: .destructive) { Task { await store.clear(id: ApplicationCacheEntry.key(for: application)) } }
        } message: { Text("只删除下载的网页资源，云居记录、网站登录和本地使用数据会保留。") }
    }
}

struct ApplicationCacheSettingsView: View {
    @ObservedObject var store: ApplicationCacheStore
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @State private var confirmClearAll = false

    private var available: [CloudApplication] {
        var seen = Set<String>()
        return (library.snapshot.applications + library.snapshot.dockApplications)
            .map { $0.refreshingPublicMetadata(with: catalog.application(id: $0.id)) }
            .filter { ApplicationCacheEntry.supports($0) && store.entry(for: $0) == nil && seen.insert(ApplicationCacheEntry.key(for: $0)).inserted }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("下载缓存", value: ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))
                Text("\(store.entries.count) 个应用已下载").foregroundStyle(.secondary)
                if store.downloadingID != nil {
                    ProgressView(value: store.progress) { Text("正在下载应用资源") }
                    Button("取消下载") { store.cancelDownload() }.disabled(store.isClearing)
                }
            } footer: { Text("单个应用最多 25 MB，总计最多 200 MB。下载缓存可加快启动；是否能离线使用取决于应用功能。") }
            Section {
                Toggle("自动更新已下载应用", isOn: $store.automaticUpdatesEnabled)
                    .accessibilityIdentifier("cache.auto-update")
                Toggle("仅在 Wi-Fi 下下载", isOn: $store.wifiOnly)
                    .disabled(!store.automaticUpdatesEnabled)
                    .accessibilityIdentifier("cache.wifi-only")
            } header: { Text("自动更新") } footer: {
                Text("开启后，使用云乐坊期间每隔至少 24 小时静默更新已下载的应用。默认仅 Wi-Fi，低数据模式下暂停。关闭 Wi-Fi 限制会使用蜂窝数据。更新在下次重新打开应用时生效；失败保留旧缓存并稍后重试。")
            }
            if !store.entries.isEmpty {
                Section("已下载") {
                    ForEach(store.entries) { entry in
                        NavigationLink {
                            ApplicationCacheView(application: entry.application, store: store)
                        } label: {
                            LabeledContent(entry.application.name,
                                           value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                        }
                    }
                }
            }
            if !available.isEmpty {
                Section("云居中的应用") {
                    ForEach(available) { application in
                        NavigationLink(application.name) { ApplicationCacheView(application: application, store: store) }
                    }
                }
            }
            Section {
                Button("清理全部下载缓存", role: .destructive) { confirmClearAll = true }
                    .disabled(store.isClearing)
                    .accessibilityIdentifier("cache.clear-all")
            } footer: { Text("云居记录、账号、网站登录和本地使用数据会保留。运行中的应用在结束后重新打开时生效。") }
            if let message = store.message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle("应用下载缓存")
        .task { await store.refresh() }
        .alert("清理全部应用下载缓存？", isPresented: $confirmClearAll) {
            Button("取消", role: .cancel) { }
            Button("清理全部", role: .destructive) { Task { await store.clear() } }
        } message: { Text("正在进行的下载会取消。之后仍可按需重新下载。") }
    }
}
