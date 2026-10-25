import Combine
import Foundation

/// One native workspace owns the visible WebKit page. Account transitions revoke
/// its authorization before publishing the new identity; only an accepted guest
/// login can continue the same page after persisting its new profile owner.
@MainActor
final class MacWorkspace: ObservableObject {
    let catalog: CatalogStore
    let accounts: AccountStore
    let runtime: MacWebRuntime
    @Published var selection = "all"
    @Published var showingApplication = false
    @Published private(set) var isStarting = true
    @Published var notice: String?
    private var started = false

    init() {
        let profiles = WebProfileRepository(
            fileURL: MacStorage.supportDirectory.appendingPathComponent("web-profiles.json"),
            namespace: MacStorage.namespace + ":" + CloudbaseAuthService.gateway.absoluteString
        )
        let runtime = MacWebRuntime(webProfiles: profiles)
        self.runtime = runtime
        catalog = CatalogStore(cacheURL: MacStorage.catalogCache)
        accounts = AccountStore(
            accountWillRemove: { try profiles.retire($0) },
            identityDidChange: { [weak runtime] uid in runtime?.accountDidChange(uid) }
        )
        runtime.configureAuthorization(accounts: accounts)
    }

    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        // Hosted unit tests own synthetic services and unique Keychain items.
        // Do not restore a developer's real account in the background.
        if MacStorage.namespace == "fun.yunle.macos.tests-host"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            isStarting = false
            return
        }
        #endif
        // A saved account must be selected before any guest page is created.
        async let identity: Void = accounts.restore()
        async let directory: Void = catalog.load()
        _ = await (identity, directory)
        isStarting = false
    }

    func refreshCatalog() async {
        await catalog.refreshWithIcons()
        guard !catalog.isCached, catalog.error == nil else { return }
        if let active = runtime.application {
            guard let current = catalog.applications.first(where: { $0.id == active.id }),
                  current.launchURL == active.launchURL,
                  MacWebNavigationPolicy.launchURL(for: current) != nil else {
                runtime.terminate()
                showingApplication = false
                notice = "此应用的访问条件或地址已变化，已结束原会话。"
                return
            }
            runtime.updateApplication(current)
        }
        if selection != "all", !catalog.categories.contains(selection) { selection = "all" }
    }

    func open(_ application: CloudApplication) {
        // Always resolve back to this launch's verified public catalog. A cache
        // is useful for browsing, never proof that an app is still available.
        guard !isStarting, !accounts.isRestoring, !catalog.isLoading,
              !catalog.isCached, catalog.error == nil,
              let current = catalog.applications.first(where: { $0.id == application.id }),
              MacWebNavigationPolicy.launchURL(for: current) != nil else {
            notice = "请刷新目录后再打开公开免费应用。"
            return
        }
        guard runtime.open(current) else {
            notice = runtime.error ?? "暂时无法打开此应用，请稍后重试。"
            return
        }
        showingApplication = true
    }

    func showCatalog() {
        showingApplication = false
        runtime.close()
    }
}
