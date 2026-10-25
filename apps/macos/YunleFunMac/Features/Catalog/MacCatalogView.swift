import SwiftUI

struct MacCatalogView: View {
    @ObservedObject var catalog: CatalogStore
    let category: String
    let query: String
    let canLaunch: Bool
    let open: (CloudApplication) -> Void
    let refresh: () async -> Void

    private var applications: [CloudApplication] {
        catalog.applications.filter { (category == "all" || $0.browseCategory == category) && $0.matches(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category == "all" ? "发现一点新乐趣" : category)
                        .font(.largeTitle.bold())
                    Text("实用工具、创意作品和小游戏，都在云乐坊。")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if let error = catalog.error {
                    HStack {
                        Label(error, systemImage: "wifi.exclamationmark")
                        Spacer()
                        Button("重试") { Task { await refresh() } }
                    }
                    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                if catalog.isCached {
                    Text("正在展示上次保存的目录，联网刷新后即可打开应用。")
                        .font(.callout).foregroundStyle(.secondary)
                }

                if applications.isEmpty {
                    if catalog.isLoading {
                        ProgressView("正在读取应用目录…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ContentUnavailableView(query.isEmpty ? "暂无应用" : "没有找到相关应用",
                                               systemImage: query.isEmpty ? "square.grid.2x2" : "magnifyingglass",
                                               description: Text(query.isEmpty ? "刷新目录后再来看看。" : "试试其他关键词或分类。"))
                            .frame(minHeight: 240)
                    }
                } else {
                    HStack {
                        Text(query.isEmpty ? "\(applications.count) 个应用" : "\(applications.count) 个搜索结果")
                            .font(.headline)
                        Spacer()
                        if catalog.isLoading { ProgressView().controlSize(.small) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 480), spacing: 18)], spacing: 18) {
                        ForEach(applications) { application in
                            MacApplicationCard(application: application,
                                               canLaunch: canLaunch && !catalog.isCached && catalog.error == nil && !catalog.isLoading,
                                               open: { open(application) })
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("catalog.content")
    }
}

private struct MacApplicationCard: View {
    let application: CloudApplication
    let canLaunch: Bool
    let open: () -> Void

    private var isAvailable: Bool { MacWebNavigationPolicy.launchURL(for: application) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MacApplicationIcon(application: application)
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.name).font(.headline).lineLimit(1)
                    Text(application.browseCategory).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(application.summary).font(.callout).foregroundStyle(.secondary)
                .lineLimit(2).frame(height: 38, alignment: .topLeading)
            HStack {
                Text(application.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button(isAvailable ? "打开" : application.accessLabel ?? "暂不可用", action: open)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!canLaunch || !isAvailable)
                    .accessibilityLabel("打开\(application.name)")
                    .accessibilityIdentifier("catalog.open.\(application.id)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))
    }
}

private struct MacApplicationIcon: View {
    let application: CloudApplication
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        CatalogApplicationIconImage(application: application,
                             pixelSize: Int((48 * displayScale).rounded(.up))) {
            Text(application.emoji?.nilIfEmpty ?? String(application.name.prefix(1)))
                .font(.system(size: 28))
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 48 * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
