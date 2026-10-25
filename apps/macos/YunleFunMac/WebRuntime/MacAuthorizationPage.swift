import AppKit
import AuthenticationServices
import WebKit

@MainActor
protocol MacAuthorizationPresenting: AnyObject {
    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool
    func showConsent(policy: HostSsoPolicy, user: AccountUser,
                     completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool
    func dismiss()
}

@MainActor
protocol MacSystemAuthorizationLaunching: AnyObject {
    func start(url: URL, window: NSWindow, completion: @escaping (URL?, Error?) -> Void) -> Bool
    func cancel()
}

@MainActor
private final class MacSystemAuthorization: NSObject, MacSystemAuthorizationLaunching,
                                              ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var window: NSWindow?

    func start(url: URL, window: NSWindow, completion: @escaping (URL?, Error?) -> Void) -> Bool {
        guard session == nil else { return false }
        self.window = window
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "yunlefun") { [weak self] url, error in
            Task { @MainActor in
                self?.session = nil
                self?.window = nil
                completion(url, error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        guard session.start() else { self.session = nil; self.window = nil; return false }
        return true
    }

    func cancel() {
        let current = session
        session = nil
        window = nil
        current?.cancel()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }
}

/// One main document's bridge transport and pending reply. The shared broker
/// owns account/registry decisions; this adapter owns WebKit document lifetime.
@MainActor
final class MacAuthorizationPage: NSObject, HostAuthorizationPage, WKScriptMessageHandlerWithReply {
    struct Source {
        let isMainFrame: Bool
        let scheme: String
        let host: String
        let port: Int
        let frameURL: URL?
    }

    private final class Pending {
        let id: String
        let generation: UUID
        let documentURL: URL
        let origin: String
        let parameters: [String: Any]
        let reply: (Any?, String?) -> Void
        var timeout: DispatchWorkItem?

        init(id: String, generation: UUID, documentURL: URL, origin: String,
             parameters: [String: Any], reply: @escaping (Any?, String?) -> Void) {
            self.id = id; self.generation = generation; self.documentURL = documentURL
            self.origin = origin; self.parameters = parameters; self.reply = reply
        }
    }

    private weak var webView: WKWebView?
    private weak var broker: NativeAuthorizationBroker?
    private let presentation: MacAuthorizationPresenting?
    private let isVisible: () -> Bool
    private let documentURL: () -> URL?
    private let window: () -> NSWindow?
    private let makeSystemAuthorization: @MainActor () -> MacSystemAuthorizationLaunching
    private let systemAuthorizationTimeout: TimeInterval
    private var application: CloudApplication
    private var generation = UUID()
    private var documentReady = false
    private var pending: Pending?
    private var systemAuthorization: MacSystemAuthorizationLaunching?
    private weak var attachedController: WKUserContentController?
    private weak var presentationWindow: NSWindow?
    private var visibilityObservers: [NSObjectProtocol] = []

    init(application: CloudApplication, broker: NativeAuthorizationBroker,
         presentation: MacAuthorizationPresenting?, isVisible: @escaping () -> Bool,
         documentURL: @escaping () -> URL?, window: @escaping () -> NSWindow?,
         makeSystemAuthorization: (@MainActor () -> MacSystemAuthorizationLaunching)? = nil,
         systemAuthorizationTimeout: TimeInterval = 300) {
        self.application = application; self.broker = broker; self.presentation = presentation
        self.isVisible = isVisible; self.documentURL = documentURL; self.window = window
        self.makeSystemAuthorization = makeSystemAuthorization ?? { MacSystemAuthorization() }
        self.systemAuthorizationTimeout = systemAuthorizationTimeout
        super.init()
    }

    deinit { visibilityObservers.forEach(NotificationCenter.default.removeObserver) }

    func attach(to webView: WKWebView) {
        self.webView = webView
        let controller = webView.configuration.userContentController
        attachedController = controller
        controller.addScriptMessageHandler(self, contentWorld: .page, name: "ylf")
        controller.addUserScript(WKUserScript(source: YunleHostBridgeScript.source,
                                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSApplication.didHideNotification] {
            visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if notification.name == NSApplication.didHideNotification {
                        self.invalidate()
                    } else if let changed = notification.object as? NSWindow,
                              changed === (self.webView?.window ?? self.presentationWindow),
                              notification.name != NSWindow.didChangeOcclusionStateNotification || !changed.isVisible {
                        self.invalidate()
                    }
                }
            })
        }
    }

    func updateApplication(_ application: CloudApplication) {
        if self.application.runtimeTrustedHosts != application.runtimeTrustedHosts { invalidate() }
        self.application = application
    }

    func navigationStarted() { documentReady = false; invalidate() }
    func documentCommitted() { documentReady = true; presentationWindow = webView?.window }

    func invalidate() {
        generation = UUID()
        broker?.cancel(page: self)
        if let pending { resolve(pending.id, result: nil, error: HostAuthorizationError.denied.code) }
        presentation?.dismiss()
        systemAuthorization?.cancel()
        systemAuthorization = nil
    }

    func detach() {
        documentReady = false
        invalidate()
        attachedController?.removeScriptMessageHandler(forName: "ylf", contentWorld: .page)
        attachedController?.removeAllUserScripts()
        attachedController = nil
        visibilityObservers.forEach(NotificationCenter.default.removeObserver)
        visibilityObservers.removeAll()
        presentationWindow = nil
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        // A popup may inherit the opener's controller. Never register a new
        // privileged handler on its supplied configuration or trust its message.
        guard let webView, message.webView === webView else {
            replyHandler(nil, "HOST_AUTH_FORBIDDEN"); return
        }
        let origin = message.frameInfo.securityOrigin
        receive(message.body, source: Source(isMainFrame: message.frameInfo.isMainFrame,
                                            scheme: origin.protocol, host: origin.host, port: origin.port,
                                            frameURL: message.frameInfo.request.url), reply: replyHandler)
    }

    // Kept separate from WKScriptMessage construction so origin/document races
    // are testable without forging WebKit's read-only security-origin objects.
    func receive(_ body: Any, source: Source, reply: @escaping (Any?, String?) -> Void) {
        guard documentReady, isVisible(), source.isMainFrame,
              let currentURL = documentURL(), let sourceOrigin = validatedOrigin(source, currentURL: currentURL),
              let body = body as? [String: Any], let method = body["method"] as? String,
              JSONSerialization.isValidJSONObject(body),
              let bytes = try? JSONSerialization.data(withJSONObject: body), bytes.count <= 16_384 else {
            reply(nil, "HOST_AUTH_FORBIDDEN"); return
        }
        let parameters = body["params"] as? [String: Any] ?? [:]
        let trusted = MacWebNavigationPolicy.isTrustedForAuthorization(currentURL, application: application)
        switch method {
        case "canIUse":
            let capability = parameters["method"] as? String ?? ""
            reply(["canIUse", "getEnv"].contains(capability) || (capability == "authorize" && trusted && broker != nil), nil)
        case "getEnv":
            reply(["platform": "macos", "appId": application.id, "displayMode": "titlebar",
                   "trusted": trusted, "capsuleVisible": false, "titleBarVisible": true,
                   "safeAreaInsets": ["top": 0, "bottom": 0, "left": 0, "right": 0]], nil)
        case "authorize":
            guard trusted, let broker else { reply(nil, "HOST_AUTH_FORBIDDEN"); return }
            guard pending == nil else { reply(nil, HostAuthorizationError.unavailable.code); return }
            let request = Pending(id: UUID().uuidString, generation: generation, documentURL: currentURL,
                                  origin: sourceOrigin, parameters: parameters, reply: reply)
            pending = request
            arm(request, seconds: 30)
            broker.begin(requestID: request.id, sourceOrigin: sourceOrigin, parameters: parameters, page: self)
        default:
            reply(nil, "HOST_API_UNSUPPORTED")
        }
    }

    private func validatedOrigin(_ source: Source, currentURL: URL) -> String? {
        guard source.scheme.lowercased() == "https", !source.host.isEmpty,
              MacWebNavigationPolicy.sameDocumentIgnoringFragment(source.frameURL, currentURL),
              let current = MacWebNavigationPolicy.origin(of: currentURL),
              MacWebNavigationPolicy.origin(of: source.frameURL) == current else { return nil }
        let port = source.port == 0 ? 443 : source.port
        let host = source.host.lowercased()
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let actual = "https://\(authority)\(port == 443 ? "" : ":\(port)")"
        return actual == current ? actual : nil
    }

    private func isCurrent(_ request: Pending) -> Bool {
        pending === request && request.generation == generation && documentReady && isVisible()
            && documentURL() == request.documentURL
            && MacWebNavigationPolicy.origin(of: documentURL()) == request.origin
            && MacWebNavigationPolicy.isTrustedForAuthorization(request.documentURL, application: application)
    }

    func isPending(_ requestID: String) -> Bool {
        guard let pending, pending.id == requestID else { return false }
        return isCurrent(pending)
    }

    func pause(_ requestID: String) -> Bool {
        guard let pending, pending.id == requestID, isCurrent(pending) else { return false }
        arm(pending, seconds: 300)
        return true
    }

    func resume(_ requestID: String) -> Bool {
        guard let pending, pending.id == requestID, isCurrent(pending) else { return false }
        arm(pending, seconds: 30)
        return true
    }

    func resolve(_ requestID: String, result: [String: Any]?, error: String?) {
        guard let request = pending, request.id == requestID else { return }
        let valid = isCurrent(request)
        pending = nil
        request.timeout?.cancel()
        request.timeout = nil
        systemAuthorization?.cancel()
        systemAuthorization = nil
        if let error { request.reply(nil, error) }
        else if valid { request.reply(result ?? [:], nil) }
        else { request.reply(nil, HostAuthorizationError.denied.code) }
    }

    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard let pending, isCurrent(pending) else { return false }
        return presentation?.showLogin(application: application, completion: completion) ?? false
    }

    func showConsent(policy: HostSsoPolicy, user: AccountUser,
                     completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        guard let pending, isCurrent(pending) else { return false }
        return presentation?.showConsent(policy: policy, user: user, completion: completion) ?? false
    }

    func dismissAuthorizationUI() { presentation?.dismiss() }

    func useOtherAccount(_ requestID: String) -> Bool {
        guard let pending, pending.id == requestID, isCurrent(pending), systemAuthorization == nil,
              let window = window(), let request = NativeSsoProtocol.readRequest(pending.parameters),
              let state = NativeSsoProtocol.randomState(),
              let url = NativeSsoProtocol.authorizationURL(request: request, state: state) else { return false }
        let system = makeSystemAuthorization()
        systemAuthorization = system
        arm(pending, seconds: systemAuthorizationTimeout)
        let started = system.start(url: url, window: window) { [weak self, weak pending] callback, error in
            // Ignore callbacks owned by an already-completed request. If this
            // request still owns the reply but its document is no longer valid,
            // complete it now instead of blocking retries until the deadline.
            guard let self, let pending, self.pending === pending else { return }
            guard self.isCurrent(pending) else {
                self.resolve(requestID, result: nil, error: HostAuthorizationError.denied.code)
                return
            }
            self.systemAuthorization = nil
            if let callback, let result = NativeSsoProtocol.readCallback(callback, expectedState: state, request: request) {
                switch result {
                case .success(let code, let issuer):
                    self.resolve(requestID, result: ["ok": true, "code": code, "issuer": issuer], error: nil)
                case .denied:
                    self.resolve(requestID, result: nil, error: HostAuthorizationError.denied.code)
                }
            } else {
                let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                self.resolve(requestID, result: nil, error: cancelled ? HostAuthorizationError.denied.code : HostAuthorizationError.unavailable.code)
            }
        }
        if !started { systemAuthorization = nil }
        return started
    }

    private func arm(_ request: Pending, seconds: TimeInterval) {
        request.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak request] in
            guard let self, let request, self.pending === request else { return }
            self.invalidate()
        }
        request.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }
}
