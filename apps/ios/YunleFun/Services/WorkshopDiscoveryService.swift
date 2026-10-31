import Foundation
import Combine

struct WorkshopDiscoveryPayload: Decodable {
    let schemaVersion: Int
    let generatedAt: Double
    let featured: [Featured]
    let weeklyChart: WeeklyChart?

    struct Featured: Decodable {
        let appId: String
        let title: String?
        let subtitle: String?
        let startsAt: Double
        let expiresAt: Double
    }

    struct WeeklyChart: Decodable {
        let weekStart: Double
        let items: [Entry]

        struct Entry: Decodable {
            let appId: String
            let rank: Int
        }
    }

    /// Metadata only selects from the current public catalog. It never supplies
    /// an application URL or changes its published revision or access policy.
    func selection(from applications: [CloudApplication], now: Date = Date()) -> WorkshopDiscoverySelection {
        let eligible = Self.publicApplications(applications)
        let byID = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let milliseconds = now.timeIntervalSince1970 * 1_000
        var featuredIDs = Set<String>()
        let selected = featured.compactMap { reference -> WorkshopDiscoverySelection.Featured? in
            guard reference.startsAt.isFinite, reference.expiresAt.isFinite,
                  reference.startsAt <= milliseconds, reference.expiresAt > milliseconds,
                  let application = byID[reference.appId], featuredIDs.insert(application.id).inserted else { return nil }
            return .init(application: application, title: reference.title?.nilIfEmpty, subtitle: reference.subtitle?.nilIfEmpty)
        }
        var rankedIDs = Set<String>()
        var ranks = Set<Int>()
        let expectedWeek = Self.weekStart(at: now)
        let chart = weeklyChart.flatMap { abs($0.weekStart - expectedWeek) < 1 ? $0 : nil }
        let ranked = (chart?.items ?? []).sorted { $0.rank < $1.rank }.compactMap { entry -> WorkshopDiscoverySelection.Ranked? in
            guard (1...10).contains(entry.rank), let application = byID[entry.appId],
                  !rankedIDs.contains(application.id), !ranks.contains(entry.rank) else { return nil }
            rankedIDs.insert(application.id)
            ranks.insert(entry.rank)
            return .init(application: application, rank: entry.rank)
        }
        return .init(featured: selected, weekly: ranked)
    }

    static func publicApplications(_ applications: [CloudApplication]) -> [CloudApplication] {
        applications.filter {
            $0.accessWorkshopID == nil && $0.accessOwnerID == nil && $0.personalMarketOwnerLogin == nil
                && ($0.audience == nil || $0.audience == "public") && $0.isPublic != false && $0.isUnavailable != true
        }
    }

    static func weekStart(at date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let start = calendar.startOfDay(for: date)
        let days = (calendar.component(.weekday, from: start) + 5) % 7
        return calendar.date(byAdding: .day, value: -days, to: start)!.timeIntervalSince1970 * 1_000
    }
}

struct WorkshopDiscoverySelection {
    struct Featured: Identifiable {
        let application: CloudApplication
        let title: String?
        let subtitle: String?
        var id: String { application.id }
    }
    struct Ranked: Identifiable {
        let application: CloudApplication
        let rank: Int
        var id: String { application.id }
    }
    let featured: [Featured]
    let weekly: [Ranked]
}

protocol WorkshopDiscoveryServing {
    func discovery() async throws -> WorkshopDiscoveryPayload
}

struct WorkshopDiscoveryService: WorkshopDiscoveryServing {
    private let session: URLSession
    private let origin: URL

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    func discovery() async throws -> WorkshopDiscoveryPayload {
        let url = origin.appendingPathComponent("api/catalog/discovery")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url == url, http.mimeType?.lowercased() == "application/json" else { throw CatalogError.invalidResponse }
        let result = try JSONDecoder().decode(WorkshopDiscoveryPayload.self, from: data)
        guard result.schemaVersion == 1, result.generatedAt.isFinite,
              result.featured.count <= 10, (result.weeklyChart?.items.count ?? 0) <= 10 else { throw CatalogError.invalidResponse }
        return result
    }
}

@MainActor
final class WorkshopDiscoveryStore: ObservableObject {
    @Published private(set) var payload: WorkshopDiscoveryPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadFailed = false
    private let service: WorkshopDiscoveryServing

    init(service: WorkshopDiscoveryServing = WorkshopDiscoveryService()) { self.service = service }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.discovery()
            try Task.checkCancellation()
            payload = result
            lastLoadFailed = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Discovery is supplementary. A missing endpoint or unavailable
            // editorial collection must not hide the usable public catalog.
            // Existing metadata is filtered for expiry every time it is used.
            lastLoadFailed = true
        }
    }
}
