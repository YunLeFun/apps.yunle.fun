import SwiftUI

/// Owns the selected home surface; workshop applications never enter the
/// personal library just because their workshop was selected.
struct HomeWorkspaceView: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var workshops: MyWorkshopsStore
    @AppStorage private var selectedID: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showPicker = false
    private let identity: UUID
    private let service: WorkshopServing
    private let iconPipeline: ApplicationImagePipeline
    let browse: () -> Void

    init(accounts: AccountStore, service: WorkshopServing = WorkshopService(), defaults: UserDefaults = .standard,
         iconPipeline: ApplicationImagePipeline = .shared,
         browse: @escaping () -> Void) {
        self.accounts = accounts; self.service = service; self.browse = browse
        self.iconPipeline = iconPipeline
        identity = accounts.identityGeneration
        _workshops = StateObject(wrappedValue: MyWorkshopsStore(accounts: accounts, service: service))
        _selectedID = AppStorage(wrappedValue: "", Self.selectionKey(userID: accounts.user?.id), store: defaults)
    }

    static func selectionKey(userID: String?) -> String { "home.workshopSelection." + (userID.map { "account." + $0 } ?? "guest") }
    private var selectedWorkshop: PersonalWorkshop? { workshops.switchableWorkshops.first { $0.id == selectedID } }
    private var title: String { selectedID.isEmpty ? "我的云居" : (selectedWorkshop?.name ?? "工坊云居") }
    private var isLoadingSelection: Bool { workshops.isLoading || (!workshops.hasLoaded && workshops.error == nil) }

    var body: some View {
        Group {
            if identity != accounts.identityGeneration {
                Color.clear.loadingOverlay(true, label: "正在切换账号", alignment: .center)
            } else if selectedID.isEmpty {
                HomeView(browse: browse)
            } else if let workshop = selectedWorkshop {
                HomeWorkshopView(workshop: workshop, accounts: accounts, service: service, iconPipeline: iconPipeline)
                    .id(workshop.id)
            } else {
                ScrollView {
                    if !isLoadingSelection {
                        ContentStateView(title: "暂时无法载入工坊", systemImage: "person.2.crop.square.stack",
                            message: workshops.error ?? "这个工坊已不在当前账号的工坊列表中。",
                            actionTitle: "重试") { Task { await refreshWorkshops() } }
                        Button("返回我的云居") { selectedID = "" }.buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .loadingOverlay(isLoadingSelection, label: "正在载入工坊")
                .navigationTitle("云居")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showPicker = true } label: {
                    HStack(spacing: 5) {
                        Text(dynamicTypeSize.isAccessibilitySize ? "云居" : title)
                            .font(.headline).lineLimit(1).truncationMode(.tail)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换云居")
                .accessibilityValue(title)
                .accessibilityIdentifier("home.workspace.switch")
            }
        }
        .task { await refreshWorkshops(ifNeeded: true) }
        .onChange(of: scenePhase) { if $0 == .active { Task { await refreshWorkshops() } } }
        .sheet(isPresented: $showPicker) {
            HomeWorkspacePicker(accounts: accounts, workshops: workshops, selectedID: $selectedID)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func refreshWorkshops(ifNeeded: Bool = false) async {
        if ifNeeded { await workshops.loadIfNeeded() }
        else { await workshops.refresh() }
        guard identity == accounts.identityGeneration else { return }
        if accounts.user == nil { selectedID = "" }
        guard workshops.hasLoaded, workshops.error == nil else { return }
        if !selectedID.isEmpty && selectedWorkshop == nil { selectedID = "" }
    }
}

struct HomeWorkspacePicker: View {
    @ObservedObject var accounts: AccountStore
    @ObservedObject var workshops: MyWorkshopsStore
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss
    @State private var showLogin = false
    @State private var isRefreshing = false

    private var availableWorkshops: [PersonalWorkshop] {
        guard accounts.user != nil, workshops.hasLoaded else { return [] }
        return workshops.switchableWorkshops
    }
    private var isInitialLoad: Bool {
        accounts.user != nil && !workshops.hasLoaded && workshops.error == nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("云居", selection: $selectedID) {
                        Label("我的云居", systemImage: "house")
                            .tag("")
                            .accessibilityIdentifier("home.workspace.personal")
                        ForEach(availableWorkshops) { workshop in
                            WorkspaceWorkshopLabel(name: workshop.name,
                                detail: workshop.status == .disabled ? "工坊已暂停" : workshop.ownerName)
                            .tag(workshop.id)
                            .accessibilityIdentifier("home.workspace.\(workshop.id)")
                        }
                        if !selectedID.isEmpty && !availableWorkshops.contains(where: { $0.id == selectedID }) {
                            Label("当前工坊", systemImage: "person.2.crop.square.stack")
                                .tag(selectedID)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if isInitialLoad {
                        ForEach(0..<3) { _ in
                            WorkspaceWorkshopLabel(name: "工坊名称", detail: "工坊创建者")
                                .redacted(reason: .placeholder)
                                .accessibilityHidden(true)
                        }
                    }
                }
                if accounts.user == nil {
                    Section("我的工坊") {
                        Text("登录后切换到你创建或加入的工坊。").foregroundStyle(.secondary)
                        Button("登录云乐坊") { showLogin = true }
                    }
                } else if workshops.error != nil || (workshops.hasLoaded && availableWorkshops.isEmpty) {
                    Section("我的工坊") {
                        WorkshopLoadStatus(isLoading: false, error: workshops.error) { await workshops.refresh() }
                        if workshops.hasLoaded && workshops.error == nil && workshops.switchableWorkshops.isEmpty {
                            Text("还没有可切换的工坊").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink { MyWorkshopsView() } label: { Label("管理与加入工坊", systemImage: "person.2.badge.gearshape") }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("切换云居").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WorkshopLoadingToolbarItem(placement: .navigationBarLeading,
                    isLoading: workshops.isLoading && !isRefreshing)
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await workshops.loadIfNeeded() }
            .refreshable {
                isRefreshing = true
                defer { isRefreshing = false }
                await workshops.refresh()
            }
            .onChange(of: selectedID) { _ in dismiss() }
            .sheet(isPresented: $showLogin) { LoginView(continuationMessage: "登录后可在云居切换工坊。") }
        }
    }
}

private struct WorkspaceWorkshopLabel: View {
    let name: String
    let detail: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "person.2.crop.square.stack")
        }
    }
}

struct HomeWorkshopView: View {
    let workshop: PersonalWorkshop
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: WorkshopPageStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRefreshing = false
    private let iconPipeline: ApplicationImagePipeline

    init(workshop: PersonalWorkshop, accounts: AccountStore, service: WorkshopServing = WorkshopService(),
         iconPipeline: ApplicationImagePipeline = .shared) {
        self.workshop = workshop; self.accounts = accounts
        self.iconPipeline = iconPipeline
        _model = StateObject(wrappedValue: WorkshopPageStore(id: workshop.id, accounts: accounts, service: service))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                List { content }
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            status
                            if let page = visiblePage {
                                heading(page)
                                let metrics = HomeGridMetrics(width: proxy.size.width - 32, sizeClass: sizeClass)
                                LazyVGrid(columns: metrics.gridItems, spacing: HomeGridMetrics.rowSpacing) {
                                    ForEach(page.apps) { app in
                                        applicationButton(app, labelWidth: metrics.labelWidth)
                                    }
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .loadingOverlay(isLoading && !isRefreshing, label: "正在载入工坊应用")
        .navigationTitle("云居")
        .task(id: accounts.identityGeneration) { await model.refresh() }
        .onChange(of: scenePhase) { if $0 == .active { Task { await model.refresh() } } }
        .refreshable {
            isRefreshing = true
            defer { isRefreshing = false }
            await model.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { PublicWorkshopView(id: workshop.id) } label: { Label("工坊信息", systemImage: "info.circle") }
            }
        }
    }

    // Fail closed while refreshing or after a failed check; a previous payload
    // must not keep private icons visible after membership may have changed.
    private var visiblePage: WorkshopPage? {
        guard workshop.status == .active, !model.isLoading, model.error == nil, let page = model.page, page.permitsApps else { return nil }
        return page
    }

    private var isLoading: Bool { model.isLoading || (model.page == nil && model.error == nil) }

    @ViewBuilder private var content: some View {
        status
        if let page = visiblePage {
            Section { heading(page) }
            Section("工坊应用") {
                ForEach(page.apps) { app in applicationButton(app, labelWidth: 0) }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if isLoading {
            EmptyView()
        } else if let error = model.error {
            ContentStateView(title: "暂时无法载入工坊", systemImage: "wifi.exclamationmark", message: error,
                             actionTitle: "重试") { Task { await model.refresh() } }
        } else if workshop.status == .disabled {
            ContentStateView(title: "工坊已暂停", systemImage: "lock", message: "可在工坊信息中查看当前状态，或切换到其他工坊。")
        } else if let page = model.page, !page.permitsApps {
            ContentStateView(title: page.workshop.status == .disabled ? "工坊已暂停" : "暂不能访问这个工坊",
                systemImage: "lock", message: "可在工坊信息中查看当前状态，或切换到其他工坊。")
        } else if visiblePage?.apps.isEmpty == true {
            ContentStateView(title: "工坊里还没有应用", systemImage: "square.grid.2x2", message: "坊主发布应用后会显示在这里。")
        }
    }

    private func heading(_ page: WorkshopPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dynamicTypeSize.isAccessibilitySize ? page.workshop.name : "工坊应用")
                .font(.headline).accessibilityAddTraits(.isHeader)
            Label("仅工坊成员可见 · \(page.apps.count) 个应用", systemImage: "person.2")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func applicationButton(_ app: CloudApplication, labelWidth: CGFloat) -> some View {
        Button { runtime.open(app, catalog: catalog, library: library) } label: {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    ApplicationIcon(application: app, pipeline: iconPipeline)
                    Text(app.name).font(.headline).foregroundStyle(.primary)
                    if let host = app.launchURL?.host { Text(host).font(.footnote).foregroundStyle(.secondary) }
                    if let restriction = app.workshopLaunchRestriction { Text(restriction).font(.footnote).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HomeAppGlyph(name: app.name, labelWidth: labelWidth) {
                    ApplicationIcon(application: app, size: HomeGridMetrics.iconSize, pipeline: iconPipeline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开\(app.name)")
        .accessibilityHint(app.launchURL?.host ?? "")
        .accessibilityIdentifier("home.workshop.application.\(app.id)")
        .contextMenu { NavigationLink(value: app) { Label("应用详情", systemImage: "info.circle") } }
    }
}
