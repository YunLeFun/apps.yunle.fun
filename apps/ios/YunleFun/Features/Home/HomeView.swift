import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var sync: HomeSyncCoordinator
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var assistantRollout: AssistantRolloutStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("home.showRecent") private var showRecent = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing = false
    @State private var isRefreshing = false
    @State private var showScanner = false
    @State private var removals = 0
    /// Width between the layout margins, measured by the grid's scroll view.
    @State private var gridWidth: CGFloat = 0
    @State private var openFolder: HomeFolderSelection?
    @State private var pinChanges = 0
    let browse: () -> Void

    /// Everything that changes the visible grid; animating on it lets icons
    /// glide into place after add / remove / pin instead of jumping.
    private var layoutKey: [String] {
        library.snapshot.applications.map(\.homeKey) + ["|"] + library.snapshot.dockApplications.map(\.homeKey)
    }

    /// The entry follows the rollout; a members-only entry stays hidden until membership is known.
    private var showsAssistant: Bool {
        let user = accounts.user?.isUsable == true ? accounts.user?.id : nil
        return assistantRollout.rollout.admits(userID: user, isMember: wallet.snapshot?.membership.isActive)
    }

    /// Membership decides the members-only entry. An explicit refresh always re-reads it; otherwise only an
    /// unknown membership, or one older than ten minutes, is read again (for example after launching offline,
    /// or after the membership changed on another device).
    private func loadMembership(force: Bool = false) async {
        guard assistantRollout.rollout.audience == .members, accounts.user?.isUsable == true, !wallet.isLoading else { return }
        if !force, wallet.snapshot != nil, let checked = wallet.checkedAt, Date().timeIntervalSince(checked) < 10 * 60 { return }
        await wallet.refreshAccount()
    }

    var body: some View {
        Group {
            if let issue = library.storageError {
                ScrollView {
                    ContentStateView(title: "云居需要一点帮助", systemImage: "externaldrive.badge.exclamationmark", message: issue,
                                     actionTitle: "重试") {
                        library.activateAccount(library.accountID)
                        library.updateCatalog(catalog.applications, markingMissingPublicAppsUnavailable: catalog.successfulLoadID != nil)
                        sync.identityChanged()
                    }
                }
            } else if editing && !dynamicTypeSize.isAccessibilitySize {
                editCanvas
            } else if editing {
                List {
                    ForEach(library.snapshot.applications, id: \.homeKey) { app in
                        ApplicationRow(application: current(app))
                    }
                        .onMove(perform: library.move)
                        .onDelete { indices in
                            let apps = indices.map { library.snapshot.applications[$0] }
                            apps.forEach(library.remove)
                        }
                    if !library.snapshot.dockApplications.isEmpty {
                        Section("常用应用") {
                            ForEach(library.snapshot.dockApplications, id: \.homeKey) { app in
                                HStack {
                                    ApplicationRow(application: current(app))
                                    Spacer()
                                    Button { withAnimation(Motion.fade) { library.setPinned(app, false) } } label: {
                                        Label("取消常用", systemImage: "pin.slash")
                                    }
                                }
                            }
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
            } else if library.snapshot.applications.isEmpty && library.snapshot.dockApplications.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        statusNotices
                        runningApplicationsLink
                        ContentStateView(title: "把喜欢的应用带回云居", systemImage: "square.grid.2x2",
                                         message: "从工坊添加应用，下次打开更顺手。", actionTitle: "去工坊看看", action: browse)
                            .accessibilityIdentifier("home.empty")
                    }
                    .padding()
                }
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    List { homeSections }
                } else {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) { homeSections }
                                .padding(.horizontal, HomeGridMetrics.margin)
                                .padding(.vertical)
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                                // Like the system home screen, holding blank space starts editing.
                                .background(Color.clear.contentShape(Rectangle()).onLongPressGesture(perform: enterEditing))
                                .animation(Motion.standard(reduceMotion: reduceMotion), value: layoutKey)
                                .animation(Motion.fade, value: sync.phase)
                                .animation(Motion.fade, value: runtime.applications.count)
                        }
                        .modifier(HomeGridWidthReader(width: proxy.size.width, into: $gridWidth))
                    }
                }
            }
        }
        .haptic(.impact, trigger: removals)
        .haptic(.impact, trigger: editing) { old, new in !old && new }
        .onChange(of: layoutKey) { keys in
            if editing && keys == ["|"] { withAnimation(Motion.fade) { editing = false } }
        }
        .haptic(.selection, trigger: pinChanges)
        .refreshable { await refreshHome() }
        .navigationTitle("云居")
        // Read membership once per identity, and again when it is unknown or stale on returning to the app.
        .task(id: "\(accounts.identityGeneration)|\(assistantRollout.rollout.audience.rawValue)") { await loadMembership() }
        .onChange(of: scenePhase) {
            if $0 == .active {
                Task {
                    if catalog.error != nil { await refreshCatalog() }
                    await loadMembership()
                }
            }
        }
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .general) }
        .sheet(item: $openFolder) { HomeFolderView(folderID: $0.id) }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if showsAssistant {
                    NavigationLink { AssistantView() } label: { Label("AI 助手", systemImage: "sparkles").labelStyle(.iconOnly) }
                        .accessibilityIdentifier("home.assistant")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: browse) { Label("添加应用", systemImage: "plus").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("home.add")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if editing {
                    Button("完成") { withAnimation(Motion.fade) { editing = false } }
                        .accessibilityIdentifier("home.edit.done")
                } else if dynamicTypeSize.isAccessibilitySize {
                    NavigationLink { HomeOptionsView(editing: $editing) } label: {
                        optionsLabel
                    }
                    .accessibilityLabel("云居选项")
                    .accessibilityValue(showsSyncActivity ? "正在同步云居" : "")
                    .accessibilityIdentifier("home.options")
                } else {
                    Menu {
                        Button { showScanner = true } label: { Label("扫一扫", systemImage: "qrcode.viewfinder") }
                            .accessibilityIdentifier("home.scan")
                        if !library.snapshot.applications.isEmpty {
                            Button(action: enterEditing) { Label("编辑云居", systemImage: "square.and.pencil") }
                        }
                        if accounts.user != nil || sync.supportsICloud {
                            NavigationLink { HomeSyncSettingsView() } label: {
                                Label(sync.message, systemImage: "icloud")
                            }
                        }
                        if !runtime.applications.isEmpty {
                            NavigationLink { RunningApplicationsView() } label: {
                                Label("正在运行（\(runtime.applications.count)）", systemImage: "square.stack")
                            }
                        }
                    } label: { optionsLabel }
                    .accessibilityLabel("云居选项")
                    .accessibilityValue(showsSyncActivity ? "正在同步云居" : "")
                    .accessibilityIdentifier("home.options")
                }
            }
        }
    }

    private var showsSyncActivity: Bool {
        sync.isActive && sync.isSyncing && !isRefreshing
    }

    /// Keep the options button's footprint while sync runs in the background.
    /// Pull-to-refresh already supplies its own system activity indicator.
    private var optionsLabel: some View {
        ZStack {
            if showsSyncActivity {
                ProgressView()
                    .controlSize(.small)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("home.sync.progress")
            } else {
                Image(systemName: "ellipsis")
            }
        }
        .frame(width: 24, height: 24)
    }

    private func enterEditing() {
        guard !library.snapshot.applications.isEmpty || !library.snapshot.dockApplications.isEmpty else { return }
        withAnimation(Motion.fade) { editing = true }
    }

    /// 我的应用: with 常用应用 shown, pinned apps live only there; with it hidden,
    /// dock-only apps join the end of the main grid.
    private var mainApplications: [CloudApplication] {
        library.snapshot.dockVisible ? library.snapshot.applications.filter { !library.isPinned($0) }
            : library.snapshot.applications + library.snapshot.dockApplications.filter { dock in
                !library.snapshot.applications.contains { $0.homeKey == dock.homeKey }
            }
    }

    private var editCanvas: some View {
        GeometryReader { proxy in
            HomeScrollView { scroller in
                HomeEditCanvas(
                    dock: library.snapshot.dockVisible ? library.snapshot.dockApplications.map(current) : nil,
                    items: mainItems,
                    reorderable: Set(library.snapshot.configuration.installedApps.map(\.appId)
                        + library.snapshot.configuration.folders.map { HomeLibrary.folderKey($0.id) }),
                    dockCapacity: 4,
                    metrics: metrics,
                    viewportHeight: proxy.size.height,
                    scroller: scroller,
                    reorderDock: { library.reorder($0, inDock: true) },
                    reorderItems: { library.reorderItems($0) },
                    setPinned: { apps, pinned in
                        let changed = library.setPinned(apps, pinned)
                        if changed { pinChanges += 1 }
                        return changed
                    },
                    remove: { app in
                        withAnimation(Motion.standard(reduceMotion: reduceMotion)) { library.remove(app) }
                        removals += 1
                    },
                    createFolder: { name, keys, anchor in library.createFolder(named: name, with: keys, at: anchor) },
                    addToFolder: { library.addToFolder($0, keys: $1) },
                    dissolveFolder: { library.dissolveFolder($0.id) },
                    openFolder: { openFolder = HomeFolderSelection(id: $0.id) })
                .padding(.horizontal, HomeGridMetrics.margin)
                .padding(.vertical)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                // Tapping blank space leaves editing, as on the system home screen.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture {
                    withAnimation(Motion.fade) { editing = false }
                })
                .animation(Motion.standard(reduceMotion: reduceMotion), value: layoutKey)
            }
            .accessibilityIdentifier("home.edit.canvas")
            .modifier(HomeGridWidthReader(width: proxy.size.width, into: $gridWidth))
        }
    }

    private var metrics: HomeGridMetrics {
        HomeGridMetrics(width: gridWidth > 0 ? gridWidth : 370, sizeClass: sizeClass)
    }

    private func current(_ app: CloudApplication) -> CloudApplication {
        app.refreshingPublicMetadata(with: catalog.application(id: app.id))
    }

    private func refreshCatalog() async {
        await catalog.load()
        library.updateCatalog(catalog.applications,
            markingMissingPublicAppsUnavailable: catalog.error == nil && catalog.successfulLoadID != nil)
    }

    /// Pull-to-refresh is the retry for a failed catalog load and a failed sync.
    /// State updates can replace SwiftUI's refresh action and cancel its task, so
    /// this explicit user request stays alive until the data refresh finishes.
    private func refreshHome() async {
        let identity = accounts.identityGeneration
        await Task { @MainActor in
            guard identity == accounts.identityGeneration, !isRefreshing else { return }
            isRefreshing = true
            defer { isRefreshing = false }
            await refreshCatalog()
            guard identity == accounts.identityGeneration else { return }
            await sync.recheck()
            guard identity == accounts.identityGeneration else { return }
            await loadMembership(force: true)
        }.value
    }

    /// Catalog and sync notices share a tight stack so a network failure does not
    /// push the grids down by two multi-line cards.
    @ViewBuilder private var statusNotices: some View {
        if showsCatalogNotice || showsSyncNotice {
            VStack(alignment: .leading, spacing: 8) {
                if showsCatalogNotice { catalogStatus }
                if showsSyncNotice { syncStatus }
            }
        }
    }

    private var showsCatalogLoadingRow: Bool {
        catalog.isLoading && (library.snapshot.applications + library.snapshot.dockApplications).contains { $0.isUnavailable == true }
    }

    /// Suppressed while the unavailable-app loading row is standing in for the same failure.
    private var catalogFailureMessage: String? {
        guard !showsCatalogLoadingRow else { return nil }
        return catalog.error
    }

    /// User-facing sync failure. `sync.message` is what Home already shows for this phase.
    private var syncFailureMessage: String? {
        guard sync.isActive, case .failed = sync.phase else { return nil }
        return sync.message
    }

    /// One strip when both failures are loss of connectivity. Other failures stay separate.
    private var combinesOfflineFailures: Bool {
        guard let catalogFailureMessage, let syncFailureMessage else { return false }
        return HomeStatusBanner.isConnectivityFailure(catalogFailureMessage)
            && HomeStatusBanner.isConnectivityFailure(syncFailureMessage)
    }

    private var showsCatalogNotice: Bool {
        showsCatalogLoadingRow || (catalogFailureMessage != nil && !combinesOfflineFailures)
    }

    private var showsSyncNotice: Bool {
        if combinesOfflineFailures { return true }
        guard sync.isActive else { return false }
        switch sync.phase {
        case .failed, .conflict:
            return true
        case .idle:
            return library.snapshot.base == nil && !library.snapshot.autoSyncEnabled
        case .syncing:
            return false
        }
    }

    @ViewBuilder private var catalogStatus: some View {
        if showsCatalogLoadingRow {
            ProgressView("正在载入应用信息")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home.catalog.loading")
        } else if let error = catalogFailureMessage, !combinesOfflineFailures {
            let message = HomeStatusBanner.catalogMessage(for: error)
            HomeStatusStrip(
                systemImage: "wifi.exclamationmark",
                message: message,
                accessibilityMessage: "应用信息载入失败。\(error)。下拉可重试。",
                refresh: refreshFromBanner
            )
        }
    }

    @ViewBuilder private var syncStatus: some View {
        if combinesOfflineFailures, let catalogFailureMessage, let syncFailureMessage {
            HomeStatusStrip(
                systemImage: "wifi.exclamationmark",
                message: HomeStatusBanner.combinedMessage(catalog: catalogFailureMessage, sync: syncFailureMessage),
                accessibilityMessage: "应用信息载入失败。\(catalogFailureMessage) \(syncFailureMessage)。下拉可重试。",
                refresh: refreshFromBanner
            ) {
                syncSettingsLink
            }
        } else if sync.isActive {
            switch sync.phase {
            case .failed:
                HomeStatusStrip(
                    systemImage: "exclamationmark.icloud",
                    message: sync.message,
                    accessibilityMessage: "\(sync.message) 下拉可重试。",
                    refresh: refreshFromBanner
                ) {
                    syncSettingsLink
                }
            case .conflict:
                NavigationLink { HomeSyncSettingsView() } label: {
                    HomeStatusStrip(
                        systemImage: "exclamationmark.icloud",
                        message: sync.message,
                        accessibilityMessage: "\(sync.message)。查看并选择要保留的版本。",
                        stacksActions: true
                    ) {
                        Text("查看并选择要保留的版本")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.sync.conflict")
            case .idle where library.snapshot.base == nil && !library.snapshot.autoSyncEnabled:
                HomeStatusStrip(systemImage: "icloud", message: "尚未同步，此设备尚未读取云端云居。", stacksActions: true) {
                    syncStartButton
                }
            default:
                EmptyView()
            }
        }
    }

    private var refreshFromBanner: () -> Void {
        { Task { await refreshHome() } }
    }

    private var syncStartButton: some View {
        Button("立即同步") { Task { await sync.synchronize() } }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("home.sync.start")
    }

    private var syncSettingsLink: some View {
        NavigationLink { HomeSyncSettingsView() } label: { Text("云居同步") }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var runningApplicationsLink: some View {
        if !runtime.applications.isEmpty {
            NavigationLink { RunningApplicationsView() } label: {
                Label("正在运行（\(runtime.applications.count)）", systemImage: "square.stack")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home.running")
        }
    }

    @ViewBuilder private var homeSections: some View {
        // Accessibility text uses a List. Each notice has to be its own row so
        // the conflict link stays a real navigation row; the regular home groups
        // them tightly inside the scroll view.
        if dynamicTypeSize.isAccessibilitySize {
            catalogStatus
            syncStatus
        } else {
            statusNotices
        }
        runningApplicationsLink
        // The dock leads, as a pinned shelf under the title; edit mode keeps
        // the same order so it doesn't move when jiggling starts.
        if library.snapshot.dockVisible && !library.snapshot.dockApplications.isEmpty {
            if dynamicTypeSize.isAccessibilitySize {
                section("常用应用", applications: library.snapshot.dockApplications.map(current))
            } else {
                dock(library.snapshot.dockApplications.map(current))
            }
        }
        if showRecent && library.snapshot.applications.count > 4 {
            let recent = Array(library.snapshot.recentApplications.prefix(4)).map(current)
            if !recent.isEmpty { section("最近使用", applications: recent) }
        }
        let main = mainItems
        if !main.isEmpty { mainSection(main) }
    }

    /// 我的应用 with folders collapsed into folder cells.
    private var mainItems: [HomeGridItem] {
        HomeGridItem.items(mainApplications.map(current), folders: library.snapshot.configuration.folders)
    }

    @ViewBuilder private func mainSection(_ items: [HomeGridItem]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Section("我的应用") {
                ForEach(items) { item in
                    switch item {
                    case .app(let app): applicationButton(app)
                    case .folder(let folder, let apps): folderButton(folder, apps: apps)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("我的应用").font(.headline).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: metrics.gridItems, spacing: HomeGridMetrics.rowSpacing) {
                    ForEach(items) { item in
                        Group {
                            switch item {
                            case .app(let app): applicationButton(app)
                            case .folder(let folder, let apps): folderButton(folder, apps: apps)
                            }
                        }
                        .transition(Motion.appear(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func folderButton(_ folder: HomeFolder, apps: [CloudApplication]) -> some View {
        Button { openFolder = HomeFolderSelection(id: folder.id) } label: {
            if dynamicTypeSize.isAccessibilitySize {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.name).font(.headline).foregroundStyle(.primary)
                        Text("\(apps.count) 个应用").font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "folder") }
            } else {
                HomeAppGlyph(name: folder.name, labelWidth: metrics.labelWidth) { HomeFolderIcon(apps: apps) }
                    .contentShape(Rectangle())
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .modifier(HomeButtonStyle(grid: !dynamicTypeSize.isAccessibilitySize))
        .accessibilityLabel("\(folder.name)，文件夹，\(apps.count) 个应用")
        .accessibilityIdentifier("home.folder.\(folder.id)")
        .contextMenu {
            Button { openFolder = HomeFolderSelection(id: folder.id) } label: { Label("打开", systemImage: "folder") }
            if !dynamicTypeSize.isAccessibilitySize {
                Button(action: enterEditing) { Label("编辑云居", systemImage: "apps.iphone") }
            }
            Button(role: .destructive) { withAnimation(Motion.fade) { library.dissolveFolder(folder.id) } } label: {
                Label("解散文件夹", systemImage: "folder.badge.minus")
            }
        }
    }

    /// Non-drag way into folders (and the VoiceOver one): pick a folder, or
    /// start a new one named after the app's category.
    @ViewBuilder private func folderMenu(_ app: CloudApplication) -> some View {
        let configuration = library.snapshot.configuration
        if let folder = configuration.folder(containing: app.homeKey) {
            Button { withAnimation(Motion.fade) { library.removeFromFolder(app.homeKey) } } label: {
                Label("移出“\(folder.name)”", systemImage: "arrow.up.forward.square")
            }
        } else if library.contains(app) && !library.isPinned(app) {
            Menu {
                ForEach(configuration.folders) { folder in
                    Button(folder.name) { withAnimation(Motion.fade) { library.addToFolder(folder.id, keys: [app.homeKey]) } }
                }
                Button {
                    withAnimation(Motion.fade) {
                        _ = library.createFolder(named: HomeGridItem.suggestedFolderName(for: [app]), with: [app.homeKey], at: app.homeKey)
                    }
                } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }
            } label: { Label("移入文件夹", systemImage: "folder") }
        }
    }

    @ViewBuilder private func section(_ title: String, applications: [CloudApplication]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Section(title) {
                ForEach(applications, id: \.homeKey) { app in
                    applicationButton(app)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: metrics.gridItems, spacing: HomeGridMetrics.rowSpacing) {
                    ForEach(applications, id: \.homeKey) { app in
                        applicationButton(app).transition(Motion.appear(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// 常用应用 as a Home Screen dock: no visible title or names, one row of up
    /// to four icons. VoiceOver keeps the section name and every app name.
    private func dock(_ applications: [CloudApplication]) -> some View {
        HomeDockPlatter {
            HomeDockRow(items: applications.map(HomeDockItem.init), metrics: metrics) { item in
                applicationButton(item.app, showsName: false).transition(Motion.appear(reduceMotion: reduceMotion))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("常用应用")
        .accessibilityIdentifier("home.dock")
    }

    private func applicationButton(_ app: CloudApplication, showsName: Bool = true) -> some View {
        Button { runtime.open(app, catalog: catalog, library: library) } label: {
            if dynamicTypeSize.isAccessibilitySize {
                ApplicationRow(application: app).foregroundStyle(.primary)
            } else {
                HomeAppGlyph(name: app.name, showsName: showsName, labelWidth: metrics.labelWidth, isUnavailable: app.isUnavailable == true) {
                    ApplicationIcon(application: app, size: HomeGridMetrics.iconSize)
                }
                .contentShape(Rectangle())
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .modifier(HomeButtonStyle(grid: !dynamicTypeSize.isAccessibilitySize))
        .accessibilityLabel("打开\(app.name)")
        .accessibilityValue(app.accessLabel ?? "")
        .contextMenu {
            if library.contains(app) && !dynamicTypeSize.isAccessibilitySize {
                Button(action: enterEditing) { Label("编辑云居", systemImage: "apps.iphone") }
            }
            NavigationLink(value: app) { Label("应用详情", systemImage: "info.circle") }
            if library.contains(app) {
                Button { library.setPinned(app, !library.isPinned(app)); pinChanges += 1 } label: {
                    Label(library.isPinned(app) ? "取消常用" : "设为常用", systemImage: library.isPinned(app) ? "pin.slash" : "pin")
                }
                .disabled(!library.isPinned(app) && library.snapshot.configuration.dockApps.count >= 4)
                folderMenu(app)
                Button(role: .destructive) { library.remove(app); removals += 1 } label: { Label("从云居移除", systemImage: "minus.circle") }
            }
            if runtime.contains(app) {
                Button(role: .destructive) { runtime.end(app) } label: { Label("结束运行", systemImage: "xmark.circle") }
            }
        }
    }
}

/// Grid icons get the springboard press; list rows keep the system highlight.
private struct HomeButtonStyle: ViewModifier {
    let grid: Bool
    func body(content: Content) -> some View {
        if grid { content.buttonStyle(PressableButtonStyle()) } else { content.buttonStyle(.plain) }
    }
}

private struct HomeOptionsView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var sync: HomeSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Binding var editing: Bool
    @State private var showScanner = false

    var body: some View {
        List {
            Button { showScanner = true } label: { Label("扫一扫", systemImage: "qrcode.viewfinder") }
                .accessibilityIdentifier("home.scan")
            if !library.snapshot.applications.isEmpty {
                Button { editing = true; dismiss() } label: { Label("编辑云居", systemImage: "square.and.pencil") }
            }
            if accounts.user != nil || sync.supportsICloud {
                NavigationLink { HomeSyncSettingsView() } label: { Label(sync.message, systemImage: "icloud") }
            }
            if !runtime.applications.isEmpty {
                NavigationLink { RunningApplicationsView() } label: {
                    Label("正在运行（\(runtime.applications.count)）", systemImage: "square.stack")
                }
            }
        }
        .navigationTitle("云居选项")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .general) }
    }
}

private struct RunningApplicationsView: View {
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: HomeLibrary

    var body: some View {
        List {
            if runtime.applications.isEmpty {
                ContentStateView(title: "还没有运行中的应用", systemImage: "square.stack",
                                 message: "打开云居或工坊里的应用后，可在这里恢复或结束会话。")
                    .accessibilityIdentifier("home.running.empty")
            }
            ForEach(runtime.applications) { app in
                Button { runtime.open(app, catalog: catalog, library: library) } label: {
                    ApplicationRow(application: app).foregroundStyle(.primary)
                }
                .accessibilityIdentifier("home.running.application.\(app.id)")
                .swipeActions {
                    Button("结束", role: .destructive) { runtime.end(app) }
                }
            }
        }
        .accessibilityIdentifier("home.running.list")
        .navigationTitle("正在运行")
    }
}

/// Feeds the scroll view's width, minus the layout margins, to the grid metrics.
private struct HomeGridWidthReader: ViewModifier {
    let width: CGFloat
    @Binding var into: CGFloat

    func body(content: Content) -> some View {
        content
            .onAppear { into = width - 2 * HomeGridMetrics.margin }
            .onChange(of: width) { into = $0 - 2 * HomeGridMetrics.margin }
    }
}

/// Copy for the compact Home status strips. Connectivity failures that happen
/// together collapse to one sentence; the sync wording stays intact so the
/// local-save reassurance is still on screen.
enum HomeStatusBanner {
    static func isConnectivityFailure(_ message: String) -> Bool {
        let folded = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let markers = ["网络", "无法连接", "互联网", "暂时无法使用", "offline", "internet", "not connected", "timed out", "超时"]
        return markers.contains { marker in
            folded.contains(marker.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))
        }
    }

    /// The title is enough when the detail only restates a network retry.
    static func catalogMessage(for error: String) -> String {
        isConnectivityFailure(error) ? "应用信息载入失败" : error
    }

    static func combinedMessage(catalog: String, sync syncMessage: String) -> String {
        if syncMessage.contains("网络暂时无法连接") {
            return "应用信息载入失败，\(syncMessage)"
        }
        return "应用信息载入失败。\(catalog) \(syncMessage)"
    }
}

/// One status row. A settings link can sit beside or under the message.
/// Pull-to-refresh retries a failed load; the message exposes that as a VoiceOver action.
private struct HomeStatusStrip<Actions: View>: View {
    let systemImage: String
    let message: String
    var accessibilityMessage: String?
    var stacksActions = false
    var refresh: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // The list row, or the empty home's own padding, is the container.
            row.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            row
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder private var row: some View {
        if Actions.self == EmptyView.self {
            messageLabel
        } else if dynamicTypeSize.isAccessibilitySize || stacksActions {
            VStack(alignment: .leading, spacing: 4) {
                messageLabel
                actions()
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                messageLabel
                actions()
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }

    private var messageLabel: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            messageText
        }
    }

    private var baseText: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(accessibilityMessage ?? message)
    }

    @ViewBuilder private var messageText: some View {
        if let refresh {
            baseText.accessibilityAction(named: Text("刷新"), refresh)
        } else {
            baseText
        }
    }
}

extension HomeStatusStrip where Actions == EmptyView {
    init(systemImage: String, message: String, accessibilityMessage: String? = nil, stacksActions: Bool = false, refresh: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.message = message
        self.accessibilityMessage = accessibilityMessage
        self.stacksActions = stacksActions
        self.refresh = refresh
        self.actions = { EmptyView() }
    }
}
