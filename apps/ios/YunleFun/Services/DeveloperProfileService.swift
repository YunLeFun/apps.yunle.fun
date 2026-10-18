import Foundation

protocol DeveloperProfileServing: Sendable {
    func profile(login: String) async throws -> DeveloperProfile
}

struct DeveloperProfileService: DeveloperProfileServing {
    let session: URLSession
    let origin: URL

    init(session: URLSession? = nil, origin: URL = CatalogService.productionOrigin) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: DeveloperProfileRedirectPolicy(), delegateQueue: nil)
        }
    }

    func profile(login: String) async throws -> DeveloperProfile {
        guard let login = DeveloperProfile.normalizedLogin(login) else { throw DeveloperProfileError.invalidLogin }
        var request = URLRequest(url: origin.appendingPathComponent("api/markets/personal").appendingPathComponent(login))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeveloperProfileError.invalidResponse }
        switch http.statusCode {
        case 400: throw DeveloperProfileError.invalidLogin
        case 404: throw DeveloperProfileError.notFound
        case 429: throw DeveloperProfileError.throttled
        case 200: break
        default: throw DeveloperProfileError.unavailable
        }
        guard http.mimeType?.lowercased() == "application/json", data.count <= 2 * 1024 * 1024,
              let value = try? JSONDecoder().decode(DeveloperProfile.self, from: data) else { throw DeveloperProfileError.invalidResponse }
        return try value.validated(for: login)
    }
}

private final class DeveloperProfileRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct PersonalMarketLaunchAuthorization {
    var service: DeveloperProfileServing = DeveloperProfileService()

    func resolve(_ app: CloudApplication) async throws -> CloudApplication {
        guard let login = app.personalMarketOwnerLogin, DeveloperProfile.normalizedLogin(login) == login,
              app.accessOwnerID == nil, app.accessWorkshopID == nil else { throw DeveloperProfileError.invalidResponse }
        let profile = try await service.profile(login: login)
        try Task.checkCancellation()
        guard let current = profile.items.first(where: { $0.id == app.id }) else { throw DeveloperProfileError.notFound }
        // A public source is never a login, membership, purchase or invitation
        // grant. Existing acquisition only authorizes the market revision.
        guard current.personalMarketOwnerLogin?.lowercased() == login.lowercased(), current.canOpenAsGuest,
              current.audience == "public", current.isPublic == true,
              current.accessOwnerID == nil, current.accessWorkshopID == nil else { throw DeveloperProfileError.restricted }
        var resolved = current
        resolved.homeReference = app.homeReference
        return resolved
    }
}
