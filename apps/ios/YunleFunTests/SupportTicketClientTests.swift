import Foundation
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

final class SupportTicketClientTests: XCTestCase {
    private let id = "fb_fixture"
    private var receipt: SupportFeedbackReceipt { sharedFeedbackTestRecord().receipt }
    override func tearDown() { SharedFeedbackURLProtocol.fixture = nil; super.tearDown() }

    func testGuestCapabilityIsExchangedOnceAndOnlyTicketCookieReachesPrivateReads() async throws {
        let image = try FeedbackScreenshot.prepare(sharedFeedbackTestImage()).data
        let fixture = ShareHTTPFixture(replies: [access(), detail(), images(image.count),
            .init(status: 200, data: image, contentType: "image/jpeg", cookie: nil)])
        let client = makeClient(fixture)
        let snapshot = try await client.open(receipt)
        let loaded = try await client.screenshot(XCTUnwrap(snapshot.screenshots.first), in: snapshot)
        XCTAssertEqual(loaded, image)
        XCTAssertEqual(snapshot.detail.messages.first?.content, "Synthetic ticket description")
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Origin"), SupportFeedbackClient.origin.absoluteString)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body["token"], "synthetic-fixture-capability")
        for request in requests.dropFirst() {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-ylf-ticket-fb_fixture=scoped-capability")
            XCTAssertNil(request.httpBody)
        }
        XCTAssertTrue(requests.allSatisfy { $0.url?.query == nil && $0.url?.fragment == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertNil(client.session.configuration.httpCookieStorage)
    }

    func testForeignOriginsAndMalformedCapabilitiesFailBeforeNetwork() async throws {
        for url in ["https://unrelated.invalid/tickets/fb_fixture#access=token", "https://support.yunle.fun/tickets/fb_fixture#access=one&access=two",
                    "https://support.yunle.fun/tickets/fb_fixture#access=unsafe%0Atoken"] {
            let fixture = ShareHTTPFixture(replies: [])
            do {
                _ = try await makeClient(fixture).open(.init(id: id, productId: "www", ticketId: id, ticketUrl: url)); XCTFail()
            } catch { XCTAssertTrue(error is SupportTicketError) }
            XCTAssertTrue(fixture.requests.isEmpty)
        }
    }

    func testCookieForAnotherTicketCannotAuthorizeReads() async throws {
        let fixture = ShareHTTPFixture(replies: [.json(["ticketCsrf": "csrf"], cookie: "__Host-ylf-ticket-other=token; Secure; HttpOnly; Path=/")])
        do { _ = try await makeClient(fixture).open(receipt); XCTFail() }
        catch { XCTAssertEqual(error as? SupportTicketError, .invalidResponse) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testForeignTicketResponseAndInvalidAttachmentMetadataAreRejected() async throws {
        let mismatched = ShareHTTPFixture(replies: [access(), detail(ticketID: "other")])
        do { _ = try await makeClient(mismatched).open(receipt); XCTFail() }
        catch { XCTAssertEqual(error as? SupportTicketError, .invalidResponse) }
        XCTAssertEqual(mismatched.requests.count, 2)
        let invalid = ShareHTTPFixture(replies: [access(), detail(), .json(["items": [["id": "../other", "mimeType": "image/jpeg", "width": 48, "height": 80, "sizeBytes": 20]]])])
        do { _ = try await makeClient(invalid).open(receipt); XCTFail() }
        catch { XCTAssertEqual(error as? SupportTicketError, .invalidResponse) }
        XCTAssertEqual(invalid.requests.count, 3)
    }

    func testHTMLImageAndExpiredAccessNeverProduceAnImage() async throws {
        let fixture = ShareHTTPFixture(replies: [access(), detail(), images(20),
            .init(status: 200, data: Data("<html>fallback</html>".utf8), contentType: "text/html", cookie: nil)])
        let client = makeClient(fixture), snapshot = try await client.open(receipt)
        do { _ = try await client.screenshot(XCTUnwrap(snapshot.screenshots.first), in: snapshot); XCTFail() }
        catch { XCTAssertEqual(error as? SupportTicketError, .invalidResponse) }
        let expired = ShareHTTPFixture(replies: [.json(["code": "UNAUTHENTICATED"], status: 401)])
        do { _ = try await makeClient(expired).open(receipt); XCTFail() }
        catch { XCTAssertEqual(error as? SupportTicketError, .expired) }
    }

    func testSignedInTicketUsesOnlyTheSupportSessionCookie() async throws {
        let fixture = ShareHTTPFixture(replies: [detail(), .json(["items": []])])
        let url = SupportFeedbackClient.origin.appendingPathComponent("tickets/" + id).absoluteString
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: SupportFeedbackClient.userCookieName, .value: "support-session",
            .domain: SupportFeedbackClient.origin.host!, .path: "/", .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"]))
        _ = try await makeClient(fixture).open(.init(id: id, productId: "www", ticketId: id, ticketUrl: url), cookies: [cookie])
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertEqual(fixture.requests.first?.value(forHTTPHeaderField: "Cookie"), "__Host-ylf-support-session=support-session")
        XCTAssertTrue(fixture.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    private func makeClient(_ fixture: ShareHTTPFixture) -> SupportTicketClient {
        SharedFeedbackURLProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.protocolClasses = [SharedFeedbackURLProtocol.self]
        return SupportTicketClient(session: URLSession(configuration: configuration))
    }
    private func access() -> ShareHTTPReply {
        .json(["ticketCsrf": "csrf"], cookie: "__Host-ylf-ticket-fb_fixture=scoped-capability; Secure; HttpOnly; Path=/")
    }
    private func detail(ticketID: String = "fb_fixture") -> ShareHTTPReply {
        .json(["ticket": ["id": ticketID, "number": "YLS-QA", "title": "Synthetic ticket", "productId": "www", "status": "new", "createdAt": "2026-10-28", "updatedAt": "2026-10-28"],
               "messages": [["id": "message_1", "content": "Synthetic ticket description", "createdAt": "2026-10-28", "author": "you"]]])
    }
    private func images(_ count: Int) -> ShareHTTPReply {
        .json(["items": [["id": "image_1", "mimeType": "image/jpeg", "width": 48, "height": 80, "sizeBytes": count]]])
    }
}
