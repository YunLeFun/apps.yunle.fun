import AppKit
import Combine
import WebKit

@MainActor
final class MacWebRuntime: NSObject, ObservableObject {
    @Published private(set) var application: CloudApplication?
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private final class Page {
        let webView: WKWebView
        let profileID: UUID
        let isPopup: Bool
        var observations: [NSKeyValueObservation] = []
        var failure: String?
        var window: NSWindow?
        var dialogs: [UUID: () -> Void] = [:]
        var authorization: MacAuthorizationPage?

        init(webView: WKWebView, profileID: UUID, isPopup: Bool = false) {
            self.webView = webView
            self.profileID = profileID
            self.isPopup = isPopup
        }
    }

    private struct Session {
        var application: CloudApplication
        var profile: WebProfileRepository.Selection
        let page: Page
    }

    private let profiles: WebProfileRepository
    private let loadRequest: @MainActor (WKWebView, URLRequest) -> Void
    // The workspace keeps this runtime for the app's lifetime. Named WebKit
    // stores flush cookies asynchronously, so releasing the last store when a
    // page closes can lose a recent login before the next page is created.
    // Retain stores independently of executable pages; UUID ownership remains
    // exclusively in WebProfileRepository, including retirement on sign-out.
    private var websiteDataStores: [UUID: WKWebsiteDataStore] = [:]
    private var accountID: String?
    private var sessions: [UUID: Session] = [:]
    private var pages: [ObjectIdentifier: Page] = [:]
    private var activeProfileID: UUID?
    private var isPresented = false
    private var authorizationBroker: NativeAuthorizationBroker?
    private var authorizationPresentation: MacAuthorizationPresenting?
    private var makeSystemAuthorization: (@MainActor () -> MacSystemAuthorizationLaunching)?

    var webView: WKWebView? { activePage?.webView }
    private var activePage: Page? { activeProfileID.flatMap { sessions[$0]?.page } }

    init(webProfiles: WebProfileRepository? = nil,
         loadRequest: @escaping @MainActor (WKWebView, URLRequest) -> Void = { webView, request in webView.load(request) }) {
        profiles = webProfiles ?? WebProfileRepository(
            fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("YunleFunMac/WebProfiles/ownership-v1.json"),
            namespace: CloudbaseAuthService.gateway.absoluteString)
        self.loadRequest = loadRequest
        super.init()
    }

    func configureAuthorization(accounts: AccountAuthorizing,
                                service: HostAuthorizationServing = HostAuthorizationService(),
                                presentation: MacAuthorizationPresenting? = nil,
                                makeSystemAuthorization: (@MainActor () -> MacSystemAuthorizationLaunching)? = nil) {
        for page in pages.values { page.authorization?.detach(); page.authorization = nil }
        authorizationBroker = NativeAuthorizationBroker(accounts: accounts, service: service)
        self.makeSystemAuthorization = makeSystemAuthorization
        accountDidChange(accounts.user?.id)
        if let presentation {
            authorizationPresentation = presentation
        } else if let accounts = accounts as? AccountStore {
            authorizationPresentation = MacAuthorizationUI(accounts: accounts, window: { [weak self] in self?.webView?.window })
        } else {
            authorizationPresentation = nil
        }
        for session in sessions.values { configureAuthorization(for: session.page, application: session.application) }
    }

    /// The caller supplies a current record from CatalogService's public endpoint.
    /// This extra check also prevents accidental use of owner/workshop metadata.
    @discardableResult
    func open(_ application: CloudApplication) -> Bool {
        guard let url = MacWebNavigationPolicy.launchURL(for: application) else {
            error = "此版本仅支持打开目录中公开、免费且可用的 HTTPS 应用。"
            return false
        }
        do {
            let principal: WebProfileRepository.Principal = accountID.map { .account($0) } ?? .guest
            let selected: WebProfileRepository.Selection
            if let current = activeProfileID.flatMap({ sessions[$0] }), current.application.id == application.id,
               current.application.launchURL == url {
                // An accepted guest login may be retained beside the account's
                // previous store. Keep its live page until explicitly ended,
                // while rechecking that this identity still owns that profile.
                let owned = try profiles.snapshot(for: principal, application: application)
                if owned.active == current.profile || owned.retained.contains(current.profile) {
                    selected = current.profile
                } else { selected = try profiles.select(principal, application: application) }
            } else { selected = try profiles.select(principal, application: application) }
            if let activeProfileID,
               activeProfileID != selected.identifier || self.application?.launchURL != url {
                terminate()
            }
            hidePopups()
            if var existing = sessions[selected.identifier] {
                existing.application = application
                existing.page.authorization?.updateApplication(application)
                sessions[selected.identifier] = existing
            } else {
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = websiteDataStore(for: selected)
                // WebKit still requires a user gesture for window.open. Only the
                // narrow SSO bridge is injected; host tokens never reach JS.
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                let page = makePage(configuration: configuration, profileID: selected.identifier)
                sessions[selected.identifier] = Session(application: application, profile: selected, page: page)
                configureAuthorization(for: page, application: application)
                loadRequest(page.webView, URLRequest(url: url))
            }
            activeProfileID = selected.identifier
            isPresented = true
            self.application = application
            publishState()
            for page in pages.values where page.profileID == selected.identifier && page.isPopup {
                page.window?.makeKeyAndOrderFront(nil)
            }
            return true
        } catch {
            self.error = "无法安全恢复此应用的网页数据，请检查本机资料文件或稍后重试。"
            return false
        }
    }

    /// Refresh authorization metadata without reopening a visible or hidden page.
    func updateApplication(_ application: CloudApplication) {
        guard let identifier = activeProfileID, var session = sessions[identifier],
              session.application.id == application.id,
              session.application.launchURL == application.launchURL,
              MacWebNavigationPolicy.launchURL(for: application) != nil else { return }
        session.page.authorization?.updateApplication(application)
        session.application = application
        sessions[identifier] = session
        self.application = application
    }

    /// Returning to the native catalogue keeps the live page and its draft state.
    func close() {
        isPresented = false
        for page in pages.values { page.authorization?.invalidate() }
        hidePopups()
        for page in pages.values {
            let dialogs = Array(page.dialogs.values)
            page.dialogs.removeAll()
            dialogs.forEach { $0() }
        }
    }

    /// A withdrawn catalogue entry must no longer retain a runnable hidden page.
    /// The persisted website profile remains available only to its original owner.
    func terminate() {
        let identifier = activeProfileID
        close()
        activeProfileID = nil
        application = nil
        if let identifier { discardSession(identifier) }
        publishState()
    }

    func accountDidChange(_ uid: String?) {
        guard uid != accountID else { return }
        let continuation = authorizationBroker?.identityWillChange(to: uid) as? MacAuthorizationPage
        if accountID == nil, let uid, let continuation, let identifier = activeProfileID,
           var session = sessions[identifier], session.page.authorization === continuation, isPresented {
            do {
                let disposition = try profiles.bindGuestContinuation(session.profile, to: uid)
                switch disposition {
                case .adopted(let selected), .retained(let selected, _): session.profile = selected
                }
                sessions[identifier] = session
                // Popups never participate in the accepted login continuation.
                for page in Array(pages.values) where page !== session.page { discardPage(page) }
                accountID = uid
                authorizationBroker?.identityCookiesCleared()
                return
            } catch {
                authorizationBroker?.cancel(page: continuation)
            }
        }
        terminate()
        for identifier in Array(sessions.keys) { discardSession(identifier) }
        accountID = uid
    }

    private func configureAuthorization(for page: Page, application: CloudApplication) {
        guard !page.isPopup, let broker = authorizationBroker else { return }
        let authorization = MacAuthorizationPage(application: application, broker: broker,
                                                presentation: authorizationPresentation,
                                                isVisible: { [weak self, weak page] in
            guard let self, let page else { return false }
            guard let window = page.webView.window else { return false }
            return self.isPresented && self.activePage === page && window.isVisible
                && !window.isMiniaturized && !NSApp.isHidden
        }, documentURL: { [weak page] in page?.webView.url }, window: { [weak page] in page?.webView.window },
                                                makeSystemAuthorization: makeSystemAuthorization)
        page.authorization = authorization
        authorization.attach(to: page.webView)
    }

    private func websiteDataStore(for selection: WebProfileRepository.Selection) -> WKWebsiteDataStore {
        if let existing = websiteDataStores[selection.identifier] { return existing }
        let store = WKWebsiteDataStore(forIdentifier: selection.identifier)
        websiteDataStores[selection.identifier] = store
        return store
    }

    func back() {
        guard let page = activePage, page.webView.canGoBack else { return }
        page.failure = nil
        page.webView.goBack()
        publishState()
    }

    func forward() {
        guard let page = activePage, page.webView.canGoForward else { return }
        page.failure = nil
        page.webView.goForward()
        publishState()
    }

    func reload() {
        guard let page = activePage else { return }
        page.failure = nil
        if page.webView.url != nil {
            page.webView.reload()
        } else if let url = application.flatMap(MacWebNavigationPolicy.launchURL) {
            loadRequest(page.webView, URLRequest(url: url))
        }
        publishState()
    }

    private func makePage(configuration: WKWebViewConfiguration, profileID: UUID, isPopup: Bool = false) -> Page {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        let page = Page(webView: webView, profileID: profileID, isPopup: isPopup)
        pages[ObjectIdentifier(webView)] = page
        webView.navigationDelegate = self
        webView.uiDelegate = self
        page.observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishState() }
            },
        ]
        return page
    }

    private func publishState() {
        currentURL = activePage?.webView.url
        isLoading = activePage?.webView.isLoading ?? false
        canGoBack = activePage?.webView.canGoBack ?? false
        canGoForward = activePage?.webView.canGoForward ?? false
        error = activePage?.failure
    }

    private func hidePopups() {
        for page in pages.values where page.isPopup { page.window?.orderOut(nil) }
    }

    private func discardSession(_ identifier: UUID) {
        let ownedPages = pages.values.filter { $0.profileID == identifier }
        for page in ownedPages { discardPage(page) }
        sessions.removeValue(forKey: identifier)
    }

    private func discardPage(_ page: Page) {
        page.authorization?.detach()
        page.authorization = nil
        pages.removeValue(forKey: ObjectIdentifier(page.webView))
        page.observations.removeAll()
        page.webView.navigationDelegate = nil
        page.webView.uiDelegate = nil
        page.webView.stopLoading()
        // Accessibility clients or other external owners may keep the view
        // alive after it leaves our session. Replace the document as well as
        // revoking its bridge so that the old page's scripts cannot keep running
        // merely because WKWebView has not yet been deallocated.
        page.webView.loadHTMLString("", baseURL: nil)
        page.webView.removeFromSuperview()
        let dialogs = Array(page.dialogs.values)
        page.dialogs.removeAll()
        dialogs.forEach { $0() }
        page.window?.delegate = nil
        page.window?.close()
        page.window = nil
    }

    private func fail(_ page: Page, message: String) {
        page.failure = message
        if page.isPopup { page.window?.title = "加载失败 · " + (sessions[page.profileID]?.application.name ?? "云应用") }
        publishState()
    }

    private func showDialog(_ alert: NSAlert, in webView: WKWebView,
                            completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard isPresented, let page = pages[ObjectIdentifier(webView)], page.profileID == activeProfileID,
              let window = webView.window, window.isVisible, window.attachedSheet == nil else {
            completion(.cancel)
            return
        }
        let identifier = UUID()
        var finished = false
        let finish: (NSApplication.ModalResponse) -> Void = { [weak page] response in
            guard !finished else { return }
            finished = true
            page?.dialogs.removeValue(forKey: identifier)
            completion(response)
        }
        page.dialogs[identifier] = { [weak window] in
            window?.endSheet(alert.window)
            alert.window.orderOut(nil)
            finish(.cancel)
        }
        alert.beginSheetModal(for: window) { response in finish(response) }
    }

    private func dialog(title: String, message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (frame.request.url?.host.map { "来自 \($0)\n\n" } ?? "") + message
        return alert
    }
}

extension MacWebRuntime: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let page = pages[ObjectIdentifier(webView)] else { decisionHandler(.cancel); return }
        let mainFrame = navigationAction.targetFrame?.isMainFrame != false
        switch MacWebNavigationPolicy.decision(for: navigationAction.request.url,
                                               isMainFrame: mainFrame,
                                               userInitiated: navigationAction.navigationType == .linkActivated,
                                               allowsBlank: page.isPopup || navigationAction.targetFrame == nil) {
        case .allow:
            if navigationAction.targetFrame?.isMainFrame == true {
                if MacWebNavigationPolicy.isFragmentNavigation(from: webView.url, to: navigationAction.request.url,
                                                               isReload: navigationAction.navigationType == .reload) {
                    // Fragment navigation keeps the document and has no commit
                    // callback. Cancel its old request without disabling new ones.
                    page.authorization?.invalidate()
                } else { page.authorization?.navigationStarted() }
            }
            decisionHandler(.allow)
        case .openExternally:
            decisionHandler(.cancel)
            if isPresented, page.profileID == activeProfileID, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
        case .cancel:
            decisionHandler(.cancel)
            if mainFrame { fail(page, message: "已阻止不受支持的地址。应用页面仅支持安全的 HTTPS 连接。") }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let page = pages[ObjectIdentifier(webView)] else { decisionHandler(.cancel); return }
        let url = navigationResponse.response.url
        let allowed = MacWebNavigationPolicy.decision(for: url, isMainFrame: navigationResponse.isForMainFrame,
                                                      userInitiated: false, allowsBlank: page.isPopup) == .allow
        guard allowed, navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            if navigationResponse.isForMainFrame {
                fail(page, message: "此页面无法在应用内显示。文件下载暂不支持，请在浏览器中打开。")
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pages[ObjectIdentifier(webView)]?.authorization?.navigationStarted()
        pages[ObjectIdentifier(webView)]?.failure = nil
        publishState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pages[ObjectIdentifier(webView)]?.authorization?.documentCommitted()
        if let page = pages[ObjectIdentifier(webView)], page.isPopup {
            let host = webView.url?.host ?? "网页"
            page.window?.title = host + " · " + (sessions[page.profileID]?.application.name ?? "云应用")
        }
        publishState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(webView, error: error)
    }

    private func navigationFailed(_ webView: WKWebView, error: Error) {
        guard let page = pages[ObjectIdentifier(webView)],
              (error as NSError).code != NSURLErrorCancelled else { return }
        page.authorization?.navigationStarted()
        fail(page, message: "页面加载失败，请检查网络后重新载入。\n" + error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let page = pages[ObjectIdentifier(webView)] else { return }
        page.authorization?.navigationStarted()
        fail(page, message: "应用页面已停止运行，请重新载入。已保存的登录资料仍保留在本机。")
    }
}

extension MacWebRuntime: WKUIDelegate, NSWindowDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard isPresented, navigationAction.targetFrame == nil,
              let source = pages[ObjectIdentifier(webView)], source.profileID == activeProfileID,
              MacWebNavigationPolicy.decision(for: navigationAction.request.url, isMainFrame: true,
                                              userInitiated: false, allowsBlank: true) == .allow,
              pages.values.filter({ $0.isPopup && $0.profileID == source.profileID }).count < 4 else { return nil }
        // Preserve WebKit's supplied configuration and opener relationship. A
        // browser-tab handoff here would lose the profile and break popup OAuth.
        let page = makePage(configuration: configuration, profileID: source.profileID, isPopup: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "网页 · " + (sessions[source.profileID]?.application.name ?? "云应用")
        window.minSize = NSSize(width: 420, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView = page.webView
        window.delegate = self
        page.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        return page.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let page = pages[ObjectIdentifier(webView)], page.isPopup else { return }
        discardPage(page)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let page = pages.values.first(where: { $0.window === window }) else { return }
        page.window = nil
        discardPage(page)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = dialog(title: "网页提示", message: message, frame: frame)
        alert.addButton(withTitle: "好")
        showDialog(alert, in: webView) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = dialog(title: "网页确认", message: message, frame: frame)
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        showDialog(alert, in: webView) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = dialog(title: "网页输入", message: prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        showDialog(alert, in: webView) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
}
