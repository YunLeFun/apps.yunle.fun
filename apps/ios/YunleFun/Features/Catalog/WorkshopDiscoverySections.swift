import SwiftUI

struct WorkshopDiscoverySections: View {
    let applications: [CloudApplication]
    let payload: WorkshopDiscoveryPayload?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let selection = payload?.selection(from: applications)
        let eligible = WorkshopDiscoveryPayload.publicApplications(applications)
        let official = eligible.filter { $0.isOfficial == true }
        let featured = selection?.featured.first
        if let featured {
            Section {
                featuredLink(featured)
            } header: { Text("编辑精选").foregroundStyle(Color.primary) }
        }
        let fallback = featured == nil ? official.first : nil
        let otherOfficial = official.filter { $0.id != (featured?.id ?? fallback?.id) }
        if fallback != nil || !otherOfficial.isEmpty {
            Section {
                if let fallback {
                    featuredLink(.init(application: fallback, title: nil, subtitle: nil))
                }
                ForEach(otherOfficial.prefix(5)) { app in
                    NavigationLink(value: app) { ApplicationRow(application: app) }
                        .accessibilityIdentifier("catalog.official.\(app.id)")
                }
            } header: { Text("云乐坊出品").foregroundStyle(Color.primary) }
        }
        if let weekly = selection?.weekly, !weekly.isEmpty {
            Section {
                ForEach(weekly) { entry in
                    NavigationLink(value: entry.application) {
                        HStack(spacing: 12) {
                            Text("\(entry.rank)").font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary).frame(minWidth: 24)
                                .accessibilityLabel("第 \(entry.rank) 名")
                            ApplicationRow(application: entry.application)
                        }
                    }
                    .accessibilityIdentifier("catalog.weekly.\(entry.application.id)")
                }
            } header: { Text("本周热门").foregroundStyle(Color.primary) }
        }
        let discoveries = eligible.filter { $0.isOfficial != true && $0.id != featured?.id }
        if !discoveries.isEmpty {
            Section {
                ForEach(discoveries.prefix(8)) { app in
                    NavigationLink(value: app) { ApplicationRow(application: app) }
                        .accessibilityIdentifier("catalog.discover.\(app.id)")
                }
            } header: { Text("随手发现").foregroundStyle(Color.primary) }
        }
    }

    private func featuredLink(_ item: WorkshopDiscoverySelection.Featured) -> some View {
        NavigationLink(value: item.application) {
            featuredContent(item)
        }
        .accessibilityIdentifier("catalog.featured")
    }

    private func featuredContent(_ item: WorkshopDiscoverySelection.Featured) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                ApplicationIcon(application: item.application, size: 56)
                featuredText(item)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ApplicationIcon(application: item.application, size: 64)
                    featuredText(item)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featuredText(_ item: WorkshopDiscoverySelection.Featured) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title ?? item.application.name).font(.headline).foregroundStyle(Color.primary)
            if let title = item.title, title != item.application.name {
                Text(item.application.name).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(item.subtitle ?? item.application.summary).font(.subheadline).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
