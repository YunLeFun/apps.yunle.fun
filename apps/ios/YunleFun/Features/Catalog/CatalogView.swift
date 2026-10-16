import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @State private var query = ""
    @State private var category = "全部"
    @State private var showScanner = false

    private var filtered: [CloudApplication] {
        catalog.applications.filter { (category == "全部" || $0.browseCategory == category) && $0.matches(query) }
    }

    var body: some View {
        List {
            Section {
                NavigationLink { MyApplicationsView() } label: { Label("我的应用", systemImage: "square.and.pencil") }
                NavigationLink { MyWorkshopsView() } label: { Label("个人工坊", systemImage: "person.2") }
                NavigationLink { WorkshopLookupView() } label: { Label("打开个人工坊", systemImage: "number") }
            }
            CatalogStatusView()
            if catalog.isLoading && catalog.applications.isEmpty {
                ProgressView("正在载入工坊").frame(maxWidth: .infinity).padding()
            } else if let error = catalog.error, catalog.applications.isEmpty {
                ContentStateView(title: "暂时无法连接工坊", systemImage: "wifi.exclamationmark", message: error,
                                 actionTitle: "重试", action: { Task { await catalog.load() } })
            } else if filtered.isEmpty {
                ContentStateView(title: query.isEmpty ? "还没有应用" : "没有找到相关应用", systemImage: "magnifyingglass",
                                 message: query.isEmpty ? "稍后再来看看。" : "试试其他关键词或分类。")
            } else {
                Section {
                    ForEach(filtered) { app in
                        NavigationLink(value: app) { ApplicationRow(application: app) }
                    }
                } header: {
                    Text(category == "全部" ? "全部应用 · \(filtered.count)" : "\(category) · \(filtered.count)")
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .navigationTitle("工坊")
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .workshop) }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索应用、用途或作者")
        .refreshable { await catalog.load() }
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
                } label: { Label("分类", systemImage: "line.3.horizontal.decrease") }
            }
        }
    }
}
