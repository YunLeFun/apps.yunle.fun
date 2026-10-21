import Foundation

protocol AssistantRolloutServing: Sendable {
    func fetch() async throws -> AssistantRollout
}

struct AssistantRolloutService: AssistantRolloutServing {
    private let session: URLSession
    private let endpoint: URL
    init(session: URLSession? = nil, origin: URL = URL(string: "https://apps.yunle.fun")!) {
        endpoint = origin.appendingPathComponent("api/features")
        if let session { self.session = session }
        else {
            // Public, identity-free request: no cookies, credentials or disk cache.
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }
    func fetch() async throws -> AssistantRollout {
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.host == endpoint.host else {
            throw URLError(.badServerResponse)
        }
        return try AssistantRollout(features: data)
    }
}

/// Holds the entry rollout: the last good server value cached in UserDefaults, falling back to
/// the compiled default. Launch arguments such as `-assistantRolloutAudience everyone` win
/// because they live in the argument domain, which UserDefaults reads first.
@MainActor
final class AssistantRolloutStore: ObservableObject {
    static let audienceKey = "assistantRolloutAudience"
    static let percentKey = "assistantRolloutPercent"
    private static let refreshInterval: TimeInterval = 5 * 60
    @Published private(set) var rollout: AssistantRollout
    private let defaults: UserDefaults
    private let service: AssistantRolloutServing
    private var lastRefresh: Date?
    private var refreshing = false
    init(defaults: UserDefaults = .standard, service: AssistantRolloutServing = AssistantRolloutService()) {
        self.defaults = defaults; self.service = service
        rollout = Self.read(defaults)
    }
    /// Failures keep the cached value; refreshes closer together than five minutes are skipped.
    func refresh(force: Bool = false) async {
        guard !refreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        refreshing = true; defer { refreshing = false }
        guard let fetched = try? await service.fetch() else { return }
        lastRefresh = Date()
        defaults.set(fetched.audience.rawValue, forKey: Self.audienceKey)
        defaults.set(fetched.percent, forKey: Self.percentKey)
        let next = Self.read(defaults)
        if next != rollout { rollout = next }
    }
    private static func read(_ defaults: UserDefaults) -> AssistantRollout {
        let fallback = AssistantRollout.compiledDefault
        let audience = defaults.string(forKey: audienceKey).flatMap(AssistantRollout.Audience.init(rawValue:)) ?? fallback.audience
        let percent = defaults.object(forKey: percentKey) == nil ? fallback.percent : defaults.integer(forKey: percentKey)
        return AssistantRollout(audience: audience, percent: percent)
    }
}
