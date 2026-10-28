import SwiftUI

/// What the cache means for one application right now, in the order a person cares about it.
enum ApplicationCacheState: Equatable {
    case unsupported, notDownloaded, downloading(updating: Bool), updateReady, downloaded

    @MainActor init(application: CloudApplication, store: ApplicationCacheStore) {
        let key = ApplicationCacheEntry.key(for: application)
        if store.downloadingID == key { self = .downloading(updating: store.entry(for: application) != nil) }
        else if !ApplicationCacheEntry.supports(application) { self = .unsupported }
        else if store.entry(for: application) == nil { self = .notDownloaded }
        else if store.updatesReady.contains(key) { self = .updateReady }
        else { self = .downloaded }
    }

    var title: String {
        switch self {
        case .unsupported: return "暂不支持下载"
        case .notDownloaded: return "尚未下载缓存"
        case .downloading(let updating): return updating ? "正在更新" : "正在下载"
        case .updateReady: return "更新已就绪"
        case .downloaded: return "已下载到本地"
        }
    }

    var systemImage: String {
        switch self {
        case .unsupported: return "icloud.slash"
        case .notDownloaded: return "icloud.and.arrow.down"
        case .downloading: return "arrow.down.circle"
        case .updateReady: return "sparkles"
        case .downloaded: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unsupported, .notDownloaded: return .secondary
        case .downloading, .updateReady: return .blue
        case .downloaded: return .green
        }
    }
}

/// Where the running session of an application loaded its first page from.
struct ApplicationLaunchSourceLabel: View {
    let revision: Date
    var staticResources = false

    var body: some View {
        if staticResources, revision != .distantPast {
            Label("在线页面 · 已准备公共资源缓存", systemImage: "bolt.fill").foregroundStyle(.green)
        } else if revision == .distantPast {
            Label("本次在线加载", systemImage: "globe").foregroundStyle(.orange)
        } else {
            Label("本次从下载缓存打开", systemImage: "bolt.fill").foregroundStyle(.green)
        }
    }
}

struct ApplicationCacheView: View {
    let application: CloudApplication
    @ObservedObject var store: ApplicationCacheStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.runtimeMenu) private var runtimeMenu
    @State private var confirmClear = false
    private var key: String { ApplicationCacheEntry.key(for: application) }
    private var entry: ApplicationCacheEntry? { store.entry(for: application) }
    private var state: ApplicationCacheState { ApplicationCacheState(application: application, store: store) }
    private var runningRevision: Date? { store.runningRevisions[key] }
    private var staticResources: Bool { ApplicationStaticResourcePolicy.supports(application) }

    var body: some View {
        List {
            Section { header } footer: { Text(headerFooter) }
            if let runningRevision {
                Section {
                    ApplicationLaunchSourceLabel(revision: runningRevision, staticResources: staticResources)
                        .accessibilityIdentifier("cache.launch-source")
                    if runningRevision != .distantPast {
                        LabeledContent("使用的版本") { Text(runningRevision, format: .dateTime.month().day().hour().minute()) }
                    }
                } header: { Text("当前运行") } footer: { Text(launchFooter(runningRevision)) }
            }
            if ApplicationCacheEntry.supports(application) {
                Section { actions } footer: {
                    Text(staticResources ? "仅下载公开脚本、样式、字体和图片。打开应用时仍实时校验登录并读取接口数据；新资源由网页按版本使用。" : "更新会重新下载网页资源，失败时保留旧缓存。正在运行的应用需结束后重新打开，才会使用更新或清理后的内容。")
                }
            }
            if let entry {
                Section {
                    Button {
                        if let runtimeMenu, runtimeMenu.represents(application) { runtimeMenu.dismiss() }
                        else { runtime.open(application, catalog: catalog, library: library) }
                    } label: { Label("打开应用", systemImage: "play.fill") }
                    .accessibilityIdentifier("cache.open")
                }
                Section("缓存内容") {
                    if staticResources { LabeledContent("缓存范围", value: "公共静态资源") }
                    LabeledContent("下载大小", value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                    LabeledContent("已保存资源", value: "\(entry.resourceCount) 项")
                    LabeledContent("更新时间") {
                        Text(entry.downloadedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            }
            if entry != nil || staticResources {
                Section {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label(staticResources ? "删除此站点资源缓存" : "清理此应用下载缓存", systemImage: "trash")
                    }
                    .disabled(store.isClearing)
                    .accessibilityIdentifier("cache.clear")
                }
            }
        }
        .animation(.default, value: state)
        .navigationTitle("应用下载缓存")
        .navigationBarTitleDisplayMode(.inline)
        .runtimeMenuToolbar()
        .task { await store.refresh() }
        .alert("清理这个应用的下载缓存？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) { }
            Button("清理下载缓存", role: .destructive) { Task { await store.clear(id: key) } }
        } message: { Text("只删除下载的网页资源，云居记录、网站登录和本地使用数据会保留。") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ApplicationIcon(application: application, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(application.name).font(.headline)
                Label(state.title, systemImage: state.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(state.tint)
                if let entry, case .downloaded = state {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)) · 更新于 \(entry.downloadedAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var headerFooter: String {
        if staticResources {
            return "把网站的公共资源预下载到本机，减少打开和切换页面时的下载。首页、登录校验和接口数据始终联网；网站登录和使用数据不会打包。显示大小为下载资源合计，实际占用由系统管理，系统可能回收缓存。"
        }
        if let url = application.launchURL, ApplicationStaticResourcePolicy.origin(for: url) != nil {
            return "管理后台与支持中心的公共资源缓存需要 iOS 17 或更高版本，当前仍可在线打开应用。"
        }
        return ApplicationCacheEntry.supports(application)
            ? "保存首页及加载时取得的网页资源，打开更快。登录、实时数据、视频和其他页面仍可能需要联网。缓存由系统按可用空间保留。"
            : "暂时只支持云乐坊中公开、免费的应用。需要登录、会员、购买或工坊权限的应用继续在线使用。"
    }

    private func launchFooter(_ revision: Date) -> String {
        if staticResources {
            return "页面和登录校验来自网站实时响应，匹配版本的公共资源由 WebKit 按缓存策略复用。账号切换后可重新下载，为当前账号准备缓存。"
        }
        if revision != .distantPast {
            return state == .updateReady ? "已下载更新，结束应用后重新打开即可使用新版本。" : "首页来自本地缓存；接口请求和未缓存的资源仍会联网。"
        }
        return entry == nil ? "下载后，下次打开会先读取本地缓存。" : "缓存是在本次打开之后保存的，结束应用后重新打开即可使用。"
    }

    @ViewBuilder private var actions: some View {
        if case .downloading = state {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(state.title)
                    Spacer()
                    Text(store.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: store.progress)
                    .accessibilityIdentifier("cache.progress")
            }
            .padding(.vertical, 4)
            Button(role: .cancel) { store.cancelDownload() } label: { Label("取消下载", systemImage: "xmark.circle") }
                .disabled(store.isClearing)
        } else {
            Button { store.download(application) } label: {
                Label(entry == nil ? "下载到本地" : "更新缓存", systemImage: entry == nil ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                    .fontWeight(.semibold)
            }
            .disabled(store.isBusy)
            .accessibilityIdentifier("cache.download")
            if store.isBusy, !store.isClearing, let name = store.downloadingName {
                Text("正在下载 \(name)，完成后可继续。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let message = store.message, store.messageApplicationID == key {
            Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("cache.message")
        }
    }
}

struct ApplicationCacheSettingsView: View {
    @ObservedObject var store: ApplicationCacheStore
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @State private var confirmClearAll = false
    @State private var pendingClear: ApplicationCacheEntry?

    private var available: [CloudApplication] {
        var seen = Set<String>()
        return (library.snapshot.applications + library.snapshot.dockApplications)
            .map { $0.refreshingPublicMetadata(with: catalog.application(id: $0.id)) }
            .filter { ApplicationCacheEntry.supports($0) && store.entry(for: $0) == nil && seen.insert(ApplicationCacheEntry.key(for: $0)).inserted }
    }

    private var usage: Double {
        min(1, Double(store.totalBytes) / Double(ApplicationCacheRepository.maximumTotalBytes))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        Text("/ \(ByteCountFormatter.string(fromByteCount: Int64(ApplicationCacheRepository.maximumTotalBytes), countStyle: .file))")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: usage).tint(usage > 0.9 ? .orange : .accentColor)
                    Text("\(store.entries.count) 个应用已下载").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if store.downloadingID != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(store.downloadingName.map { "正在下载 \($0)" } ?? "正在下载应用资源").lineLimit(1)
                            Spacer()
                            Text(store.progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: store.progress)
                    }
                    Button("取消下载") { store.cancelDownload() }.disabled(store.isClearing)
                }
            } footer: { Text("单次下载最多 25 MB，已下载版本合计最多 200 MB。公共资源缓存的实际占用由系统管理。下载缓存可加快启动；是否能离线使用取决于应用功能。") }
            if !store.entries.isEmpty {
                Section {
                    ForEach(store.entries) { entry in
                        NavigationLink {
                            ApplicationCacheView(application: entry.application, store: store)
                        } label: { DownloadedRow(entry: entry, store: store) }
                        .swipeActions {
                            Button("清理", role: .destructive) { pendingClear = entry }
                        }
                    }
                } header: { Text("已下载") } footer: { Text("左滑可清理单个应用。") }
            }
            if !available.isEmpty {
                Section {
                    ForEach(available) { application in
                        NavigationLink { ApplicationCacheView(application: application, store: store) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(application: application, size: 32)
                                Text(application.name)
                                Spacer()
                                Button { store.download(application) } label: {
                                    Image(systemName: "arrow.down.circle").font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .disabled(store.isBusy)
                                .accessibilityLabel("下载\(application.name)")
                            }
                        }
                    }
                } header: { Text("云居中的应用") } footer: { Text("点按右侧图标直接下载。") }
            }
            Section {
                Toggle(isOn: $store.automaticUpdatesEnabled) {
                    SettingsLabel("自动更新已下载应用", systemImage: "arrow.triangle.2.circlepath", color: .blue)
                }
                .accessibilityIdentifier("cache.auto-update")
                Toggle(isOn: $store.wifiOnly) {
                    SettingsLabel("仅在 Wi-Fi 下下载", systemImage: "wifi", color: .teal)
                }
                .disabled(!store.automaticUpdatesEnabled)
                .accessibilityIdentifier("cache.wifi-only")
            } header: { Text("自动更新") } footer: {
                Text("开启后，使用云乐坊期间每隔至少 24 小时静默更新已下载的应用。默认仅 Wi-Fi，低数据模式下暂停。关闭 Wi-Fi 限制会使用蜂窝数据。更新在下次重新打开应用时生效；失败保留旧缓存并稍后重试。")
            }
            Section {
                Button(role: .destructive) { confirmClearAll = true } label: { Label("清理全部下载缓存", systemImage: "trash") }
                    .disabled(store.isClearing)
                    .accessibilityIdentifier("cache.clear-all")
            } footer: { Text("云居记录、账号、网站登录和本地使用数据会保留。运行中的应用在结束后重新打开时生效。") }
            if let message = store.message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .animation(.default, value: store.entries)
        .navigationTitle("应用下载缓存")
        .task { await store.refresh() }
        .alert("清理全部应用下载缓存？", isPresented: $confirmClearAll) {
            Button("取消", role: .cancel) { }
            Button("清理全部", role: .destructive) { Task { await store.clear() } }
        } message: { Text("正在进行的下载会取消。之后仍可按需重新下载。") }
        .alert("清理这个应用的下载缓存？", isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
               presenting: pendingClear) { entry in
            Button("取消", role: .cancel) { }
            Button("清理下载缓存", role: .destructive) { Task { await store.clear(id: entry.id) } }
        } message: { entry in Text("只删除「\(entry.application.name)」下载的网页资源，云居记录、网站登录和本地使用数据会保留。") }
    }
}

private struct DownloadedRow: View {
    let entry: ApplicationCacheEntry
    @ObservedObject var store: ApplicationCacheStore

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(application: entry.application, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.application.name)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)) · \(entry.downloadedAt.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if store.downloadingID == entry.id {
                ProgressView().accessibilityLabel("正在更新")
            } else if store.updatesReady.contains(entry.id) {
                Text("更新已就绪").font(.caption).foregroundStyle(.blue)
            } else if let revision = store.runningRevisions[entry.id] {
                Text(revision == .distantPast ? "运行中" : "运行中 · 缓存").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
