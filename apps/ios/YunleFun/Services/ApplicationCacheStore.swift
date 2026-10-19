import Combine
import Foundation
import OSLog

@MainActor
final class ApplicationCacheStore: ObservableObject {
    private let logger = Logger(subsystem: "fun.yunle.apps", category: "cache-store")
    @Published private(set) var entries: [ApplicationCacheEntry] = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadingName: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isClearing = false
    @Published private(set) var isAutomaticDownload = false
    @Published private(set) var message: String?
    /// The application `message` is about; nil for store-wide results such as clearing everything.
    @Published private(set) var messageApplicationID: String?
    @Published private(set) var updatesReady: Set<String> = []
    @Published var automaticUpdatesEnabled: Bool {
        didSet {
            guard oldValue != automaticUpdatesEnabled else { return }
            defaults.set(automaticUpdatesEnabled, forKey: Self.enabledKey)
            updateMonitoring()
        }
    }
    @Published var wifiOnly: Bool {
        didSet {
            guard oldValue != wifiOnly else { return }
            defaults.set(wifiOnly, forKey: Self.wifiKey)
            // Restart under the new URLRequest policy as well as the path policy.
            if isAutomaticDownload { task?.cancel() }
            scheduleAutomaticCheck()
        }
    }

    let repository: ApplicationCacheRepository
    static let automaticUpdateInterval: TimeInterval = 24 * 60 * 60
    private static let enabledKey = "applicationCache.automaticUpdates"
    private static let wifiKey = "applicationCache.wifiOnly"
    private static let retriesKey = "applicationCache.retryDates"
    private struct Retry: Codable { var failures: Int; var after: Date }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let monitor: ApplicationCacheNetworkMonitoring
    private let makeDownloader: @MainActor () -> ApplicationCacheDownloading
    private let makeAutomaticDownloader: @MainActor (Bool) -> ApplicationCacheDownloading
    private var task: Task<Void, Never>?
    private var scheduledCheck: Task<Void, Never>?
    private var checkID = UUID()
    private var operationID = UUID()
    private var active = false
    private var monitoring = false
    private var network = ApplicationCacheNetwork()
    private var catalog: [CloudApplication] = []
    private var retries: [String: Retry]
    /// Archive revision each running session loaded; `.distantPast` means it loaded online.
    @Published private(set) var runningRevisions: [String: Date] = [:]
    var isBusy: Bool { downloadingID != nil || isClearing }
    var totalBytes: Int64 { entries.reduce(0) { $0 + Int64($1.byteCount) } }

    init(repository: ApplicationCacheRepository = ApplicationCacheRepository(),
         defaults: UserDefaults = .standard,
         monitor: ApplicationCacheNetworkMonitoring? = nil,
         now: @escaping () -> Date = Date.init,
         makeAutomaticDownloader: @escaping @MainActor (Bool) -> ApplicationCacheDownloading = {
             ApplicationCacheDownloader(allowsCellularAccess: !$0, allowsConstrainedNetworkAccess: false)
         },
         makeDownloader: @escaping @MainActor () -> ApplicationCacheDownloading = { ApplicationCacheDownloader() }) {
        self.repository = repository; self.makeDownloader = makeDownloader
        self.defaults = defaults; self.monitor = monitor ?? ApplicationCacheNetworkMonitor(); self.now = now
        self.makeAutomaticDownloader = makeAutomaticDownloader
        automaticUpdatesEnabled = defaults.bool(forKey: Self.enabledKey)
        wifiOnly = defaults.object(forKey: Self.wifiKey) as? Bool ?? true
        retries = defaults.data(forKey: Self.retriesKey).flatMap { try? JSONDecoder().decode([String: Retry].self, from: $0) } ?? [:]
    }

    func entry(for application: CloudApplication) -> ApplicationCacheEntry? {
        entries.first { $0.id == ApplicationCacheEntry.key(for: application) }
    }

    func refresh() async {
        do { entries = try await repository.entries() }
        catch { message = "无法读取下载缓存，请稍后重试。"; messageApplicationID = nil }
    }

    func setApplicationActive(_ active: Bool) {
        self.active = active
        updateMonitoring()
    }

    func updateAutomaticApplications(_ applications: [CloudApplication]) {
        catalog = applications
        if isAutomaticDownload, let id = downloadingID, automaticApplication(id: id) == nil { task?.cancel() }
        scheduleAutomaticCheck()
    }

    func sessionStarted(_ application: CloudApplication, revision: Date?) {
        let id = ApplicationCacheEntry.key(for: application)
        runningRevisions[id] = revision ?? .distantPast
        updateReadyState()
    }

    func sessionEnded(_ application: CloudApplication) {
        let id = ApplicationCacheEntry.key(for: application)
        runningRevisions[id] = nil; updatesReady.remove(id)
    }

    func download(_ application: CloudApplication) { startDownload(application, automatic: false) }

    private func startDownload(_ application: CloudApplication, automatic: Bool) {
        guard !isBusy, ApplicationCacheEntry.supports(application), let url = application.launchURL else { return }
        scheduledCheck?.cancel()
        let operation = UUID(), id = ApplicationCacheEntry.key(for: application)
        operationID = operation
        downloadingID = id; downloadingName = application.name; progress = 0; message = nil; messageApplicationID = id; isAutomaticDownload = automatic
        let downloader = automatic ? makeAutomaticDownloader(wifiOnly) : makeDownloader()
        task = Task { [self] in
            defer {
                if operationID == operation {
                    downloadingID = nil; downloadingName = nil; isAutomaticDownload = false; task = nil
                    scheduleAutomaticCheck()
                }
            }
            do {
                let data = try await downloader.download(url) { [weak self] value in
                    guard let self, self.operationID == operation, !Task.isCancelled else { return }
                    self.progress = value
                }
                try Task.checkCancellation()
                if automatic {
                    guard permitsAutomaticDownload, automaticApplication(id: id) != nil else { throw CancellationError() }
                }
                try await repository.save(data, for: application, now: now())
                retries[id] = nil; persistRetries()
                await refresh(); updateReadyState()
                if !Task.isCancelled { messageApplicationID = id; message = automatic ? "自动更新已就绪，下次重新打开应用时生效。" : "缓存已保存。下次重新打开应用时使用新缓存。" }
            } catch is CancellationError {
                if !automatic && !isClearing { messageApplicationID = id; message = "已取消下载，原有缓存继续保留。" }
            } catch {
                if !Task.isCancelled {
                    let failure = error as NSError
                    let cause = (error as? ApplicationCacheError).map { String(describing: $0) }
                        ?? "\(failure.domain):\(failure.code)"
                    logger.error("Download failed automatic=\(automatic, privacy: .public) cause=\(cause, privacy: .public)")
                    if automatic {
                        let failures = min((retries[id]?.failures ?? 0) + 1, 6)
                        retries[id] = Retry(failures: failures, after: now().addingTimeInterval(min(3600 * pow(2, Double(failures - 1)), Self.automaticUpdateInterval)))
                        persistRetries()
                        messageApplicationID = id; message = "自动更新未完成，继续使用旧缓存，稍后自动重试。"
                    } else {
                        messageApplicationID = id; message = (error as? ApplicationCacheError)?.localizedDescription ?? "无法保存下载缓存，请检查网络或可用空间后重试。"
                    }
                }
            }
        }
    }

    func cancelDownload() {
        if isAutomaticDownload, let id = downloadingID {
            retries[id] = Retry(failures: retries[id]?.failures ?? 0, after: now().addingTimeInterval(3600))
            persistRetries()
        }
        task?.cancel()
    }

    func clear(id: String? = nil) async {
        guard !isClearing else { return }
        isClearing = true; message = nil; messageApplicationID = id
        scheduledCheck?.cancel(); checkID = UUID()
        task?.cancel()
        // Wait for any in-flight atomic write before deletion, so late downloads cannot recreate the cache.
        await task?.value
        do {
            if let id { try await repository.remove(id: id); retries[id] = nil; updatesReady.remove(id) }
            else { try await repository.removeAll(); retries.removeAll(); updatesReady.removeAll() }
            persistRetries()
            await refresh()
            message = "下载缓存已清理。下次重新打开应用时从网络加载。"
        } catch { message = "缓存未能清理，请稍后重试。" }
        isClearing = false
        scheduleAutomaticCheck()
    }

    private var permitsAutomaticDownload: Bool {
        automaticUpdatesEnabled && active && network.permitsAutomaticDownload(wifiOnly: wifiOnly)
    }

    private func automaticApplication(id: String) -> CloudApplication? {
        catalog.first { ApplicationCacheEntry.supports($0) && ApplicationCacheEntry.key(for: $0) == id }
    }

    private func updateMonitoring() {
        if automaticUpdatesEnabled && active {
            if !monitoring {
                monitoring = true
                monitor.start { [weak self] state in
                    guard let self, self.monitoring else { return }
                    self.network = state
                    if !self.permitsAutomaticDownload && self.isAutomaticDownload { self.task?.cancel() }
                    self.scheduleAutomaticCheck()
                }
            }
        } else {
            monitoring = false; monitor.stop(); network = ApplicationCacheNetwork()
            if isAutomaticDownload { task?.cancel() }
        }
        scheduleAutomaticCheck()
    }

    private func scheduleAutomaticCheck(after delay: TimeInterval = 0) {
        scheduledCheck?.cancel(); checkID = UUID()
        guard permitsAutomaticDownload, !isBusy else { return }
        let check = checkID
        scheduledCheck = Task { [weak self] in
            if delay > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(min(delay, Self.automaticUpdateInterval) * 1_000_000_000)) }
                catch { return }
            }
            await self?.checkAutomaticUpdates(check: check)
        }
    }

    private func checkAutomaticUpdates(check: UUID) async {
        await refresh()
        guard !Task.isCancelled, checkID == check, permitsAutomaticDownload, !isBusy else { return }
        let due = entries.compactMap { entry -> (CloudApplication, Date)? in
            guard let application = automaticApplication(id: entry.id) else { return nil }
            return (application, max(entry.downloadedAt.addingTimeInterval(Self.automaticUpdateInterval), retries[entry.id]?.after ?? .distantPast))
        }.sorted { $0.1 < $1.1 }
        guard let (application, date) = due.first else { return }
        let delay = date.timeIntervalSince(now())
        if delay > 0 { scheduleAutomaticCheck(after: delay) }
        else { startDownload(application, automatic: true) }
    }

    private func persistRetries() {
        if let data = try? JSONEncoder().encode(retries) { defaults.set(data, forKey: Self.retriesKey) }
    }

    private func updateReadyState() {
        updatesReady = Set(entries.filter { entry in runningRevisions[entry.id].map { $0 < entry.downloadedAt } ?? false }.map(\.id))
    }

    deinit { scheduledCheck?.cancel(); task?.cancel() }
}
