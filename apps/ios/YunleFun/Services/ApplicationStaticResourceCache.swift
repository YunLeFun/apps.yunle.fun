import Foundation
import WebKit

/// Only these first-party sites opt into resource-only downloads. Never archive
/// their HTML: even an anonymous document can contain a login redirect or SSR data.
enum ApplicationStaticResourcePolicy {
    static func origin(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), ["admin.yunle.fun", "support.yunle.fun"].contains(host) else { return nil }
        return URL(string: "https://\(host)/")
    }

    static func supports(_ application: CloudApplication) -> Bool {
        guard #available(iOS 17, *), application.isUnavailable != true, let url = application.launchURL else { return false }
        return origin(for: url) != nil
    }

    static func permits(_ url: URL, from origin: URL) -> Bool {
        ApplicationCacheRepository.sameOrigin(url, origin) && url.query == nil && url.fragment == nil
            && url.path.range(of: #"^/_nuxt/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
            && !url.absoluteString.contains("%")
            && ["js", "css", "woff", "woff2", "png", "jpg", "jpeg", "webp", "svg", "avif", "ico"].contains(url.pathExtension.lowercased())
    }

    static func navigationRequest(to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // Keep useProtocolCachePolicy so child scripts/styles retain normal
        // cache behavior. Only the live document carries this request header.
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func isPublic(_ response: HTTPURLResponse) -> Bool {
        let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return response.statusCode == 200 && directives.contains("public")
            && !directives.contains(where: { ["private", "no-store", "no-cache"].contains($0.split(separator: "=").first.map(String.init) ?? "") })
            && directives.contains(where: { directive in
                let parts = directive.split(separator: "=", maxSplits: 1)
                return parts.count == 2 && parts[0] == "max-age" && (Int(parts[1]) ?? 0) > 0
            }) && response.value(forHTTPHeaderField: "Set-Cookie") == nil
            && !(response.value(forHTTPHeaderField: "Vary") ?? "").lowercased().split(separator: ",")
                .contains(where: { ["*", "cookie", "authorization"].contains($0.trimmingCharacters(in: .whitespaces)) })
    }

    /// Treat references only as URLs, never execute downloaded JavaScript.
    /// Nuxt's entry module lists both immediate imports and lazy route chunks.
    static func references(in text: String, relativeTo base: URL, origin: URL) -> [URL] {
        let pattern = #"[\"'(`](?<url>(?:\./|/_nuxt/|https://)[^\s\"'`<>\)]+\.(?:js|css|woff2?|png|jpe?g|webp|svg|avif|ico))[\"'`\)]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard let url = URL(string: source.substring(with: match.range(withName: "url")), relativeTo: base)?.absoluteURL,
                  permits(url, from: origin) else { return nil }
            return url
        }
    }
}

struct ApplicationStaticResourceReceipt: Codable {
    struct Resource: Codable { let url: URL; let byteCount: Int }
    let origin: URL
    let profileIdentifier: UUID
    let resources: [Resource]
    var byteCount: Int { resources.reduce(0) { $0 + $1.byteCount } }

    func validate(for url: URL) throws {
        guard origin == ApplicationStaticResourcePolicy.origin(for: url), !resources.isEmpty,
              resources.count <= 512, Set(resources.map(\.url)).count == resources.count,
              resources.allSatisfy({ $0.byteCount > 0 && $0.byteCount <= ApplicationCacheRepository.maximumArchiveBytes
                  && ApplicationStaticResourcePolicy.permits($0.url, from: origin) }),
              byteCount <= ApplicationCacheRepository.maximumArchiveBytes else { throw ApplicationCacheError.invalidArchive }
    }
}

/// Uses the browser's actual persistent network cache. URLSession's cache is
/// separate from WebKit and cannot accelerate a WKWebView's subresource loads.
@MainActor
final class ApplicationStaticResourceCache {
    var profile: ((CloudApplication) throws -> UUID)?
    private let defaults: UserDefaults
    private static let registryKey = "applicationCache.publicResourceProfiles.v1"
    private static let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func register(_ identifier: UUID, origin: URL) {
        guard ApplicationStaticResourcePolicy.origin(for: origin) == origin else { return }
        var registry = defaults.dictionary(forKey: Self.registryKey) as? [String: [String]] ?? [:]
        registry[origin.absoluteString] = Array(Set((registry[origin.absoluteString] ?? []) + [identifier.uuidString]))
        defaults.set(registry, forKey: Self.registryKey)
    }

    func downloader(for application: CloudApplication, wifiOnly: Bool) throws -> ApplicationCacheDownloading {
        guard #available(iOS 17, *), let identifier = try profile?(application),
              let url = application.launchURL, let origin = ApplicationStaticResourcePolicy.origin(for: url) else {
            throw ApplicationCacheError.unsupported
        }
        // Register before the first request, so cancelled/failed partial downloads
        // can also be removed by Clear All without touching cookies or storage.
        register(identifier, origin: origin)
        return ApplicationStaticResourceDownloader(identifier: identifier, wifiOnly: wifiOnly)
    }

    func clear(id: String? = nil) async {
        guard #available(iOS 17, *) else { return }
        let registry = defaults.dictionary(forKey: Self.registryKey) as? [String: [String]] ?? [:]
        let origins = registry.keys.filter { origin in
            id == nil || id == ApplicationCacheEntry.key(for: CloudApplication(id: "public-resources", name: "", websiteUrl: origin))
        }
        for key in origins {
            for raw in registry[key] ?? [] {
                guard let identifier = UUID(uuidString: raw) else { continue }
                let store = WKWebsiteDataStore(forIdentifier: identifier)
                await store.removeData(ofTypes: Self.cacheTypes, modifiedSince: .distantPast)
            }
        }
        // Keep identifiers (never contents) so a running page that naturally
        // refills its HTTP cache can still be cleaned again without reopening.
    }
}

/// Anonymous discovery plus public-asset fetches in an inert same-origin
/// document: no site scripts, host bridge, API calls, or saved HTML are involved.
@MainActor
final class ApplicationStaticResourceDownloader: NSObject, ApplicationCacheDownloading, WKNavigationDelegate, URLSessionTaskDelegate {
    private let identifier: UUID
    private let wifiOnly: Bool
    private var origin: URL?
    private var web: WKWebView?
    private var session: URLSession?

    init(identifier: UUID, wifiOnly: Bool) { self.identifier = identifier; self.wifiOnly = wifiOnly }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        // Discovery can reach /login, but never another site or an API endpoint.
        let allowed = request.url.flatMap(ApplicationStaticResourcePolicy.origin(for:))
            == task.originalRequest?.url.flatMap(ApplicationStaticResourcePolicy.origin(for:))
        completionHandler(allowed && request.url?.path.hasPrefix("/api/") != true ? request : nil)
    }

    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        try await withTaskCancellationHandler {
            try await performDownload(url, progress: progress)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func performDownload(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        try Task.checkCancellation()
        guard #available(iOS 17, *), let origin = ApplicationStaticResourcePolicy.origin(for: url), web == nil else {
            throw ApplicationCacheError.unsupported
        }
        self.origin = origin
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsCellularAccess = !wifiOnly; configuration.allowsExpensiveNetworkAccess = !wifiOnly
        configuration.allowsConstrainedNetworkAccess = false
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 135
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        defer { session.invalidateAndCancel(); self.session = nil; web?.stopLoading(); web?.navigationDelegate = nil; web = nil }
        let deadline = Date().addingTimeInterval(135)
        // Always discover from the site's public root, never a token-bearing launch URL.
        let (html, response) = try await session.data(from: origin)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType == "text/html", let finalURL = response.url,
              ApplicationCacheRepository.sameOrigin(finalURL, origin), html.count <= 2 * 1024 * 1024 else {
            throw ApplicationCacheError.downloadFailed
        }
        var queue = ApplicationStaticResourcePolicy.references(in: String(decoding: html, as: UTF8.self), relativeTo: finalURL, origin: origin)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        let web = WKWebView(frame: .zero, configuration: config)
        self.web = web; web.navigationDelegate = self
        web.loadSimulatedRequest(URLRequest(url: origin), responseHTML: "<html><head><title>resource-cache</title></head><body></body></html>")
        while (try? await web.evaluateJavaScript("document.title")) as? String != "resource-cache" {
            try check(deadline); try await Task.sleep(nanoseconds: 50_000_000)
        }
        var visited = Set<URL>(), resources: [ApplicationStaticResourceReceipt.Resource] = [], total = 0
        while !queue.isEmpty {
            try check(deadline)
            var batch: [URL] = []
            while !queue.isEmpty, batch.count < 12 {
                let next = queue.removeFirst()
                if visited.insert(next).inserted { batch.append(next) }
            }
            guard visited.count <= 512 else { throw ApplicationCacheError.tooLarge }
            // Anonymous, non-storing discovery verifies policy before allowing
            // these public URLs into the browser's persistent network cache.
            let fetched = try await withThrowingTaskGroup(of: (URL, Data).self) { group in
                for next in batch {
                    group.addTask {
                        let (data, result) = try await session.data(from: next)
                        guard let result = result as? HTTPURLResponse, result.url == next,
                              ApplicationStaticResourcePolicy.isPublic(result) else { throw ApplicationCacheError.notCacheable }
                        return (next, data)
                    }
                }
                var values: [(URL, Data)] = []
                for try await value in group { values.append(value) }
                return values.sorted { $0.0.absoluteString < $1.0.absoluteString }
            }
            for (next, data) in fetched {
                total += data.count
                guard total <= ApplicationCacheRepository.maximumArchiveBytes else { throw ApplicationCacheError.tooLarge }
                if ["js", "css"].contains(next.pathExtension) {
                    queue += ApplicationStaticResourcePolicy.references(in: String(decoding: data, as: UTF8.self), relativeTo: next, origin: origin)
                }
            }
            try check(deadline)
            let counts = try await web.callAsyncJavaScript("""
                globalThis.resourceCacheAbort = new AbortController();
                const timer = setTimeout(() => resourceCacheAbort.abort(), 20000);
                try {
                    return await Promise.all(urls.map(async url => {
                        const response = await fetch(url, { credentials: 'same-origin', redirect: 'error', cache: 'default', signal: resourceCacheAbort.signal });
                        const policy = (response.headers.get('cache-control') || '').toLowerCase();
                        if (!response.ok || !policy.includes('public') || /(?:private|no-store|no-cache)/.test(policy)) throw Error('Not public');
                        return (await response.arrayBuffer()).byteLength;
                    }));
                } finally { clearTimeout(timer); }
                """, arguments: ["urls": fetched.map { $0.0.absoluteString }], in: nil, contentWorld: .defaultClient) as? [Int]
            guard counts == fetched.map({ $0.1.count }), fetched.allSatisfy({ !$0.1.isEmpty }) else { throw ApplicationCacheError.downloadFailed }
            // Prime the resource type the page will use, too. A raw fetch has
            // different memory-cache options from a module/style/font load.
            let typedResources = fetched.map(\.0)
            if !typedResources.isEmpty {
                _ = try await web.callAsyncJavaScript("""
                    await Promise.all(urls.map(url => new Promise((resolve, reject) => {
                        const link = document.createElement('link');
                        if (url.endsWith('.js')) { link.rel = 'modulepreload'; link.crossOrigin = 'anonymous'; }
                        else if (url.endsWith('.css')) { link.rel = 'preload'; link.as = 'style'; }
                        else if (/[.]woff2?$/.test(url)) { link.rel = 'preload'; link.as = 'font'; link.crossOrigin = 'anonymous'; }
                        else { link.rel = 'preload'; link.as = 'image'; }
                        link.href = url;
                        const timer = setTimeout(() => { link.remove(); reject(Error('Preload timeout')); }, 20000);
                        link.onload = () => { clearTimeout(timer); link.remove(); resolve(true); };
                        link.onerror = () => { clearTimeout(timer); link.remove(); reject(Error('Preload failed')); };
                        document.head.append(link);
                    })));
                    return true;
                    """, arguments: ["urls": typedResources.map(\.absoluteString)], in: nil, contentWorld: .defaultClient)
            }
            resources += fetched.map { .init(url: $0.0, byteCount: $0.1.count) }
            progress(min(0.95, Double(visited.count) / Double(visited.count + Set(queue).subtracting(visited).count + 1)))
        }
        try check(deadline)
        let receipt = ApplicationStaticResourceReceipt(origin: origin, profileIdentifier: identifier, resources: resources)
        try receipt.validate(for: url)
        progress(1)
        return try JSONEncoder().encode(receipt)
    }

    func cancel() {
        session?.invalidateAndCancel()
        web?.evaluateJavaScript("globalThis.resourceCacheAbort?.abort()", in: nil, in: .defaultClient, completionHandler: nil)
        web?.stopLoading()
    }

    private func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw ApplicationCacheError.timedOut }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only our inert simulated document can navigate this download engine.
        decisionHandler(navigationAction.request.url == origin ? .allow : .cancel)
    }
}
