import WebKit

@MainActor
protocol LegacyLocalDataReading {
    func read() async throws -> [String: String]
}

/// A one-shot local storage reader, not the former application or an auth SDK.
/// The sole document has no scripts, external resources or navigation links.
@MainActor
final class LegacyLocalDataReader: NSObject, LegacyLocalDataReading, WKNavigationDelegate {
    nonisolated static let url = URL(string: "capacitor://localhost/__native_data_import__/index.html")!
    private let dataStore: WKWebsiteDataStore
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var operationID: UUID?
    private var timeout: Task<Void, Never>?
    private let timeoutNanoseconds: UInt64

    init(dataStore: WKWebsiteDataStore? = nil, timeoutNanoseconds: UInt64 = 8_000_000_000) {
        self.dataStore = dataStore ?? .default(); self.timeoutNanoseconds = timeoutNanoseconds
    }

    func read() async throws -> [String: String] {
        let id = UUID()
        guard continuation == nil else { throw LegacyImportError.unreadable }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation; operationID = id
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = dataStore
                configuration.setURLSchemeHandler(LegacyImportSchemeHandler(), forURLScheme: "capacitor")
                let web = WKWebView(frame: .zero, configuration: configuration)
                web.navigationDelegate = self; webView = web
                timeout = Task { @MainActor [weak self] in
                    guard let duration = self?.timeoutNanoseconds else { return }
                    do { try await Task.sleep(nanoseconds: duration) } catch { return }
                    self?.finish(id, result: .failure(LegacyImportError.timedOut))
                }
                web.load(URLRequest(url: Self.url))
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, let id = operationID, webView.url == Self.url else { return }
        Task { @MainActor [weak self] in
            do {
                let value = try await webView.callAsyncJavaScript("""
                    const result = {}; let size = 0;
                    for (const key of keys) {
                        const value = localStorage.getItem(key);
                        if (value !== null) {
                            size += key.length + value.length;
                            if (size > 524288) throw new Error('storage limit');
                            if (key === 'ylf_saved_accounts') {
                                const accounts = JSON.parse(value);
                                if (!Array.isArray(accounts) || accounts.length > 10) throw new Error('account records');
                                result[key] = JSON.stringify(accounts.map(account => ({uid: account.uid, nickname: account.nickname})));
                            } else { result[key] = value; }
                        }
                    }
                    return result;
                    """, arguments: ["keys": LegacyLocalData.keys], in: nil, contentWorld: .page)
                guard let values = value as? [String: String] else { throw LegacyImportError.invalidData }
                self?.finish(id, result: .success(try LegacyLocalData(values: values).values))
            } catch { self?.finish(id, result: .failure(error as? LegacyImportError ?? .unreadable)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(webView) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(webView) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(self.webView === webView && navigationAction.request.url == Self.url
                        && navigationAction.targetFrame?.isMainFrame == true ? .allow : .cancel)
    }
    private func fail(_ webView: WKWebView) {
        guard self.webView === webView, let id = operationID else { return }
        finish(id, result: .failure(LegacyImportError.unreadable))
    }
    private func finish(_ id: UUID, result: Result<[String: String], Error>) {
        guard operationID == id else { return }
        operationID = nil; timeout?.cancel(); timeout = nil
        let completion = continuation; continuation = nil
        webView?.navigationDelegate = nil; webView?.stopLoading(); webView = nil
        completion?.resume(with: result)
    }
}

final class LegacyImportSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard urlSchemeTask.request.url == LegacyLocalDataReader.url else {
            urlSchemeTask.didFailWithError(LegacyImportError.unreadable); return
        }
        let data = Data("<html><head><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; base-uri 'none'; form-action 'none'\"></head><body></body></html>".utf8)
        urlSchemeTask.didReceive(URLResponse(url: LegacyLocalDataReader.url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
