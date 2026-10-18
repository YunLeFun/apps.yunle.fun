import WebKit
import OSLog

@MainActor
protocol ApplicationCacheDownloading {
    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data
}

/// A fresh, anonymous WebKit session downloads the page and its loaded resources.
/// It never receives host credentials, the running app's cookies, or a JS bridge.
@MainActor
final class ApplicationCacheDownloader: NSObject, ApplicationCacheDownloading, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeout: Task<Void, Never>?
    private var observation: NSKeyValueObservation?
    private var sourceURL: URL?
    private var capturing = false
    private var operationID = UUID()
    private var timeoutID = UUID()
    private var navigationStarted = false
    private var navigationAllowed = false
    private var startedAt: TimeInterval = 0
    private let logger = Logger(subsystem: "fun.yunle.apps", category: "cache-download")
    private let allowsCellularAccess: Bool
    private let allowsConstrainedNetworkAccess: Bool
    private let timeoutInterval: TimeInterval
    private let startupTimeoutInterval: TimeInterval
    private let makeWebView: @MainActor (WKWebViewConfiguration) -> WKWebView

    init(allowsCellularAccess: Bool = true, allowsConstrainedNetworkAccess: Bool = true,
         timeoutInterval: TimeInterval = 45, startupTimeoutInterval: TimeInterval = 90,
         makeWebView: @escaping @MainActor (WKWebViewConfiguration) -> WKWebView = {
             WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: $0)
         }) {
        self.allowsCellularAccess = allowsCellularAccess
        self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
        self.timeoutInterval = timeoutInterval; self.startupTimeoutInterval = startupTimeoutInterval
        self.makeWebView = makeWebView
        super.init()
    }

    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        try Task.checkCancellation()
        guard continuation == nil else { throw ApplicationCacheError.downloadFailed }
        let operation = UUID(); operationID = operation
        capturing = false; navigationStarted = false; navigationAllowed = false
        startedAt = ProcessInfo.processInfo.systemUptime
        record("preparing-engine")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.sourceURL = url
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.mediaTypesRequiringUserActionForPlayback = .all
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                let web = makeWebView(configuration)
                web.navigationDelegate = self
                web.uiDelegate = self
                webView = web
                observation = web.observe(\.estimatedProgress, options: [.new]) { web, _ in
                    progress(min(0.95, web.estimatedProgress * 0.95))
                }
                scheduleTimeout(for: operation, interval: startupTimeoutInterval)
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
                request.allowsCellularAccess = allowsCellularAccess
                request.allowsExpensiveNetworkAccess = allowsCellularAccess
                request.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
                web.load(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operationID == operation else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        guard let url = navigationAction.request.url, url.scheme == "https", url.user == nil, url.password == nil,
              navigationAction.targetFrame != nil,
              navigationAction.targetFrame?.isMainFrame != true || sourceURL.map({ ApplicationCacheRepository.sameOrigin(url, $0) }) == true else {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame == true { finish(.failure(ApplicationCacheError.downloadFailed)) }
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, !navigationAllowed {
            navigationAllowed = true; record("main-frame-navigation-allowed")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        if navigationResponse.isForMainFrame {
            guard let response = navigationResponse.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  ["text/html", "application/xhtml+xml"].contains(response.mimeType ?? "") else {
                decisionHandler(.cancel); finish(.failure(ApplicationCacheError.downloadFailed)); return
            }
            let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased().split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).split(separator: "=").first.map(String.init) ?? "" }
            if directives.contains("no-store") || directives.contains("private") {
                decisionHandler(.cancel); finish(.failure(ApplicationCacheError.notCacheable)); return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, continuation != nil, !capturing else { return }
        capturing = true
        record("capturing-archive")
        let operation = operationID
        webView.createWebArchiveData { [weak self, weak webView] result in
            guard let self, let webView, self.webView === webView, self.operationID == operation else { return }
            self.finish(result)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        startNavigation(in: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }; finish(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }; finish(.failure(error))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }; finish(.failure(ApplicationCacheError.downloadFailed))
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    private func startNavigation(in web: WKWebView) {
        guard web === webView, continuation != nil, !navigationStarted else { return }
        navigationStarted = true
        record("provisional-navigation-started")
        // Give WebKit startup and the actual navigation/archive separate bounded
        // budgets. Redirects and repeated callbacks cannot extend the latter.
        scheduleTimeout(for: operationID, interval: timeoutInterval)
    }

    private func scheduleTimeout(for operation: UUID, interval: TimeInterval) {
        timeout?.cancel()
        let deadline = UUID()
        timeoutID = deadline
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, let self,
                  self.operationID == operation, self.timeoutID == deadline else { return }
            self.finish(.failure(ApplicationCacheError.timedOut))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        switch result {
        case .success: record("archive-complete")
        case .failure(let error):
            let failure = error as NSError
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let phase = capturing ? "archive" : navigationStarted ? "navigation" : "engine"
            logger.error("operation=\(self.operationID.uuidString, privacy: .public) phase=\(phase, privacy: .public) elapsed=\(elapsed, privacy: .public) error-domain=\(failure.domain, privacy: .public) error-code=\(failure.code, privacy: .public)")
        }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        observation?.invalidate(); observation = nil
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView?.stopLoading(); webView = nil
        continuation.resume(with: result)
    }

    private func record(_ event: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        logger.notice("operation=\(self.operationID.uuidString, privacy: .public) event=\(event, privacy: .public) elapsed=\(elapsed, privacy: .public)")
    }
}
