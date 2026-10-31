import Combine
import CryptoKit
import Foundation
import Network
import WebKit

enum NativeGameResourceCacheError: LocalizedError {
    case unsupported, invalidManifest, invalidResource, tooLarge, notPublic, integrity, notCached, busy, quota, storage, networkRestricted
    var errorDescription: String? {
        switch self {
        case .unsupported: return "游戏资源准备需要 iOS 17 或更新版本。"
        case .invalidManifest: return "游戏资源清单暂不可用，请在线开玩。"
        case .invalidResource: return "游戏资源来源或格式不受支持，请在线开玩。"
        case .tooLarge: return "这款游戏的资源超过 25 MB，暂不支持准备，可直接在线开玩。"
        case .notPublic: return "部分游戏资源不允许公共缓存，请在线开玩。"
        case .integrity: return "游戏资源版本校验失败，请稍后重新准备。"
        case .notCached: return "尚未确认游戏资源缓存可用，请在线开玩。"
        case .busy: return "正在处理游戏资源，请完成或取消后再试。"
        case .quota: return "游戏资源准备已达到 200 MB，请先清理部分资源。"
        case .storage: return "游戏资源记录暂时无法保存，请稍后再试。"
        case .networkRestricted: return "当前网络不允许准备游戏资源，请连接 Wi-Fi 或关闭仅 Wi-Fi 后重试。"
        }
    }
}

struct NativeGameResourceManifest: Codable, Equatable, Sendable {
    struct Resource: Codable, Equatable, Sendable {
        let url: URL
        let sha256: String
        let byteCount: Int
        let contentType: String
        let required: Bool
    }
    let schemaVersion: Int
    let gameId: String
    let version: String
    let generatedAt: String
    let totalBytes: Int
    let resources: [Resource]

    static func decode(_ data: Data, manifestURL: URL, gameID: String) throws -> Self {
        guard data.count <= 524_288, NativeGameResourcePolicy.manifestURL(manifestURL, gameID: gameID) else {
            throw NativeGameResourceCacheError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate(gameID: gameID)
        return manifest
    }

    func validate(gameID: String) throws {
        guard schemaVersion == 1, gameId == gameID, NativeGame.validIdentifier(gameID),
              NativeGameResourcePolicy.isDigest(version), NativeGameCatalog.date(generatedAt) != nil,
              !resources.isEmpty, resources.count <= 512, totalBytes > 0 else {
            throw NativeGameResourceCacheError.invalidManifest
        }
        guard totalBytes <= NativeGameResourcePolicy.maximumBytes else { throw NativeGameResourceCacheError.tooLarge }
        var count = 0
        var seen = Set<URL>()
        for resource in resources {
            guard NativeGameResourcePolicy.resourceURL(resource.url, gameID: gameID), resource.required,
                  NativeGameResourcePolicy.isDigest(resource.sha256), resource.byteCount > 0,
                  resource.byteCount <= NativeGameResourcePolicy.maximumBytes,
                  NativeGameResourcePolicy.acceptsType(resource.contentType, for: resource.url),
                  seen.insert(resource.url).inserted else { throw NativeGameResourceCacheError.invalidResource }
            count += resource.byteCount
            guard count <= NativeGameResourcePolicy.maximumBytes else { throw NativeGameResourceCacheError.tooLarge }
        }
        guard count == totalBytes else { throw NativeGameResourceCacheError.invalidManifest }
    }
}

enum NativeGameResourcePolicy {
    static let maximumBytes = 25 * 1024 * 1024
    static let maximumTotalBytes = 200 * 1024 * 1024
    static let origin = URL(string: "https://play.yunle.fun/")!
    static let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]

    static func manifestURL(_ url: URL, gameID: String) -> Bool {
        NativeGame.validIdentifier(gameID) && publicURL(url) && url.host?.lowercased() == "play.yunle.fun"
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/native/resources/\(gameID)-v1.json"
    }

    static func publicURL(_ url: URL) -> Bool {
        NativeGame.publicHTTPS(url) && url.query == nil && url.fragment == nil
            && !url.absoluteString.contains("%")
            && ["play.yunle.fun", "assets.play.yunle.fun"].contains(url.host?.lowercased() ?? "")
    }

    static func resourceURL(_ url: URL, gameID: String) -> Bool {
        guard NativeGame.validIdentifier(gameID), publicURL(url),
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              path.range(of: #"\A/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\z"#, options: .regularExpression) != nil,
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let permittedPath = url.host?.lowercased() == "play.yunle.fun"
            ? (path.hasPrefix("/_nuxt/") || path.hasPrefix("/games/\(gameID)/"))
            : path.hasPrefix("/games/\(gameID)/")
        return permittedPath && types[url.pathExtension.lowercased()] != nil
    }

    static func isDigest(_ value: String) -> Bool {
        value.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil
    }

    static func acceptsType(_ type: String, for url: URL) -> Bool {
        let mime = type.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        return types[url.pathExtension.lowercased()]?.contains(mime) == true
    }

    static func validate(_ data: Data, response: HTTPURLResponse, resource: NativeGameResourceManifest.Resource,
                         expectedResponseURL: URL? = nil) throws {
        let expected = expectedResponseURL ?? resource.url
        guard (expected == resource.url || expected == NativeGameHostEnvironment.transportURL(resource.url)),
              response.url == expected, ApplicationStaticResourcePolicy.isPublic(response),
              let mime = response.mimeType, acceptsType(mime, for: resource.url) else { throw NativeGameResourceCacheError.notPublic }
        guard data.count == resource.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == resource.sha256 else {
            throw NativeGameResourceCacheError.integrity
        }
    }

    private static let types: [String: Set<String>] = [
        "js": ["application/javascript", "text/javascript"], "mjs": ["application/javascript", "text/javascript"],
        "css": ["text/css"], "wasm": ["application/wasm", "application/octet-stream"],
        "woff": ["font/woff", "application/font-woff"], "woff2": ["font/woff2"],
        "ttf": ["font/ttf", "application/x-font-ttf"], "otf": ["font/otf"],
        "png": ["image/png"], "jpg": ["image/jpeg"], "jpeg": ["image/jpeg"],
        "webp": ["image/webp"], "avif": ["image/avif"], "svg": ["image/svg+xml"], "gif": ["image/gif"], "ico": ["image/x-icon", "image/vnd.microsoft.icon"],
        "mp3": ["audio/mpeg"], "ogg": ["audio/ogg", "application/ogg"], "wav": ["audio/wav", "audio/x-wav"],
        "m4a": ["audio/mp4"], "aac": ["audio/aac"],
        "glb": ["model/gltf-binary", "application/octet-stream"], "gltf": ["model/gltf+json", "application/json"],
        "bin": ["application/octet-stream"], "ktx2": ["image/ktx2", "application/octet-stream"], "basis": ["application/octet-stream"],
        "json": ["application/json"],
    ]
}

struct NativeGameResourceCacheEntry: Codable, Identifiable, Equatable {
    let gameID: String
    let profileID: UUID
    let version: String
    let byteCount: Int
    let resourceCount: Int
    /// Same-origin resources re-read using WebKit only-if-cached, never URLSession files.
    let cacheVerifiedResourceCount: Int
    let preparedAt: Date
    var id: String { profileID.uuidString + ":" + gameID }
}

/// Public game assets in the exact persistent WebKit profile used by the runtime.
/// Clearing this shared Play profile also invalidates every game's preparation receipt.
@MainActor
final class NativeGameResourceCache: ObservableObject {
    @Published private(set) var entries: [NativeGameResourceCacheEntry] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isClearing = false
    @Published private(set) var downloadingGameID: String?
    private let defaults: UserDefaults
    private var profiles: Set<UUID> = []
    private var task: Task<Void, Never>?
    private var downloader: NativeGameResourceDownloader?
    private var activeProfileID: UUID?
    private let entriesKey = "nativeGameResourceCache.entries.v1"
    private let profilesKey = "nativeGameResourceCache.profiles.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = Set((defaults.stringArray(forKey: profilesKey) ?? []).compactMap(UUID.init(uuidString:)))
        if let data = defaults.data(forKey: entriesKey) {
            do {
                let saved = try JSONDecoder().decode([NativeGameResourceCacheEntry].self, from: data)
                var seen = Set<String>()
                guard saved.count <= 64, saved.allSatisfy({
                    profiles.contains($0.profileID) && NativeGame.validIdentifier($0.gameID) && NativeGameResourcePolicy.isDigest($0.version)
                        && $0.byteCount > 0 && $0.byteCount <= NativeGameResourcePolicy.maximumBytes
                        && $0.resourceCount > 0 && $0.resourceCount <= 512 && $0.cacheVerifiedResourceCount > 0
                        && $0.cacheVerifiedResourceCount <= $0.resourceCount && seen.insert($0.id).inserted
                }), saved.reduce(0, { $0 + $1.byteCount }) <= NativeGameResourcePolicy.maximumTotalBytes else {
                    throw NativeGameResourceCacheError.storage
                }
                entries = saved
            } catch { self.error = NativeGameResourceCacheError.storage.localizedDescription }
        }
    }

    func entry(gameID: String, profileID: UUID) -> NativeGameResourceCacheEntry? {
        entries.first { $0.gameID == gameID && $0.profileID == profileID }
    }

    /// Includes interrupted preparations, whose partial HTTP cache is still cleanable.
    func hasResources(profileID: UUID) -> Bool { profiles.contains(profileID) }

    func download(manifestURL: URL, gameID: String, profileID: UUID, wifiOnly: Bool = true) {
        guard #available(iOS 17, *) else { error = NativeGameResourceCacheError.unsupported.localizedDescription; return }
        guard !isBusy else { error = NativeGameResourceCacheError.busy.localizedDescription; return }
        guard NativeGameResourcePolicy.manifestURL(manifestURL, gameID: gameID) else {
            error = NativeGameResourceCacheError.invalidManifest.localizedDescription; return
        }
        isBusy = true; downloadingGameID = gameID; activeProfileID = profileID; progress = 0; error = nil
        let worker = NativeGameResourceDownloader(profileID: profileID, wifiOnly: wifiOnly)
        downloader = worker
        task = Task { [weak self] in
            guard let self else { return }
            defer { worker.close(); self.isBusy = false; self.downloadingGameID = nil; self.activeProfileID = nil; self.downloader = nil; self.task = nil }
            do {
                let manifest = try await worker.manifest(at: manifestURL, gameID: gameID)
                let existingBytes = self.entries.filter { $0.profileID != profileID || $0.gameID != gameID }.reduce(0) { $0 + $1.byteCount }
                guard existingBytes + manifest.totalBytes <= NativeGameResourcePolicy.maximumTotalBytes,
                      self.entries.contains(where: { $0.profileID == profileID && $0.gameID == gameID }) || self.entries.count < 64 else {
                    throw NativeGameResourceCacheError.quota
                }
                try Task.checkCancellation()
                // Ownership is registered before WebKit's first request, so partial
                // or cancelled preparations remain explicitly cleanable.
                self.profiles.insert(profileID)
                self.defaults.set(self.profiles.map(\.uuidString), forKey: self.profilesKey)
                let result = try await worker.prepare(manifest) { [weak self] value in self?.progress = value }
                try Task.checkCancellation()
                self.entries.removeAll { $0.profileID == profileID && $0.gameID == gameID }
                self.entries.append(result)
                try self.save()
                self.progress = 1
            } catch is CancellationError {
                self.progress = 0
            } catch let issue as URLError where issue.code == .cancelled {
                self.progress = 0
                if worker.stoppedForNetwork { self.error = NativeGameResourceCacheError.networkRestricted.localizedDescription }
            } catch {
                self.error = worker.stoppedForNetwork ? NativeGameResourceCacheError.networkRestricted.localizedDescription
                    : (error as? LocalizedError)?.errorDescription ?? "游戏资源准备未完成，请稍后重试或在线开玩。"
            }
        }
    }

    func cancel() {
        task?.cancel()
        downloader?.cancel()
    }

    func clear(profileID: UUID) async {
        guard #available(iOS 17, *) else { error = NativeGameResourceCacheError.unsupported.localizedDescription; return }
        guard !isClearing else { return }
        if isBusy {
            guard activeProfileID == profileID else { error = NativeGameResourceCacheError.busy.localizedDescription; return }
            let pending = task
            cancel()
            await pending?.value
        }
        guard profiles.contains(profileID) else { return }
        isBusy = true; isClearing = true; error = nil
        defer { isBusy = false; isClearing = false; progress = 0 }
        await WKWebsiteDataStore(forIdentifier: profileID).removeData(ofTypes: NativeGameResourcePolicy.cacheTypes, modifiedSince: .distantPast)
        entries.removeAll { $0.profileID == profileID }
        do { try save() } catch { self.error = NativeGameResourceCacheError.storage.localizedDescription }
    }

    private func save() throws { defaults.set(try JSONEncoder().encode(entries), forKey: entriesKey) }
}

@MainActor
private final class NativeGameResourceDownloader: NSObject, URLSessionTaskDelegate, WKNavigationDelegate {
    private let profileID: UUID
    private let wifiOnly: Bool
    private var session: URLSession?
    private var web: WKWebView?
    private var pathMonitor: NWPathMonitor?
    private(set) var stoppedForNetwork = false
    private static var cookieRule: WKContentRuleList?

    init(profileID: UUID, wifiOnly: Bool) { self.profileID = profileID; self.wifiOnly = wifiOnly }

    private func networkSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsCellularAccess = !wifiOnly; configuration.allowsExpensiveNetworkAccess = !wifiOnly
        configuration.allowsConstrainedNetworkAccess = false
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 120
        let result = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = result
        let monitor = NWPathMonitor()
        let wifiOnly = self.wifiOnly
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.isConstrained || (wifiOnly && path.isExpensive) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stoppedForNetwork = true
                self.cancel()
            }
        }
        pathMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "fun.yunle.apps.game-resource-network"))
        return result
    }

    func manifest(at url: URL, gameID: String) async throws -> NativeGameResourceManifest {
        let transportURL = NativeGameHostEnvironment.transportURL(url)
        var request = URLRequest(url: transportURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await networkSession().data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == transportURL, http.statusCode == 200,
              http.mimeType == "application/json", http.value(forHTTPHeaderField: "Set-Cookie") == nil else {
            throw NativeGameResourceCacheError.invalidManifest
        }
        let policy = (http.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
        guard !policy.contains("private"), !policy.contains("no-store") else { throw NativeGameResourceCacheError.invalidManifest }
        return try NativeGameResourceManifest.decode(data, manifestURL: url, gameID: gameID)
    }

    func prepare(_ manifest: NativeGameResourceManifest, progress: (Double) -> Void) async throws -> NativeGameResourceCacheEntry {
        guard #available(iOS 17, *) else { throw NativeGameResourceCacheError.unsupported }
        defer { dispose() }
        try manifest.validate(gameID: manifest.gameId)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(try await Self.noCookieRule())
        let browser = WKWebView(frame: .zero, configuration: configuration)
        web = browser; browser.navigationDelegate = self
        let origin = NativeGameHostEnvironment.transportURL(NativeGameResourcePolicy.origin)
        let sources = manifest.resources.map { NativeGameHostEnvironment.transportURL($0.url).absoluteString }.joined(separator: " ")
        let html = "<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; connect-src \(origin.absoluteString) https://assets.play.yunle.fun; script-src \(sources); style-src \(sources); img-src \(sources); font-src \(sources); media-src \(sources); base-uri 'none'; form-action 'none'\"><title>native-game-resource-cache</title></head><body></body></html>"
        browser.loadSimulatedRequest(URLRequest(url: origin), responseHTML: html)
        let deadline = Date().addingTimeInterval(150)
        while (try? await browser.evaluateJavaScript("document.title")) as? String != "native-game-resource-cache" {
            try check(deadline)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        var completeBytes = 0
        var verifiedCount = 0
        for start in stride(from: 0, to: manifest.resources.count, by: 8) {
            try check(deadline)
            let batch = Array(manifest.resources[start..<min(start + 8, manifest.resources.count)])
            let session = networkSession()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for resource in batch {
                    group.addTask {
                        let transportURL = NativeGameHostEnvironment.transportURL(resource.url)
                        let (data, response) = try await session.data(from: transportURL)
                        guard let response = response as? HTTPURLResponse else { throw NativeGameResourceCacheError.notPublic }
                        try NativeGameResourcePolicy.validate(data, response: response, resource: resource, expectedResponseURL: transportURL)
                    }
                }
                try await group.waitForAll()
            }
            try check(deadline)
            // The URLSession data is verification input only. Fetch again in the
            // runtime's actual profile; no downloaded file is passed to WebKit.
            try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                for resource in batch {
                    group.addTask { @MainActor in
                        try self.check(deadline)
                        return try await self.prepareResource(resource, browser: browser)
                    }
                }
                for try await (bytes, verified) in group {
                    completeBytes += bytes
                    verifiedCount += verified
                    progress(min(0.99, Double(completeBytes) / Double(manifest.totalBytes)))
                }
            }
        }
        try check(deadline)
        guard verifiedCount > 0 else { throw NativeGameResourceCacheError.notCached }
        return .init(gameID: manifest.gameId, profileID: profileID, version: manifest.version, byteCount: completeBytes,
                     resourceCount: manifest.resources.count, cacheVerifiedResourceCount: verifiedCount, preparedAt: Date())
    }

    private func prepareResource(_ resource: NativeGameResourceManifest.Resource, browser: WKWebView) async throws -> (Int, Int) {
        let arguments: [String: Any] = ["url": NativeGameHostEnvironment.transportURL(resource.url).absoluteString,
                                        "expectedBytes": resource.byteCount, "expectedHash": resource.sha256]
        let result = try await browser.callAsyncJavaScript(Self.fetchScript, arguments: arguments, in: nil, contentWorld: .defaultClient) as? Bool
        guard result == true else { throw NativeGameResourceCacheError.integrity }
        try await typedPreload(resource, browser: browser)
        if resource.url.host?.lowercased() == "play.yunle.fun" {
            let cached = try await browser.callAsyncJavaScript(Self.cacheReadScript, arguments: arguments, in: nil, contentWorld: .defaultClient) as? Bool
            guard cached == true else { throw NativeGameResourceCacheError.notCached }
            return (resource.byteCount, 1)
        }
        return (resource.byteCount, 0)
    }

    private static let fetchScript = """
        globalThis.nativeGameCacheAbort ||= new AbortController();
        const controller = new AbortController();
        const abort = () => controller.abort();
        nativeGameCacheAbort.signal.addEventListener('abort', abort, {once:true});
        const timer = setTimeout(abort, 20000);
        try {
            const response = await fetch(url, {credentials: 'same-origin', redirect: 'error', cache: 'default', signal: controller.signal});
            const policy = (response.headers.get('cache-control') || '').toLowerCase();
            const vary = (response.headers.get('vary') || '').toLowerCase().split(',').map(x => x.trim());
            if (response.status !== 200 || !policy.split(',').some(x => x.trim() === 'public') || /(?:private|no-store|no-cache)/.test(policy)
                || vary.some(x => ['*','cookie','authorization'].includes(x))) throw Error('Resource is not public');
            const data = await response.arrayBuffer();
            if (data.byteLength !== expectedBytes) return false;
            const digest = await crypto.subtle.digest('SHA-256', data);
            return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('') === expectedHash;
        } finally { clearTimeout(timer); nativeGameCacheAbort.signal.removeEventListener('abort', abort); }
        """

    private static let cacheReadScript = """
        const response = await fetch(url, {credentials: 'same-origin', redirect: 'error', cache: 'only-if-cached', mode: 'same-origin'});
        if (response.status !== 200) return false;
        const data = await response.arrayBuffer();
        if (data.byteLength !== expectedBytes) return false;
        const digest = await crypto.subtle.digest('SHA-256', data);
        return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('') === expectedHash;
        """

    private func typedPreload(_ resource: NativeGameResourceManifest.Resource, browser: WKWebView) async throws {
        let kind: String
        switch resource.url.pathExtension.lowercased() {
        case "js", "mjs": kind = "module"
        case "css": kind = "style"
        case "woff", "woff2", "ttf", "otf": kind = "font"
        case "png", "jpg", "jpeg", "webp", "avif", "svg", "gif", "ico": kind = "image"
        default: return // fetch() matches WASM, models and audio loaders without executing or playing them.
        }
        let result = try await browser.callAsyncJavaScript("""
            return await new Promise((resolve, reject) => {
                const link = document.createElement('link');
                if (kind === 'module') { link.rel = 'modulepreload'; link.crossOrigin = 'anonymous'; }
                else { link.rel = 'preload'; link.as = kind; if (kind === 'font') link.crossOrigin = 'anonymous'; }
                link.href = url;
                const finish = value => { clearTimeout(timer); link.remove(); resolve(value); };
                const timer = setTimeout(() => finish(false), 20000);
                link.onload = () => finish(true); link.onerror = () => finish(false);
                globalThis.nativeGameCacheAbort?.signal.addEventListener('abort', () => finish(false), {once:true});
                document.head.append(link);
            });
            """, arguments: ["url": NativeGameHostEnvironment.transportURL(resource.url).absoluteString, "kind": kind], in: nil, contentWorld: .defaultClient) as? Bool
        guard result == true else { throw NativeGameResourceCacheError.notCached }
    }

    private static func noCookieRule() async throws -> WKContentRuleList {
        if let cookieRule { return cookieRule }
        let encoded = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block-cookies"}}]"#
        let rule: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "native-game-public-assets-no-cookies-v1", encodedContentRuleList: encoded) { rule, error in
                if let error { continuation.resume(throwing: error) }
                else if let rule { continuation.resume(returning: rule) }
                else { continuation.resume(throwing: NativeGameResourceCacheError.notPublic) }
            }
        }
        cookieRule = rule
        return rule
    }

    func cancel() {
        session?.invalidateAndCancel()
        web?.evaluateJavaScript("globalThis.nativeGameCacheAbort?.abort()", in: nil, in: .defaultClient, completionHandler: nil)
        web?.stopLoading()
    }

    func close() { dispose() }

    private func dispose() {
        pathMonitor?.cancel(); pathMonitor = nil
        session?.invalidateAndCancel(); session = nil
        web?.stopLoading(); web?.navigationDelegate = nil; web = nil
    }

    private func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard !stoppedForNetwork else { throw NativeGameResourceCacheError.networkRestricted }
        guard Date() < deadline else { throw URLError(.timedOut) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url == NativeGameHostEnvironment.transportURL(NativeGameResourcePolicy.origin) ? .allow : .cancel)
    }
}
