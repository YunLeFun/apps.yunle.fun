import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var sync: HomeSyncCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("home.showRecent") private var showRecent = true
    @ScaledMetric private var gridWidth = 88
    @State private var editing = false
    @State private var showScanner = false
    let browse: () -> Void

    var body: some View {
        Group {
            if let issue = library.storageError {
                ScrollView {
                    ContentStateView(title: "云居需要一点帮助", systemImage: "externaldrive.badge.exclamationmark", message: issue,
                                     actionTitle: "重试") {
                        library.activateAccount(library.accountID)
                        library.updateCatalog(catalog.applications)
                        sync.identityChanged()
                    }
                }
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
                                    Button { library.setPinned(app, false) } label: {
                                        Label("取消常用", systemImage: "pin.slash")
                                    }
                                }
                            }
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
            } else if library.snapshot.applications.isEmpty && library.snapshot.dockApplications.isEmpty && runtime.applications.isEmpty {
                ScrollView {
                    ContentStateView(title: "把喜欢的应用带回云居", systemImage: "square.grid.2x2",
                                     message: "从工坊添加应用，下次打开更顺手。", actionTitle: "去工坊看看", action: browse)
                }
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    List { homeSections }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) { homeSections }
                            .padding()
                    }
                }
            }
        }
        .refreshable { await sync.recheck() }
        .navigationTitle("云居")
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .general) }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink { AssistantView() } label: { Label("AI 助手", systemImage: "sparkles").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("home.assistant")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: browse) { Label("添加应用", systemImage: "plus").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("home.add")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if editing {
                    Button("完成") { editing = false }
                } else if dynamicTypeSize.isAccessibilitySize {
                    NavigationLink { HomeOptionsView(editing: $editing) } label: {
                        Label("云居选项", systemImage: "ellipsis").labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("home.options")
                } else {
                    Menu {
                        Button { showScanner = true } label: { Label("扫一扫", systemImage: "qrcode.viewfinder") }
                            .accessibilityIdentifier("home.scan")
                        if !library.snapshot.applications.isEmpty {
                            Button { editing = true } label: { Label("编辑云居", systemImage: "square.and.pencil") }
                        }
                        if accounts.user != nil {
                            NavigationLink { HomeSyncSettingsView() } label: {
                                Label(sync.message, systemImage: "icloud")
                            }
                        }
                        if !runtime.applications.isEmpty {
                            NavigationLink { RunningApplicationsView() } label: {
                                Label("正在运行（\(runtime.applications.count)）", systemImage: "square.stack")
                            }
                        }
                    } label: { Label("云居选项", systemImage: "ellipsis").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("home.options")
                }
            }
        }
    }

    private func current(_ app: CloudApplication) -> CloudApplication {
        app.refreshingPublicMetadata(with: catalog.application(id: app.id))
    }

    @ViewBuilder private var homeSections: some View {
        if accounts.user != nil {
            switch sync.phase {
            case .failed, .conflict:
                NavigationLink { HomeSyncSettingsView() } label: {
                    Label(sync.message, systemImage: "exclamationmark.icloud")
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
            default: EmptyView()
            }
        }
        if showRecent && library.snapshot.applications.count > 4 {
            let recent = Array(library.snapshot.recentApplications.prefix(4)).map(current)
            if !recent.isEmpty { section("最近使用", applications: recent) }
        }
        if library.snapshot.dockVisible && !library.snapshot.dockApplications.isEmpty {
            section("常用应用", applications: library.snapshot.dockApplications.map(current))
        }
        let main = library.snapshot.dockVisible ? library.snapshot.applications.filter { !library.isPinned($0) }
            : library.snapshot.applications + library.snapshot.dockApplications.filter { dock in
                !library.snapshot.applications.contains { $0.homeKey == dock.homeKey }
            }
        if !main.isEmpty { section("我的应用", applications: main.map(current)) }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: gridWidth), spacing: 16)], spacing: 24) {
                    ForEach(applications, id: \.homeKey) { app in applicationButton(app) }
                }
            }
        }
    }

    private func applicationButton(_ app: CloudApplication) -> some View {
        Button { runtime.open(app, catalog: catalog, library: library) } label: {
            if dynamicTypeSize.isAccessibilitySize {
                ApplicationRow(application: app).foregroundStyle(.primary)
            } else {
                VStack(spacing: 8) {
                    ApplicationIcon(application: app, size: 60)
                    Text(app.name).font(.footnote).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .top)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开\(app.name)")
        .accessibilityValue(app.accessLabel ?? "")
        .contextMenu {
            NavigationLink(value: app) { Label("应用详情", systemImage: "info.circle") }
            if library.contains(app) {
                Button { library.setPinned(app, !library.isPinned(app)) } label: {
                    Label(library.isPinned(app) ? "取消常用" : "设为常用", systemImage: library.isPinned(app) ? "pin.slash" : "pin")
                }
                .disabled(!library.isPinned(app) && library.snapshot.configuration.dockApps.count >= 4)
                Button(role: .destructive) { library.remove(app) } label: { Label("从云居移除", systemImage: "minus.circle") }
            }
            if runtime.contains(app) {
                Button(role: .destructive) { runtime.end(app) } label: { Label("结束运行", systemImage: "xmark.circle") }
            }
        }
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
            if accounts.user != nil {
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
            ForEach(runtime.applications) { app in
                Button { runtime.open(app, catalog: catalog, library: library) } label: {
                    ApplicationRow(application: app).foregroundStyle(.primary)
                }
                .swipeActions {
                    Button("结束", role: .destructive) { runtime.end(app) }
                }
            }
        }
        .navigationTitle("正在运行")
    }
}
