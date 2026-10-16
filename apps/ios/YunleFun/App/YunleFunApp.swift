import SwiftUI

@main
struct YunleFunApp: App {
    @StateObject private var catalog: CatalogStore
    @StateObject private var library: HomeLibrary
    @StateObject private var runtime: NativeWebRuntime
    @StateObject private var accounts: AccountStore
    @StateObject private var homeSync: HomeSyncCoordinator
    @StateObject private var wallet: WalletStore
    @StateObject private var purchases: PurchaseCoordinator
    @StateObject private var assistant: AssistantStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppAppearance.system

    init() {
        let catalog = CatalogStore()
        let library = HomeLibrary()
        let runtime = NativeWebRuntime()
        _library = StateObject(wrappedValue: library)
        _runtime = StateObject(wrappedValue: runtime)
        let accounts = AccountStore { id in
            runtime.resetIdentity(to: id)
            library.activateAccount(id)
            library.updateCatalog(catalog.applications)
        }
        _catalog = StateObject(wrappedValue: catalog)
        _accounts = StateObject(wrappedValue: accounts)
        runtime.configureAuthorization(accounts: accounts)
        _homeSync = StateObject(wrappedValue: HomeSyncCoordinator(accounts: accounts, library: library))
        let wallet = WalletStore(accounts: accounts)
        _wallet = StateObject(wrappedValue: wallet)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet)
        _purchases = StateObject(wrappedValue: purchases)
        runtime.configureCommerce(wallet: wallet, purchases: purchases)
        _assistant = StateObject(wrappedValue: AssistantStore(accounts: accounts))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(runtime)
                .environmentObject(accounts)
                .environmentObject(homeSync)
                .environmentObject(wallet)
                .environmentObject(purchases)
                .environmentObject(assistant)
                .preferredColorScheme(appearance.colorScheme)
                .task { await catalog.load() }
                .task { await accounts.restore() }
                .task { homeSync.identityChanged() }
                .task { await purchases.start() }
                .onChange(of: accounts.overview.activeID) { _ in homeSync.identityChanged() }
                .onChange(of: accounts.identityGeneration) { _ in
                    wallet.identityChanged(); purchases.identityChanged()
                    assistant.identityChanged()
                    Task { await purchases.processUnfinished() }
                }
                .onChange(of: catalog.applications) { library.updateCatalog($0) }
                .onChange(of: scenePhase) { if $0 == .active { homeSync.schedule() } }
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var label: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum AppTab: Hashable { case home, discovery, workshop, me }
