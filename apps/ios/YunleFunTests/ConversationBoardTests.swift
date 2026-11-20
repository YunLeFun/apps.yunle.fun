import SwiftUI
import XCTest
@testable import YunleFun

final class ConversationBoardTests: XCTestCase {
    private let boardID = "9fad9eef-b0da-4b0f-8161-79bfc59c88bc"

    func testCommonLinkAndLegacyCardsResolveToTheirOriginalInstances() throws {
        for (type, prefix, payloadKey) in [("team.signup", "team-signup", "signupId"), ("play.board", "play-board", "boardId")] {
            let reference = try XCTUnwrap(ConversationCardReference(type: type, instanceID: boardID))
            let link = ConversationCardLink(reference: reference)
            XCTAssertEqual(link.url.absoluteString, "https://apps.yunle.fun/cards/\(type)/\(boardID)")
            XCTAssertEqual(ConversationCardLink.parse(link.url), link)
            XCTAssertEqual(ConversationCardLink.parse(URL(string: "yunlefun://card/\(type)/\(boardID)")!), link)
            XCTAssertNil(ConversationCardLink.parse(URL(string: link.url.absoluteString + "?role=player")!))
            let legacy = """
            {"schemaVersion":1,"type":"\(type)","id":"\(prefix):\(boardID)","fallbackText":"摘要","payload":{"\(payloadKey)":"\(boardID)"}}
            """
            let saved = try JSONDecoder().decode(ConversationCard.self, from: Data(legacy.utf8))
            XCTAssertEqual(saved.reference, reference)
        }
        let legacyBoardURL = URL(string: "https://apps.yunle.fun/boards/" + boardID)!
        XCTAssertEqual(ConversationCardLink.parse(legacyBoardURL)?.reference.type, "play.board")
        XCTAssertEqual(ConversationCardLink.parse(legacyBoardURL)?.reference.instanceId, boardID)
    }

    func testCommonServiceReadsTemplatesAndRejectsUnknownComponents() async throws {
        let reference = try XCTUnwrap(ConversationCardReference(type: "team.signup", instanceID: boardID))
        let payload = """
        {
          "schemaVersion":1,"reference":{"type":"team.signup","instanceId":"\(boardID)"},
          "revision":2,"finished":false,"fallbackText":"周末联机",
          "template":{"schemaVersion":1,"components":[
            {"kind":"text","field":"subtitle"},{"kind":"title","field":"title"},
            {"kind":"seats","filled":"count","total":"capacity"},{"kind":"button","action":"signup.cancel"}
          ]},
          "data":{"title":"动态标题","subtitle":"模板决定顺序","count":1,"capacity":2},
          "actions":{"signup.cancel":{"label":"取消报名","enabled":true}}
        }
        """
        let host = UUID().uuidString.lowercased() + ".card.test"
        let unsupported = payload.replacingOccurrences(of: #""kind":"seats""#, with: #""kind":"future-widget""#)
        let fixture = AuthHTTPFixture(replies: [(200, payload), (200, unsupported)])
        AuthHTTPProtocol.register(host, fixture: fixture)
        defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPProtocol.self]
        let service = NativeConversationCardService(session: URLSession(configuration: config), origin: URL(string: "https://" + host)!)
        let identity = AuthorizedAccount(userID: "fixture", accessToken: "fixture-token")
        let card = try await service.load(reference, identity: identity)
        XCTAssertEqual(card.template.components.map(\.kind), [.text, .title, .seats, .button])
        XCTAssertEqual(card.text(card.template.components[0].field), "模板决定顺序")
        XCTAssertEqual(card.actions["signup.cancel"]?.label, "取消报名")
        do {
            _ = try await service.load(reference, identity: identity)
            XCTFail("Unknown components should use the message fallback")
        } catch {
            XCTAssertEqual(error as? NativeConversationCardError, .unsupported)
        }
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.path == "/api/conversation-cards/team.signup/" + boardID })
    }

    func testShareLinkRoundTripsThroughHTTPSAndBrowserFallback() throws {
        let link = try XCTUnwrap(ConversationBoardLink(boardID: boardID))
        let expected = "https://apps.yunle.fun/boards/" + boardID
        XCTAssertEqual(link.url.absoluteString, expected)
        XCTAssertEqual(ConversationBoardLink.parse(link.url), link)
        XCTAssertEqual(ConversationBoardLink.parse(URL(string: "yunlefun://board/" + boardID)!), link)

        for invalid in [
            "http://apps.yunle.fun/boards/" + boardID,
            "https://example.com/boards/" + boardID,
            "https://user@apps.yunle.fun/boards/" + boardID,
            "https://apps.yunle.fun:444/boards/" + boardID,
            "https://apps.yunle.fun/boards/%39" + String(boardID.dropFirst()),
            "yunlefun://boards/" + boardID, expected + "/", expected + "?role=player",
            expected + "#other", "https://apps.yunle.fun/boards/" + boardID.uppercased()
        ] {
            XCTAssertNil(ConversationBoardLink.parse(try XCTUnwrap(URL(string: invalid))), invalid)
        }
    }

    func testSceneAndReferenceDecodeAndUnsupportedInteractionFallsBack() throws {
        let data = try JSONEncoder().encode(boardFixture(id: boardID, played: true))
        let snapshot = try JSONDecoder().decode(ConversationBoardSnapshot.self, from: data)
        try snapshot.validate(for: boardID)
        XCTAssertEqual(snapshot.scene.size, 11)
        XCTAssertEqual(snapshot.scene.interaction.gesture, .dragToPlace)
        XCTAssertTrue(snapshot.canPlace)
        XCTAssertFalse(snapshot.allows(.init(row: 4, column: 6)))
        XCTAssertFalse(snapshot.allows(.init(row: -1, column: 6)))
        XCTAssertTrue(snapshot.allows(.init(row: 4, column: 7)))
        XCTAssertThrowsError(try snapshot.validate(for: UUID().uuidString.lowercased()))
        let unsupported = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "drag-to-place", with: "remote-script")
        XCTAssertThrowsError(try JSONDecoder().decode(ConversationBoardSnapshot.self, from: Data(unsupported.utf8)))

        let saved = try JSONEncoder().encode(ConversationCard(board: snapshot))
        let card = try JSONDecoder().decode(ConversationCard.self, from: saved)
        XCTAssertEqual(card.boardId, boardID)
        let future = """
        {"id":"play-board:\(boardID)","type":"play.board","schemaVersion":3,"fallbackText":"联机五子棋","payload":{"instanceId":"\(boardID)"}}
        """
        let fallback = try JSONDecoder().decode(ConversationCard.self, from: Data(future.utf8))
        XCTAssertNil(fallback.boardId)
        XCTAssertEqual(fallback.fallbackText, "联机五子棋")
    }

    func testCanvasHitRegionsRoundTripAndIgnoreTray() {
        let layout = ConversationBoardLayout(in: CGSize(width: 300, height: 352), size: 11)
        for row in 0..<11 {
            for column in 0..<11 {
                let point = ConversationBoardPosition(row: row, column: column)
                XCTAssertEqual(layout.intersection(at: layout.center(point)), point)
            }
        }
        XCTAssertNil(layout.intersection(at: CGPoint(x: 150, y: 325)))
        XCTAssertNil(layout.intersection(at: CGPoint(x: 300, y: 30)))
        XCTAssertNil(layout.intersection(at: CGPoint(x: -1, y: 30)))
        XCTAssertNil(ConversationBoardLayout(in: .zero, size: 11).intersection(at: .zero))
    }

    func testAuthenticatedSnapshotStreamAndVersionedPlaceAction() async throws {
        let host = UUID().uuidString.lowercased() + ".board.test"
        let data = try JSONEncoder().encode(boardFixture(id: boardID, played: true))
        let json = String(decoding: data, as: UTF8.self)
        let fixture = AuthHTTPFixture(replies: [(200, ": ping\n\ndata: " + json + "\n\n")], contentType: "text/event-stream")
        AuthHTTPProtocol.register(host, fixture: fixture)
        defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPProtocol.self]
        let service = ConversationBoardService(session: URLSession(configuration: config), origin: URL(string: "https://" + host)!)
        let identity = AuthorizedAccount(userID: "white", accessToken: "only-fixture")
        let stream = try await service.events(id: boardID, identity: identity)
        var results: [ConversationBoardSnapshot] = []
        for try await snapshot in stream { results.append(snapshot) }
        XCTAssertEqual(results, [boardFixture(id: boardID, played: true)])
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/api/boards/" + boardID + "/events")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer only-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let actionID = UUID().uuidString.lowercased()
        let encoded = try JSONEncoder().encode(ConversationBoardAction.place(.init(row: 4, column: 7), revision: 3, id: actionID))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: AnyHashable])
        XCTAssertEqual(fields, ["action": "place", "row": 4, "column": 7, "expectedRevision": 3, "actionId": actionID])
    }

    @MainActor
    func testCreateRetryAndSharedOpenUseTheSameBoardWithoutSubmittingInviteToAgent() async throws {
        let service = BoardCardFixture()
        let agent = AssistantFixture()
        let chat = AssistantStore(accounts: BillingAccounts(), service: agent, wallet: AssistantWalletFixture(), boardService: service)
        chat.draft = ConversationBoardCommand.createPrompt
        await chat.send()?.value
        let card = try XCTUnwrap(chat.messages.last?.conversationCards?.first)
        let id = try XCTUnwrap(card.boardId)
        await chat.retry()?.value
        XCTAssertEqual(chat.messages.last?.conversationCards, [card])
        chat.draft = ConversationBoardCommand.openPrompt + " " + id
        await chat.send()?.value
        XCTAssertEqual(chat.messages.last?.conversationCards, [card])
        chat.draft = "推荐几款棋盘游戏"
        await chat.send()?.value
        let inputs = await agent.inputs
        XCTAssertEqual(inputs.count, 1)
        XCTAssertTrue(inputs[0].messages.allSatisfy { !$0.content.contains(id) })
    }
}

private func boardFixture(id: String, played: Bool) -> ConversationBoardSnapshot {
    let scene = ConversationBoardScene(schemaVersion: 1, size: 11,
                                       palette: .init(board: "#ecc28d", grid: "#45323a", black: "#1b1c22", white: "#fbeedd"),
                                       interaction: .init(gesture: .dragToPlace, action: .place))
    return ConversationBoardSnapshot(schemaVersion: 1, boardId: id, scene: scene, revision: played ? 3 : 1,
                                     status: played ? .playing : .waiting, seat: played ? .white : .black,
                                     turn: played ? .white : nil, winner: nil,
                                     pieces: played ? [.init(row: 4, column: 6, color: .black)] : [])
}

private struct BoardCardFixture: ConversationBoardServing {
    func load(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot { boardFixture(id: id, played: false) }
    func create(id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot { boardFixture(id: id, played: false) }
    func act(_ action: ConversationBoardAction, id: String, identity: AuthorizedAccount) async throws -> ConversationBoardSnapshot {
        throw ConversationBoardError.unavailable
    }
    func events(id: String, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<ConversationBoardSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(boardFixture(id: id, played: true))
            continuation.finish()
        }
    }
}
