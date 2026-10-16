import XCTest
@testable import YunleFun

func assistantEvent(_ fields: [String: Any]) throws -> AssistantEvent { try AssistantEvent(data: JSONSerialization.data(withJSONObject: fields)) }
func assistantEvents(input: AssistantRunInput, text: String = " 你好\n世界 ", finish: Bool = true) throws -> [AssistantEvent] {
    var events = try [
        assistantEvent(["type": "RUN_STARTED", "threadId": input.threadId, "runId": input.runId]),
        assistantEvent(["type": "TEXT_MESSAGE_START", "messageId": "reply", "role": "assistant"]),
        assistantEvent(["type": "TEXT_MESSAGE_CONTENT", "messageId": "reply", "delta": text]),
        assistantEvent(["type": "TEXT_MESSAGE_END", "messageId": "reply"])
    ]
    if finish { events.append(try assistantEvent(["type": "RUN_FINISHED", "threadId": input.threadId, "runId": input.runId])) }
    return events
}
let assistantInput = AssistantRunInput(botId: AssistantService.botID, threadId: "thread", runId: "run", messages: [.init(id: "user", role: .user, content: "找开发工具")])

final class AssistantProtocolTests: XCTestCase {
    func testSSEPreservesUTF8WhitespaceMultilineDataAndCRLFBOM() throws {
        let raw = "\u{FEFF}: ping\r\ndata: {\"content\":\r\ndata: \" 你好🌏\\n \"}\r\n\r\n"
        var decoder = AssistantSSEDecoder(), frames: [Data] = []
        for byte in raw.utf8 { if let frame = try decoder.append(byte) { frames.append(frame) } }
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(try AssistantEvent(data: frames[0]).content, " 你好🌏\n ")
    }
    func testSSEDoesNotDispatchAnIncompleteFinalEvent() throws {
        var decoder = AssistantSSEDecoder(), frames: [Data] = []
        for byte in "data: {\"content\":\"partial\"}\n".utf8 { if let frame = try decoder.append(byte) { frames.append(frame) } }
        XCTAssertTrue(frames.isEmpty)
    }
    func testInvalidUTF8AndOversizedFramesAreRejected() throws {
        var decoder = AssistantSSEDecoder()
        XCTAssertThrowsError(try (Array("data: ".utf8) + [255, 10]).forEach { _ = try decoder.append($0) })
        decoder = AssistantSSEDecoder()
        XCTAssertThrowsError(try Array(repeating: UInt8(65), count: 512 * 1024 + 1).forEach { _ = try decoder.append($0) })
    }
    func testRunIdentityAndMessageLifecycleAreRequired() throws {
        var accumulator = AssistantRunAccumulator(threadID: "thread", runID: "run")
        XCTAssertThrowsError(try accumulator.apply(assistantEvent(["type": "RUN_STARTED", "threadId": "other", "runId": "run"])))
        XCTAssertThrowsError(try accumulator.apply(assistantEvent(["type": "TEXT_MESSAGE_CONTENT", "messageId": "missing", "delta": "bad"])))
        for event in try assistantEvents(input: assistantInput) { try accumulator.apply(event) }
        XCTAssertTrue(accumulator.finished)
        XCTAssertEqual(accumulator.content, " 你好\n世界 ")
        XCTAssertThrowsError(try accumulator.apply(assistantEvent(["content": "late"])))
    }
    func testReasoningIsAStatusAndNeverReplyContent() throws {
        var accumulator = AssistantRunAccumulator(threadID: "thread", runID: "run")
        try accumulator.apply(assistantEvent(["reasoning_content": "private reasoning fixture"]))
        XCTAssertEqual(accumulator.status, "正在思考")
        XCTAssertTrue(accumulator.content.isEmpty)
    }
    func testLegacyContentNeedsAnExplicitDoneMarker() throws {
        var accumulator = AssistantRunAccumulator(threadID: "thread", runID: "run")
        try accumulator.apply(assistantEvent(["content": " a \n b "]))
        XCTAssertFalse(accumulator.finished)
        try accumulator.apply(AssistantEvent(data: Data("[DONE]".utf8)))
        XCTAssertTrue(accumulator.finished)
        XCTAssertEqual(accumulator.content, " a \n b ")
    }
    func testUnknownToolsCannotCreateApplicationCards() throws {
        var accumulator = AssistantRunAccumulator(threadID: "thread", runID: "run")
        try accumulator.apply(assistantEvent(["type": "RUN_STARTED", "threadId": "thread", "runId": "run"]))
        let cards = #"{"apps":[{"id":"known","slug":"public-key","name":"工具","websiteUrl":"https://untrusted.example"}]}"#
        try accumulator.apply(assistantEvent(["type": "TOOL_CALL_START", "toolCallId": "unknown", "toolCallName": "open_url"]))
        try accumulator.apply(assistantEvent(["type": "TOOL_CALL_RESULT", "toolCallId": "unknown", "content": cards]))
        XCTAssertTrue(accumulator.cards.isEmpty)
        try accumulator.apply(assistantEvent(["type": "TOOL_CALL_START", "toolCallId": "search", "toolCallName": "search_apps"]))
        try accumulator.apply(assistantEvent(["type": "TOOL_CALL_RESULT", "toolCallId": "search", "content": cards]))
        XCTAssertEqual(accumulator.cards.count, 1)
        let app = CloudApplication(id: "known", name: "正式工具", marketShortName: "public-key", websiteUrl: "https://trusted.example", coinCost: 10)
        let resolved = accumulator.cards[0].resolve(in: [app])
        XCTAssertEqual(resolved?.websiteUrl, "https://trusted.example")
        XCTAssertEqual(resolved?.coinCost, 10)
    }
    func testCardsRejectAmbiguousSlugsPrivateEditionsAndWrongIDs() {
        let card = AssistantAppCard(applicationID: nil, slug: "local", name: "工具", reason: nil)
        let a = CloudApplication(id: "a", name: "A", slug: "local", marketShortName: "public-a", websiteUrl: "https://a.example")
        let b = CloudApplication(id: "b", name: "B", slug: "local", marketShortName: "public-b", websiteUrl: "https://b.example")
        XCTAssertNil(card.resolve(in: [a, b]))
        let wrong = AssistantAppCard(applicationID: "missing", slug: "public-a", name: "工具", reason: nil)
        XCTAssertNil(wrong.resolve(in: [a]))
        var scoped = a; scoped.accessWorkshopID = "ABC234"
        XCTAssertNil(AssistantAppCard(applicationID: "a", slug: "public-a", name: "工具", reason: nil).resolve(in: [scoped]))
    }
    func testMarkdownPreservesCodeListsAndRejectsUnsafeLinks() {
        let fence = "\u{0060}\u{0060}\u{0060}"
        let blocks = AssistantMarkdown.blocks("# 标题\n\n- 应用\n1. 打开\n> 引用\n" + fence + "swift\nlet x = 1\n" + fence)
        XCTAssertEqual(blocks, [.heading("标题"), .bullet("•", "应用"), .bullet("1.", "打开"), .quote("引用"), .code("let x = 1")])
        for url in ["javascript:alert(1)", "data:text/html,hi", "yunlefun://app/other", "https://user:pass@example.com", "http://example.com"] {
            XCTAssertFalse(AssistantMarkdown.safeLink(URL(string: url)!))
        }
        XCTAssertTrue(AssistantMarkdown.safeLink(URL(string: "https://example.com/help")!))
        let attributed = AssistantMarkdown.inline("[bad](javascript:alert) and [ok](https://example.com)")
        XCTAssertEqual(attributed.runs.compactMap(\.link), [URL(string: "https://example.com")!])
    }
}

final class AssistantServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }
    func testBearerSSEProtocolUsesExistingAgentWithNoCallerUIDOrAPIKey() async throws {
        let fields: [[String: Any]] = [
            ["type": "RUN_STARTED", "threadId": "thread", "runId": "run"],
            ["type": "TEXT_MESSAGE_START", "messageId": "reply"],
            ["type": "TEXT_MESSAGE_CONTENT", "messageId": "reply", "delta": " text \n"],
            ["type": "TEXT_MESSAGE_END", "messageId": "reply"],
            ["type": "RUN_FINISHED", "threadId": "thread", "runId": "run"]
        ]
        let body = try fields.map { "data: " + String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! + "\n\n" }.joined()
        let (service, fixture) = service(status: 200, body: body, type: "text/event-stream")
        let stream = try await service.events(input: assistantInput, identity: .init(userID: "alice", accessToken: "fixture-only"))
        var events: [AssistantEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[2].delta, " text \n")
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/aibot/bots/" + AssistantService.botID + "/send-message")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
        let input = try JSONSerialization.jsonObject(with: walletRequestBody(request)) as! [String: Any]
        XCTAssertNil(input["userId"]); XCTAssertNil(input["apiKey"]); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
    func testMemberRestrictionQuotaAndAccountOutageAreDistinct() async throws {
        for (status, body, expected) in [
            (401, "{}", AssistantError.unauthorized), (403, #"{"code":"MEMBERSHIP_REQUIRED"}"#, .membershipRequired),
            (403, #"{"code":"ACCOUNT_RESTRICTED"}"#, .forbidden), (429, "{}", .quota), (503, "{}", .unavailable)
        ] {
            let (service, _) = service(status: status, body: body, type: "application/json")
            do { _ = try await service.events(input: assistantInput, identity: .init(userID: "alice", accessToken: "fixture-only")); XCTFail("Expected a rejected stream") }
            catch { XCTAssertEqual(error as? AssistantError, expected) }
        }
    }
    func testJSONOrHTML200IsNotAReplyStream() async throws {
        for type in ["application/json", "text/html"] {
            let (service, _) = service(status: 200, body: "{}", type: type)
            do { _ = try await service.events(input: assistantInput, identity: .init(userID: "alice", accessToken: "fixture-only")); XCTFail("Require SSE") }
            catch { XCTAssertEqual(error as? AssistantError, .invalidResponse) }
        }
    }
    private func service(status: Int, body: String, type: String) -> (AssistantService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".assistant.test"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: [(status, body)], contentType: type); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (AssistantService(session: URLSession(configuration: config), gateway: URL(string: "https://\(host)")!), fixture)
    }
}

actor AssistantFixture: AssistantServing {
    let started = XCTestExpectation(description: "assistant stream started")
    private(set) var inputs: [AssistantRunInput] = []
    private var continuations: [String: AsyncThrowingStream<AssistantEvent, Error>.Continuation] = [:]
    let automatic: Bool
    let finish: Bool
    init(automatic: Bool = true, finish: Bool = true) { self.automatic = automatic; self.finish = finish }
    func events(input: AssistantRunInput, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<AssistantEvent, Error> {
        inputs.append(input)
        let stream = AsyncThrowingStream<AssistantEvent, Error> { continuations[input.runId] = $0 }
        if automatic {
            for event in try assistantEvents(input: input, finish: finish) { continuations[input.runId]?.yield(event) }
            continuations[input.runId]?.finish()
        }
        started.fulfill()
        return stream
    }
    func emitAndFinish(_ input: AssistantRunInput) throws {
        for event in try assistantEvents(input: input) { continuations[input.runId]?.yield(event) }
        continuations[input.runId]?.finish()
    }
    func search(query: String, identity: AuthorizedAccount) async throws -> [AssistantAppCard] { [] }
}
actor AssistantWalletFixture: WalletServing {
    let member: Bool
    let gate: BillingGate?
    init(member: Bool = true, gate: BillingGate? = nil) { self.member = member; self.gate = gate }
    func account(identity: AuthorizedAccount) async throws -> WalletSnapshot {
        if let gate { await gate.wait() }
        return WalletSnapshot(coin: 10, membership: .init(isActive: member, level: member ? "basic" : nil, expireAt: member ? 4_000_000_000_000 : nil))
    }
    func transactions(skip: Int, limit: Int, identity: AuthorizedAccount) async throws -> CoinLedgerPage { throw WalletError.unavailable }
    func verify(transactionID: String, identity: AuthorizedAccount) async throws -> IapVerificationReceipt { throw WalletError.unavailable }
    func reconcile(identity: AuthorizedAccount) async throws -> WalletReconciliation { throw WalletError.unavailable }
    func purchaseReadiness(identity: AuthorizedAccount) async throws { throw WalletError.unavailable }
}
@MainActor
final class AssistantStoreTests: XCTestCase {
    func testSuccessfulReplyPreservesWhitespaceAndStartsOnlyOneRun() async throws {
        let accounts = BillingAccounts(), service = AssistantFixture()
        let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture())
        store.draft = "找工具"
        await store.send()?.value
        XCTAssertEqual(store.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.messages.last?.content, " 你好\n世界 ")
        XCTAssertEqual(store.messages.last?.status, .done)
        XCTAssertFalse(store.running); XCTAssertNil(store.error)
        let requests = await service.inputs; XCTAssertEqual(requests.count, 1)
    }
    func testGuestAndNonmemberNeverSendAnAgentRequest() async {
        for guest in [false, true] {
            let accounts = BillingAccounts(), service = AssistantFixture()
            if guest { accounts.select(nil) }
            let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture(member: false))
            store.draft = "问题"; await store.send()?.value
            let requests = await service.inputs; XCTAssertTrue(requests.isEmpty)
            XCTAssertTrue(store.messages.isEmpty); XCTAssertEqual(store.draft, "问题")
        }
    }
    func testPartialEOFIsAnErrorRatherThanSuccess() async {
        let service = AssistantFixture(finish: false)
        let store = AssistantStore(accounts: BillingAccounts(), service: service, wallet: AssistantWalletFixture())
        store.draft = "问题"; await store.send()?.value
        XCTAssertEqual(store.messages.last?.status, .failed)
        XCTAssertEqual(store.messages.last?.content, " 你好\n世界 ")
        XCTAssertEqual(store.error, AssistantError.interrupted.message)
    }
    func testRetryDoesNotAppendTheSameUserMessageTwice() async {
        let store = AssistantStore(accounts: BillingAccounts(), service: AssistantFixture(finish: false), wallet: AssistantWalletFixture())
        store.draft = "问题"; await store.send()?.value; await store.retry()?.value
        XCTAssertEqual(store.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(store.messages.filter { $0.role == .assistant }.count, 1)
    }
    func testABASwitchDuringPreflightDoesNotSendOrExposeOldDraft() async throws {
        let accounts = BillingAccounts(), service = AssistantFixture(), gate = BillingGate()
        let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture(gate: gate))
        store.draft = "private question"; let task = store.send()
        await fulfillment(of: [gate.entered], timeout: 2)
        accounts.select("bob"); accounts.select("alice")
        XCTAssertTrue(store.draft.isEmpty); XCTAssertTrue(store.messages.isEmpty)
        await gate.open(); await task?.value
        let requests = await service.inputs; XCTAssertTrue(requests.isEmpty)
    }
    func testStopAndResetDiscardLateEventsWithoutReusingThread() async throws {
        let service = AssistantFixture(automatic: false)
        let store = AssistantStore(accounts: BillingAccounts(), service: service, wallet: AssistantWalletFixture())
        store.draft = "问题"; let task = store.send()
        await fulfillment(of: [service.started], timeout: 2)
        let requests = await service.inputs
        let old = try XCTUnwrap(requests.first)
        store.stop(); XCTAssertFalse(store.running)
        XCTAssertEqual(store.messages.last?.status, .stopped)
        store.reset(); XCTAssertNotEqual(store.threadID, old.threadId)
        try await service.emitAndFinish(old); await task?.value
        XCTAssertTrue(store.messages.isEmpty); XCTAssertNil(store.error)
    }
    func testIdentityChangeDuringStreamHidesReplyAndDropsLateEvents() async throws {
        let accounts = BillingAccounts(), service = AssistantFixture(automatic: false)
        let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture())
        store.draft = "私密问题"; let task = store.send()
        await fulfillment(of: [service.started], timeout: 2)
        let requests = await service.inputs
        let old = try XCTUnwrap(requests.first)
        accounts.select("bob")
        XCTAssertTrue(store.messages.isEmpty); XCTAssertNil(store.error)
        try await service.emitAndFinish(old); await task?.value
        XCTAssertTrue(store.messages.isEmpty)
    }
}
