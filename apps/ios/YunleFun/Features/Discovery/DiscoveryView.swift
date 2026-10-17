import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var official: [CloudApplication] { catalog.applications.filter { $0.isOfficial == true } }

    var body: some View {
        List {
            CatalogStatusView()
            if let featured = official.first {
                Section {
                    NavigationLink(value: featured) {
                        VStack(alignment: .leading, spacing: 20) {
                            officialLabel.foregroundStyle(Color.primary)
                            ApplicationIcon(application: featured, size: 76)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(featured.name).font(.title2.bold()).foregroundStyle(Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(featured.summary).font(.body).foregroundStyle(Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .accessibilityIdentifier("discovery.featured")
                } header: { Text("发现一点小乐趣").foregroundStyle(Color.primary) }
            }
            if !official.isEmpty {
                Section {
                    ForEach(official.dropFirst().prefix(5)) { app in
                        NavigationLink(value: app) { ApplicationRow(application: app) }
                            .accessibilityIdentifier("discovery.application.\(app.id)")
                    }
                } header: { Text("官方出品").foregroundStyle(Color.primary) }
            }
            if !catalog.applications.isEmpty {
                Section {
                    ForEach(catalog.applications.filter { $0.isOfficial != true }.prefix(8)) { app in
                        NavigationLink(value: app) { ApplicationRow(application: app) }
                            .accessibilityIdentifier("discovery.application.\(app.id)")
                    }
                } header: { Text("随手发现").foregroundStyle(Color.primary) }
            } else if catalog.isLoading {
                ProgressView("正在寻找小乐趣").frame(maxWidth: .infinity).padding()
            } else {
                ContentStateView(title: "稍后再来看看", systemImage: "safari",
                                 message: catalog.error ?? "工坊里的新鲜应用会出现在这里。",
                                 actionTitle: "刷新", action: { Task { await catalog.load() } })
            }
        }
        .navigationTitle("寻乐")
        .refreshable { await catalog.load() }
    }

    @ViewBuilder private var officialLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text("云乐坊出品").font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text("云乐坊出品").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkle").font(.subheadline).accessibilityHidden(true)
            }
        }
    }
}
