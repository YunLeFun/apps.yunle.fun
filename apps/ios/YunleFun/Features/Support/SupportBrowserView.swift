import SwiftUI
import WebKit

/// An isolated, in-memory browser for the remaining Support workflows.
/// Only Support's HttpOnly cookies cross from the native client into WebKit.
struct SupportBrowserView: View {
    let page: SupportBrowserPage
    @StateObject private var browser = SupportBrowserModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if browser.ready { SupportWebView(browser: browser) }
                else { ProgressView("正在打开支持中心") }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = browser.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                        Button("重新载入") { browser.webView.reload() }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.background)
                } else if browser.loading { ProgressView().padding(6) }
            }
            .navigationTitle("云乐坊支持中心").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("support.browser.close")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if browser.canGoBack {
                        Button { browser.webView.goBack() } label: { Label("返回上一页", systemImage: "chevron.backward") }
                    }
                    Button { browser.webView.reload() } label: { Label("重新载入", systemImage: "arrow.clockwise") }
                }
            }
        }
        .task { await browser.load(page) }
        .onDisappear { browser.webView.stopLoading() }
        .sheet(item: $browser.externalPage) { SafariView(url: $0.url) }
        .onChange(of: browser.externalAction) { url in
            if let url { openURL(url); browser.externalAction = nil }
        }
    }
}

private struct SupportExternalPage: Identifiable { let id = UUID(); let url: URL }

@MainActor
private final class SupportBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var ready = false
    @Published var loading = false
    @Published var canGoBack = false
    @Published var error: String?
    @Published var externalPage: SupportExternalPage?
    @Published var externalAction: URL?
    private var historyObservation: NSKeyValueObservation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Presentation only: Support keeps all authorization checks on its API.
        configuration.applicationNameForUserAgent = "YunleFunSupport/1"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        historyObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
            Task { @MainActor [weak self] in self?.canGoBack = view.canGoBack }
        }
    }

    func load(_ page: SupportBrowserPage) async {
        guard !ready, SupportCenterService.isSupportURL(page.url) else { return }
        for cookie in page.access?.cookies ?? [] {
            guard cookie.domain == SupportCenterService.origin.host, cookie.isSecure else { continue }
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
            }
            guard !Task.isCancelled else { return }
        }
        guard !Task.isCancelled else { return }
        ready = true
        webView.load(URLRequest(url: page.url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Leave subframes to WebKit's same-origin policies, but never move the
        // authenticated top-level browser onto an unrelated origin.
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if SupportCenterService.isSupportURL(url) {
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel); webView.load(navigationAction.request)
            } else { decisionHandler(.allow) }
        } else {
            decisionHandler(.cancel)
            if url.scheme == "https" || url.scheme == "http" { externalPage = SupportExternalPage(url: url) }
            else if ["mailto", "weixin"].contains(url.scheme ?? "") { externalAction = url }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; canGoBack = webView.canGoBack
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false; error = "页面已暂停，请重新载入。"
    }
    private func failed(_ error: Error) {
        loading = false
        guard (error as? URLError)?.code != .cancelled else { return }
        self.error = "页面暂时无法打开，请检查网络后重试。"
    }
}

private struct SupportWebView: UIViewRepresentable {
    let browser: SupportBrowserModel
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
