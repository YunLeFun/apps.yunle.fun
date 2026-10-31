import SwiftUI

struct NativeApplicationMenuView: View {
    let application: CloudApplication
    let currentURL: URL?
    let hasMarketEntry: Bool
    let isGame: Bool
    let perform: (WebAppMenuAction) -> Void
    @EnvironmentObject private var runtime: NativeWebRuntime
    @Environment(\.dismiss) private var dismiss

    init(application: CloudApplication, currentURL: URL?, hasMarketEntry: Bool = true, isGame: Bool = false,
         perform: @escaping (WebAppMenuAction) -> Void) {
        self.application = application; self.currentURL = currentURL
        self.hasMarketEntry = hasMarketEntry; self.isGame = isGame; self.perform = perform
    }

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
                    if hasMarketEntry {
                        NavigationLink {
                            ApplicationDetailView(application: application)
                        } label: { Label("应用详情", systemImage: "info.circle") }
                        if application.accessWorkshopID == nil && application.accessOwnerID == nil && application.personalMarketOwnerLogin == nil {
                            NavigationLink {
                                ApplicationReviewsView(application: application)
                            } label: { Label("评分与评价", systemImage: "star.bubble") }
                        }
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
                    if !isGame {
                        NavigationLink {
                            ApplicationCacheView(application: application, store: runtime.applicationCache)
                        } label: { Label("应用下载缓存", systemImage: "arrow.down.circle") }
                        .accessibilityIdentifier("runtime.menu.cache")
                        ApplicationCacheUpdateNotice(application: application, store: runtime.applicationCache)
                    }
                }
                if isGame {
                    Section {
                        Toggle("页面回弹", isOn: gameInteractionBinding(\.allowsPageBounce))
                            .accessibilityIdentifier("runtime.menu.game-page-bounce")
                        Toggle("长按选中与预览", isOn: gameInteractionBinding(\.allowsLongPress))
                            .accessibilityIdentifier("runtime.menu.game-long-press")
                    } header: { Text("游戏网页交互") }
                    footer: { Text("默认关闭以减少游戏操作干扰。长按开关包含文字选中、链接预览和图片拖动。设置对当前游戏立即生效并自动保存，输入框仍可编辑。") }
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

    private func gameInteractionBinding(_ keyPath: WritableKeyPath<WebGameInteractionSettings, Bool>) -> Binding<Bool> {
        Binding(get: { runtime.gameInteractionSettings(for: application.id)[keyPath: keyPath] }, set: { value in
            var settings = runtime.gameInteractionSettings(for: application.id)
            settings[keyPath: keyPath] = value
            runtime.setGameInteractionSettings(settings, for: application.id)
        })
    }
}

private struct ApplicationCacheUpdateNotice: View {
    let application: CloudApplication
    @ObservedObject var store: ApplicationCacheStore

    var body: some View {
        let key = ApplicationCacheEntry.key(for: application)
        if store.updatesReady.contains(key) {
            Label("更新已就绪，下次重新打开生效", systemImage: "checkmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        } else if let revision = store.runningRevisions[key], revision != .distantPast || store.entry(for: application) != nil {
            ApplicationLaunchSourceLabel(revision: revision, staticResources: ApplicationStaticResourcePolicy.supports(application)).font(.footnote)
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
