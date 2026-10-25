import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var featuredZoom
    @State private var returningApplicationID: String?
    @AccessibilityFocusState(for: .voiceOver) private var focusedApplicationID: String?
    private var official: [CloudApplication] { catalog.applications.filter { $0.isOfficial == true } }

    var body: some View {
        List {
            CatalogStatusView()
            if let featured = official.first {
                Section {
                    applicationLink(featured, zoom: true) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("discovery.featured")
                } header: { Text("发现一点小乐趣").foregroundStyle(Color.primary) }
            }
            if !official.isEmpty {
                Section {
                    ForEach(official.dropFirst().prefix(5)) { app in
                        applicationLink(app) { ApplicationRow(application: app) }
                            .accessibilityIdentifier("discovery.application.\(app.id)")
                    }
                } header: { Text("官方出品").foregroundStyle(Color.primary) }
            }
            if !catalog.applications.isEmpty {
                Section {
                    ForEach(catalog.applications.filter { $0.isOfficial != true }.prefix(8)) { app in
                        applicationLink(app) { ApplicationRow(application: app) }
                            .accessibilityIdentifier("discovery.application.\(app.id)")
                    }
                } header: { Text("随手发现").foregroundStyle(Color.primary) }
            } else if catalog.isLoading {
                ProgressView("正在寻找小乐趣").frame(maxWidth: .infinity).padding()
            } else {
                ContentStateView(title: "稍后再来看看", systemImage: "safari",
                                 message: catalog.error ?? "工坊里的新鲜应用会出现在这里。",
                                 actionTitle: "刷新", action: { Task { await catalog.refreshWithIcons() } })
            }
        }
        .navigationTitle("寻乐")
        .onAppear {
            if let returningApplicationID {
                focusedApplicationID = returningApplicationID
                self.returningApplicationID = nil
            }
        }
        .refreshable { await catalog.refreshWithIcons() }
    }

    /// The featured card zooms into its detail like an App Store story; list
    /// rows keep the standard push that matches every other list in the app.
    private func applicationLink<Content: View>(_ application: CloudApplication, zoom: Bool = false,
                                                @ViewBuilder label: @escaping () -> Content) -> some View {
        NavigationLink {
            ApplicationDetailView(application: application)
                .onAppear { returningApplicationID = application.id; focusedApplicationID = nil }
                .modifier(OptionalZoom(enabled: zoom, id: application.id, namespace: featuredZoom, isDestination: true,
                                       reduceMotion: reduceMotion))
        } label: {
            label().modifier(OptionalZoom(enabled: zoom, id: application.id, namespace: featuredZoom, isDestination: false,
                                          reduceMotion: reduceMotion))
        }
        .accessibilityFocused($focusedApplicationID, equals: application.id)
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

private struct OptionalZoom: ViewModifier {
    let enabled: Bool
    let id: String
    let namespace: Namespace.ID
    let isDestination: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if !enabled { content }
        else if isDestination { content.zoomDestination(id: id, in: namespace, reduceMotion: reduceMotion) }
        else { content.zoomSource(id: id, in: namespace) }
    }
}
