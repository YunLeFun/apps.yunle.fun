import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationCacheDownloaderTests: XCTestCase {
    func testNavigationGetsFullDeadlineAfterEngineStartup() async throws {
        // WebKit's data-only navigation objects must come from a real callback.
        let recorder = CacheNavigationRecorder()
        let setupConfiguration = WKWebViewConfiguration()
        setupConfiguration.websiteDataStore = .nonPersistent()
        let setupWeb = WKWebView(frame: .zero, configuration: setupConfiguration)
        setupWeb.navigationDelegate = recorder
        setupWeb.load(URLRequest(url: URL(string: "https://cache.example/")!))
        defer { setupWeb.stopLoading() }
        for _ in 0..<1200 {
            if recorder.action != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let action = try XCTUnwrap(recorder.action)
        var view: StalledCacheWebView?
        let downloader = ApplicationCacheDownloader(timeoutInterval: 1, startupTimeoutInterval: 1, makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            view = web; return web
        })
        let task = Task { try await downloader.download(URL(string: "https://cache.example/")!, progress: { _ in }) }
        defer { task.cancel() }
        try await wait { view?.request != nil }
        let web = try XCTUnwrap(view), delegate: WKNavigationDelegate = downloader
        downloader.webView(web, decidePolicyFor: action) { policy in XCTAssertEqual(policy, .allow) }
        try await Task.sleep(nanoseconds: 650_000_000)
        delegate.webView?(web, didStartProvisionalNavigation: nil)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(web.stopped, "Navigation must still have time to finish after engine startup")
        if web.stopped { _ = try? await task.value; return }
        downloader.webView(web, didFinish: nil)
        web.archiveCompletion?(.success(Data("current".utf8)))
        let archive = try await task.value
        XCTAssertEqual(archive, Data("current".utf8), "Engine startup must not consume the navigation and archive budget")
    }

    func testStartupDeadlineStopsAnEngineWithoutNavigation() async throws {
        var view: StalledCacheWebView?
        let downloader = ApplicationCacheDownloader(timeoutInterval: 2, startupTimeoutInterval: 0.2, makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            view = web; return web
        })
        let task = Task { try await downloader.download(URL(string: "https://cache.example/")!, progress: { _ in }) }
        defer { task.cancel() }
        try await wait { view?.request != nil }
        let web = try XCTUnwrap(view)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(web.stopped, "An engine that never starts navigation must have its own finite deadline")
        if !web.stopped { task.cancel(); _ = try? await task.value; return }
        do { _ = try await task.value; XCTFail("A stalled engine must time out") }
        catch ApplicationCacheError.timedOut { }
    }

    func testRepeatedNavigationStartsCannotExtendDeadline() async throws {
        var view: StalledCacheWebView?
        let downloader = ApplicationCacheDownloader(timeoutInterval: 0.4, makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            view = web; return web
        })
        let task = Task { try await downloader.download(URL(string: "https://cache.example/")!, progress: { _ in }) }
        defer { task.cancel() }
        try await wait { view?.request != nil }
        let web = try XCTUnwrap(view), delegate: WKNavigationDelegate = downloader
        for _ in 0..<10 {
            delegate.webView?(web, didStartProvisionalNavigation: nil)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(web.stopped, "Repeated main-frame starts must not keep a stalled download alive")
        if !web.stopped { task.cancel(); _ = try? await task.value; return }
        do { _ = try await task.value; XCTFail("A stalled navigation must time out") }
        catch ApplicationCacheError.timedOut { }
    }

    func testTimeoutStopsLoadingAndLateArchiveCannotCompleteRetry() async throws {
        var views: [StalledCacheWebView] = []
        let downloader = ApplicationCacheDownloader(timeoutInterval: 0.2, makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            views.append(web); return web
        })
        let url = URL(string: "https://cache.example/")!
        let first = Task { try await downloader.download(url, progress: { _ in }) }
        try await wait { views.count == 1 && views[0].request != nil }
        downloader.webView(views[0], didStartProvisionalNavigation: nil)
        downloader.webView(views[0], didFinish: nil)
        do { _ = try await first.value; XCTFail("A stalled archive must time out") }
        catch ApplicationCacheError.timedOut { }
        XCTAssertTrue(views[0].stopped)
        XCTAssertNil(views[0].navigationDelegate)
        let retry = Task { try await downloader.download(url, progress: { _ in }) }
        try await wait { views.count == 2 && views[1].request != nil }
        // Simulate WebKit completing the previous capture after cancellation.
        views[0].archiveCompletion?(.success(Data("stale".utf8)))
        downloader.webView(views[1], didFinish: nil)
        views[1].archiveCompletion?(.success(Data("current".utf8)))
        let result = try await retry.value
        XCTAssertEqual(result, Data("current".utf8))
    }

    func testCancelledNavigationCallbacksCannotFailTheNextDownload() async throws {
        var views: [StalledCacheWebView] = []
        let downloader = ApplicationCacheDownloader(makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            views.append(web); return web
        })
        let url = URL(string: "https://cache.example/")!
        let first = Task { try await downloader.download(url, progress: { _ in }) }
        try await wait { views.count == 1 && views[0].request != nil }
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancellation must finish the operation") }
        catch is CancellationError { }
        XCTAssertTrue(views[0].stopped)
        let retry = Task { try await downloader.download(url, progress: { _ in }) }
        try await wait { views.count == 2 && views[1].request != nil }
        downloader.webView(views[0], didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        downloader.webViewWebContentProcessDidTerminate(views[0])
        downloader.webView(views[1], didFinish: nil)
        views[1].archiveCompletion?(.success(Data("current".utf8)))
        let result = try await retry.value
        XCTAssertEqual(result, Data("current".utf8))
    }

    func testAutomaticRequestDisablesCellularExpensiveAndConstrainedAccess() async throws {
        var view: StalledCacheWebView?
        let downloader = ApplicationCacheDownloader(allowsCellularAccess: false, allowsConstrainedNetworkAccess: false,
                                                    makeWebView: { configuration in
            let web = StalledCacheWebView(frame: .zero, configuration: configuration)
            view = web; return web
        })
        let task = Task { try await downloader.download(URL(string: "https://cache.example/")!, progress: { _ in }) }
        try await wait { view?.request != nil }
        let web = try XCTUnwrap(view), request = try XCTUnwrap(web.request)
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(request.allowsCellularAccess)
        XCTAssertFalse(request.allowsExpensiveNetworkAccess)
        XCTAssertFalse(request.allowsConstrainedNetworkAccess)
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError { }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Downloader did not start")
        throw URLError(.timedOut)
    }
}

@MainActor
private final class CacheNavigationRecorder: NSObject, WKNavigationDelegate {
    var action: WKNavigationAction?
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true { action = navigationAction }
        decisionHandler(.cancel)
    }
}

@MainActor
private final class StalledCacheWebView: WKWebView {
    // Deliver only the callbacks selected by each regression, rather than real
    // WebKit initialization failures from this non-navigating test double.
    private weak var assignedNavigationDelegate: WKNavigationDelegate?
    override var navigationDelegate: WKNavigationDelegate? {
        get { assignedNavigationDelegate }
        set { assignedNavigationDelegate = newValue }
    }
    var request: URLRequest?
    var stopped = false
    var archiveCompletion: ((Result<Data, Error>) -> Void)?
    override func load(_ request: URLRequest) -> WKNavigation? { self.request = request; return nil }
    override func stopLoading() { stopped = true }
    // The public Objective-C API underlying WebKit's non-overridable Swift Result overlay.
    override func __createWebArchiveData(completionHandler: @escaping @MainActor @Sendable (Data?, Error?) -> Void) {
        archiveCompletion = { result in
            switch result {
            case .success(let data): completionHandler(data, nil)
            case .failure(let error): completionHandler(nil, error)
            }
        }
    }
}
