import SwiftUI
import UIKit

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
    @StateObject private var assistantRollout = AssistantRolloutStore()
    @StateObject private var diagnostics: DiagnosticLogStore
    @StateObject private var games = NativeGameCatalogStore()
    @StateObject private var gameResources = NativeGameResourceCache()
    @StateObject private var gameHistory: NativeGameHistoryStore
    @StateObject private var gameRooms: NativeGameRoomStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppAppearance.system

    init() {
#if DEBUG && targetEnvironment(simulator)
        // Interaction tests verify visible state and usable controls, while
        // avoiding XCTest's lost animation-completion notification on iOS 27.
        if ProcessInfo.processInfo.environment["YUNLEFUN_UI_DISABLE_ANIMATIONS"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
#endif
        let catalog = CatalogStore()
        let library = HomeLibrary()
        let runtime = NativeWebRuntime()
        let gameHistory = NativeGameHistoryStore()
        let gameRooms = NativeGameRoomStore()
        gameHistory.activate(accountID: nil)
        gameRooms.activate(accountID: nil)
        _gameHistory = StateObject(wrappedValue: gameHistory)
        _gameRooms = StateObject(wrappedValue: gameRooms)
        runtime.onGameReady = { gameID, modeID, accountID in
            gameHistory.recordReady(gameID: gameID, modeID: modeID, accountID: accountID)
        }
        runtime.onGameRoomConfirmed = { gameID, room, accountID in
            gameRooms.confirmed(gameID: gameID, room: room, accountID: accountID)
        }
        let diagnostics = DiagnosticLogStore()
        diagnostics.record(.info, message: "app.launched")
        _diagnostics = StateObject(wrappedValue: diagnostics)
        _library = StateObject(wrappedValue: library)
        _runtime = StateObject(wrappedValue: runtime)
        let assistantHistory = AssistantHistory()
        let accounts = AccountStore(accountWillRemove: { id in try runtime.retireAccount(id) },
                                    accountDidRemove: { id in assistantHistory.deleteAll(accountID: id) },
                                    identityDidChange: { id in
            diagnostics.activateAccount(id)
            diagnostics.record(.info, message: "account.scope.activated")
            gameHistory.activate(accountID: id)
            gameRooms.activate(accountID: id)
            runtime.resetIdentity(to: id)
            library.activateAccount(id)
            library.updateCatalog(catalog.applications, markingMissingPublicAppsUnavailable: catalog.successfulLoadID != nil)
            do { try SharedFeedbackHistory().activate(userID: id, channel: .current) }
            catch { diagnostics.record(.error, message: "feedback.share.storage.unavailable") }
        })
        accounts.prepareInitialRestore()
        _catalog = StateObject(wrappedValue: catalog)
        _accounts = StateObject(wrappedValue: accounts)
        runtime.configureAuthorization(accounts: accounts)
        _homeSync = StateObject(wrappedValue: HomeSyncCoordinator(accounts: accounts, library: library, iCloud: HomeICloudSync()))
        let billingEnvironment = WalletEnvironment.forLaunch()
        let billingService = WalletService(environment: billingEnvironment)
        let wallet = WalletStore(accounts: accounts, service: billingService)
        _wallet = StateObject(wrappedValue: wallet)
        let journal = PurchaseOwnershipJournal(vault: KeychainAccountVault(service:
            billingEnvironment.ownershipService(bundleID: Bundle.main.bundleIdentifier ?? "fun.yunle.apps")))
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: billingService, journal: journal)
        _purchases = StateObject(wrappedValue: purchases)
        runtime.configureCommerce(wallet: wallet, purchases: purchases)
        _assistant = StateObject(wrappedValue: AssistantStore(accounts: accounts, history: assistantHistory))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modifier(CatalogIconUpdates())
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(runtime)
                .environmentObject(accounts)
                .environmentObject(homeSync)
                .environmentObject(wallet)
                .environmentObject(purchases)
                .environmentObject(assistant)
                .environmentObject(assistantRollout)
                .environmentObject(diagnostics)
                .environmentObject(games)
                .environmentObject(gameHistory)
                .environmentObject(gameRooms)
                .environmentObject(gameResources)
                .preferredColorScheme(appearance.colorScheme)
                .task { await catalog.load() }
                .task {
                    await accounts.consumeInitialRestore()
                    guard !Task.isCancelled, !accounts.isRestoring, !accounts.isInitialRestorePending else { return }
                    do { try SharedFeedbackHistory().activate(userID: accounts.user?.id, channel: .current) }
                    catch { diagnostics.record(.error, message: "feedback.share.storage.unavailable") }
                }
                .task { homeSync.identityChanged() }
                .task { await purchases.start() }
                .task { await assistantRollout.refresh(force: true) }
                .task {
                    runtime.applicationCache.updateAutomaticApplications(catalog.applications)
                    runtime.applicationCache.setApplicationActive(scenePhase == .active)
                }
                .onChange(of: accounts.overview.activeID) { _ in homeSync.identityChanged() }
                .onChange(of: accounts.identityGeneration) { _ in
                    wallet.identityChanged(); purchases.identityChanged()
                    assistant.identityChanged()
                    Task { await purchases.processUnfinished() }
                }
                .onChange(of: catalog.applications) {
                    library.updateCatalog($0)
                    runtime.applicationCache.updateAutomaticApplications($0)
                    diagnostics.record(.info, message: "catalog.updated")
                }
                .onChange(of: catalog.successfulLoadID) { _ in
                    library.updateCatalog(catalog.applications, markingMissingPublicAppsUnavailable: true)
                }
                .onChange(of: catalog.error) { if $0 != nil { diagnostics.record(.error, message: "catalog.load.failed") } }
                .onChange(of: runtime.issue?.id) { if $0 != nil { diagnostics.record(.error, message: "runtime.operation.failed") } }
                .onChange(of: homeSync.phase) { phase in
                    // Only fixed host event names enter diagnostics. Never log the
                    // associated error, cloud data, URLs, or authentication state.
                    let event: String
                    switch phase {
                    case .idle: event = "home.sync.idle"
                    case .syncing: event = "home.sync.syncing"
                    case .failed: event = "home.sync.failed"
                    case .conflict: event = "home.sync.conflict"
                    }
                    diagnostics.record(.info, message: event)
                }
                .onChange(of: scenePhase) {
                    runtime.applicationCache.setApplicationActive($0 == .active)
                    if $0 == .active {
                        diagnostics.record(.info, message: "app.foregrounded")
                        homeSync.schedule()
                        Task { await assistantRollout.refresh() }
                    }
                }
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
