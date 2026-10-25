import SwiftUI

struct MacRootView: View {
    @ObservedObject var workspace: MacWorkspace
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var accounts: AccountStore
    @ObservedObject var runtime: MacWebRuntime
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $workspace.selection) {
                Section("发现") {
                    Label("全部应用", systemImage: "square.grid.2x2").tag("all")
                }
                Section("分类") {
                    ForEach(catalog.categories.filter { $0 != "全部" }, id: \.self) { category in
                        Label(category, systemImage: categorySymbol(category)).tag(category)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    if let application = runtime.application {
                        Button {
                            workspace.open(application)
                        } label: {
                            Label(application.name, systemImage: "play.circle")
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("继续使用当前应用")
                        .accessibilityIdentifier("workspace.resume")
                    }
                    SettingsLink {
                        Label(accounts.user?.displayName ?? "登录云乐坊", systemImage: "person.crop.circle")
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workspace.account")
                }
                .padding()
            }
        } detail: {
            Group {
                if workspace.showingApplication, runtime.application != nil {
                    MacRuntimePane(runtime: runtime, showCatalog: workspace.showCatalog)
                } else {
                    MacCatalogView(catalog: catalog, category: workspace.selection, query: query,
                                   canLaunch: !workspace.isStarting && !accounts.isRestoring,
                                   open: workspace.open, refresh: workspace.refreshCatalog)
                }
            }
            .navigationTitle(workspace.showingApplication ? runtime.application?.name ?? "云乐坊" : "应用目录")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !workspace.showingApplication {
                        Button { Task { await workspace.refreshCatalog() } } label: {
                            Label("刷新目录", systemImage: "arrow.clockwise")
                        }
                        .disabled(catalog.isLoading)
                        .accessibilityIdentifier("catalog.refresh")
                    }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "搜索应用、分类或开发者")
        .onChange(of: workspace.selection) { _, _ in workspace.showCatalog() }
        .onChange(of: query) { _, _ in if !query.isEmpty { workspace.showCatalog() } }
        .onChange(of: accounts.identityGeneration) { _, _ in
            // The broker may preserve exactly the guest page whose own login
            // just completed, after durably transferring its profile ownership.
            if runtime.application == nil { workspace.showingApplication = false }
        }
        .alert("云乐坊", isPresented: Binding(get: { workspace.notice != nil }, set: { if !$0 { workspace.notice = nil } })) {
            Button("好", role: .cancel) { workspace.notice = nil }
        } message: { Text(workspace.notice ?? "") }
    }

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "效率工具": return "checklist"
        case "创意设计": return "paintpalette"
        case "生活方式": return "leaf"
        case "游戏": return "gamecontroller"
        case "开发": return "hammer"
        case "AI": return "sparkles"
        case "趣味娱乐": return "face.smiling"
        default: return "square.grid.2x2"
        }
    }
}

private struct MacRuntimePane: View {
    @ObservedObject var runtime: MacWebRuntime
    let showCatalog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: showCatalog) { Label("应用目录", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("runtime.catalog")
                Divider().frame(height: 18)
                Button(action: runtime.back) { Image(systemName: "chevron.left") }
                    .disabled(!runtime.canGoBack).help("后退").accessibilityLabel("后退")
                Button(action: runtime.forward) { Image(systemName: "chevron.right") }
                    .disabled(!runtime.canGoForward).help("前进").accessibilityLabel("前进")
                Button(action: runtime.reload) { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r").help("重新载入").accessibilityLabel("重新载入")
                if runtime.isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Text(runtime.currentURL?.host ?? runtime.application?.launchURL?.host ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button {
                    runtime.terminate()
                    showCatalog()
                } label: { Image(systemName: "xmark") }
                    .help("结束应用").accessibilityLabel("结束应用")
            }
            .buttonStyle(.borderless).padding(12)
            Divider()
            if let error = runtime.error {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("重试", action: runtime.reload)
                }
                .font(.callout).padding(12).background(.quaternary)
            }
            MacWebContentView(runtime: runtime)
        }
    }
}
