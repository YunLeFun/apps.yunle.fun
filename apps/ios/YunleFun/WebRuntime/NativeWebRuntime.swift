import SwiftUI
import UIKit

struct RuntimeIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class NativeWebRuntime: ObservableObject {
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
    }
    private var sessions: [String: Session] = [:]
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

    init() {
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

    func contains(_ app: CloudApplication) -> Bool { sessions[app.id] != nil }

    func configureAuthorization(accounts: AccountStore) {
        self.accounts = accounts
        authorizationBroker = NativeAuthorizationBroker(accounts: accounts)
    }

    func configureCommerce(wallet: WalletStore, purchases: PurchaseCoordinator) {
        self.wallet = wallet; self.purchases = purchases
    }

    func acquire(_ app: CloudApplication, intent: ApplicationAcquisitionIntent, catalog: CatalogStore, library: HomeLibrary) {
        guard app.accessWorkshopID == nil, app.accessOwnerID == nil else { return }
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
        acquisitionController = page
        presenter.present(page, animated: true)
    }

    func open(_ app: CloudApplication, catalog: CatalogStore, library: HomeLibrary) {
        guard app.isUnavailable != true else {
            issue = RuntimeIssue(title: "应用资料尚未载入", message: "安装记录仍保留在云居。请联网更新应用资料后再试。")
            return
        }
        guard !isClearingIdentity else {
            issue = RuntimeIssue(title: "正在切换账号", message: "请稍后再打开应用。")
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
            controller.url = url
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
                    return self.localPage(DeveloperApplicationsView(login: login), applicationID: app.id, catalog: catalog, library: library)
                }
                if target == "reviews" {
                    return self.localPage(ApplicationReviewsView(application: current), applicationID: app.id, catalog: catalog, library: library)
                }
                return self.localPage(ApplicationDetailView(application: current), applicationID: app.id, catalog: catalog, library: library)
            }
            let navigation = NativeWebNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            sessions[app.id] = Session(browser: controller, presentation: navigation)
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
        controller.extraTrustedHosts = app.trustedHosts ?? []
        controller.appInfo = WebAppInfo(
            id: app.id, slug: app.publicKey, name: app.name, emoji: app.emoji ?? "",
            logo: app.iconURL?.absoluteString ?? "", themeColor: app.themeColor ?? "#007AFF",
            description: app.summary, category: app.browseCategory,
            developer: app.ownerLogin ?? "", developerName: app.developerName ?? "",
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
        if pendingOpen?.application.id == app.id { pendingOpen = nil }
        guard let session = sessions[app.id] else { return }
        session.presentation.presentingViewController?.dismiss(animated: true)
        removeSession(app)
    }

    func resetIdentity(to id: String? = nil) {
        scopedOpenID = UUID(); scopedOpenTask?.cancel(); scopedOpenTask = nil; verifyingScopedApplicationID = nil
        let reset = UUID()
        identityReset = reset
        pendingOpen = nil
        isClearingIdentity = true
        let continuation = authorizationBroker?.identityWillChange(to: id) as? NativeAuthorizationPage
        let kept = continuation?.browser
        for session in sessions.values where session.browser !== kept {
            session.browser.cancelPendingAuthorizations()
            session.presentation.presentingViewController?.dismiss(animated: false)
        }
        sessions = sessions.filter { $0.value.browser === kept }
        authorizationPages = authorizationPages.filter { $0.value === continuation }
        applications = applications.filter { sessions[$0.id] != nil }
        issue = nil
        HostIdentitySessions.clear { [weak self] in
            guard let self, self.identityReset == reset else { return }
            self.isClearingIdentity = false
            self.authorizationBroker?.identityCookiesCleared()
            self.drainPendingOpen()
        }
    }

    private func removeSession(_ app: CloudApplication) {
        if let page = authorizationPages.removeValue(forKey: app.id) { authorizationBroker?.cancel(page: page) }
        sessions.removeValue(forKey: app.id)?.browser.cancelPendingAuthorizations()
        applications.removeAll { $0.id == app.id }
    }

    private func localPage<Content: View>(_ content: Content, applicationID: String, catalog: CatalogStore, library: HomeLibrary) -> UIViewController {
        guard let accounts else {
            return UIHostingController(rootView: Text("账号服务暂时不可用，请返回主界面重试。").padding())
        }
        return UIHostingController(rootView: RuntimeLocalPage(content: content, applicationID: applicationID)
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

    var body: some View {
        NavigationStack {
            content
        }
        .environment(\.runtimeMenu, RuntimeMenuContext(applicationID: applicationID, dismiss: { dismiss() }))
    }
}

struct DeveloperApplicationsView: View {
    let login: String
    @EnvironmentObject private var catalog: CatalogStore

    var body: some View {
        List {
            Section("公开作品") {
                ForEach(catalog.applications.filter { $0.ownerLogin?.lowercased() == login.lowercased() }) { app in
                    NavigationLink {
                        ApplicationDetailView(application: app)
                    } label: { ApplicationRow(application: app) }
                }
            }
        }
        .navigationTitle(login)
        .runtimeMenuToolbar()
    }
}
