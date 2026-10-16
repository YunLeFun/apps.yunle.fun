import XCTest
@testable import YunleFun

final class CommunityServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }

    func testRealEmptyShapeAndPublishedSummaryAreDistinctFromMalformedData() async throws {
        let (service, _) = service([(200, communityJSON()), (200, "<html>not an API</html>"), (200, "{}")])
        let list = try await service.reviews(appKey: "ai-sfc", identity: nil)
        XCTAssertEqual(list.summary.count, 0)
        XCTAssertTrue(list.reviews.isEmpty)
        for _ in 0..<2 {
            do { _ = try await service.reviews(appKey: "ai-sfc", identity: nil); XCTFail() }
            catch { XCTAssertEqual(error as? CommunityError, .invalidResponse) }
        }
        let invalid = ReviewSummary(average: 5, count: 1, distribution: ["1": 1, "2": 0, "3": 0, "4": 0, "5": 0])
        XCTAssertThrowsError(try invalid.validate())
    }

    func testPrivateReviewMustBelongToBothTheRequestedAppAndCurrentAccount() async throws {
        let own = communityReview(uid: "a", status: .pending)
        let (service, _) = service([(200, communityJSON(own: own)), (200, communityJSON(own: own))])
        do { _ = try await service.reviews(appKey: "ai-sfc", identity: nil); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .invalidResponse) }
        do { _ = try await service.reviews(appKey: "ai-sfc", identity: AuthorizedAccount(userID: "b", accessToken: "test-b")); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .invalidResponse) }
        XCTAssertThrowsError(try own.validate(appKey: "another-app", owner: "a"))
    }

    func testSubmissionKeepsPendingStatusAndNeverLetsTheClientChooseAnAuthor() async throws {
        let review = communityReview(uid: "a", status: .pending)
        let body = try json(["code": 0, "data": ["status": "pending", "review": reviewObject(review)]])
        let (service, fixture) = service([(200, body)])
        var draft = ReviewDraft(); draft.content = "  有帮助的使用体验  "; draft.title = "  好用  "
        let result = try await service.submit(appKey: "ai-sfc", draft: draft, identity: AuthorizedAccount(userID: "a", accessToken: "test-a"))
        XCTAssertEqual(result.status, .pending)
        let request = try XCTUnwrap(fixture.requests.first)
        let fields = try fields(request)
        XCTAssertEqual(fields["content"] as? String, "有帮助的使用体验")
        XCTAssertEqual(fields["title"] as? String, "好用")
        XCTAssertNil(fields["uid"]); XCTAssertNil(fields["authorName"]); XCTAssertNil(fields["status"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-a")
        XCTAssertNil(request.url?.query)
    }

    func testUTF16LimitsAndDeletePathAreCheckedBeforeAnyRequest() async throws {
        let (service, fixture) = service([])
        var draft = ReviewDraft(); draft.content = String(repeating: "😀", count: 501)
        XCTAssertFalse(draft.isValid)
        do { _ = try await service.submit(appKey: "ai-sfc", draft: draft, identity: AuthorizedAccount(userID: "a", accessToken: "test")); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .invalidInput) }
        do { try await service.delete(reviewID: "../victim", identity: AuthorizedAccount(userID: "a", accessToken: "test")); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .invalidInput) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testReportRequiresAReceiptAndPreservesDuplicateAndCooldownFailures() async throws {
        let (service, fixture) = service([(200, #"{"code":0,"data":{"id":""}}"#), (409, "{}"), (429, "{}"), (200, #"{"code":0,"data":{"id":"report-one"}}"#)])
        let target = ReportTarget(type: .review, id: "review-one", appKey: "ai-sfc", label: "评价")
        let identity = AuthorizedAccount(userID: "a", accessToken: "test-a")
        for expected in [CommunityError.invalidResponse, .duplicate, .throttled] {
            do { try await service.report(target: target, reason: .spam, detail: "说明", identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? CommunityError, expected) }
        }
        try await service.report(target: target, reason: .privacy, detail: "请核对", identity: identity)
        let submitted = try fields(XCTUnwrap(fixture.requests.last))
        XCTAssertEqual(submitted["targetType"] as? String, "review")
        XCTAssertEqual(submitted["targetId"] as? String, "review-one")
        XCTAssertEqual(submitted["reason"] as? String, "privacy")
        XCTAssertNil(submitted["uid"])
    }
    private func service(_ replies: [(Int, String)]) -> (CommunityService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (CommunityService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
    private func fields(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }; data.append(buffer, count: count)
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
final class CommunityStoreTests: XCTestCase {
    func testConfirmedDeletionDoesNotResurrectItsCachedRowWhenRefreshFails() async throws {
        let accounts = CommunityAccounts("a"), service = CommunityFixture()
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        await store.refresh()
        XCTAssertEqual(store.reviews.count, 1)
        await service.failLoads()
        try await store.deleteMine(expectedID: "review-one", generation: accounts.identityGeneration)
        XCTAssertNil(store.myReview)
        XCTAssertTrue(store.reviews.isEmpty)
        XCTAssertEqual(store.notice, "评价已删除")
        XCTAssertNotNil(store.error)
    }
    func testDeleteAndReportConfirmationsCannotTransferToANewAccount() async throws {
        let accounts = CommunityAccounts("a"), service = CommunityFixture()
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        await store.refresh()
        let generation = accounts.identityGeneration
        accounts.select("b")
        store.identityChanged()
        await store.refresh()
        do { try await store.deleteMine(expectedID: "review-one", generation: generation); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .identityChanged) }
        let target = ReportTarget(type: .app, id: "ai-sfc", appKey: "ai-sfc", label: "AI 春联")
        do { try await store.report(target: target, reason: .spam, detail: "旧说明", generation: generation); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .identityChanged) }
        let writes = await service.writes
        XCTAssertEqual(writes, 0)
    }
    func testGuestReportHistoryNeverRequestsPrivateData() async {
        let accounts = CommunityAccounts(nil), service = CommunityFixture()
        let store = MyReportsStore(accounts: accounts, service: service)
        await store.refresh()
        let calls = await service.reportLoads
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(accounts.refreshes.isEmpty)
        XCTAssertTrue(store.reports.isEmpty)
    }
    func testPrivateContentDisappearsEvenWhenUIUpdatesCoalesceBackToTheSameUID() async throws {
        let accounts = CommunityAccounts("a"), service = CommunityFixture()
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        await store.refresh()
        XCTAssertEqual(store.myReview?.uid, "a")
        accounts.select("b"); accounts.select("a")
        XCTAssertNil(store.myReview, "The UID is the same but the original session is gone")
        let oldGeneration = UUID()
        var draft = ReviewDraft(); draft.content = "旧草稿"
        do { _ = try await store.submit(draft, generation: oldGeneration); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .identityChanged) }
        let calls = await service.writes
        XCTAssertEqual(calls, 0)
    }

    func testLateWriteCannotPublishSuccessIntoANewAccount() async throws {
        let accounts = CommunityAccounts("a"), gate = CommunityGate()
        let service = CommunityFixture(writeGate: gate)
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        let generation = accounts.identityGeneration
        var draft = ReviewDraft(); draft.content = "新的使用体验"
        let pending = Task { try await store.submit(draft, generation: generation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("b")
        store.identityChanged()
        await gate.open()
        do { _ = try await pending.value; XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .identityChanged) }
        XCTAssertNil(store.myReview); XCTAssertNil(store.notice); XCTAssertFalse(store.isSubmitting)
    }

    func testAnOldReadCannotReplaceTheNewSubmissionAcknowledgement() async throws {
        let accounts = CommunityAccounts("a"), gate = CommunityGate()
        let service = CommunityFixture(loadGate: gate)
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        let loading = Task { await store.refresh() }
        await fulfillment(of: [gate.entered], timeout: 3)
        var draft = ReviewDraft(); draft.content = "新内容"
        let status = try await store.submit(draft, generation: accounts.identityGeneration)
        XCTAssertEqual(status, .pending)
        await gate.open(); await loading.value
        XCTAssertEqual(store.myReview?.content, "新内容")
        XCTAssertEqual(store.myReview?.status, .pending)
        XCTAssertFalse(store.isLoading)
    }

    func test401RefreshesOnlyOnceAndKeepsTheOwner() async throws {
        let accounts = CommunityAccounts("a")
        let service = CommunityFixture(unauthorizedOnce: true)
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        await store.refresh()
        XCTAssertEqual(accounts.refreshes, [false, true])
        XCTAssertEqual(store.myReview?.uid, "a")
        XCTAssertNil(store.error)
    }
    func testFailedRefreshKeepsValidContentAndShowsAnError() async throws {
        let accounts = CommunityAccounts("a"), service = CommunityFixture()
        let store = ReviewsStore(appKey: "ai-sfc", accounts: accounts, service: service)
        await store.refresh()
        await service.failLoads()
        await store.refresh()
        XCTAssertEqual(store.myReview?.uid, "a")
        XCTAssertNotNil(store.error)
    }
    func testReportsDoNotShowAnotherAccountsLateResponse() async throws {
        let accounts = CommunityAccounts("a"), gate = CommunityGate(), service = CommunityFixture(loadGate: nil, reportGate: nil)
        let store = MyReportsStore(accounts: accounts, service: service)
        await store.refresh()
        XCTAssertEqual(store.reports.count, 1)
        accounts.select("b")
        XCTAssertTrue(store.reports.isEmpty)
        let delayed = CommunityFixture(reportGate: gate)
        let second = MyReportsStore(accounts: accounts, service: delayed)
        let pending = Task { await second.refresh() }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("c")
        await gate.open(); await pending.value
        XCTAssertTrue(second.reports.isEmpty)
        XCTAssertFalse(second.hasLoaded)
    }
}

@MainActor
private final class CommunityAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser?
    var identityGeneration = UUID()
    var refreshes: [Bool] = []
    init(_ uid: String?) { user = uid.map { AccountUser(id: $0) } }
    func select(_ uid: String?) { user = uid.map { AccountUser(id: $0) }; identityGeneration = UUID() }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        refreshes.append(forceRefresh)
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: "test-\(user.id)")
    }
}
private actor CommunityGate {
    let entered = XCTestExpectation(description: "Community operation entered")
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
private actor CommunityFixture: CommunityServing {
    let loadGate: CommunityGate?, writeGate: CommunityGate?, reportGate: CommunityGate?
    var unauthorizedOnce: Bool
    var fails = false
    var writes = 0
    var reportLoads = 0
    init(loadGate: CommunityGate? = nil, writeGate: CommunityGate? = nil, reportGate: CommunityGate? = nil, unauthorizedOnce: Bool = false) {
        self.loadGate = loadGate; self.writeGate = writeGate; self.reportGate = reportGate; self.unauthorizedOnce = unauthorizedOnce
    }
    func failLoads() { fails = true }
    func reviews(appKey: String, identity: AuthorizedAccount?) async throws -> ReviewList {
        await loadGate?.wait()
        if fails { throw URLError(.notConnectedToInternet) }
        if unauthorizedOnce { unauthorizedOnce = false; throw CommunityError.unauthorized }
        return ReviewList(summary: ReviewSummary(average: 5, count: 1, distribution: ["1": 0, "2": 0, "3": 0, "4": 0, "5": 1]),
                          reviews: [communityReview(uid: "public-author", status: .published)],
                          myReview: identity.map { communityReview(uid: $0.userID, status: .published) })
    }
    func submit(appKey: String, draft: ReviewDraft, identity: AuthorizedAccount) async throws -> ReviewSubmission {
        writes += 1; await writeGate?.wait()
        return ReviewSubmission(status: .pending, review: communityReview(uid: identity.userID, status: .pending, content: draft.content))
    }
    func delete(reviewID: String, identity: AuthorizedAccount) async throws { writes += 1 }
    func report(target: ReportTarget, reason: ReportReason, detail: String, identity: AuthorizedAccount) async throws { writes += 1 }
    func reports(identity: AuthorizedAccount) async throws -> [MyReport] {
        reportLoads += 1
        await reportGate?.wait()
        return [MyReport(id: "r-one", targetType: .app, targetId: "ai-sfc", appKey: "ai-sfc", appName: nil, reason: .spam,
                         detail: "我的说明", status: .open, createdAt: 1_800_000_000_000, handledAt: nil)]
    }
}
private func communityReview(uid: String, status: ReviewStatus, content: String = "使用体验") -> AppReview {
    AppReview(id: "review-one", appKey: "ai-sfc", authorName: "测试账号", rating: 5, title: nil, content: content,
              createdAt: 1_800_000_000_000, updatedAt: 1_800_000_000_000, uid: uid, status: status, rejectedReason: nil)
}
private func reviewObject(_ review: AppReview) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as? [String: Any])
}
private func communityJSON(own: AppReview? = nil) -> String {
    let review = own.flatMap { try? reviewObject($0) }
    return (try? json(["code": 0, "data": ["summary": ["average": 0, "count": 0, "distribution": ["1": 0, "2": 0, "3": 0, "4": 0, "5": 0]],
                                                    "reviews": [], "myReview": review.map { $0 as Any } ?? NSNull()]])) ?? "{}"
}
private func json(_ value: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}
