import SwiftUI

struct NativeApplicationMenuView: View {
    let application: CloudApplication
    let currentURL: URL?
    let perform: (WebAppMenuAction) -> Void
    @EnvironmentObject private var runtime: NativeWebRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        ApplicationIcon(application: application, size: 56)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(application.name).font(.headline)
                            Text(application.summary).font(.subheadline).foregroundStyle(.secondary)
                            if let origin = Self.originLabel(currentURL) {
                                Text(origin).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    NavigationLink {
                        ApplicationDetailView(application: application)
                    } label: { Label("应用详情", systemImage: "info.circle") }
                    if application.accessWorkshopID == nil && application.accessOwnerID == nil && application.personalMarketOwnerLogin == nil {
                        NavigationLink {
                            ApplicationReviewsView(application: application)
                        } label: { Label("评分与评价", systemImage: "star.bubble") }
                    }
                    if let login = (application.personalMarketOwnerLogin ?? application.ownerLogin)?.nilIfEmpty {
                        NavigationLink {
                            DeveloperApplicationsView(login: login)
                        } label: {
                            LabeledContent { Text(application.author) } label: { Label("作者", systemImage: "person.crop.circle") }
                        }
                        .accessibilityIdentifier("runtime.menu.author")
                    }
                }
                Section {
                    Button { perform(.share) } label: { Label("分享", systemImage: "square.and.arrow.up") }
                    Button { perform(.copyLink) } label: { Label("复制链接", systemImage: "link") }
                    Button { perform(.openBrowser) } label: { Label("在浏览器中打开", systemImage: "safari") }
                    Button { perform(.reload) } label: { Label("重新载入", systemImage: "arrow.clockwise") }
                    NavigationLink {
                        ApplicationCacheView(application: application, store: runtime.applicationCache)
                    } label: { Label("应用下载缓存", systemImage: "arrow.down.circle") }
                    .accessibilityIdentifier("runtime.menu.cache")
                    ApplicationCacheUpdateNotice(application: application, store: runtime.applicationCache)
                }
                Section {
                    Button(role: .destructive) { perform(.end) } label: { Label("结束", systemImage: "xmark.circle") }
                } footer: { Text("结束后会释放当前会话，再次打开将重新载入。") }
            }
            .navigationTitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .runtimeMenuToolbar()
        }
        .environment(\.runtimeMenu, RuntimeMenuContext(applicationID: application.id, runtimeScope: application.runtimeScope,
                                                       launchURL: application.launchURL, dismiss: { dismiss() }))
    }

    static func originLabel(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme; origin.host = host; origin.port = url.port
        return origin.string
    }
}

private struct ApplicationCacheUpdateNotice: View {
    let application: CloudApplication
    @ObservedObject var store: ApplicationCacheStore

    var body: some View {
        if store.updatesReady.contains(ApplicationCacheEntry.key(for: application)) {
            Label("更新已就绪，下次重新打开生效", systemImage: "checkmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct RuntimeMenuContext {
    let applicationID: String
    let runtimeScope: String
    let launchURL: URL?
    let dismiss: () -> Void

    init(applicationID: String, runtimeScope: String = "public", launchURL: URL?, dismiss: @escaping () -> Void) {
        self.applicationID = applicationID; self.runtimeScope = runtimeScope; self.launchURL = launchURL; self.dismiss = dismiss
    }

    func represents(_ application: CloudApplication) -> Bool {
        launchURL != nil && applicationID == application.id && runtimeScope == application.runtimeScope && launchURL == application.launchURL
    }
}

private struct RuntimeMenuKey: EnvironmentKey {
    static let defaultValue: RuntimeMenuContext? = nil
}

extension EnvironmentValues {
    var runtimeMenu: RuntimeMenuContext? {
        get { self[RuntimeMenuKey.self] }
        set { self[RuntimeMenuKey.self] = newValue }
    }
}

private struct RuntimeMenuToolbar: ViewModifier {
    @Environment(\.runtimeMenu) private var menu
    func body(content: Content) -> some View {
        content.toolbar {
            if let menu {
                ToolbarItem(placement: .confirmationAction) { Button("完成", action: menu.dismiss) }
            }
        }
    }
}

extension View {
    func runtimeMenuToolbar() -> some View { modifier(RuntimeMenuToolbar()) }
}
