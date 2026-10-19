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
    @Published var issue: RuntimeIssue?
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
    private let launchLogger = Logger(subsystem: "fun.yunle.apps", category: "cache-launch")

    init(personalMarketService: DeveloperProfileServing = DeveloperProfileService(), applicationCache: ApplicationCacheStore? = nil, webProfiles: WebProfileRepository? = nil) {
        self.applicationCache = applicationCache ?? ApplicationCacheStore()
        self.webProfiles = webProfiles ?? WebProfileRepository(
            fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WebProfiles/ownership-v1.json"),
            namespace: CloudbaseAuthService.gateway.absoluteString)
        self.personalMarketService = personalMarketService
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

    func contains(_ app: CloudApplication) -> Bool { sessions[app.id] != nil }

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
        guard app.isUnavailable != true else {
            issue = RuntimeIssue(title: "应用资料尚未载入", message: "安装记录仍保留在云居。请联网更新应用资料后再试。")
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
                        current = try await OwnerPreviewAuthorization(accounts: accounts).resolve(app, boundary: boundary)
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
                    let selected = try webProfiles.select(profileAccountID.map(WebProfileRepository.Principal.account) ?? .guest, application: app)
                    profile = selected
                    controller.websiteDataStore = WKWebsiteDataStore(forIdentifier: selected.identifier)
                } catch {
                    issue = RuntimeIssue(title: "无法安全打开应用", message: "原有应用数据已保留。请稍后重试。")
                    return
                }
            }
            // iOS 16 remains on the existing compatibility path until its
            // persistent isolation and migration policy is implemented.
            controller.url = url
            let identity = identityReset
            controller.initialContentLoader = { [weak self, weak controller] web, url, prepared in
                Task { @MainActor [weak self, weak controller] in
                    defer { prepared() }
                    guard let self, let controller else { return }
                    let snapshot: (entry: ApplicationCacheEntry, archive: Data)?
                    var unreadable: Error?
                    do { snapshot = try await self.applicationCache.repository.snapshot(for: app) }
                    catch { snapshot = nil; unreadable = error }
                    guard self.identityReset == identity, self.sessions[app.id]?.browser === controller else { return }
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
            let menu = NativeApplicationMenuView(application: current, currentURL: currentURL, perform: perform)
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
            logo: app.iconURL?.absoluteString ?? "", themeColor: app.themeColor ?? "#007AFF",
            description: app.summary, category: app.browseCategory,
            developer: app.personalMarketOwnerLogin ?? app.ownerLogin ?? "", developerName: app.developerName ?? "",
            rating: app.displayRating ?? 0, ratingCount: app.ratingCount ?? 0)
        markRecent(app)
        evictIfNeeded(except: app.id)
        guard let session = sessions[app.id] else { return }
        let transition = UUID()
        presentationTransition = transition
        presenter.present(session.presentation, animated: true) { [weak self] in self?.finishPresentation(transition) }
        library.recordUse(app)
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
        let boundary: AccountRequestBoundary
        let profiles: WebProfileRepository.Snapshot
    }

    func profileRecovery(for application: CloudApplication) throws -> ProfileRecoverySnapshot {
        guard #available(iOS 17, *), let accounts, let user = accounts.user, user.isUsable,
              profileAccountID == user.id, !isClearingIdentity else { throw AccountError.sessionChanged }
        return ProfileRecoverySnapshot(application: application,
            boundary: AccountRequestBoundary(uid: user.id, generation: accounts.identityGeneration),
            profiles: try webProfiles.snapshot(for: .account(user.id), application: application))
    }

    func restoreWebProfile(_ selected: WebProfileRepository.Selection, from snapshot: ProfileRecoverySnapshot) throws {
        guard #available(iOS 17, *), let accounts, let user = accounts.user, user.isUsable,
              snapshot.boundary == AccountRequestBoundary(uid: user.id, generation: accounts.identityGeneration),
              profileAccountID == user.id, !isClearingIdentity else { throw AccountError.sessionChanged }
        try webProfiles.activateRetained(selected, accountID: user.id, application: snapshot.application,
                                        replacing: snapshot.profiles.active)
        // The previous store remains retained. Close its page only after the
        // durable swap succeeds; reopening still goes through normal access checks.
        end(snapshot.application)
    }

    func resetIdentity(to id: String? = nil) {
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
