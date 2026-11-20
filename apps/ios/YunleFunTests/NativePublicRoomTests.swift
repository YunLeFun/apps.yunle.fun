import Combine
import XCTest
@testable import YunleFun

final class NativePublicRoomTests: XCTestCase {
    func testDirectorySelectionUsesExistingJoinAndSpectatorIntents() throws {
        let rooms = try NativePublicRoom.decodeList(data([
            room("ABC234", status: "waiting"), room("DEF567", status: "playing"), room("GHI890", status: "completed"),
        ]))
        XCTAssertEqual(try rooms[0].intent(), try NativeGameRoomIntent(input: "ABC234"))
        XCTAssertEqual(try rooms[1].intent().url.absoluteString, "https://play.yunle.fun/room/DEF567?role=spectator")
        XCTAssertEqual(try rooms[2].intent().role, .player)
    }

    func testRejectsInvalidCodesCountsStatusDuplicatesAndNonDirectoryResponses() throws {
        for code in ["bad", "abc234", "https://play.yunle.fun/room/ABC234", "ABC234?role=player"] {
            XCTAssertThrowsError(try NativePublicRoom.decodeList(data([room(code)])), code)
        }
        for (key, value) in [("memberCount", 0), ("memberCount", 4), ("capacity", 3)] {
            var invalid = room("ABC234"); invalid[key] = value
            XCTAssertThrowsError(try NativePublicRoom.decodeList(data([invalid])))
        }
        for (key, value) in [("status", "expired"), ("gameId", "../other")] {
            var invalid = room("ABC234"); invalid[key] = value
            XCTAssertThrowsError(try NativePublicRoom.decodeList(data([invalid])))
        }
        XCTAssertThrowsError(try NativePublicRoom.decodeList(data([room("ABC234"), room("ABC234")])))
        XCTAssertThrowsError(try NativePublicRoom.decodeList(data(Array(repeating: room("ABC234"), count: 51))))
        XCTAssertThrowsError(try NativePublicRoom.decodeList(Data(#"{"ok":false,"rooms":[]}"#.utf8)))
        XCTAssertEqual(try NativePublicRoom.decodeList(data([])), [])
    }

    func testPublicRequestOmitsCredentialsAndRejectsHTMLAndUnavailableResponses() async throws {
        for (status, contentType, body, succeeds) in [
            (200, "application/json", String(data: try data([room("ABC234")]), encoding: .utf8)!, true),
            (200, "text/html", "<html>fallback</html>", false),
            (503, "application/json", #"{"ok":false}"#, false),
        ] {
            let host = UUID().uuidString.lowercased() + ".public-rooms.test"
            let fixture = AuthHTTPFixture(replies: [(status, body)], contentType: contentType)
            AuthHTTPProtocol.register(host, fixture: fixture)
            defer { AuthHTTPProtocol.unregister(host) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AuthHTTPProtocol.self]
            let service = NativePublicRoomService(session: URLSession(configuration: config), endpoint: URL(string: "https://\(host)/v1/rooms/public")!)
            do {
                let rooms = try await service.rooms()
                XCTAssertTrue(succeeds)
                XCTAssertEqual(rooms.map(\.inviteCode), ["ABC234"])
            } catch { XCTAssertFalse(succeeds) }
            XCTAssertEqual(fixture.requests.count, 1)
            XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(fixture.requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")
        }
    }

    @MainActor
    func testCancelledLoadFinishesWithoutAnErrorAndCanBeRetried() async throws {
        let rooms = try NativePublicRoom.decodeList(data([room("ABC234")]))
        let store = NativePublicRoomStore(service: PublicRoomSequence(results: [.failure(CancellationError()), .success(rooms)]))
        await store.load()
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.rooms.isEmpty)
        XCTAssertNil(store.error)
        await store.load()
        XCTAssertEqual(store.rooms, rooms)
    }

    @MainActor
    func testFailedRefreshClearsPreviouslyAvailableRoomsAndRetryRecovers() async throws {
        let rooms = try NativePublicRoom.decodeList(data([room("ABC234")]))
        let store = NativePublicRoomStore(service: PublicRoomSequence(results: [
            .success(rooms), .failure(NativePublicRoomError.unavailable), .success([]),
        ]))
        await store.load()
        XCTAssertEqual(store.rooms, rooms)
        await store.load()
        XCTAssertTrue(store.rooms.isEmpty)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isLoading)
        await store.load()
        XCTAssertTrue(store.rooms.isEmpty)
        XCTAssertNil(store.error)
    }

    func testConversationCardMatchesPortableEnvelopeAndKeepsFutureFallback() throws {
        let publicRoom = try XCTUnwrap(NativePublicRoom.decodeList(data([room("ABC234")])).first)
        let card = ConversationCard(publicRoom: publicRoom)
        let encoded = try JSONEncoder().encode(card)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(fields["schemaVersion"] as? Int, 1)
        XCTAssertEqual(fields["type"] as? String, "play.public-room")
        XCTAssertEqual(fields["id"] as? String, "play-room:ABC234")
        XCTAssertEqual(fields["payload"] as? [String: String], ["inviteCode": "ABC234"])
        XCTAssertNil(fields["memberCount"], "History should store the reference rather than the live seats")
        XCTAssertEqual(try JSONDecoder().decode(ConversationCard.self, from: encoded).publicRoomCode, "ABC234")

        let future = Data(#"{"schemaVersion":2,"type":"play.public-room","id":"play-room:ABC234","fallbackText":"继续查看房间","payload":{"room":{"code":"ABC234"}}}"#.utf8)
        let decoded = try JSONDecoder().decode(ConversationCard.self, from: future)
        XCTAssertEqual(decoded.fallbackText, "继续查看房间")
        XCTAssertNil(decoded.publicRoomCode)
        let mismatched = Data(#"{"schemaVersion":1,"type":"play.public-room","id":"play-room:ABC234","fallbackText":"公开房间","payload":{"inviteCode":"DEF567"}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ConversationCard.self, from: mismatched).publicRoomCode)
    }

    @MainActor
    func testAssistantLoadsPublicRoomReferencesAndRestoresThemInHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = AssistantHistory(directory: directory)
        let publicRooms = try NativePublicRoom.decodeList(data([
            room("ABC234"), room("DEF567"), room("GHI890"), room("JKL123")
        ]))
        let agent = AssistantFixture()
        let chat = AssistantStore(accounts: BillingAccounts(), service: agent, wallet: AssistantWalletFixture(),
                                  history: history, publicRooms: PublicRoomSequence(results: [.success(publicRooms)]))
        chat.draft = AssistantStore.publicRoomPrompt
        await chat.send()?.value

        XCTAssertNil(chat.error)
        let agentInputs = await agent.inputs
        XCTAssertTrue(agentInputs.isEmpty)
        XCTAssertEqual(chat.messages.last?.status, .done)
        XCTAssertEqual(chat.messages.last?.conversationCards?.compactMap(\.publicRoomCode), ["ABC234", "DEF567", "GHI890"])
        let saved = try XCTUnwrap(history.load(accountID: "alice").first)
        XCTAssertTrue(chat.reset())
        XCTAssertTrue(chat.open(saved.id))
        XCTAssertEqual(chat.messages.last?.conversationCards, saved.messages.last?.conversationCards)
    }

    @MainActor
    func testAssistantRoomFeedUpdatesSeatsAndDisablesMissingRoom() async throws {
        let waiting = try NativePublicRoom.decodeList(data([room("ABC234")]))
        var updated = room("ABC234", status: "playing")
        updated["memberCount"] = 2
        let playing = try NativePublicRoom.decodeList(data([updated]))
        let feed = AssistantRoomFeed(service: PublicRoomSequence(results: [.success(waiting), .success(playing), .success([])]))
        let changed = expectation(description: "Every public snapshot arrives in order")
        changed.expectedFulfillmentCount = 3
        var snapshots: [[NativePublicRoom]] = []
        let subscription = feed.$state.sink { state in
            if case .current(let rooms) = state { snapshots.append(rooms); changed.fulfill() }
        }
        let watch = Task { await feed.watch() }
        await fulfillment(of: [changed], timeout: 16)
        watch.cancel()
        await watch.value
        subscription.cancel()

        XCTAssertEqual(snapshots, [waiting, playing, []])
        XCTAssertEqual(try XCTUnwrap(snapshots.dropFirst().first?.first).intent().role, .spectator)
        XCTAssertEqual(feed.state, .loading)
    }

    private func room(_ code: String, status: String = "waiting") -> [String: Any] {
        ["inviteCode": code, "gameId": "gomoku", "status": status, "memberCount": 1, "capacity": 4]
    }
    private func data(_ rooms: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["ok": true, "rooms": rooms])
    }
}

private actor PublicRoomSequence: NativePublicRoomServing {
    var results: [Result<[NativePublicRoom], Error>]
    init(results: [Result<[NativePublicRoom], Error>]) { self.results = results }
    func rooms() async throws -> [NativePublicRoom] { try results.removeFirst().get() }
}
