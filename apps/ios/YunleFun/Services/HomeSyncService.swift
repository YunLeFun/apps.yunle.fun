import CryptoKit
import Foundation

protocol HomeSyncServing: Sendable {
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen
}

struct HomeSyncService: HomeSyncServing {
    private let session: URLSession
    private let endpoint: URL
    private var readEndpoint: URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "schema", value: String(HomeScreenWrite.schemaVersion))]
        return components.url!
    }
    init(session: URLSession? = nil, origin: URL = URL(string: "https://apps.yunle.fun")!) {
        endpoint = origin.appendingPathComponent("api/home-screen")
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: HomeRedirectPolicy(), delegateQueue: nil)
        }
    }
    func load(identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        try await request(identity: identity, write: nil)
    }
    func save(_ write: HomeScreenWrite, identity: AuthorizedAccount) async throws -> RemoteHomeScreen {
        try write.configuration.validate()
        let saved = try await request(identity: identity, write: write)
        guard saved.carriesSources else { throw HomeSyncError.unsupportedSchema }
        guard saved.revision != nil, write.configuration.matches(saved) else {
            throw HomeSyncError.invalidResponse
        }
        return saved
    }
    private func request(identity: AuthorizedAccount, write: HomeScreenWrite?) async throws -> RemoteHomeScreen {
        // Reads opt in to schema 3 (source selections); writes carry it in the body.
        var request = URLRequest(url: write == nil ? readEndpoint : endpoint)
        request.httpMethod = write == nil ? "GET" : "PUT"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        if let write {
            request.httpBody = try JSONEncoder().encode(write)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.mimeType?.lowercased() == "application/json",
              data.count <= 2 * 1024 * 1024 else { throw HomeSyncError.invalidResponse }
        if http.statusCode == 401 { throw HomeSyncError.unauthorized }
        if http.statusCode == 403 { throw HomeSyncError.forbidden }
        if http.statusCode == 409,
           let failure = try? JSONDecoder().decode(Failure.self, from: data) {
            if failure.data?.code == "HOME_CONFLICT", let remote = failure.data?.current {
                try remote.validate()
                throw HomeSyncError.conflict(remote)
            }
            throw HomeSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else { throw HomeSyncError.unavailable }
        let remote: RemoteHomeScreen
        do { remote = try JSONDecoder().decode(RemoteHomeScreen.self, from: data) }
        catch { throw HomeSyncError.invalidResponse }
        try remote.validate()
        return remote
    }
    private struct Failure: Decodable {
        let data: Details?
        struct Details: Decodable { let code: String?; let current: RemoteHomeScreen? }
    }
}

private final class HomeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Key-value storage the guest Home Screen syncs through: iCloud in the app,
/// memory in tests.
protocol HomeKeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}
extension NSUbiquitousKeyValueStore: HomeKeyValueStoring {}

/// Guest-only Home Screen sync through the person's own iCloud key-value
/// storage. Signed-in accounts keep using `HomeSyncService`; the two copies
/// never mix. The record is a schema 3 `RemoteHomeScreen`, so the coordinator's
/// revision, conflict and acknowledgement rules apply unchanged.
@MainActor
final class HomeICloudSync {
    static let recordKey = "home.guest.v1"
    /// iCloud key-value storage holds at most 1 MB per app.
    static let maximumBytes = 1_000_000
    private static let enabledKey = "home.icloud.enabled"
    private static let identityKey = "home.icloud.identity"
    private let store: HomeKeyValueStoring
    private let defaults: UserDefaults
    private let identity: () -> Data?
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    var onExternalChange: (() -> Void)?

    init(store: HomeKeyValueStoring = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard,
         identity: @escaping () -> Data? = HomeICloudSync.currentIdentity, now: @escaping () -> Date = Date.init,
         observeChanges: Bool = true) {
        self.store = store
        self.defaults = defaults
        self.identity = identity
        self.now = now
        guard observeChanges else { return }
        let center = NotificationCenter.default
        for name in [NSUbiquitousKeyValueStore.didChangeExternallyNotification, .NSUbiquityIdentityDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onExternalChange?() }
            })
        }
        store.synchronize()
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// A device preference: each device opts in on its own.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
    /// Signed in to iCloud. Without it writes would only stay on this device.
    var isAvailable: Bool { identity() != nil }

    nonisolated static func currentIdentity() -> Data? {
        FileManager.default.ubiquityIdentityToken.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false)
        }
    }

    /// True once after the iCloud account changed since the last check, so the
    /// device compares its layout with the new account's instead of adopting it.
    func consumeIdentityChange() -> Bool {
        guard let current = identity() else { return false }
        let previous = defaults.data(forKey: Self.identityKey)
        defaults.set(current, forKey: Self.identityKey)
        return previous != nil && previous != current
    }

    func load() throws -> RemoteHomeScreen {
        guard isAvailable else { throw HomeSyncError.iCloudUnavailable }
        store.synchronize()
        guard let data = store.data(forKey: Self.recordKey) else {
            return RemoteHomeScreen(revision: nil, configuration: HomeConfiguration())
        }
        // A damaged record is reported, never treated as an empty cloud.
        do { return try JSONDecoder().decode(RemoteHomeScreen.self, from: data) }
        catch { throw HomeSyncError.invalidResponse }
    }

    func save(_ write: HomeScreenWrite) throws -> RemoteHomeScreen {
        try write.configuration.validate()
        let current = try load()
        let revision = try Self.revision(for: write)
        // A retried write that already landed returns the stored copy.
        if current.revision == revision { return current }
        guard current.revision == write.baseRevision else { throw HomeSyncError.conflict(current) }
        var configuration = write.configuration
        configuration.updatedAt = max(Int64(now().timeIntervalSince1970 * 1000), current.configuration.updatedAt + 1)
        let saved = RemoteHomeScreen(revision: revision, configuration: configuration)
        try saved.validate()
        let data = try JSONEncoder().encode(saved)
        guard data.count <= Self.maximumBytes else { throw HomeSyncError.iCloudFull }
        store.set(data, forKey: Self.recordKey)
        store.synchronize()
        return saved
    }

    /// Lowercase SHA-256 of the write's identity and content, the same shape
    /// as server revisions.
    static func revision(for write: HomeScreenWrite) throws -> String {
        var content = write.configuration
        content.updatedAt = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: Data("yunle-home-icloud-v1:\(write.mutationId):".utf8) + (try encoder.encode(content)))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
