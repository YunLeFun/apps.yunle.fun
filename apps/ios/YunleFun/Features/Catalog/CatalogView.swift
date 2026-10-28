import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var category = "全部"
    @State private var showScanner = false
    @State private var isRefreshing = false
    @State private var returningShortcut: Shortcut?
    @AccessibilityFocusState(for: .voiceOver) private var focusedShortcut: Shortcut?
    private enum Shortcut: Hashable { case applications, workshops, lookup }

    private var filtered: [CloudApplication] {
        catalog.applications.filter { (category == "全部" || $0.browseCategory == category) && $0.matches(query) }
    }

    var body: some View {
        content
        .loadingOverlay(catalog.isLoading && catalog.applications.isEmpty && !isRefreshing, label: "正在载入工坊")
        .navigationTitle("工坊")
        .onAppear {
            if let returningShortcut { focusedShortcut = returningShortcut; self.returningShortcut = nil }
        }
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .workshop) }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(dynamicTypeSize.isAccessibilitySize ? "搜索应用" : "搜索应用、用途或作者"))
        .refreshable {
            isRefreshing = true
            defer { isRefreshing = false }
            await catalog.refreshWithIcons()
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: category)
        .haptic(.selection, trigger: category)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showScanner = true } label: { Label("扫描工坊二维码", systemImage: "qrcode.viewfinder") }
                    .accessibilityIdentifier("catalog.scan")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("分类", selection: $category) {
                        ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    // A filled glyph tells people a filter is hiding part of the catalog.
                    Label("分类", systemImage: category == "全部" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityValue(category)
            }
        }
    }

    private var content: some View {
        List {
            Section {
                shortcut("我的应用", systemImage: "square.and.pencil", entry: .applications) { MyApplicationsView() }
                shortcut("个人工坊", systemImage: "person.2", entry: .workshops) { MyWorkshopsView() }
                shortcut("打开个人工坊", systemImage: "number", entry: .lookup) { WorkshopLookupView() }
            }
            CatalogStatusView()
            if catalog.isLoading && catalog.applications.isEmpty {
                EmptyView()
            } else if let error = catalog.error, catalog.applications.isEmpty {
                ContentStateView(title: "暂时无法连接工坊", systemImage: "wifi.exclamationmark", message: error,
                                 actionTitle: "重试", action: { Task { await catalog.refreshWithIcons() } })
            } else if filtered.isEmpty {
                ContentStateView(title: query.isEmpty ? "还没有应用" : "没有找到相关应用", systemImage: "magnifyingglass",
                                 message: query.isEmpty ? "稍后再来看看。" : "试试其他关键词或分类。",
                                 actionTitle: category == "全部" ? nil : "显示全部分类",
                                 action: category == "全部" ? nil : { category = "全部" })
            } else {
                Section {
                    ForEach(filtered) { app in
                        NavigationLink(value: app) { ApplicationRow(application: app) }
                            .accessibilityIdentifier("catalog.application.\(app.id)")
                    }
                } header: {
                    HStack {
                        Text(category == "全部" ? "全部应用 · \(filtered.count)" : "\(category) · \(filtered.count)")
                            .foregroundStyle(Color.primary)
                            .numericTransition(Double(filtered.count))
                        Spacer()
                        if category != "全部" {
                            Button("显示全部") { category = "全部" }
                                .font(.subheadline)
                                .textCase(nil)
                                .accessibilityIdentifier("catalog.filter.clear")
                        }
                    }
                }
            }
        }
    }

    private func shortcut<Destination: View>(_ title: String, systemImage: String, entry: Shortcut,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination().onAppear { returningShortcut = entry; focusedShortcut = nil } } label: {
            shortcutLabel(title, systemImage: systemImage)
        }
        .accessibilityFocused($focusedShortcut, equals: entry)
    }

    @ViewBuilder private func shortcutLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text(title).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage).font(.body).accessibilityHidden(true)
            }
        }
    }
}
