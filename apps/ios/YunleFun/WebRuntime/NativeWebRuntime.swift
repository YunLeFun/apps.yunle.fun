import OSLog
import SwiftUI
import UIKit
import WebKit

struct RuntimeIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class NativeWebRuntime: ObservableObject {
    let applicationCache: ApplicationCacheStore
    @Published private(set) var applications: [CloudApplication] = []
    @Published private(set) var gameSessionStatuses: [String: NativeGameSessionStatus] = [:]
    var onGameReady: ((String, String, String?) -> Void)?
    var onGameRoomConfirmed: ((String, NativeGameLifecycleEvent.Room, String?) -> Void)?
    private struct GameContext {
        let gameID: String
        let modeID: String
        let launchID: UUID
        let launchURL: URL
        let profileApplication: CloudApplication
        let messageOrigin: URL
        let orientation: String?
        var identity: UUID
    }
    private var gameContexts: [String: GameContext] = [:]
    private var registeredGames: [String: NativeGame] = [:]
    // Keep the current principal's named stores alive between resource
    // preparation and game creation. Releasing the last store owner here can
    // tear down its network session while the next WebView is reading cache.
    private var preparedGameStores: [UUID: WKWebsiteDataStore] = [:]
    @Published var issue: RuntimeIssue?
    @Published var unavailableApplication: CloudApplication?
    @Published private(set) var verifyingScopedApplicationID: String?
    private var scopedOpenTask: Task<Void, Never>?
    private var scopedOpenID = UUID()
    weak var anchor: UIViewController?
    private weak var presentationWindow: UIWindow?
    private struct Session {
        let browser: WebViewController
        let presentation: UINavigationController
        var profile: WebProfileRepository.Selection?
    }
    private var sessions: [String: Session] = [:]
    private let webProfiles: WebProfileRepository
    private var profileAccountID: String?
    private struct PendingOpen {
        let application: CloudApplication
        let url: URL
        let catalog: CatalogStore
        let library: HomeLibrary
        let identity: UUID
    }
    private var pendingOpen: PendingOpen?
    private var presentationTransition: UUID?
    private var authorizationPages: [String: NativeAuthorizationPage] = [:]
    private var authorizationBroker: NativeAuthorizationBroker?
    private weak var accounts: AccountStore?
    private weak var wallet: WalletStore?
    private weak var purchases: PurchaseCoordinator?
    private weak var acquisitionController: UIViewController?
    private var acquisitionID = UUID()
    private var memoryObserver: NSObjectProtocol?
    private var identityReset = UUID()
    private var isClearingIdentity = false
    private let limit = WebViewSessionPolicy.automaticLimit(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    private let personalMarketService: DeveloperProfileServing
    private let publishingService: PublishingServing
    private let launchLogger = Logger(subsystem: "fun.yunle.apps", category: "cache-launch")
    private let gameInteractionDefaults: UserDefaults

    init(personalMarketService: DeveloperProfileServing = DeveloperProfileService(), applicationCache: ApplicationCacheStore? = nil, webProfiles: WebProfileRepository? = nil,
         publishingService: PublishingServing = PublishingService(), gameInteractionDefaults: UserDefaults = .standard) {
        self.gameInteractionDefaults = gameInteractionDefaults
        self.applicationCache = applicationCache ?? ApplicationCacheStore()
        self.webProfiles = webProfiles ?? WebProfileRepository(
            fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WebProfiles/ownership-v1.json"),
            namespace: CloudbaseAuthService.gateway.absoluteString)
        self.personalMarketService = personalMarketService
        self.publishingService = publishingService
        self.applicationCache.staticResources.profile = { [weak self] app in
            guard let self, #available(iOS 17, *) else { throw ApplicationCacheError.unsupported }
            return try self.webProfiles.select(self.profileAccountID.map(WebProfileRepository.Principal.account) ?? .guest,
                                               application: self.gameContexts[app.id]?.profileApplication ?? app).identifier
        }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.releasePausedSessions() } }
        // Also cover a previous process exiting between local logout and its
        // asynchronous cookie cleanup. The first new session must start clean.
        resetIdentity()
    }

    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    }

    var isIdentityCleanupPending: Bool { isClearingIdentity }

    func gameInteractionSettings(for applicationID: String) -> WebGameInteractionSettings {
        guard let data = gameInteractionDefaults.data(forKey: "native.game-interactions.v1." + applicationID),
              let settings = try? JSONDecoder().decode(WebGameInteractionSettings.self, from: data) else {
            return WebGameInteractionSettings()
        }
        return settings
    }

    func setGameInteractionSettings(_ settings: WebGameInteractionSettings, for applicationID: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        objectWillChange.send()
        gameInteractionDefaults.set(data, forKey: "native.game-interactions.v1." + applicationID)
        if gameContexts[applicationID] != nil { sessions[applicationID]?.browser.gameInteractionSettings = settings }
    }

    func contains(_ app: CloudApplication) -> Bool { sessions[app.id] != nil }

    var runningGameIDs: Set<String> {
        let active = gameContexts.compactMap { sessions[$0.key] != nil ? resolvedGameID($0.value) : nil }
        let legacy = applications.compactMap { app -> String? in
            guard sessions[app.id] != nil, gameContexts[app.id] == nil, app.runtimeScope == "public",
                  app.launchURL?.host?.lowercased() == "play.yunle.fun" else { return nil }
            return registeredGame(for: app)?.gameId
        }
        return Set(active + legacy)
    }

    private func resolvedGameID(_ context: GameContext) -> String? {
        if gameSessionStatuses[context.gameID]?.phase == .roomLeft { return nil }
        if let room = gameSessionStatuses[context.gameID]?.room, let game = room.gameId {
            return NativeGame.firstReleaseIDs.contains(game) ? game : nil
        }
        return NativeGame.firstReleaseIDs.contains(context.gameID) ? context.gameID : nil
    }

    private func registeredGame(for application: CloudApplication) -> NativeGame? {
        [application.id, application.marketShortName, application.slug].compactMap { $0 }
            .compactMap { registeredGames[$0] }.first
    }

    func updateGameCatalog(_ games: [NativeGame]) {
        registeredGames = games.reduce(into: [:]) { result, game in
            guard game.matchesFirstRelease, (try? game.validate()) != nil else { return }
            result[game.appId] = game
        }
    }

    func openGameFallback(_ game: NativeGame, catalog: CatalogStore, library: HomeLibrary) {
        invalidateOpenRequest()
        guard !isClearingIdentity, game.matchesFirstRelease, (try? game.validate()) != nil,
              let raw = game.fallbackURL, let url = URL(string: raw),
              let play = catalog.application(id: "play"), play.runtimeScope == "public", play.canOpenAsGuest,
              play.launchURL?.host?.lowercased() == "play.yunle.fun" else { return }
        if let saved = sessions[play.id], saved.browser.url != url {
            issue = RuntimeIssue(title: "云乐坊间仍在运行", message: "请先返回原来的页面，或在菜单中结束后再查看其他玩法。")
            return
        }
        // Keep the canonical market identity and metadata. Only the requested
        // destination changes; a compatibility page is not a native-ready game.
        present(play, url: url, catalog: catalog, library: library)
    }

    func gameResourceProfile(for game: NativeGame, catalog: CatalogStore) throws -> UUID {
        guard #available(iOS 17, *) else { throw NativeGameResourceCacheError.unsupported }
        guard !isClearingIdentity else { throw AccountError.sessionChanged }
        guard game.matchesFirstRelease, (try? game.validate()) != nil, let mode = game.launchModes.first else {
            throw NativeGameError.invalidLaunch
        }
        guard
              let play = catalog.application(id: "play"), play.runtimeScope == "public", play.canOpenAsGuest,
              play.launchURL?.host?.lowercased() == "play.yunle.fun" else { throw NativeGameError.hostUnavailable }
        if let current = gameContexts.first(where: { resolvedGameID($0.value) == game.gameId }),
           let profile = sessions[current.key]?.profile { return keepGameResourceStore(profile.identifier) }
        var app = catalog.application(id: game.appId) ?? CloudApplication(id: game.appId, name: game.name)
        guard app.runtimeScope == "public", app.launchRestriction == nil, app.isPublic != false else {
            throw NativeGameError.modeUnavailable
        }
        app.websiteUrl = mode.launchURL
        let principal = profileAccountID.map(WebProfileRepository.Principal.account) ?? .guest
        let old = try webProfiles.snapshot(for: principal, application: app)
        let identity = NativeGameHostEnvironment.previewProfileApplication ?? (old.active != nil || !old.retained.isEmpty ? app : play)
        return keepGameResourceStore(try webProfiles.select(principal, application: identity).identifier)
    }

    @available(iOS 17, *)
    private func keepGameResourceStore(_ identifier: UUID) -> UUID {
        if preparedGameStores[identifier] == nil {
            preparedGameStores[identifier] = WKWebsiteDataStore(forIdentifier: identifier)
        }
        return identifier
    }

    /// These explicit first-party catalog entries use Play's registered host
    /// scope. Existing per-game stores remain attached to their original game;
    /// neither cookies nor saved games are copied or silently overwritten.
    func openGame(_ game: NativeGame, mode: NativeGameMode, catalog: CatalogStore, library: HomeLibrary) {
        invalidateOpenRequest()
        guard !isClearingIdentity else {
            issue = RuntimeIssue(title: "正在切换账号", message: "请稍后再打开游戏。")
            return
        }
        guard game.matchesFirstRelease else { return }
        do {
            try game.validate()
            let destination = try game.launchURL(for: mode)
            guard let play = catalog.application(id: "play"), play.runtimeScope == "public", play.canOpenAsGuest,
                  play.launchURL?.host?.lowercased() == "play.yunle.fun" else {
                issue = RuntimeIssue(title: "暂时无法打开游戏", message: "请先刷新工坊中的云乐坊间应用资料，再试一次。")
                return
            }
            let market = catalog.application(id: game.appId)
            let applicationID = market?.id ?? game.appId
            if let active = gameContexts.first(where: { sessions[$0.key] != nil && resolvedGameID($0.value) == game.gameId }) {
                guard active.value.modeID == mode.id else {
                    issue = RuntimeIssue(title: "游戏仍在运行", message: "请先继续当前游戏，或在游戏菜单中结束后再切换玩法。")
                    return
                }
                resumeGame(game.gameId, catalog: catalog, library: library)
                return
            }
            if sessions[applicationID] != nil, gameContexts[applicationID] == nil {
                issue = RuntimeIssue(title: "游戏仍在运行", message: "原来的游戏已保留，可从“继续游戏”恢复。切换玩法前请先在游戏菜单中结束当前会话。")
                return
            }
            if let current = gameContexts[applicationID], sessions[applicationID] != nil {
                guard current.gameID == game.gameId, current.modeID == mode.id else {
                    issue = RuntimeIssue(title: "游戏仍在运行", message: "请先继续当前游戏，或在游戏菜单中结束后再切换玩法。")
                    return
                }
                resumeGame(game.gameId, catalog: catalog, library: library)
                return
            }
            var app = market
                ?? CloudApplication(id: game.appId, name: game.name, description: game.description,
                                    websiteUrl: destination.absoluteString, logo: game.iconURL, category: "游戏", isOfficial: true)
            guard app.runtimeScope == "public", app.launchRestriction == nil,
                  app.audience != "owner", app.audience != "workshop", app.isPublic != false else {
                issue = RuntimeIssue(title: "暂时无法打开游戏", message: "请先在工坊确认这个游戏的访问条件。")
                return
            }
            app.websiteUrl = destination.absoluteString
            let principal = profileAccountID.map(WebProfileRepository.Principal.account) ?? .guest
            let legacy = try webProfiles.snapshot(for: principal, application: app)
            // New games share only the explicitly selected Play profile. A
            // game's already owned store always takes precedence for its data.
            let profileApplication = NativeGameHostEnvironment.previewProfileApplication ?? (legacy.active != nil || !legacy.retained.isEmpty ? app : play)
            let launchID = UUID()
            guard let canonicalURL = NativeGameLaunchURL.addingContext(to: destination, launchID: launchID,
                                                              gameID: game.gameId, modeID: mode.id) else {
                throw NativeGameError.invalidLaunch
            }
            let url = NativeGameHostEnvironment.transportURL(canonicalURL)
            gameContexts[app.id] = GameContext(gameID: game.gameId, modeID: mode.id, launchID: launchID,
                launchURL: url, profileApplication: profileApplication,
                messageOrigin: NativeGameHostEnvironment.previewOrigin ?? NativeGameHostEnvironment.productionOrigin,
                orientation: mode.orientation, identity: identityReset)
            gameSessionStatuses[game.gameId] = NativeGameSessionStatus(gameID: game.gameId, modeID: mode.id,
                launchID: launchID, startedAt: ProcessInfo.processInfo.systemUptime)
            present(app, url: url, catalog: catalog, library: library)
        } catch {
            issue = RuntimeIssue(title: "暂时无法打开游戏", message: error.localizedDescription)
        }
    }

    func resumeGame(_ gameID: String, catalog: CatalogStore, library: HomeLibrary) {
        if let entry = gameContexts.first(where: { $0.value.gameID == gameID || resolvedGameID($0.value) == gameID }),
           sessions[entry.key] != nil, let app = applications.first(where: { $0.id == entry.key }) {
            present(app, url: entry.value.launchURL, catalog: catalog, library: library)
        } else if let game = registeredGames.values.first(where: { $0.gameId == gameID }),
                  let app = applications.first(where: { registeredGame(for: $0)?.gameId == game.gameId }),
                  let browser = sessions[app.id]?.browser, let url = browser.url {
            present(app, url: url, catalog: catalog, library: library)
        }
    }

    func openGameRoom(_ intent: NativeGameRoomIntent, catalog: CatalogStore, library: HomeLibrary) {
        invalidateOpenRequest()
        guard !isClearingIdentity else {
            issue = RuntimeIssue(title: "正在切换账号", message: "请稍后再打开房间。")
            return
        }
        let current = gameContexts.first { entry in
            guard sessions[entry.key] != nil else { return false }
            if let room = gameSessionStatuses[entry.value.gameID]?.room {
                return room.inviteCode == intent.inviteCode && room.role == intent.role.rawValue
            }
            // A navigation failure may precede the first confirmed room event.
            return NativeGameLaunchURL.publicURL(entry.value.launchURL).flatMap(NativeGameRoomIntent.parse) == intent
        }
        if let current, let status = gameSessionStatuses[current.value.gameID] {
            if status.phase != .failed, !isClosedRoom(status) {
                resumeGame(current.value.gameID, catalog: catalog, library: library)
                return
            }
        }
        guard var app = catalog.application(id: "play"), app.runtimeScope == "public", app.canOpenAsGuest,
              app.launchURL?.host?.lowercased() == "play.yunle.fun" else {
            issue = RuntimeIssue(title: "暂时无法打开房间", message: "请先刷新工坊中的云乐坊间应用资料，再试一次。")
            return
        }
        // The selected room has not been resolved yet. Do not guess its game
        // or use a local record as proof that the caller still owns a seat.
        if sessions[app.id] != nil, current?.key != app.id {
            guard let occupied = gameContexts[app.id], occupied.gameID == "room",
                  occupied.identity == identityReset,
                  let status = gameSessionStatuses[occupied.gameID], status.launchID == occupied.launchID,
                  isClosedRoom(status) || (status.phase == .failed && status.room == nil) else {
                issue = RuntimeIssue(title: "云乐坊间仍在运行", message: "请先返回原来的游戏，或在菜单中结束后再打开其他房间。")
                return
            }
            // An ended or never-confirmed failed room can outlive its continue
            // entry after minimization. Retire only that container; a failed
            // page with a confirmed live room still needs explicit recovery/end.
            removeSession(app)
        }
        // A closed room needs a fresh operation and page, while its persistent
        // profile remains owned. Only the same intent inherits a legacy game's
        // profile; an unresolved different room selects the registered Play profile.
        let profileApplication = current?.value.profileApplication ?? NativeGameHostEnvironment.previewProfileApplication ?? app
        if let current, let old = applications.first(where: { $0.id == current.key }) { removeSession(old) }
        app.websiteUrl = intent.url.absoluteString
        let launchID = UUID()
        guard let canonicalURL = NativeGameLaunchURL.addingContext(to: intent.url, launchID: launchID,
                                                          gameID: "room", modeID: "online") else { return }
        let url = NativeGameHostEnvironment.transportURL(canonicalURL)
        gameContexts[app.id] = GameContext(gameID: "room", modeID: "online", launchID: launchID,
            launchURL: url, profileApplication: profileApplication,
            messageOrigin: NativeGameHostEnvironment.previewOrigin ?? NativeGameHostEnvironment.productionOrigin,
            orientation: nil, identity: identityReset)
        gameSessionStatuses["room"] = NativeGameSessionStatus(gameID: "room", modeID: "online", launchID: launchID,
            startedAt: ProcessInfo.processInfo.systemUptime)
        present(app, url: url, catalog: catalog, library: library)
    }

    private func isClosedRoom(_ status: NativeGameSessionStatus) -> Bool {
        status.phase == .roomLeft || ["left", "closed", "expired", "removed", "ended"].contains(status.room?.state ?? "")
    }

    private func receiveGameLifecycle(_ body: [String: Any], source: URL,
                                      applicationID: String, browser: WebViewController) {
        guard !isClearingIdentity, sessions[applicationID]?.browser === browser,
              let context = gameContexts[applicationID], context.identity == identityReset,
              var status = gameSessionStatuses[context.gameID],
              let event = NativeGameLifecycleEvent.parse(body, source: source, launchID: context.launchID,
                                                        gameID: context.gameID, modeID: context.modeID, expectedOrigin: context.messageOrigin) else { return }
        status.phase = event.state
        if let room = event.room {
            status.room = room
            let actualGameID = room.gameId ?? (context.gameID == "room" ? "" : context.gameID)
            onGameRoomConfirmed?(actualGameID, room, profileAccountID)
        }
        if event.state == .ready || event.state == .roomReady {
            if event.state == .ready, status.readyMilliseconds == nil {
                status.readyMilliseconds = max(0, (ProcessInfo.processInfo.systemUptime - status.startedAt) * 1000)
                launchLogger.notice("game=\(context.gameID, privacy: .public) mode=\(context.modeID, privacy: .public) ready-ms=\(status.readyMilliseconds ?? 0, privacy: .public)")
            }
            if event.state == .roomReady, status.roomReadyMilliseconds == nil {
                status.roomReadyMilliseconds = max(0, (ProcessInfo.processInfo.systemUptime - status.startedAt) * 1000)
                launchLogger.notice("game=\(context.gameID, privacy: .public) room-connected-ms=\(status.roomReadyMilliseconds ?? 0, privacy: .public)")
            }
            let gameID = event.room?.gameId ?? status.room?.gameId ?? (context.gameID == "room" ? nil : context.gameID)
            if event.state == .ready, let gameID, NativeGame.firstReleaseIDs.contains(gameID), status.recordedGameID != gameID {
                status.recordedGameID = gameID
                onGameReady?(gameID, context.modeID, profileAccountID)
            }
        }
        gameSessionStatuses[context.gameID] = status
    }

    func configureAuthorization(accounts: AccountStore, service: HostAuthorizationServing = HostAuthorizationService()) {
        self.accounts = accounts
        authorizationBroker = NativeAuthorizationBroker(accounts: accounts, service: service)
        if profileAccountID != accounts.user?.id { resetIdentity(to: accounts.user?.id) }
    }

    var isAuthorizationBusy: Bool { authorizationBroker?.isBusy == true }

    /// 跨 App 授权与网页内授权共用同一个 broker，互斥并随账号切换一起撤销
    func beginCrossAppAuthorization(_ page: CrossAppAuthorizationPage) {
        guard let broker = authorizationBroker else {
            page.resolve(page.requestID, result: nil, error: HostAuthorizationError.unavailable.code)
            return
        }
        broker.begin(requestID: page.requestID, sourceOrigin: page.request.sourceOrigin,
                     parameters: page.request.brokerParameters, page: page, requireConsent: true)
    }

    func configureCommerce(wallet: WalletStore, purchases: PurchaseCoordinator) {
        self.wallet = wallet; self.purchases = purchases
    }

    func acquire(_ app: CloudApplication, intent: ApplicationAcquisitionIntent, catalog: CatalogStore, library: HomeLibrary) {
        guard app.accessWorkshopID == nil, app.accessOwnerID == nil, app.personalMarketOwnerLogin == nil else { return }
        guard let accounts, let wallet, let purchases,
              var presenter = presentationRootController(), acquisitionController == nil, !isClearingIdentity else { return }
        let requestID = UUID(); acquisitionID = requestID
        let store = ApplicationAcquisitionStore(application: app, accounts: accounts)
        let page = UIHostingController(rootView: ApplicationAcquisitionView(store: store, intent: intent) { [weak self] permit in
            guard let self, self.acquisitionID == requestID, accounts.user?.isUsable == true, accounts.identityGeneration == permit.boundary.generation,
                  accounts.user?.id == permit.boundary.uid, !self.isClearingIdentity,
                  let page = self.acquisitionController, page.presentingViewController != nil, !page.isBeingDismissed else { return }
            if intent == .install {
                guard library.accountID == permit.boundary.uid else { return }
                library.add(permit.application)
                guard library.contains(permit.application) else { store.storageFailed(); return }
            }
            page.dismiss(animated: true) { [weak self] in
                guard let self, self.acquisitionID == requestID, accounts.user?.isUsable == true, accounts.identityGeneration == permit.boundary.generation,
                      accounts.user?.id == permit.boundary.uid, !self.isClearingIdentity else { return }
                if intent == .open, let url = permit.application.launchURL {
                    self.present(permit.application, url: url, catalog: catalog, library: library)
                }
            }
        }.environmentObject(accounts).environmentObject(wallet).environmentObject(purchases))
        page.modalPresentationStyle = .pageSheet
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed, !presenter.isBeingPresented else { return }
        invalidateOpenRequest()
        acquisitionController = page
        presenter.present(page, animated: true)
    }

    func open(_ app: CloudApplication, catalog: CatalogStore, library: HomeLibrary) {
        // A handled new intent, including an unavailable application, must not
        // later be replaced by an earlier asynchronous publication lookup.
        invalidateOpenRequest()
        if app.runtimeScope == "public", app.canOpenAsGuest,
           let game = registeredGame(for: app), let url = app.launchURL,
           url.host?.lowercased() == "play.yunle.fun",
           url.path == "/games/\(game.gameId)" || url.path.hasPrefix("/games/\(game.gameId)/") {
            if gameContexts[app.id] != nil, sessions[app.id] != nil {
                resumeGame(game.gameId, catalog: catalog, library: library)
                return
            }
            let mode = game.availableModes.first(where: { $0.id == "computer" })
                ?? game.availableModes.first(where: { $0.id == "local" }) ?? game.availableModes.first
            if let mode {
                openGame(game, mode: mode, catalog: catalog, library: library)
                return
            }
        }
        guard app.isUnavailable != true else {
            unavailableApplication = app
            return
        }
        guard !isClearingIdentity else {
            issue = RuntimeIssue(title: "正在切换账号", message: "请稍后再打开应用。")
            return
        }
        if app.personalMarketOwnerLogin != nil {
            let identity = identityReset, operationID = UUID()
            scopedOpenID = operationID; verifyingScopedApplicationID = app.id
            scopedOpenTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.scopedOpenID == operationID { self.verifyingScopedApplicationID = nil; self.scopedOpenTask = nil } }
                do {
                    let current = try await PersonalMarketLaunchAuthorization(service: self.personalMarketService).resolve(app)
                    guard !Task.isCancelled, self.scopedOpenID == operationID, self.identityReset == identity,
                          !self.isClearingIdentity, let url = current.launchURL else { return }
                    self.present(current, url: url, catalog: catalog, library: library)
                } catch {
                    guard !Task.isCancelled, self.scopedOpenID == operationID, self.identityReset == identity else { return }
                    self.issue = RuntimeIssue(title: "无法打开作者作品", message: (error as? DeveloperProfileError)?.message ?? DeveloperProfileError.unavailable.message)
                }
            }
            return
        }
        if app.accessWorkshopID != nil || app.accessOwnerID != nil {
            guard let accounts, let uid = accounts.user?.id, accounts.user?.isUsable == true else {
                issue = RuntimeIssue(title: "请先登录", message: app.accessOwnerID != nil ? "登录作品所属账号后再预览。" : "登录工坊坊客账号后再打开这个应用。")
                return
            }
            scopedOpenTask?.cancel()
            let boundary = AccountRequestBoundary(uid: uid, generation: accounts.identityGeneration)
            let operationID = UUID(); scopedOpenID = operationID; verifyingScopedApplicationID = app.id
            scopedOpenTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.scopedOpenID == operationID { self.verifyingScopedApplicationID = nil; self.scopedOpenTask = nil } }
                do {
                    let current: CloudApplication
                    if app.accessOwnerID != nil {
                        current = try await OwnerPreviewAuthorization(accounts: accounts, service: self.publishingService).resolve(app, boundary: boundary)
                    } else {
                        current = try await WorkshopLaunchAuthorization(accounts: accounts).resolve(app, boundary: boundary)
                    }
                    guard !Task.isCancelled, self.scopedOpenID == operationID,
                          accounts.identityGeneration == boundary.generation, !self.isClearingIdentity,
                          let url = current.launchURL else { return }
                    self.present(current, url: url, catalog: catalog, library: library)
                } catch {
                    guard !Task.isCancelled, self.scopedOpenID == operationID,
                          accounts.identityGeneration == boundary.generation else { return }
                    self.issue = RuntimeIssue(title: "无法打开作品", message: app.accessOwnerID != nil ? PublishingError.message(for: error) : WorkshopError.message(for: error))
                }
            }
            return
        }
        guard app.canOpenAsGuest, let url = app.launchURL else {
            if app.launchURL != nil {
                acquire(app, intent: .open, catalog: catalog, library: library)
                return
            }
            issue = RuntimeIssue(title: app.accessLabel ?? "暂时无法打开",
                                 message: app.accessLabel == nil ? "这个应用暂时没有可用的网址。" : "请先确认这个应用的使用权限。")
            return
        }
        present(app, url: url, catalog: catalog, library: library)
    }

    private func present(_ app: CloudApplication, url: URL, catalog: CatalogStore, library: HomeLibrary) {
        pendingOpen = PendingOpen(application: app, url: url, catalog: catalog, library: library, identity: identityReset)
        drainPendingOpen()
    }

    private func invalidateOpenRequest() {
        scopedOpenTask?.cancel(); scopedOpenID = UUID(); scopedOpenTask = nil
        verifyingScopedApplicationID = nil; pendingOpen = nil
        unavailableApplication = nil
    }

    private func drainPendingOpen() {
        guard presentationTransition == nil, !isClearingIdentity, let request = pendingOpen else { return }
        guard request.identity == identityReset else { pendingOpen = nil; return }
        guard let presenter = presentationRootController() else {
            pendingOpen = nil
            issue = RuntimeIssue(title: "暂时无法打开", message: "请稍后再试。")
            return
        }
        if let saved = sessions[request.application.id], presenter.presentedViewController === saved.presentation,
           saved.browser.url == request.url,
           applications.first(where: { $0.id == request.application.id })?.runtimeScope == request.application.runtimeScope {
            pendingOpen = nil
            return
        }
        if let presented = presenter.presentedViewController {
            let transition = UUID()
            presentationTransition = transition
            if presented.isBeingPresented || presented.isBeingDismissed {
                guard let coordinator = presented.transitionCoordinator,
                      coordinator.animate(alongsideTransition: nil, completion: { [weak self] _ in self?.finishPresentation(transition) }) else {
                    presentationTransition = nil; pendingOpen = nil
                    issue = RuntimeIssue(title: "界面正在切换", message: "请稍后再打开应用。")
                    return
                }
            } else {
                for session in sessions.values where session.presentation.presentingViewController != nil {
                    if let page = authorizationPages[session.browser.appInfo?.id ?? ""] { authorizationBroker?.cancel(page: page) }
                    session.browser.cancelPendingAuthorizations()
                }
                // Dismiss from the owner of the entire hierarchy, including first-party sheets.
                presenter.dismiss(animated: true) { [weak self] in self?.finishPresentation(transition) }
            }
            return
        }
        pendingOpen = nil
        showSession(request, from: presenter)
    }

    private func finishPresentation(_ transition: UUID) {
        guard presentationTransition == transition else { return }
        presentationTransition = nil
        drainPendingOpen()
    }

    private func presentationRootController() -> UIViewController? {
        guard let anchor else { return nil }
        if let window = anchor.viewIfLoaded?.window { presentationWindow = window }
        guard let root = presentationWindow?.rootViewController else { return nil }
        // Full-screen presentation removes the covered anchor's view from its window.
        // Its containment must still belong to this root before using the cached window.
        var ancestor = anchor
        while let parent = ancestor.parent { ancestor = parent }
        return ancestor === root ? root : nil
    }

    private func showSession(_ request: PendingOpen, from presenter: UIViewController) {
        let app = request.application, url = request.url, catalog = request.catalog, library = request.library
        if let saved = sessions[app.id], saved.browser.url != url || applications.first(where: { $0.id == app.id })?.runtimeScope != app.runtimeScope {
            removeSession(app)
        }
        let controller: WebViewController
        if let saved = sessions[app.id] {
            if saved.presentation.presentingViewController != nil { return }
            controller = saved.browser
        } else {
            controller = WebViewController()
            var profile: WebProfileRepository.Selection?
            if #available(iOS 17, *) {
                do {
                    let selected = try webProfiles.select(profileAccountID.map(WebProfileRepository.Principal.account) ?? .guest,
                                                         application: gameContexts[app.id]?.profileApplication ?? app)
                    profile = selected
                    controller.websiteDataStore = WKWebsiteDataStore(forIdentifier: selected.identifier)
                    if let origin = ApplicationStaticResourcePolicy.origin(for: url) {
                        applicationCache.staticResources.register(selected.identifier, origin: origin)
                    }
                } catch {
                    issue = RuntimeIssue(title: "无法安全打开应用", message: "原有应用数据已保留。请稍后重试。")
                    return
                }
            }
            // iOS 16 remains on the existing compatibility path until its
            // persistent isolation and migration policy is implemented.
            controller.url = url
            if gameContexts[app.id] != nil {
                controller.usesGameInteractionPolicy = true
                controller.gameInteractionSettings = gameInteractionSettings(for: app.id)
                controller.showsApplicationDetails = catalog.application(id: app.id) != nil
                controller.publicLinkURL = { NativeGameLaunchURL.publicURL($0) ?? NativeGameLaunchURL.publicURL(url) }
                controller.gameLifecycleOrigin = gameContexts[app.id]?.messageOrigin
                controller.preferredGameOrientation = gameContexts[app.id]?.orientation
                controller.onGameLifecycleMessage = { [weak self, weak controller] body, source in
                    guard let self, let controller else { return }
                    self.receiveGameLifecycle(body, source: source, applicationID: app.id, browser: controller)
                }
                controller.onGameNavigationFailure = { [weak self, weak controller] in
                    guard let self, let controller, self.sessions[app.id]?.browser === controller,
                          let game = self.gameContexts[app.id], game.identity == self.identityReset else { return }
                    self.gameSessionStatuses[game.gameID]?.phase = .failed
                }
            }
            let identity = identityReset
            controller.initialContentLoader = { [weak self, weak controller] web, url, prepared in
                Task { @MainActor [weak self, weak controller] in
                    defer { prepared() }
                    guard let self, let controller else { return }
                    if let game = self.gameContexts[app.id] {
                        guard self.identityReset == game.identity, self.sessions[app.id]?.browser === controller else { return }
                        // Game resources use the selected persistent WebKit
                        // network cache. Never load an archived gameplay page.
                        self.applicationCache.sessionStarted(app, revision: nil)
                        web.load(URLRequest(url: url))
                        return
                    }
                    let snapshot: (entry: ApplicationCacheEntry, archive: Data)?
                    var unreadable: Error?
                    do { snapshot = try await self.applicationCache.repository.snapshot(for: app) }
                    catch { snapshot = nil; unreadable = error }
                    guard self.identityReset == identity, self.sessions[app.id]?.browser === controller else { return }
                    if #available(iOS 17, *), ApplicationStaticResourcePolicy.supports(app) {
                        // Always navigate to the live server. Only public subresources
                        // can come from the selected account/application's HTTP cache.
                        let receipt = snapshot.flatMap { try? JSONDecoder().decode(ApplicationStaticResourceReceipt.self, from: $0.archive) }
                        let matches = receipt?.profileIdentifier == web.configuration.websiteDataStore.identifier
                        self.applicationCache.sessionStarted(app, revision: matches ? snapshot?.entry.downloadedAt : nil)
                        self.launchLogger.notice("application=\(app.id, privacy: .public) source=live-page public-resource-cache=\(matches, privacy: .public)")
                        web.load(ApplicationStaticResourcePolicy.navigationRequest(to: url))
                        return
                    }
                    self.applicationCache.sessionStarted(app, revision: snapshot?.entry.downloadedAt)
                    if let snapshot {
                        controller.initialContentFailure = { [weak self, weak controller] web in
                            guard let self, let controller, self.identityReset == identity,
                                  self.sessions[app.id]?.browser === controller else { return }
                            self.launchLogger.error("application=\(app.id, privacy: .public) source=network reason=archive-load-failed")
                            self.applicationCache.sessionStarted(app, revision: nil)
                            web.load(URLRequest(url: url))
                        }
                        self.launchLogger.notice("application=\(app.id, privacy: .public) source=archive bytes=\(snapshot.entry.byteCount, privacy: .public) resources=\(snapshot.entry.resourceCount, privacy: .public) downloaded-at=\(snapshot.entry.downloadedAt.timeIntervalSince1970, privacy: .public)")
                        web.load(snapshot.archive, mimeType: "application/x-webarchive", characterEncodingName: "UTF-8", baseURL: url)
                    } else {
                        if let unreadable {
                            let failure = unreadable as NSError
                            self.launchLogger.error("application=\(app.id, privacy: .public) source=network reason=cache-unreadable error-domain=\(failure.domain, privacy: .public) error-code=\(failure.code, privacy: .public)")
                        } else {
                            let reason = ApplicationCacheEntry.supports(app) ? "not-downloaded" : "unsupported"
                            self.launchLogger.notice("application=\(app.id, privacy: .public) source=network reason=\(reason, privacy: .public)")
                        }
                        web.load(URLRequest(url: url))
                    }
                }
            }
            controller.displayMode = .titlebar
            controller.usesSystemNavigationBar = true
            controller.onClose = { [weak self, weak controller] in
                guard let self, let controller, self.sessions[app.id]?.browser === controller else { return }
                self.end(app)
            }
            controller.onMinimize = { [weak self, weak controller] in
                guard let self, let controller, !self.isClearingIdentity, self.sessions[app.id]?.browser === controller else { return }
                if let page = self.authorizationPages[app.id] { self.authorizationBroker?.cancel(page: page) }
                controller.cancelPendingAuthorizations()
                self.markRecent(self.applications.first(where: { $0.id == app.id }) ?? app)
            }
            if let accounts {
                let page = NativeAuthorizationPage(browser: controller, accounts: accounts)
                authorizationPages[app.id] = page
                controller.onAuthorizationRequest = { [weak self, weak page] requestID, origin, parameters in
                    guard let self, let page, let broker = self.authorizationBroker else { return }
                    broker.begin(requestID: requestID, sourceOrigin: origin, parameters: parameters, page: page)
                }
            }
            controller.localPageFactory = { [weak self] path, kind, target in
                guard let self else { return UIViewController() }
                let current = self.applications.first(where: { $0.id == app.id }) ?? app
                if kind == "developer-sheet" {
                    let login = String(path.split(separator: "/").last ?? "").removingPercentEncoding ?? ""
                    return self.localPage(DeveloperApplicationsView(login: login), applicationID: app.id, runtimeScope: current.runtimeScope,
                                          launchURL: current.launchURL, catalog: catalog, library: library)
                }
                if target == "reviews", current.personalMarketOwnerLogin == nil {
                    return self.localPage(ApplicationReviewsView(application: current), applicationID: app.id, runtimeScope: current.runtimeScope,
                                          launchURL: current.launchURL, catalog: catalog, library: library)
                }
                return self.localPage(ApplicationDetailView(application: current), applicationID: app.id, runtimeScope: current.runtimeScope,
                                      launchURL: current.launchURL, catalog: catalog, library: library)
            }
            let navigation = NativeWebNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            sessions[app.id] = Session(browser: controller, presentation: navigation, profile: profile)
        }
        controller.localMenuPageFactory = { [weak self, weak controller] currentURL, perform in
            guard let self, let controller, let accounts = self.accounts,
                  self.sessions[app.id]?.browser === controller, !self.isClearingIdentity else { return nil }
            let identity = self.identityReset
            let generation = accounts.identityGeneration
            let current = self.applications.first(where: { $0.id == app.id }) ?? app
            let menu = NativeApplicationMenuView(application: current, currentURL: currentURL,
                                                 hasMarketEntry: catalog.application(id: app.id) != nil,
                                                 isGame: self.gameContexts[app.id] != nil, perform: perform)
                .environmentObject(catalog).environmentObject(library)
                .environmentObject(self).environmentObject(accounts)
            return WebAppMenuPage(controller: UIHostingController(rootView: menu), isCurrent: { [weak self, weak controller] in
                guard let self, let controller else { return false }
                return self.identityReset == identity && !self.isClearingIdentity
                    && accounts.identityGeneration == generation && self.sessions[app.id]?.browser === controller
            })
        }
        controller.customTitle = app.name
        controller.extraTrustedHosts = app.runtimeTrustedHosts
        controller.appInfo = WebAppInfo(
            id: app.id, slug: app.publicKey, name: app.name, emoji: app.emoji ?? "",
            logo: app.iconCandidates(dark: false, downloaded: CatalogIconStore.shared.assets).first?.url.absoluteString ?? "", themeColor: app.themeColor ?? "#007AFF",
            description: app.summary, category: app.browseCategory,
            developer: app.personalMarketOwnerLogin ?? app.ownerLogin ?? "", developerName: app.developerName ?? "",
            rating: app.displayRating ?? 0, ratingCount: app.ratingCount ?? 0)
        markRecent(app)
        evictIfNeeded(except: app.id)
        guard let session = sessions[app.id] else { return }
        let transition = UUID()
        presentationTransition = transition
        presenter.present(session.presentation, animated: true) { [weak self] in self?.finishPresentation(transition) }
        // Games without a market entry have their own recent list. Do not
        // introduce an unresolvable ID into the user's cloud-synced library.
        if gameContexts[app.id] == nil || (NativeGameHostEnvironment.previewOrigin == nil && catalog.application(id: app.id) != nil) {
            library.recordUse(app)
        }
    }

    func end(_ app: CloudApplication) {
        if verifyingScopedApplicationID == app.id { invalidateOpenRequest() }
        if pendingOpen?.application.id == app.id { pendingOpen = nil }
        guard let session = sessions[app.id] else { return }
        session.presentation.presentingViewController?.dismiss(animated: true)
        removeSession(app)
    }

    func retireAccount(_ id: String) throws {
        if #available(iOS 17, *) { try webProfiles.retire(id) }
    }

    struct ProfileRecoverySnapshot {
        let application: CloudApplication
        let profileApplication: CloudApplication
        let boundary: AccountRequestBoundary
        let profiles: WebProfileRepository.Snapshot
    }

    func profileRecovery(for application: CloudApplication) throws -> ProfileRecoverySnapshot {
        guard #available(iOS 17, *), let accounts, let user = accounts.user, user.isUsable,
              profileAccountID == user.id, !isClearingIdentity else { throw AccountError.sessionChanged }
        let profileApplication = gameContexts[application.id]?.profileApplication ?? application
        return ProfileRecoverySnapshot(application: application, profileApplication: profileApplication,
            boundary: AccountRequestBoundary(uid: user.id, generation: accounts.identityGeneration),
            profiles: try webProfiles.snapshot(for: .account(user.id), application: profileApplication))
    }

    func restoreWebProfile(_ selected: WebProfileRepository.Selection, from snapshot: ProfileRecoverySnapshot) throws {
        guard #available(iOS 17, *), let accounts, let user = accounts.user, user.isUsable,
              snapshot.boundary == AccountRequestBoundary(uid: user.id, generation: accounts.identityGeneration),
              profileAccountID == user.id, !isClearingIdentity else { throw AccountError.sessionChanged }
        try webProfiles.activateRetained(selected, accountID: user.id, application: snapshot.profileApplication,
                                        replacing: snapshot.profiles.active)
        // The previous store remains retained. Close its page only after the
        // durable swap succeeds; reopening still goes through normal access checks.
        end(snapshot.application)
    }

    func resetIdentity(to id: String? = nil) {
        unavailableApplication = nil
        preparedGameStores.removeAll()
        profileAccountID = id
        scopedOpenID = UUID(); scopedOpenTask?.cancel(); scopedOpenTask = nil; verifyingScopedApplicationID = nil
        let reset = UUID()
        identityReset = reset
        pendingOpen = nil
        isClearingIdentity = true
        let continuation = authorizationBroker?.identityWillChange(to: id) as? NativeAuthorizationPage
        var kept = continuation?.browser
        var profileError: RuntimeIssue?
        if #available(iOS 17, *), let continuation, let browser = kept {
            do {
                guard let id, let key = sessions.first(where: { $0.value.browser === browser })?.key,
                      let selected = sessions[key]?.profile else { throw WebProfileRepository.Failure.staleSelection }
                let result = try webProfiles.bindGuestContinuation(selected, to: id)
                switch result {
                case .adopted(let profile), .retained(let profile, _): sessions[key]?.profile = profile
                }
            } catch {
                authorizationBroker?.cancel(page: continuation)
                kept = nil
                profileError = RuntimeIssue(title: "无法安全切换应用", message: "原有应用数据已保留。请重新打开应用后再试。")
            }
        }
        for session in sessions.values where session.browser !== kept {
            session.browser.cancelPendingAuthorizations()
            session.presentation.presentingViewController?.dismiss(animated: false)
        }
        sessions = sessions.filter { $0.value.browser === kept }
        gameContexts = gameContexts.filter { sessions[$0.key] != nil }
        for key in gameContexts.keys { gameContexts[key]?.identity = reset }
        let keptGames = Set(gameContexts.values.map(\.gameID))
        gameSessionStatuses = gameSessionStatuses.filter { keptGames.contains($0.key) }
        authorizationPages = authorizationPages.filter { kept != nil && $0.value === continuation }
        for app in applications where sessions[app.id] == nil { applicationCache.sessionEnded(app) }
        applications = applications.filter { sessions[$0.id] != nil }
        issue = profileError
        let complete: () -> Void = { [weak self] in
            guard let self, self.identityReset == reset else { return }
            self.isClearingIdentity = false
            self.authorizationBroker?.identityCookiesCleared()
            self.drainPendingOpen()
        }
        if #available(iOS 17, *) {
            // Account stores are disjoint. Only a guest continuation keeps its
            // old browser, and its store was durably detached from future guests.
            // Never clear unrelated drafts or adopt the legacy default store.
            complete()
        } else { HostIdentitySessions.clear(completion: complete) }
    }

    private func removeSession(_ app: CloudApplication) {
        if let game = gameContexts.removeValue(forKey: app.id) { gameSessionStatuses[game.gameID] = nil }
        applicationCache.sessionEnded(applications.first(where: { $0.id == app.id }) ?? app)
        if let page = authorizationPages.removeValue(forKey: app.id) { authorizationBroker?.cancel(page: page) }
        sessions.removeValue(forKey: app.id)?.browser.cancelPendingAuthorizations()
        applications.removeAll { $0.id == app.id }
    }

    private func localPage<Content: View>(_ content: Content, applicationID: String, runtimeScope: String, launchURL: URL?, catalog: CatalogStore, library: HomeLibrary) -> UIViewController {
        guard let accounts else {
            return UIHostingController(rootView: Text("账号服务暂时不可用，请返回主界面重试。").padding())
        }
        return UIHostingController(rootView: RuntimeLocalPage(content: content, applicationID: applicationID, runtimeScope: runtimeScope, launchURL: launchURL)
            .environmentObject(catalog).environmentObject(library).environmentObject(self).environmentObject(accounts))
    }

    private func markRecent(_ app: CloudApplication) {
        applications.removeAll { $0.id == app.id }
        applications.insert(app, at: 0)
    }

    private func evictIfNeeded(except activeID: String) {
        while sessions.count > limit {
            guard let oldest = applications.last(where: {
                $0.id != activeID && sessions[$0.id]?.presentation.presentingViewController == nil
            }) else { return }
            end(oldest)
        }
    }

    private func releasePausedSessions() {
        let hasForeground = sessions.values.contains { $0.presentation.presentingViewController != nil }
        let keep = hasForeground ? nil : applications.first?.id
        for app in applications where app.id != keep && sessions[app.id]?.presentation.presentingViewController == nil { end(app) }
    }
}

private final class NativeWebNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { topViewController?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation }
}

struct RuntimePresentationAnchor: UIViewControllerRepresentable {
    let runtime: NativeWebRuntime
    let catalog: CatalogStore
    let library: HomeLibrary

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        runtime.anchor = controller
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { runtime.anchor = controller }
}

private struct RuntimeLocalPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let content: Content
    let applicationID: String
    let runtimeScope: String
    let launchURL: URL?

    var body: some View {
        NavigationStack {
            content
        }
        .environment(\.runtimeMenu, RuntimeMenuContext(applicationID: applicationID, runtimeScope: runtimeScope, launchURL: launchURL, dismiss: { dismiss() }))
    }
}
