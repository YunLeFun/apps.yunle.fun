import XCTest
@testable import YunleFun

final class NativeGameLifecycleTests: XCTestCase {
    func testSharedRoomLinkCanBeJoinedWithoutHostOperationOrLoginParameters() throws {
        let source = try XCTUnwrap(URL(string: "https://play.yunle.fun/room/AB23CD?role=spectator&ylfLaunchId=private-operation&ylfGameId=room&ylfMode=online&code=one-time#fragment"))
        let publicURL = try XCTUnwrap(NativeGameLaunchURL.publicURL(source))
        let intent = try NativeGameRoomIntent(input: publicURL.absoluteString)
        XCTAssertEqual(intent.inviteCode, "AB23CD")
        XCTAssertEqual(intent.role, .spectator)
        XCTAssertEqual(publicURL.absoluteString, "https://play.yunle.fun/room/AB23CD?role=spectator")
        XCTAssertEqual(NativeGameLaunchURL.publicURL(URL(string: "https://play.yunle.fun/games/gomoku/computer?ylfLaunchId=private&code=one-time")!)?.absoluteString,
                       "https://play.yunle.fun/games/gomoku/computer")
        for value in ["https://evil.test/room/AB23CD", "https://user@play.yunle.fun/room/AB23CD", "https://play.yunle.fun/auth/callback?code=one-time"] {
            XCTAssertNil(NativeGameLaunchURL.publicURL(URL(string: value)!))
        }
    }

    func testReadyRequiresMatchingLaunchGameModeAndTrustedOrigin() {
        let id = UUID()
        let body = event(id: id)
        let source = URL(string: "https://play.yunle.fun/games/gomoku/computer")!
        XCTAssertEqual(NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "gomoku", modeID: "computer")?.state, .ready)
        XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: source, launchID: UUID(), gameID: "gomoku", modeID: "computer"))
        XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "paper-star", modeID: "computer"))
        XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "gomoku", modeID: "local"))
        for value in ["http://play.yunle.fun/games/gomoku/computer", "https://evil.test/", "https://play.yunle.fun.evil.test/",
                      "https://secret@play.yunle.fun/", "https://play.yunle.fun:8443/"] {
            XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: URL(string: value)!, launchID: id, gameID: "gomoku", modeID: "computer"), value)
        }
    }

    func testMalformedOversizedOrUnsupportedEventsCannotBecomeReady() {
        let id = UUID(), source = URL(string: "https://play.yunle.fun/games/gomoku/computer")!
        for (key, value) in [("schemaVersion", 2 as Any), ("launchId", "not-a-uuid" as Any), ("state", "made-up" as Any),
                             ("elapsedMilliseconds", -1 as Any), ("elapsedMilliseconds", 86_400_001 as Any)] {
            var body = event(id: id); body[key] = value
            XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "gomoku", modeID: "computer"), key)
        }
        var oversized = event(id: id); oversized["ignored"] = String(repeating: "x", count: 8192)
        XCTAssertNil(NativeGameLifecycleEvent.parse(oversized, source: source, launchID: id, gameID: "gomoku", modeID: "computer"))
        var invalidJSON = event(id: id); invalidJSON["elapsedMilliseconds"] = Double.nan
        XCTAssertNil(NativeGameLifecycleEvent.parse(invalidJSON, source: source, launchID: id, gameID: "gomoku", modeID: "computer"))
    }

    func testRoomEventsPreserveRoleAndRejectMalformedReferences() {
        let id = UUID(), source = URL(string: "https://play.yunle.fun/room/AB23CD?role=spectator")!
        var body = event(id: id, gameID: "room", modeID: "online")
        body["state"] = "room-ready"
        body["room"] = ["inviteCode": "AB23CD", "role": "spectator", "state": "waiting", "gameId": "gomoku"]
        let parsed = NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "room", modeID: "online")
        XCTAssertEqual(parsed?.room?.role, "spectator")
        XCTAssertEqual(parsed?.room?.inviteCode, "AB23CD")
        for room: [String: Any] in [
            ["inviteCode": "AB23CD\n", "role": "player"], ["inviteCode": "SHORT", "role": "player"],
            ["inviteCode": "AB23CD", "role": "owner"], ["inviteCode": "AB23CD", "role": "player", "state": "bad\nstate"],
            ["inviteCode": "AB23CD", "role": "player", "state": String(repeating: "x", count: 65)],
        ] {
            body["room"] = room
            XCTAssertNil(NativeGameLifecycleEvent.parse(body, source: source, launchID: id, gameID: "room", modeID: "online"), "\(room)")
        }
    }

    func testContextDoesNotAllowReservedParametersOrUntrustedOrigins() throws {
        let id = UUID()
        let plain = URL(string: "https://play.yunle.fun/games/gomoku/computer")!
        let result = try XCTUnwrap(NativeGameLaunchURL.addingContext(to: plain, launchID: id, gameID: "gomoku", modeID: "computer"))
        let query = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.filter { $0.name == "ylfLaunchId" }.map(\.value), [id.uuidString])
        XCTAssertEqual(query.filter { $0.name == "ylfGameId" }.map(\.value), ["gomoku"])
        XCTAssertEqual(query.filter { $0.name == "ylfMode" }.map(\.value), ["computer"])
        for value in ["http://play.yunle.fun/games/gomoku/computer", "https://evil.test/", "https://user@play.yunle.fun/",
                      "https://play.yunle.fun:8443/", "https://play.yunle.fun/games/gomoku/computer?ylfLaunchId=old",
                      "https://play.yunle.fun/games/gomoku/computer?ylfGameId=other",
                      "https://play.yunle.fun/games/gomoku/computer?ylfMode=local", "https://play.yunle.fun/games/gomoku/computer#fragment"] {
            XCTAssertNil(NativeGameLaunchURL.addingContext(to: URL(string: value)!, launchID: id, gameID: "gomoku", modeID: "computer"), value)
        }
        XCTAssertNil(NativeGameLaunchURL.addingContext(to: plain, launchID: id, gameID: "gomoku\n", modeID: "computer"))
        XCTAssertNil(NativeGameLaunchURL.addingContext(to: plain, launchID: id, gameID: "gomoku", modeID: "computer\n"))
        let room = URL(string: "https://play.yunle.fun/room/AB23CD?role=spectator")!
        let roomURL = try XCTUnwrap(NativeGameLaunchURL.addingContext(to: room, launchID: id, gameID: "room", modeID: "online"))
        XCTAssertEqual(URLComponents(url: roomURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "role" }?.value, "spectator")
    }

    @MainActor
    func testRoomReferencesStayAccountScopedAndClearingOneAccountPreservesAnother() throws {
        let suite = "native-game-rooms-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeGameRoomStore(defaults: defaults)
        store.activate(accountID: "a")
        store.confirmed(gameID: "gomoku", room: try room("AB23CD", role: "spectator"), accountID: "a")
        XCTAssertEqual(store.continuation?.inviteCode, "AB23CD")
        XCTAssertEqual(store.continuation?.role, .spectator)
        store.activate(accountID: "b")
        XCTAssertNil(store.continuation)
        store.confirmed(gameID: "paper-star", room: try room("ZZ23CD"), accountID: "a")
        XCTAssertNil(store.continuation)
        store.confirmed(gameID: "flight-chess", room: try room("EF45GH"), accountID: "b")
        store.activate(accountID: "a")
        XCTAssertEqual(store.gameID, "gomoku")
        XCTAssertEqual(store.continuation?.inviteCode, "AB23CD")
        store.clear()
        XCTAssertNil(store.continuation)
        let restarted = NativeGameRoomStore(defaults: defaults)
        restarted.activate(accountID: "a")
        XCTAssertNil(restarted.continuation)
        restarted.activate(accountID: "b")
        XCTAssertEqual(restarted.continuation?.inviteCode, "EF45GH")
        restarted.activate(accountID: nil)
        XCTAssertNil(restarted.continuation)
        restarted.confirmed(gameID: "gomoku", room: try room("AB23CD"), accountID: nil)
        XCTAssertNil(restarted.continuation)
    }

    @MainActor
    func testTerminalRoomStateClearsOnlyMatchingContinuation() throws {
        let suite = "native-game-rooms-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeGameRoomStore(defaults: defaults)
        store.activate(accountID: "a")
        store.confirmed(gameID: "gomoku", room: try room("AB23CD"), accountID: "a")
        store.confirmed(gameID: "gomoku", room: try room("ZZ23CD", state: "ended"), accountID: "a")
        XCTAssertEqual(store.continuation?.inviteCode, "AB23CD")
        store.confirmed(gameID: "gomoku", room: try room("AB23CD", state: "removed"), accountID: "a")
        XCTAssertNil(store.continuation)
        store.confirmed(gameID: "unregistered-game", room: try room("AB23CD"), accountID: "a")
        XCTAssertNil(store.continuation)
    }

    private func event(id: UUID, gameID: String = "gomoku", modeID: String = "computer") -> [String: Any] {
        ["schemaVersion": 1, "launchId": id.uuidString, "gameId": gameID, "modeId": modeID, "state": "ready", "elapsedMilliseconds": 120]
    }

    private func room(_ code: String, role: String = "player", state: String = "waiting") throws -> NativeGameLifecycleEvent.Room {
        let data = try JSONSerialization.data(withJSONObject: ["inviteCode": code, "role": role, "state": state, "gameId": "gomoku"])
        return try JSONDecoder().decode(NativeGameLifecycleEvent.Room.self, from: data)
    }
}
