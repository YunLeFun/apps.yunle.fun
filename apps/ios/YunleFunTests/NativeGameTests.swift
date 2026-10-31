import XCTest
@testable import YunleFun

final class NativeGameTests: XCTestCase {
    func testCatalogReadsModeSpecificCapabilitiesAndFractionalDate() throws {
        let catalog = try NativeGameCatalog.decode(catalogData())
        let game = try XCTUnwrap(catalog.games.first)
        XCTAssertEqual(game.players?.label, "1–2 人")
        XCTAssertEqual(try game.launchURL(for: XCTUnwrap(game.mode(id: "computer"))).path, "/games/gomoku/computer")
        XCTAssertTrue(game.matchesFirstRelease)
        let online = try XCTUnwrap(game.mode(id: "online"))
        XCTAssertFalse(online.available)
        XCTAssertThrowsError(try game.launchURL(for: online))
    }

    func testUnknownSchemaMissingAvailableAndDuplicateIdentitiesFailClosed() throws {
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(schema: 2)))
        let original = gameFields()
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [original, original])))
        var second = original
        second["gameId"] = "flight-chess"
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [original, second])))
        var game = original
        var modes = game["launchModes"] as! [[String: Any]]
        modes[0].removeValue(forKey: "available")
        game["launchModes"] = modes
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [game])))
        game = original
        game["gameId"] = "gomoku\n"
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [game])))
    }

    func testLaunchDoesNotTrustArbitraryOriginPathOrPreinsertedHostParameters() throws {
        let invalid = [
            "http://play.yunle.fun/games/gomoku/computer",
            "https://play.yunle.fun.evil.test/games/gomoku/computer",
            "https://user:secret@play.yunle.fun/games/gomoku/computer",
            "https://play.yunle.fun:8443/games/gomoku/computer",
            "https://play.yunle.fun/games/paper-star/computer",
            "https://play.yunle.fun/games/gomoku/local",
            "https://play.yunle.fun/games/gomoku/%63omputer",
            "https://play.yunle.fun/games/gomoku/computer/",
            "https://play.yunle.fun/games/gomoku/computer?ylfLaunchId=injected",
            "https://play.yunle.fun/games/gomoku/computer#token",
        ]
        for url in invalid {
            XCTAssertThrowsError(try NativeGame.validatedLaunchURL(url, gameID: "gomoku", modeID: "computer"), url)
        }
        XCTAssertThrowsError(try NativeGame.validatedLaunchURL("https://play.yunle.fun/games/gomoku/new-mode", gameID: "gomoku", modeID: "new-mode"))
    }

    func testCatalogCannotRepurposeAnotherMarketIdentityOrResourceManifest() throws {
        var fields = gameFields()
        fields["appId"] = "cook"
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [fields])))
        fields = gameFields()
        for manifest in ["https://play.yunle.fun/native/resources/paper-star-v1.json",
                         "https://assets.play.yunle.fun/native/resources/gomoku-v1.json",
                         "https://play.yunle.fun/native/resources/gomoku-v1.json?token=secret"] {
            fields["resourceManifestURL"] = manifest
            XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [fields])), manifest)
        }
    }

    func testModeMustBelongToCurrentGameAndOnlineNeedsExplicitRequirements() throws {
        let game = try XCTUnwrap(NativeGameCatalog.decode(catalogData()).games.first)
        let rogue = NativeGameMode(id: "computer", title: "Other", requiresLogin: false, requiresNetwork: false,
                                   launchURL: "https://play.yunle.fun/games/gomoku/computer", available: true,
                                   unavailableReason: nil, orientation: nil)
        XCTAssertThrowsError(try game.launchURL(for: rogue))
        var fields = gameFields()
        var modes = fields["launchModes"] as! [[String: Any]]
        modes[1]["requiresLogin"] = false
        fields["launchModes"] = modes
        XCTAssertThrowsError(try NativeGameCatalog.decode(catalogData(games: [fields])))
    }

    func testRoomParsingPreservesSpectatorAndRejectsUntrustedInvitations() throws {
        let code = try NativeGameRoomIntent(input: "  ab23cd\n", role: .spectator)
        XCTAssertEqual(code.inviteCode, "AB23CD")
        XCTAssertEqual(code.role, .spectator)
        XCTAssertEqual(code.url.absoluteString, "https://play.yunle.fun/room/AB23CD?role=spectator")
        XCTAssertEqual(try NativeGameRoomIntent(input: code.url.absoluteString), code)
        XCTAssertEqual(try NativeGameRoomIntent(input: "https://play.yunle.fun/room/AB23CD").role, .player)
        for value in [
            "http://play.yunle.fun/room/AB23CD", "https://evil.test/room/AB23CD",
            "https://play.yunle.fun.evil.test/room/AB23CD", "https://secret@play.yunle.fun/room/AB23CD",
            "https://play.yunle.fun:8443/room/AB23CD", "https://play.yunle.fun/room/AB23CD/",
            "https://play.yunle.fun/room/AB23CD?role=owner", "https://play.yunle.fun/room/AB23CD?token=secret",
            "https://play.yunle.fun/room/AB23CD?role=player&role=spectator",
            "https://play.yunle.fun/room/%41B23CD", "https://play.yunle.fun/room/AB23CD#fragment",
            "ABC", "AB23CD/path",
        ] { XCTAssertThrowsError(try NativeGameRoomIntent(input: value), value) }
    }

    @MainActor
    func testCatalogFailurePreservesVerifiedSnapshotAndNeverMarksItOnline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = GameCatalogStub(result: .failure(NativeGameError.http(503)))
        let store = NativeGameCatalogStore(service: service, cacheURL: directory.appendingPathComponent("catalog.json"), bundledData: try catalogData())
        XCTAssertEqual(store.source, .bundled)
        await store.load()
        XCTAssertEqual(store.source, .bundled)
        XCTAssertEqual(store.games.map(\.gameId), ["gomoku"])
        XCTAssertNotNil(store.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("catalog.json").path))
    }

    @MainActor
    func testOnlyValidatedNetworkCatalogReplacesSuccessfulSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog.json")
        let valid = try NativeGameCatalog.decode(catalogData())
        let initial = NativeGameCatalogStore(service: GameCatalogStub(result: .success(valid)), cacheURL: cache, bundledData: nil)
        await initial.load()
        XCTAssertEqual(initial.source, .online)
        let before = try Data(contentsOf: cache)
        let invalid = NativeGameCatalog(schemaVersion: 99, catalogVersion: "future", generatedAt: valid.generatedAt, games: [])
        let restored = NativeGameCatalogStore(service: GameCatalogStub(result: .success(invalid)), cacheURL: cache, bundledData: nil)
        XCTAssertEqual(restored.source, .saved)
        await restored.load()
        XCTAssertEqual(restored.catalog, valid)
        XCTAssertEqual(restored.source, .saved)
        XCTAssertEqual(try Data(contentsOf: cache), before)
        XCTAssertNotNil(restored.error)
    }

    @MainActor
    func testReadyHistoryIsAccountScopedAndRejectsDelayedGenerations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeGameHistoryStore(directory: directory)
        store.activate(accountID: "account-a")
        let oldGeneration = store.generation
        store.recordReady(gameID: "gomoku", modeID: "computer", accountID: "account-a")
        XCTAssertEqual(store.entries.map(\.gameID), ["gomoku"])
        store.activate(accountID: "account-b")
        XCTAssertTrue(store.entries.isEmpty)
        store.recordReady(gameID: "paper-star", modeID: "local", accountID: "account-a")
        XCTAssertTrue(store.entries.isEmpty)
        store.activate(accountID: "account-a")
        store.recordReady(gameID: "paper-star", modeID: "local", accountID: "account-a", expectedGeneration: oldGeneration)
        XCTAssertEqual(store.entries.map(\.gameID), ["gomoku"])
        store.recordReady(gameID: "gomoku", modeID: "local", accountID: "account-a", expectedGeneration: store.generation)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.modeID, "local")
        let restored = NativeGameHistoryStore(directory: directory)
        restored.activate(accountID: "account-a")
        XCTAssertEqual(restored.entries, store.entries)
        restored.activate(accountID: nil)
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testPublicCatalogRequestDoesNotSendHostCredentialsAndRejectsHTML() async throws {
        let host = UUID().uuidString.lowercased() + ".native-games.test"
        let fixture = AuthHTTPFixture(replies: [(200, String(data: try catalogData(), encoding: .utf8)!)])
        AuthHTTPProtocol.register(host, fixture: fixture)
        defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPProtocol.self]
        let service = NativeGameCatalogService(session: URLSession(configuration: config), endpoint: URL(string: "https://\(host)/native/catalog-v1.json")!)
        _ = try await service.catalog()
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(fixture.requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")
        let htmlHost = UUID().uuidString.lowercased() + ".native-games.test"
        AuthHTTPProtocol.register(htmlHost, fixture: AuthHTTPFixture(replies: [(200, "<html>fallback</html>")], contentType: "text/html"))
        defer { AuthHTTPProtocol.unregister(htmlHost) }
        let html = NativeGameCatalogService(session: URLSession(configuration: config), endpoint: URL(string: "https://\(htmlHost)/native/catalog-v1.json")!)
        do { _ = try await html.catalog(); XCTFail("HTML fallback cannot become a game catalog") } catch { }
    }

    private func gameFields() -> [String: Any] {
        ["gameId": "gomoku", "appId": "gomoku", "name": "五子棋", "description": "测试规则与启动入口",
         "lifecycle": "playable", "players": ["min": 1, "max": 2], "type": "board", "launchModes": [
            ["id": "computer", "title": "电脑对手", "requiresLogin": false, "requiresNetwork": false,
             "launchURL": "https://play.yunle.fun/games/gomoku/computer", "available": true],
            ["id": "online", "title": "邀请联机", "requiresLogin": true, "requiresNetwork": true,
             "launchURL": "https://play.yunle.fun/games/gomoku/online", "available": false, "unavailableReason": "暂未开放"],
         ]]
    }

    private func catalogData(schema: Int = 1, games: [[String: Any]]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "catalogVersion": "test-v1",
                                                    "generatedAt": "2026-10-28T09:00:00.000Z", "games": games ?? [gameFields()]])
    }
}

private struct GameCatalogStub: NativeGameCatalogServing {
    let result: Result<NativeGameCatalog, Error>
    func catalog() async throws -> NativeGameCatalog { try result.get() }
}
