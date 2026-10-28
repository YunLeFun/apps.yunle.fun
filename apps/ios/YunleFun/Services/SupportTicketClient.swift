import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Requester-only APIs. A ticket capability is exchanged in a POST body and
/// scoped to its own HttpOnly cookie, never sent in an image URL or to WebKit.
struct SupportTicketClient {
    let session: URLSession
    init(session: URLSession? = nil) {
        self.session = session ?? SupportFeedbackClient().session
    }

    func open(_ receipt: SupportFeedbackReceipt, cookies: [HTTPCookie] = []) async throws -> SupportTicketSnapshot {
        guard let url = SupportFeedbackClient.ticketURL(receipt), let id = receipt.ticketId else {
            throw SupportTicketError.invalidResponse
        }
        var scoped = cookies.filter { validCookie($0, name: SupportFeedbackClient.userCookieName) }
        if let fragment = url.fragment {
            guard let items = URLComponents(string: "https://local.invalid/?" + fragment)?.queryItems,
                  items.count == 1, items[0].name == "access", let token = items[0].value,
                  !token.isEmpty, token.utf8.count <= 1024,
                  token.range(of: #"^[A-Za-z0-9._-]+\z"#, options: .regularExpression) != nil else {
                throw SupportTicketError.invalidResponse
            }
            let (data, response) = try await request("api/v1/tickets/\(id)/access", method: "POST",
                body: JSONEncoder().encode(["token": token]), cookies: [])
            struct Access: Decodable { let ticketCsrf: String }
            let access: Access = try decode(data)
            guard !access.ticketCsrf.isEmpty, access.ticketCsrf.utf8.count <= 1024 else { throw SupportTicketError.invalidResponse }
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields { if let key = key as? String, let value = value as? String { headers[key] = value } }
            scoped = HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url!).filter { validCookie($0, name: "__Host-ylf-ticket-" + id) }
            guard scoped.count == 1 else { throw SupportTicketError.invalidResponse }
        }
        let (data, _) = try await request("api/v1/tickets/" + id, cookies: scoped)
        let detail: SupportTicketDetail = try decode(data)
        guard detail.ticket.id == id, detail.ticket.productId == receipt.productId,
              detail.messages.count <= 1000, Set(detail.messages.map(\.id)).count == detail.messages.count,
              detail.messages.allSatisfy({ SupportFeedbackClient.identifier($0.id) && ["you", "team"].contains($0.author) && $0.content.utf8.count <= 100_000 }) else {
            throw SupportTicketError.invalidResponse
        }
        let (images, _) = try await request("api/v1/tickets/\(id)/screenshots", cookies: scoped)
        struct Images: Decodable { let items: [SupportTicketScreenshot] }
        let list: Images = try decode(images)
        guard list.items.count <= FeedbackScreenshot.maximumCount, Set(list.items.map(\.id)).count == list.items.count,
              list.items.allSatisfy({ SupportFeedbackClient.identifier($0.id) && $0.mimeType == "image/jpeg"
                && (1...2048).contains($0.width) && (1...2048).contains($0.height)
                && (1...FeedbackScreenshot.maximumBytes).contains($0.sizeBytes) }) else { throw SupportTicketError.invalidResponse }
        return SupportTicketSnapshot(detail: detail, screenshots: list.items, cookies: scoped)
    }

    func screenshot(_ item: SupportTicketScreenshot, in snapshot: SupportTicketSnapshot) async throws -> Data {
        guard snapshot.screenshots.contains(item), SupportFeedbackClient.identifier(snapshot.detail.ticket.id),
              SupportFeedbackClient.identifier(item.id) else { throw SupportTicketError.invalidResponse }
        let (data, response) = try await request("api/v1/tickets/\(snapshot.detail.ticket.id)/screenshots/\(item.id)",
            cookies: snapshot.cookies, image: true)
        guard response.mimeType == "image/jpeg", data.count == item.sizeBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == item.width,
              properties[kCGImagePropertyPixelHeight] as? Int == item.height else { throw SupportTicketError.invalidResponse }
        return data
    }

    private func validCookie(_ cookie: HTTPCookie, name: String) -> Bool {
        cookie.name == name && cookie.domain == SupportFeedbackClient.origin.host && cookie.path == "/"
            && cookie.isSecure && cookie.isHTTPOnly
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw SupportTicketError.invalidResponse }
        return value
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         cookies: [HTTPCookie], image: Bool = false) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let url = SupportFeedbackClient.origin.appendingPathComponent(path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method; request.httpBody = body
        request.setValue(image ? "image/jpeg" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], forHTTPHeaderField: "Cookie")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(SupportFeedbackClient.origin.absoluteString, forHTTPHeaderField: "Origin")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.url == url else { throw SupportTicketError.invalidResponse }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw SupportTicketError.expired
        case 404: throw SupportTicketError.notFound
        case 429: throw SupportTicketError.throttled
        default: throw SupportTicketError.unavailable
        }
        guard data.count <= (image ? FeedbackScreenshot.maximumBytes : 2 * 1024 * 1024),
              response.mimeType == (image ? "image/jpeg" : "application/json") else { throw SupportTicketError.invalidResponse }
        return (data, response)
    }
}
