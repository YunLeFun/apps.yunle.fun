import Foundation
import Combine
import OSLog

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var applications: [CloudApplication] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isCached = false
    private let service: CatalogServing
    private let cacheURL: URL
    private let logger = Logger(subsystem: "fun.yunle.apps", category: "catalog")

    init(service: CatalogServing = CatalogService(), cacheURL: URL? = nil) {
        self.service = service
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("public-catalog.json")
        do {
            let data = try Data(contentsOf: self.cacheURL)
            applications = try JSONDecoder().decode([CloudApplication].self, from: data)
            isCached = true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A new installation has no cached public catalog.
        } catch {
            logger.error("Public catalog cache could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    var categories: [String] {
        ["全部"] + Set(applications.map(\.browseCategory)).sorted()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.applications()
            try Task.checkCancellation()
            applications = result
            error = nil
            isCached = false
            do {
                let data = try JSONEncoder().encode(result)
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
            } catch {
                logger.error("Public catalog cache could not be saved: \(error.localizedDescription, privacy: .public)")
            }
        } catch is CancellationError {
            return
        } catch let issue as URLError where issue.code == .cancelled {
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "无法连接工坊，请检查网络后重试。"
            isCached = !applications.isEmpty
        }
    }

    func application(id: String) -> CloudApplication? {
        applications.first { $0.id == id || $0.marketShortName == id || $0.slug == id }
    }
}
