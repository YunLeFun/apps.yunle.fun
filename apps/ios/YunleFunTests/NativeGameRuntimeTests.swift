import CryptoKit
import OSLog
import UIKit
import WebKit
import XCTest
@testable import YunleFun

@MainActor
final class NativeGameRuntimeTests: XCTestCase {
    func testGameInteractionPreferencesPersistAcrossRuntimeRecreation() async throws {
        let suite = "game-interaction-settings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try await makeFixture(interactionDefaults: defaults)
        let selected = WebGameInteractionSettings(allowsPageBounce: true, allowsLongPress: true)
        try await changeGameInteractionSettings(fixture, to: selected)
        XCTAssertEqual(fixture.runtime.gameInteractionSettings(for: "paper-star"), WebGameInteractionSettings())
        await fixture.close()

        let restored = try await makeFixture(interactionDefaults: XCTUnwrap(UserDefaults(suiteName: suite)))
        let reopened = try await restored.open(try restored.game("gomoku"), mode: restored.mode("computer", gameID: "gomoku"))
        XCTAssertEqual(reopened.gameInteractionSettings, selected)
        XCTAssertTrue(try restored.web(reopened).scrollView.bounces)
        XCTAssertTrue(try restored.web(reopened).allowsLinkPreview)
        XCTAssertEqual(restored.runtime.gameInteractionSettings(for: "paper-star"), WebGameInteractionSettings())
    }

    private func changeGameInteractionSettings(_ fixture: NativeGameRuntimeFixture, to settings: WebGameInteractionSettings) async throws {
        let game = try fixture.game("gomoku"), mode = try fixture.mode("computer", gameID: "gomoku")
        let browser = try await fixture.open(game, mode: mode)
        XCTAssertEqual(browser.gameInteractionSettings, WebGameInteractionSettings())
        fixture.runtime.setGameInteractionSettings(settings, for: game.appId)
        XCTAssertEqual(browser.gameInteractionSettings, settings)
        XCTAssertTrue(try fixture.web(browser).scrollView.bounces)
        XCTAssertTrue(try fixture.web(browser).allowsLinkPreview)
    }

    func testFixtureCleanupBeforeOpeningFirstGamePage() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Named stores require iOS 17") }
        let fixture = try await NativeGameRuntimeFixture(simulated: true)
        let profile = try fixture.runtime.gameResourceProfile(for: fixture.game("gomoku"), catalog: fixture.catalog)
        fixture.track(profile)
        await fixture.close()
        let remaining = try await NativeGameRuntimeStoreCleanup.identifiers()
        XCTAssertFalse(remaining.contains(profile), "An early manifest failure must leave no fixture profile")
    }

    func testDiscoveryAndHomeReuseOneGameSessionWithoutLosingLaunchContext() async throws {
        let fixture = try await makeFixture()
        let game = try fixture.game("gomoku"), mode = try fixture.mode("computer", gameID: "gomoku")
        let first = try await fixture.open(game, mode: mode)
        let original = try XCTUnwrap(fixture.runtime.gameSessionStatuses[game.gameId])
        XCTAssertTrue(first.usesGameInteractionPolicy)
        XCTAssertFalse(try fixture.web(first).scrollView.bounces)
        XCTAssertFalse(try fixture.web(first).allowsLinkPreview)
        var readyGames: [String] = []
        fixture.runtime.onGameReady = { gameID, _, _ in readyGames.append(gameID) }

        fixture.runtime.open(fixture.application("gomoku"), catalog: fixture.catalog, library: fixture.library)
        let fromHome = try await fixture.browser(applicationID: "gomoku")
        XCTAssertTrue(fromHome === first)
        fixture.runtime.openGame(game, mode: mode, catalog: fixture.catalog, library: fixture.library)
        let fromDiscovery = try await fixture.browser(applicationID: "gomoku")
        XCTAssertTrue(fromDiscovery === first)
        XCTAssertEqual(fixture.runtime.applications.filter { $0.id == "gomoku" }.count, 1)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses[game.gameId]?.launchID, original.launchID)

        try await fixture.document(first, origin: try XCTUnwrap(first.url), messages: [fixture.message(original)])
        XCTAssertEqual(readyGames, ["gomoku"], "Reopening from Home must not delete the live launch binding")
        XCTAssertNotNil(fixture.runtime.gameSessionStatuses[game.gameId]?.readyMilliseconds)
        XCTAssertTrue(fixture.library.contains(fixture.application("gomoku")))
    }

    func testMarketDatabaseIdentityAndCanonicalGameSlugReuseOneSession() async throws {
        let market = CloudApplication(id: "market-gomoku", name: "Runtime fixture gomoku", slug: "gomoku",
                                      websiteUrl: "https://play.yunle.fun/games/gomoku",
                                      accessMode: "public", audience: "public", isPublic: true)
        let fixture = try await makeFixture(applications: [NativeGameRuntimeCatalog.application("play"), market,
                                                        NativeGameRuntimeCatalog.application("paper-star")])
        try await exerciseMarketIdentityReuse(fixture, market: market)
        await fixture.endAll()
        await Task.yield()
    }

    private func exerciseMarketIdentityReuse(_ fixture: NativeGameRuntimeFixture, market: CloudApplication) async throws {
        let game = try fixture.game("gomoku"), mode = try fixture.mode("computer", gameID: "gomoku")
        let first = try await fixture.open(game, mode: mode)
        let initial = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"])
        XCTAssertEqual(first.appInfo?.id, market.id)
        fixture.runtime.open(market, catalog: fixture.catalog, library: fixture.library)
        let fromHome = try await fixture.browser(applicationID: market.id)
        XCTAssertTrue(fromHome === first)
        fixture.runtime.openGame(game, mode: mode, catalog: fixture.catalog, library: fixture.library)
        let fromDiscovery = try await fixture.browser(applicationID: market.id)
        XCTAssertTrue(fromDiscovery === first)
        XCTAssertEqual(fixture.runtime.applications.map(\.id), [market.id])
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.launchID, initial.launchID)
        try await fixture.document(first, origin: try XCTUnwrap(first.url), messages: [fixture.message(initial)])
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.recordedGameID, "gomoku")
        XCTAssertTrue(fixture.library.contains(market))
    }

    func testExplicitPlaySharingPreservesPerGameStoresAndAccountIsolation() async throws {
        let fixture = try await makeFixture()
        try await exercisePlayProfileIsolation(fixture)
        // Finish the async frame that owns every browser before teardown asks
        // WebKit to delete the fixture's named website data stores.
        await fixture.endAll()
        await Task.yield()
    }

    private func exercisePlayProfileIsolation(_ fixture: NativeGameRuntimeFixture) async throws {
        let gomoku = try fixture.game("gomoku"), computer = try fixture.mode("computer", gameID: "gomoku")
        let paper = try fixture.game("paper-star"), local = try fixture.mode("local", gameID: "paper-star")
        let first = try await fixture.open(gomoku, mode: computer)
        let shared = try fixture.profile(first)
        let second = try await fixture.open(paper, mode: local)
        XCTAssertEqual(try fixture.profile(second), shared)
        XCTAssertEqual(try fixture.profiles.snapshot(for: .guest, application: fixture.application("play")).active?.identifier, shared)

        await fixture.endAll()
        let legacy = try fixture.profiles.select(.guest, application: fixture.application("gomoku"))
        fixture.track(legacy.identifier)
        let legacyBrowser = try await fixture.open(gomoku, mode: computer)
        XCTAssertEqual(try fixture.profile(legacyBrowser), legacy.identifier)
        XCTAssertNotEqual(legacy.identifier, shared)

        await fixture.resetIdentity("account-a")
        let retained = try fixture.profiles.select(.account("account-a"), application: fixture.application("gomoku"))
        try fixture.profiles.retire("account-a")
        let accountA = try await fixture.open(gomoku, mode: computer)
        let accountAProfile = try fixture.profile(accountA)
        XCTAssertNotEqual(accountAProfile, retained.identifier)
        XCTAssertEqual(try fixture.profiles.retained(for: .account("account-a"), application: fixture.application("gomoku")), [retained])
        XCTAssertNil(try fixture.profiles.snapshot(for: .account("account-a"), application: fixture.application("play")).active,
                     "A retained per-game store keeps this game out of a new shared Play profile")
        let key = "native_game_runtime_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try await fixture.document(accountA, origin: try XCTUnwrap(accountA.url))
        _ = try await WebStoragePageFixture.evaluate(in: fixture.web(accountA), script: "localStorage.setItem(key, 'account-a'); return true;", arguments: ["key": key])

        await fixture.resetIdentity("account-b")
        let accountB = try await fixture.open(gomoku, mode: computer)
        XCTAssertNotEqual(try fixture.profile(accountB), accountAProfile)
        try await fixture.document(accountB, origin: try XCTUnwrap(accountB.url))
        let other = try await WebStoragePageFixture.evaluate(in: fixture.web(accountB), script: "return localStorage.getItem(key);", arguments: ["key": key])
        XCTAssertTrue(other == nil || other is NSNull)

        await fixture.resetIdentity("account-a")
        let returned = try await fixture.open(gomoku, mode: computer)
        XCTAssertEqual(try fixture.profile(returned), accountAProfile)
        try await fixture.document(returned, origin: try XCTUnwrap(returned.url))
        let restored = try await WebStoragePageFixture.evaluate(in: fixture.web(returned), script: "return localStorage.getItem(key);", arguments: ["key": key]) as? String
        XCTAssertEqual(restored, "account-a")
        XCTAssertEqual(try fixture.profiles.retained(for: .account("account-a"), application: fixture.application("gomoku")), [retained])
    }

    func testRealWebKitMessageChecksOriginAndOperationBeforeRecordingReadyOnce() async throws {
        let fixture = try await makeFixture()
        let browser = try await fixture.open(try fixture.game("gomoku"), mode: try fixture.mode("computer", gameID: "gomoku"))
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"])
        var readyGames: [String] = []
        fixture.runtime.onGameReady = { gameID, _, _ in readyGames.append(gameID) }
        let wrongOrigin = URL(string: "https://native-game-message.invalid/")!
        browser.extraTrustedHosts = ["native-game-message.invalid"]
        try await fixture.document(browser, origin: wrongOrigin, messages: [fixture.message(status)])
        XCTAssertTrue(readyGames.isEmpty, "A navigation-trusted origin does not gain the game message channel")

        var wrongOperation = fixture.message(status)
        wrongOperation["launchId"] = UUID().uuidString
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [wrongOperation])
        XCTAssertTrue(readyGames.isEmpty)
        XCTAssertNil(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds)

        let valid = fixture.message(status)
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [valid, valid])
        XCTAssertEqual(readyGames, ["gomoku"])
        let ready = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds)
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [valid])
        XCTAssertEqual(readyGames.count, 1)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds, ready)
    }

    func testRoomSentinelResolvesTheReportedGameAndResumesWithoutDuplicateSession() async throws {
        let fixture = try await makeFixture()
        let intent = try NativeGameRoomIntent(input: "ABC234", role: .spectator)
        fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
        let browser = try await fixture.browser(applicationID: "play")
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses["room"])
        XCTAssertTrue(fixture.runtime.runningGameIDs.isEmpty)
        var readyGames: [String] = []
        fixture.runtime.onGameReady = { gameID, _, _ in readyGames.append(gameID) }
        var confirmedRooms: [String] = []
        fixture.runtime.onGameRoomConfirmed = { gameID, _, _ in confirmedRooms.append(gameID) }
        let reference: [String: Any] = ["inviteCode": "ABC234", "role": "spectator", "gameId": "paper-star", "state": "playing"]
        var message = fixture.message(status, state: "room-ready")
        message["room"] = reference
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [message, message])
        XCTAssertEqual(fixture.runtime.runningGameIDs, Set(["paper-star"]))
        XCTAssertTrue(readyGames.isEmpty, "Room connection does not establish that the game engine is operable")
        XCTAssertTrue(confirmedRooms.contains("paper-star"))
        XCTAssertNotNil(fixture.runtime.gameSessionStatuses["room"]?.roomReadyMilliseconds)
        XCTAssertNil(fixture.runtime.gameSessionStatuses["room"]?.readyMilliseconds)
        var engineReady = fixture.message(status)
        engineReady["room"] = reference
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [engineReady, engineReady])
        XCTAssertEqual(readyGames, ["paper-star"])
        XCTAssertNotNil(fixture.runtime.gameSessionStatuses["room"]?.readyMilliseconds)

        fixture.runtime.resumeGame("paper-star", catalog: fixture.catalog, library: fixture.library)
        let resumed = try await fixture.browser(applicationID: "play")
        XCTAssertTrue(resumed === browser)
        fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
        let reopened = try await fixture.browser(applicationID: "play")
        XCTAssertTrue(reopened === browser)
        XCTAssertEqual(fixture.runtime.applications.count, 1)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["room"]?.launchID, status.launchID)

        var left = fixture.message(status, state: "room-left")
        left["room"] = reference.merging(["state": "left"]) { _, new in new }
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [left])
        XCTAssertTrue(fixture.runtime.runningGameIDs.isEmpty)
    }

    func testClosedAndFailedRoomsReenterWithNewLaunchWhileKeepingProfileAndStorage() async throws {
        for (phase, roomState) in [("room-left", "left"), ("failed", "playing"), ("room-state", "closed"),
                                   ("room-state", "expired"), ("room-state", "removed"), ("room-state", "ended")] {
            let fixture = try await makeFixture()
            try await exerciseRoomReentry(fixture, phase: phase, roomState: roomState)
            await fixture.close()
        }
    }

    func testFailedRoomBeforeFirstConfirmationCanBeOpenedAgain() async throws {
        let fixture = try await makeFixture()
        try await exerciseRoomReentry(fixture, phase: "failed", roomState: nil)
        await fixture.endAll()
    }

    func testClosedOrUnconfirmedFailedRoomOpensDifferentInviteAfterMinimize() async throws {
        let next = try NativeGameRoomIntent(input: "DEF567", role: .player)
        for (phase, roomState) in [("room-left", "left" as String?), ("failed", nil)] {
            let fixture = try await makeFixture()
            try await exerciseRoomReentry(fixture, phase: phase, roomState: roomState,
                                          nextIntent: next, minimizeBeforeReentry: true)
            await fixture.close()
        }
    }

    func testDifferentInvitePreservesLiveAndRecoverableRoomSessions() async throws {
        let fixture = try await makeFixture()
        let intent = try NativeGameRoomIntent(input: "ABC234", role: .spectator)
        let next = try NativeGameRoomIntent(input: "DEF567", role: .player)
        fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
        let browser = try await fixture.browser(applicationID: "play")
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses["room"])
        let profile = try fixture.profile(browser)
        for (phase, roomState) in [("connecting", nil as String?), ("room-ready", "waiting"), ("ready", "playing"),
                                   ("room-state", "completed"), ("failed", "playing")] {
            var message = fixture.message(status, state: phase)
            if let roomState {
                message["room"] = ["inviteCode": intent.inviteCode, "role": intent.role.rawValue,
                                   "gameId": "gomoku", "state": roomState]
            }
            try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [message])
            try await minimizeRoom(browser, fixture: fixture)
            fixture.runtime.openGameRoom(next, catalog: fixture.catalog, library: fixture.library)
            XCTAssertEqual(fixture.runtime.issue?.title, "云乐坊间仍在运行", phase)
            XCTAssertEqual(fixture.runtime.gameSessionStatuses["room"]?.launchID, status.launchID, phase)
            XCTAssertTrue(fixture.runtime.contains(fixture.application("play")), phase)
            XCTAssertNil(fixture.root.presentedViewController, "A rejected invite must not reopen or replace the paused page")
            fixture.runtime.issue = nil
            fixture.runtime.resumeGame("room", catalog: fixture.catalog, library: fixture.library)
            let retained = try await fixture.browser(applicationID: "play")
            XCTAssertTrue(retained === browser, phase)
            XCTAssertEqual(try fixture.profile(retained), profile, phase)
        }
        await fixture.endAll()
    }

    func testRoomInviteDoesNotReplaceOrdinaryPlayPage() async throws {
        let fixture = try await makeFixture()
        let play = fixture.application("play")
        fixture.runtime.open(play, catalog: fixture.catalog, library: fixture.library)
        let browser = try await fixture.browser(applicationID: play.id)
        let profile = try fixture.profile(browser)
        try await minimizeRoom(browser, fixture: fixture)
        fixture.runtime.openGameRoom(try NativeGameRoomIntent(input: "DEF567", role: .player),
                                     catalog: fixture.catalog, library: fixture.library)
        XCTAssertEqual(fixture.runtime.issue?.title, "云乐坊间仍在运行")
        XCTAssertNil(fixture.runtime.gameSessionStatuses["room"])
        XCTAssertTrue(fixture.runtime.runningGameIDs.isEmpty)
        fixture.runtime.issue = nil
        fixture.runtime.open(play, catalog: fixture.catalog, library: fixture.library)
        let retained = try await fixture.browser(applicationID: play.id)
        XCTAssertTrue(retained === browser)
        XCTAssertEqual(try fixture.profile(retained), profile)
        await fixture.endAll()
    }

    func testDifferentInviteDoesNotInheritLegacySingleGameProfile() async throws {
        let fixture = try await makeFixture()
        try await exerciseRoomReentry(fixture, phase: "room-left", roomState: "left", legacy: true)
        let old = try await fixture.browser(applicationID: "play")
        let legacyProfile = try fixture.profile(old)
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses["room"])
        let key = "native_room_legacy_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var left = fixture.message(status, state: "room-left")
        left["room"] = ["inviteCode": "ABC234", "role": "spectator", "gameId": "gomoku", "state": "left"]
        try await fixture.document(old, origin: try XCTUnwrap(old.url), messages: [left])
        _ = try await WebStoragePageFixture.evaluate(in: fixture.web(old),
            script: "localStorage.setItem(key, 'legacy'); return true;", arguments: ["key": key])
        try await minimizeRoom(old, fixture: fixture)
        fixture.runtime.openGameRoom(try NativeGameRoomIntent(input: "DEF567", role: .player),
                                     catalog: fixture.catalog, library: fixture.library)
        XCTAssertNil(fixture.runtime.issue)
        let replacement = try await fixture.browser(applicationID: "play")
        let playProfile = try fixture.profile(replacement)
        XCTAssertNotEqual(playProfile, legacyProfile)
        XCTAssertEqual(try fixture.profiles.snapshot(for: .guest, application: fixture.application("gomoku")).active?.identifier, legacyProfile)
        XCTAssertEqual(try fixture.profiles.snapshot(for: .guest, application: fixture.application("play")).active?.identifier, playProfile)
        try await fixture.document(replacement, origin: try XCTUnwrap(replacement.url))
        let copied = try await WebStoragePageFixture.evaluate(in: fixture.web(replacement),
            script: "return localStorage.getItem(key);", arguments: ["key": key])
        XCTAssertTrue(copied == nil || copied is NSNull, "An unresolved different room must not inherit single-game storage")
        let preserved = try await WebStoragePageFixture.evaluate(in: fixture.web(old),
            script: "return localStorage.getItem(key);", arguments: ["key": key]) as? String
        XCTAssertEqual(preserved, "legacy")
        await fixture.endAll()
    }

    func testClosedRoomFromLegacyGameProfileKeepsThatProfileOnReentry() async throws {
        let fixture = try await makeFixture()
        try await exerciseRoomReentry(fixture, phase: "room-left", roomState: "left", legacy: true)
        await fixture.endAll()
    }

    func testConnectingWaitingAndCompletedRoomsKeepTheirLiveSession() async throws {
        let fixture = try await makeFixture()
        try await exerciseLiveRoomReuse(fixture)
        await fixture.endAll()
    }

    private func exerciseLiveRoomReuse(_ fixture: NativeGameRuntimeFixture) async throws {
        let intent = try NativeGameRoomIntent(input: "ABC234", role: .spectator)
        fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
        let browser = try await fixture.browser(applicationID: "play")
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses["room"])
        for (phase, roomState) in [("connecting", "playing"), ("room-ready", "waiting"), ("room-state", "completed")] {
            var message = fixture.message(status, state: phase)
            message["room"] = ["inviteCode": intent.inviteCode, "role": intent.role.rawValue,
                               "gameId": "gomoku", "state": roomState]
            try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [message])
            fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
            let reused = try await fixture.browser(applicationID: "play")
            XCTAssertTrue(reused === browser, phase + ":" + roomState)
            XCTAssertEqual(fixture.runtime.gameSessionStatuses["room"]?.launchID, status.launchID)
        }
    }

    private func exerciseRoomReentry(_ fixture: NativeGameRuntimeFixture, phase: String,
                                     roomState: String?, legacy: Bool = false,
                                     nextIntent: NativeGameRoomIntent? = nil,
                                     minimizeBeforeReentry: Bool = false) async throws {
        let intent = try NativeGameRoomIntent(input: "ABC234", role: .spectator)
        let browser: WebViewController
        if legacy {
            let selected = try fixture.profiles.select(.guest, application: fixture.application("gomoku"))
            fixture.track(selected.identifier)
            let online = NativeGameMode(id: "online", title: "联机", requiresLogin: true, requiresNetwork: true,
                launchURL: "https://play.yunle.fun/games/gomoku/online", available: true, unavailableReason: nil, orientation: nil)
            let game = NativeGame(gameId: "gomoku", appId: "gomoku", name: "五子棋", description: "", iconURL: nil,
                lifecycle: "playable", launchModes: [online], resourceManifestURL: nil, players: nil, type: nil)
            browser = try await fixture.open(game, mode: online)
        } else {
            fixture.runtime.openGameRoom(intent, catalog: fixture.catalog, library: fixture.library)
            browser = try await fixture.browser(applicationID: "play")
        }
        let profile = try fixture.profile(browser)
        let status = try XCTUnwrap(fixture.runtime.gameSessionStatuses[legacy ? "gomoku" : "room"])
        var terminal = fixture.message(status, state: phase)
        if let roomState {
            terminal["room"] = ["inviteCode": intent.inviteCode, "role": intent.role.rawValue,
                                "gameId": "gomoku", "state": roomState]
        }
        try await fixture.document(browser, origin: try XCTUnwrap(browser.url), messages: [terminal])
        let key = "native_game_reentry_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        _ = try await WebStoragePageFixture.evaluate(in: fixture.web(browser), script: "localStorage.setItem(key, 'saved'); return true;", arguments: ["key": key])
        if minimizeBeforeReentry {
            try await minimizeRoom(browser, fixture: fixture)
            XCTAssertTrue(fixture.runtime.contains(fixture.application("play")))
            XCTAssertTrue(fixture.runtime.runningGameIDs.isEmpty)
        }
        fixture.runtime.openGameRoom(nextIntent ?? intent, catalog: fixture.catalog, library: fixture.library)
        XCTAssertNil(fixture.runtime.issue, "An ended room container must not block an explicit new room operation")
        let replacement = try await fixture.browser(applicationID: "play")
        XCTAssertFalse(replacement === browser, phase + ":" + (roomState ?? "unconfirmed"))
        XCTAssertEqual(try fixture.profile(replacement), profile)
        XCTAssertNotEqual(fixture.runtime.gameSessionStatuses["room"]?.launchID, status.launchID)
        XCTAssertEqual(fixture.runtime.applications.count, 1)
        // The replacement's own WebKit channel must also reject the previous launch.
        try await fixture.document(replacement, origin: try XCTUnwrap(replacement.url), messages: [fixture.message(status)])
        let saved = try await WebStoragePageFixture.evaluate(in: fixture.web(replacement), script: "return localStorage.getItem(key);", arguments: ["key": key]) as? String
        XCTAssertEqual(saved, "saved")
        // A late event from the discarded page cannot mark the new operation ready.
        browser.onGameLifecycleMessage?(fixture.message(status), try XCTUnwrap(browser.url))
        XCTAssertNil(fixture.runtime.gameSessionStatuses["room"]?.readyMilliseconds)
    }

    private func minimizeRoom(_ browser: WebViewController, fixture: NativeGameRuntimeFixture) async throws {
        _ = browser.perform(NSSelectorFromString("minimizeTapped"))
        try await fixture.wait {
            fixture.root.presentedViewController == nil && browser.viewIfLoaded?.window == nil
        }
    }

    func testCapacityEvictsPausedGameAndReopensWithStoredData() async throws {
        let discarded = try await exerciseGameReclamation(trigger: .capacity)
        await observeDiscardedGameRelease(discarded, trigger: .capacity)
    }

    func testMemoryWarningEvictsPausedGameAndReopensWithStoredData() async throws {
        let discarded = try await exerciseGameReclamation(trigger: .memoryWarning)
        await observeDiscardedGameRelease(discarded, trigger: .memoryWarning)
    }

    func testMemoryWarningWithoutForegroundKeepsMostRecentPausedGame() async throws {
        let discarded = try await exerciseGameReclamation(trigger: .memoryWarningWhilePaused)
        await observeDiscardedGameRelease(discarded, trigger: .memoryWarningWhilePaused)
    }

    private enum ReclamationTrigger: String { case capacity, memoryWarning, memoryWarningWhilePaused }

    private final class DiscardedGameReferences {
        weak var browser: WebViewController?
        weak var page: WKWebView?
        init(browser: WebViewController, page: WKWebView) { self.browser = browser; self.page = page }
    }

    private func observeDiscardedGameRelease(_ references: DiscardedGameReferences, trigger: ReclamationTrigger) async {
        // The inner async frame has returned, releasing the test's intentional
        // stale-callback owners. Only weak references cross that frame boundary.
        let deadline = Date().addingTimeInterval(5)
        while (references.browser != nil || references.page != nil) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let report: [String: Any] = ["trigger": trigger.rawValue,
            "oldBrowserReleased": references.browser == nil, "oldWebViewReleased": references.page == nil,
            "scope": "Weak object observations after the test's strong callback-validation frame ended; not an assertion about system RAM or WebContent process exit."]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "native-game-discarded-object-release-\(trigger.rawValue).json"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertNil(references.browser, "The discarded browser must not stay strongly owned after runtime eviction and the test frame ending")
        XCTAssertNil(references.page, "The discarded WebView must not stay strongly owned after runtime eviction and the test frame ending")
    }

    private func exerciseGameReclamation(trigger: ReclamationTrigger) async throws -> DiscardedGameReferences {
        guard #available(iOS 17, *) else { throw XCTSkip("Named WebKit store integration requires iOS 17") }
        let limit = WebViewSessionPolicy.automaticLimit(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        // Fill the product's actual automatic capacity instead of injecting a
        // test-only limit or copying the policy's memory thresholds here.
        let fillers = (0..<max(0, limit - 1)).map { index in
            CloudApplication(id: "native-capacity-\(index)", name: "Capacity fixture \(index)",
                websiteUrl: "https://native-capacity.invalid/session/\(index)",
                accessMode: "public", audience: "public", isPublic: true)
        }
        let applications = ["play", "gomoku", "paper-star"].map(NativeGameRuntimeCatalog.application)
            + (trigger == .capacity ? fillers : [])
        let fixture = try await makeFixture(applications: applications)
        let history = NativeGameHistoryStore(directory: fixture.directory.appendingPathComponent("history"))
        history.activate(accountID: nil)
        let historyGeneration = history.generation
        var readyGames: [String] = []
        fixture.runtime.onGameReady = { gameID, modeID, accountID in
            readyGames.append(gameID)
            history.recordReady(gameID: gameID, modeID: modeID, accountID: accountID,
                expectedGeneration: historyGeneration,
                now: Date(timeIntervalSince1970: 1_700_000_000 + Double(readyGames.count)))
        }
        defer { fixture.runtime.onGameReady = nil }
        var steps: [[String: Any]] = []
        var completed = false
        defer {
            let report: [String: Any] = ["kind": "native-game-session-reclamation", "trigger": trigger.rawValue,
                "completed": completed, "automaticSessionLimit": limit, "steps": steps,
                "scope": "Real NativeWebRuntime and WKWebView with simulated origin-bound documents and lifecycle messages; no Play network, production account or room.",
                "memoryWarningModel": "NotificationCenter posts UIApplication.didReceiveMemoryWarningNotification to the product's real observer. This is not actual OS pressure, WebContent termination or app restart.",
                "lateCallbackOwnership": "The test alone holds the evicted old browser long enough to deliver a stale callback. A separate attachment observes weak object release only after that strong-owner frame has returned; system RAM and process exit are not inferred.",
                "pausedPolicy": "Capacity removes the oldest unpresented session; memory warning preserves a presented session and, when none is presented, the most recent paused session.",
                "storageScope": "Random fixture-only Cookie/localStorage/IndexedDB marker in the exact owned named profile; fixture teardown removes only its tracked stores."]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-game-session-reclamation-\(trigger.rawValue).json"
                attachment.lifetime = .keepAlways; add(attachment)
            } else { XCTFail("Session reclamation evidence must remain JSON serializable") }
        }

        let game = try fixture.game("gomoku"), mode = try fixture.mode("computer", gameID: "gomoku")
        let old = try await fixture.open(game, mode: mode)
        let oldProfile = try fixture.profile(old)
        let oldStatus = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"])
        let oldURL = try XCTUnwrap(old.url)
        let lateCallback = try XCTUnwrap(old.onGameLifecycleMessage)
        try await fixture.document(old, origin: oldURL, messages: [fixture.message(oldStatus)])
        let key = "native_game_reclamation_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let seeded = try await reclamationStorage(fixture.web(old), profileID: oldProfile, key: key, seed: true)
        XCTAssertEqual(seeded, ["cookie": "keep", "localStorage": "keep", "indexedDB": "keep"])
        let previousHistory = try XCTUnwrap(history.entries.first { $0.gameID == "gomoku" })
        XCTAssertEqual(readyGames, ["gomoku"])
        if trigger == .capacity {
            for app in fillers {
                fixture.runtime.open(app, catalog: fixture.catalog, library: fixture.library)
                _ = try await fixture.browser(applicationID: app.id)
            }
            XCTAssertEqual(fixture.runtime.applications.count, limit)
            XCTAssertTrue(fixture.runtime.contains(fixture.application("gomoku")))
            XCTAssertNil(old.viewIfLoaded?.window)
        }
        let visibleGame = try fixture.game("paper-star"), visibleMode = try fixture.mode("local", gameID: "paper-star")
        let visible = try await fixture.open(visibleGame, mode: visibleMode)
        let visibleStatus = try XCTUnwrap(fixture.runtime.gameSessionStatuses["paper-star"])
        try await fixture.document(visible, origin: try XCTUnwrap(visible.url), messages: [fixture.message(visibleStatus)])
        XCTAssertTrue(visible.viewIfLoaded?.window === fixture.window)
        if trigger != .capacity {
            XCTAssertTrue(fixture.runtime.contains(fixture.application("gomoku")))
            XCTAssertNil(old.viewIfLoaded?.window)
            if trigger == .memoryWarningWhilePaused {
                let items = visible.navigationItem.leftBarButtonItems ?? visible.navigationItem.leftBarButtonItem.map { [$0] } ?? []
                let minimize = try XCTUnwrap(items.first { $0.accessibilityIdentifier == "runtime.minimize" })
                XCTAssertTrue(minimize.isEnabled)
                let action = try XCTUnwrap(minimize.action)
                XCTAssertTrue(UIApplication.shared.sendAction(action, to: minimize.target, from: minimize, for: nil))
                try await fixture.wait {
                    fixture.root.presentedViewController == nil && visible.viewIfLoaded?.window == nil
                }
                XCTAssertEqual(fixture.runtime.applications.first?.id, "paper-star", "The real minimize callback must make Star the most recent paused session")
                XCTAssertTrue(fixture.runtime.runningGameIDs.contains("gomoku") && fixture.runtime.runningGameIDs.contains("paper-star"))
            }
            let notificationHadForeground = fixture.root.presentedViewController != nil
            XCTAssertEqual(notificationHadForeground, trigger == .memoryWarning)
            steps.append(["stage": "memory-warning-notification", "hadPresentedController": notificationHadForeground,
                          "expectedRetainedGame": "paper-star", "olderPausedGame": "gomoku",
                          "retainedWasPaused": visible.viewIfLoaded?.window == nil,
                          "mostRecentApplicationID": fixture.runtime.applications.first?.id ?? "",
                          "retainedLaunchID": visibleStatus.launchID.uuidString, "olderLaunchID": oldStatus.launchID.uuidString])
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification,
                                            object: UIApplication.shared)
            try await fixture.wait { !fixture.runtime.contains(fixture.application("gomoku")) }
        } else {
            XCTAssertEqual(fixture.runtime.applications.count, limit)
        }
        XCTAssertFalse(fixture.runtime.contains(fixture.application("gomoku")))
        XCTAssertFalse(fixture.runtime.runningGameIDs.contains("gomoku"), "A released game cannot remain in the live continue section")
        XCTAssertNil(fixture.runtime.gameSessionStatuses["gomoku"])
        XCTAssertTrue(fixture.runtime.contains(fixture.application("paper-star")))
        XCTAssertTrue(fixture.runtime.runningGameIDs.contains("paper-star"))
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["paper-star"]?.launchID, visibleStatus.launchID)
        if trigger == .memoryWarningWhilePaused {
            XCTAssertNil(fixture.root.presentedViewController, "Keeping the MRU paused game must not present it automatically")
            XCTAssertNil(visible.viewIfLoaded?.window)
            steps.append(["stage": "most-recent-paused-session-retained", "presentedController": fixture.root.presentedViewController != nil,
                          "retainedGame": "paper-star", "removedGame": "gomoku",
                          "runningGameIDs": fixture.runtime.runningGameIDs.sorted(),
                          "launchID": try XCTUnwrap(fixture.runtime.gameSessionStatuses["paper-star"]?.launchID).uuidString])
            fixture.runtime.resumeGame("paper-star", catalog: fixture.catalog, library: fixture.library)
        }
        let stillVisible = try await fixture.browser(applicationID: "paper-star")
        XCTAssertTrue(stillVisible === visible)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["paper-star"]?.launchID, visibleStatus.launchID)
        XCTAssertEqual(history.entries.first { $0.gameID == "gomoku" }, previousHistory,
                       "Released and recent are separate states; session eviction must not delete recent history")
        steps.append(["stage": "paused-session-released", "releasedGame": "gomoku", "retainedGame": "paper-star",
                      "retainedReason": trigger == .memoryWarningWhilePaused ? "most-recent-paused-then-explicitly-resumed" : "presented-session",
                      "sessionCount": fixture.runtime.applications.count, "runningGameIDs": fixture.runtime.runningGameIDs.sorted(),
                      "releasedStatusRemoved": fixture.runtime.gameSessionStatuses["gomoku"] == nil,
                      "recentHistoryRetained": history.entries.contains(previousHistory), "sameRetainedBrowser": stillVisible === visible])

        // The stale live-session action must not reopen an evicted page. A
        // recent-history action below uses the normal new-launch entry instead.
        fixture.runtime.resumeGame("gomoku", catalog: fixture.catalog, library: fixture.library)
        await Task.yield()
        let afterStaleResume = try await fixture.browser(applicationID: "paper-star")
        XCTAssertTrue(afterStaleResume === visible)
        XCTAssertFalse(fixture.runtime.contains(fixture.application("gomoku")))
        let recent = try XCTUnwrap(history.entries.first { $0.gameID == "gomoku" })
        let reopened = try await fixture.open(try fixture.game(recent.gameID),
                                              mode: try fixture.mode(recent.modeID, gameID: recent.gameID))
        let current = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"])
        let reopenedProfile = try fixture.profile(reopened)
        XCTAssertFalse(reopened === old)
        XCTAssertFalse(try fixture.web(reopened) === fixture.web(old))
        XCTAssertNotEqual(current.launchID, oldStatus.launchID)
        XCTAssertEqual(reopenedProfile, oldProfile)
        XCTAssertNil(current.readyMilliseconds)
        let readyBeforeStale = readyGames.count
        lateCallback(fixture.message(oldStatus), oldURL)
        XCTAssertNil(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds)
        XCTAssertEqual(readyGames.count, readyBeforeStale)
        try await fixture.document(reopened, origin: try XCTUnwrap(reopened.url), messages: [fixture.message(oldStatus)])
        XCTAssertNil(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds)
        XCTAssertEqual(readyGames.count, readyBeforeStale)
        XCTAssertEqual(history.entries.first { $0.gameID == "gomoku" }, previousHistory)
        let restored = try await reclamationStorage(fixture.web(reopened), profileID: reopenedProfile, key: key, seed: false)
        XCTAssertEqual(restored, seeded)
        try await fixture.document(reopened, origin: try XCTUnwrap(reopened.url), messages: [fixture.message(current)])
        XCTAssertNotNil(fixture.runtime.gameSessionStatuses["gomoku"]?.readyMilliseconds)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.launchID, current.launchID)
        XCTAssertEqual(readyGames.count, readyBeforeStale + 1)
        XCTAssertEqual(readyGames.filter { $0 == "gomoku" }.count, 2)
        XCTAssertTrue(fixture.runtime.runningGameIDs.contains("gomoku"))
        steps.append(["stage": "recent-history-reopens-fresh-session", "newWebView": reopened !== old,
                      "oldProfileID": oldProfile.uuidString, "newProfileID": reopenedProfile.uuidString,
                      "oldLaunchID": oldStatus.launchID.uuidString, "newLaunchID": current.launchID.uuidString,
                      "sameProfile": reopenedProfile == oldProfile, "newLaunch": current.launchID != oldStatus.launchID,
                      "seededStorage": seeded, "restoredStorage": restored,
                      "discardedBrowserCallbackRejected": true, "oldLaunchThroughCurrentWebKitChannelRejected": true,
                      "readyCallbacksByGame": readyGames, "runningGameIDs": fixture.runtime.runningGameIDs.sorted()])
        completed = true
        return DiscardedGameReferences(browser: old, page: try fixture.web(old))
    }

    @available(iOS 17, *)
    private func reclamationStorage(_ page: WKWebView, profileID: UUID, key: String, seed: Bool) async throws -> [String: String] {
        let store = page.configuration.websiteDataStore
        XCTAssertEqual(store.identifier, profileID, "Storage checks must use the actual page's owned profile")
        if seed {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "play.yunle.fun", .path: "/", .name: key, .value: "keep", .secure: "TRUE"]))
            await store.httpCookieStore.setCookie(cookie)
        }
        let observed = try await WebStoragePageFixture.evaluate(in: page, script: """
            const database = await new Promise((resolve, reject) => {
                const request = indexedDB.open(key, 1);
                request.onupgradeneeded = () => {
                    if (seed) request.result.createObjectStore('drafts');
                    else request.transaction.abort();
                };
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error || Error('Fixture database missing'));
            });
            try {
                if (seed) {
                    localStorage.setItem(key, 'keep');
                    await new Promise((resolve, reject) => {
                        const transaction = database.transaction('drafts', 'readwrite');
                        transaction.oncomplete = () => resolve();
                        transaction.onerror = transaction.onabort = () => reject(transaction.error || Error('Fixture write failed'));
                        transaction.objectStore('drafts').put('keep', 'save');
                    });
                }
                const indexedDBValue = await new Promise((resolve, reject) => {
                    const transaction = database.transaction('drafts', 'readonly');
                    const request = transaction.objectStore('drafts').get('save');
                    transaction.oncomplete = () => resolve(request.result ?? '');
                    transaction.onerror = transaction.onabort = () => reject(transaction.error || Error('Fixture read failed'));
                });
                return {localStorage: localStorage.getItem(key) || '', indexedDB: indexedDBValue};
            } finally { database.close(); }
            """, arguments: ["key": key, "seed": seed]) as? [String: String]
        var result = try XCTUnwrap(observed)
        let cookies = await store.httpCookieStore.allCookies()
        result["cookie"] = cookies.first { $0.name == key }?.value ?? ""
        return result
    }

    private func makeFixture(applications: [CloudApplication]? = nil, interactionDefaults: UserDefaults? = nil) async throws -> NativeGameRuntimeFixture {
        guard #available(iOS 17, *) else { throw XCTSkip("Named WebKit profile integration requires iOS 17") }
        guard NativeGameHostEnvironment.previewOrigin == nil else {
            throw XCTSkip("Run production-origin runtime isolation tests without YUNLEFUN_PLAY_PREVIEW")
        }
        let fixture = try await NativeGameRuntimeFixture(simulated: true, catalogApplications: applications, interactionDefaults: interactionDefaults)
        addTeardownBlock { await fixture.close() }
        return fixture
    }
}

/// Explicit recovery of stores proven to belong to failed fixture runs.
/// No other identifier can enter this cleanup.
@MainActor
final class NativeGameRuntimeFixtureCleanupTests: XCTestCase {
    func testRemoveOnlyPreviouslyOwnedFixtureStores() async throws {
        guard #available(iOS 17, *),
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_FIXTURE_CLEANUP"] == "1" else {
            throw XCTSkip("Explicit fixture-only WebKit cleanup is not enabled")
        }
        let allowed = Set([
            // Isolated follow-up of the same fixture, recorded in
            // closed-room-isolation-followup.xcresult; not an account store.
            UUID(uuidString: "C8C36775-D3B7-436E-A443-58B9C0E77B77")!,
            // Owned by the 2026-10-29 closed-room invite regression run;
            // exact cleanup failures are retained in closed-room-regression.xcresult.
            UUID(uuidString: "ABC737C6-2266-4803-85F9-8DF1C3661D09")!,
            UUID(uuidString: "E8E9FB90-E302-4531-B724-F7F32CBE152E")!,
            UUID(uuidString: "2FC97C31-FFC1-4578-A1B3-D5A0582514BB")!,
            UUID(uuidString: "05C5A036-D050-479A-9987-AFB6BE922181")!,
            UUID(uuidString: "C73F02A6-B2DF-444E-8C2F-DD5AFD9CBF05")!,
            UUID(uuidString: "A2E7DF1C-122B-4693-8582-32C786F7AB83")!,
            UUID(uuidString: "B2AD256A-B65D-482D-990E-56A38A90DBD8")!,
            // Early manifest failure at 02:42; recovered only from its owned
            // native-game-runtime-7236DBED…/profiles.json registry.
            UUID(uuidString: "1987226B-D9D7-40DE-B0DD-DCF1F9B316A7")!,
            // Only stores created during the isolated runtime-ui-final unit
            // phase; timestamps and failing cleanup IDs are archived by root.
            UUID(uuidString: "5B1B9BE8-E1CE-4E6B-BC16-06608545DE7C")!,
            UUID(uuidString: "955D80C2-2EE0-44E1-A130-71C00679CE2E")!,
            UUID(uuidString: "60B29606-157D-4890-9D1E-EE892D1D86D5")!,
            UUID(uuidString: "DAF38FEE-0776-4EE8-A834-22910E3ACA70")!,
            UUID(uuidString: "65D53551-B72E-42B7-BC6E-A3F3BE105056")!,
        ])
        let raw = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_FIXTURE_IDS"] ?? ""
        let fields = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let requested = Set(fields.compactMap(UUID.init(uuidString:)))
        guard !fields.isEmpty, requested.count == fields.count, requested.isSubset(of: allowed) else {
            throw NSError(domain: "NativeGameFixtureCleanup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cleanup requires an explicit, unique subset of the recorded fixture UUIDs"])
        }
        // Initialize WebKit's run loops before the first identifier enumeration.
        // This keeper is transient and cannot own any persistent fixture store.
        let keeper = try await NativeGameRuntimeStoreCleanup.initializedKeeper()
        defer { keeper.stopLoading() }
        let before = try await NativeGameRuntimeStoreCleanup.identifiers()
        for id in requested.intersection(before) {
            try await NativeGameRuntimeStoreCleanup.remove(id)
        }
        let after = try await NativeGameRuntimeStoreCleanup.identifiers()
        XCTAssertTrue(requested.intersection(after).isEmpty, "Every requested fixture store must be confirmed absent")
        print("NATIVE_GAME_FIXTURE_CLEANUP requested=\(requested.count) existed=\(requested.intersection(before).count) remaining=\(requested.intersection(after).count)")
        let evidence = XCTAttachment(string: "Explicit fixture UUIDs: \(requested.map(\.uuidString).sorted().joined(separator: ",")); present before: \(requested.intersection(before).count); remaining after: \(requested.intersection(after).count)")
        evidence.name = "native-game-fixture-store-cleanup"
        evidence.lifetime = .keepAlways
        add(evidence)
    }


}

/// Faults affect only the task-owned loopback server. This exercises the real
/// preparer and game, without claiming OS eviction or a second game build.
@MainActor
final class NativeGameResourceFaultLiveTests: XCTestCase {
    func testPreparationFailuresCancellationVersionTransitionAndHTTPEviction() async throws {
        guard #available(iOS 17, *), NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_RESOURCE_FAULTS"] == "1" else {
            throw XCTSkip("Opt in with YUNLEFUN_PLAY_PREVIEW=1 and YUNLEFUN_NATIVE_GAME_RESOURCE_FAULTS=1; enable task-owned server fault control")
        }
        let control = NativeGameResourceFaultControl()
        let keepStoreForDiagnosis = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_STORE_KEEPER_DIAGNOSTIC"] == "1"
        let runID = UUID()
        _ = try await control.set("healthy", runID: runID)
        addTeardownBlock { control.close() }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        let cache = NativeGameResourceCache(defaults: fixture.defaults)
        addTeardownBlock {
            _ = try? await control.set("healthy", runID: runID)
            await MainActor.run { cache.cancel() }
            try? await fixture.wait(seconds: 30) { await MainActor.run { !cache.isBusy } }
            for id in await fixture.trackedProfiles() { await cache.clear(profileID: id) }
            await fixture.close()
        }
        var records: [[String: Any]] = []
        var flowCompleted = false
        defer {
            let report: [String: Any] = ["kind": "native-resource-fault-injection", "origin": "http://127.0.0.1:18146",
                "gameId": "gomoku", "modeId": "computer", "flowCompleted": flowCompleted, "steps": records,
                "diagnosticNamedStoreKeeper": keepStoreForDiagnosis,
                "boundaries": ["Real built game and Worker ready; same named WebKit profile",
                               "Version B appends a test-only binary to exercise receipt updates, not game-build compatibility",
                               "HTTP cache API removal models reclamation; no claim of actual OS eviction",
                               "Fault server HTML CSP restricts network access to loopback; no production account or room"]]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-game-resource-faults.json"; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let game = try fixture.game("gomoku"), mode = try fixture.mode("computer", gameID: "gomoku")
        let profileID = try fixture.runtime.gameResourceProfile(for: game, catalog: fixture.catalog)
        fixture.track(profileID)
        // Diagnostic only: distinguish a named-store teardown race from a
        // genuine cache miss. This opt-in is never an acceptance workaround.
        let storeKeeper: WKWebsiteDataStore? = keepStoreForDiagnosis ? WKWebsiteDataStore(forIdentifier: profileID) : nil
        defer { withExtendedLifetime(storeKeeper) {} }
        let endpoint = try XCTUnwrap(game.resourceManifestURL.flatMap(URL.init(string:)))
        let baseline = try await control.manifest(endpoint)
        XCTAssertEqual(baseline.version, game.resourceVersion)
        guard baseline.resources.count > 100, baseline.resources.allSatisfy({ $0.url.host == "play.yunle.fun" }) else {
            throw NSError(domain: "NativeGameResourceFaults", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Use the actual gomoku dependency tree with loopback-only resources"])
        }
        try await download(cache, fixture: fixture, endpoint: endpoint, profileID: profileID)
        let original = try XCTUnwrap(cache.entry(gameID: "gomoku", profileID: profileID), cache.error ?? "Missing baseline preparation")
        XCTAssertNil(cache.error)
        let baselineVerification = try await verifyCacheOnly(baseline, profileID: profileID, fixture: fixture, stage: "baseline-after-preparation")
        records.append(["stage": "baseline-cache-only", "verification": baselineVerification])
        let marker = "native_resource_fault_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let transitioned = try await exerciseLiveGame(fixture, cache: cache, control: control, runID: runID,
            game: game, mode: mode, endpoint: endpoint, profileID: profileID, baseline: baseline,
            original: original, marker: marker, records: &records)
        // End the async frame holding the original browser before clearing HTTP
        // caches and asking the same profile to create a fresh runtime page.
        await fixture.endAll()
        await Task.yield()
        _ = try await control.set("healthy", runID: runID)
        await WKWebsiteDataStore(forIdentifier: profileID).removeData(ofTypes: NativeGameResourcePolicy.cacheTypes, modifiedSince: .distantPast)
        let missing = try await cacheOnlyStatus(try XCTUnwrap(baseline.resources.first).url, profileID: profileID, fixture: fixture)
        XCTAssertTrue([0, 504].contains(missing), "HTTP cache removal must be observable without a network fallback")
        XCTAssertEqual(cache.entry(gameID: "gomoku", profileID: profileID), transitioned.receipt,
                       "An advisory receipt is not a claim that WebKit retained every HTTP entry")
        let reloadedMarkers = try await exerciseOnlineReload(fixture, game: game, mode: mode, profileID: profileID,
                                                            previousLaunch: transitioned.launchID, marker: marker)
        let status = try await control.status()
        XCTAssertGreaterThan(status.counts.baseAssetRequests, 0, "The fresh game must actually fetch its built assets online")
        records.append(["stage": "modeled-http-cache-reclamation", "cacheOnlyStatus": missing,
                        "freshGameEngineReady": true, "assetRequests": status.counts.baseAssetRequests,
                        "cookiePreserved": reloadedMarkers["cookiePreserved"] ?? false,
                        "localStoragePreserved": reloadedMarkers["localStoragePreserved"] ?? false,
                        "indexedDBPreserved": reloadedMarkers["indexedDBPreserved"] ?? false,
                        "storageMarkers": reloadedMarkers])
        flowCompleted = true
    }

    @available(iOS 17, *)
    private func exerciseLiveGame(_ fixture: NativeGameRuntimeFixture, cache: NativeGameResourceCache,
                                 control: NativeGameResourceFaultControl, runID: UUID, game: NativeGame, mode: NativeGameMode,
                                 endpoint: URL, profileID: UUID, baseline: NativeGameResourceManifest,
                                 original: NativeGameResourceCacheEntry, marker: String,
                                 records: inout [[String: Any]]) async throws -> (receipt: NativeGameResourceCacheEntry, launchID: UUID) {
        var readyCount = 0
        fixture.runtime.onGameReady = { gameID, _, _ in if gameID == "gomoku" { readyCount += 1 } }
        let browser = try await fixture.open(game, mode: mode)
        try await fixture.wait(seconds: 90) { readyCount == 1 }
        let launchID = try XCTUnwrap(fixture.runtime.gameSessionStatuses["gomoku"]?.launchID)
        let page = try fixture.web(browser)
        XCTAssertEqual(try fixture.profile(browser), profileID)
        _ = try await WebStoragePageFixture.evaluate(in: page, script: "localStorage.setItem(marker, 'keep'); window.__nativeResourceFaultPage = marker; return true;", arguments: ["marker": marker])
        _ = try await WebStoragePageFixture.evaluate(in: page, script: """
            const database = await new Promise((resolve, reject) => {
                const request = indexedDB.open(marker, 1);
                request.onupgradeneeded = () => request.result.createObjectStore('fixture');
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error || Error('IndexedDB marker open failed'));
            });
            try {
                await new Promise((resolve, reject) => {
                    const transaction = database.transaction('fixture', 'readwrite');
                    transaction.oncomplete = () => resolve();
                    transaction.onerror = transaction.onabort = () => reject(transaction.error || Error('IndexedDB marker write failed'));
                    transaction.objectStore('fixture').put('keep', 'value');
                });
            } finally { database.close(); }
            return true;
            """, arguments: ["marker": marker])
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: marker, .value: "keep"]))
        await WKWebsiteDataStore(forIdentifier: profileID).httpCookieStore.setCookie(cookie)
        let initialStones = try await playMove(page, fixture: fixture)
        for scenario in ["manifest503", "badDigest"] {
            _ = try await control.set(scenario, runID: runID)
            try await download(cache, fixture: fixture, endpoint: endpoint, profileID: profileID)
            XCTAssertNotNil(cache.error)
            XCTAssertEqual(cache.entry(gameID: "gomoku", profileID: profileID), original)
            let verification = try await verifyCacheOnly(baseline, profileID: profileID, fixture: fixture, stage: "after-\(scenario)")
            let markers = try await verifyMarkers(page, profileID: profileID, marker: marker)
            records.append(["stage": scenario, "errorReported": cache.error != nil,
                            "oldReceiptRetained": cache.entry(gameID: "gomoku", profileID: profileID) == original,
                            "oldResourcesCacheOnlySHA256Verified": verification["allVerified"] as? Bool ?? false,
                            "verification": verification, "storageMarkers": markers])
        }
        _ = try await control.set("slowPrepare", runID: runID)
        cache.download(manifestURL: endpoint, gameID: "gomoku", profileID: profileID, wifiOnly: false)
        try await fixture.wait(seconds: 90) {
            let delayed = (try? await control.status().counts.slowResourceRequests) ?? 0
            return cache.isBusy && cache.progress > 0 && delayed > 0
        }
        let partialProgress = cache.progress
        cache.cancel()
        try await fixture.wait(seconds: 30) { !cache.isBusy }
        XCTAssertNil(cache.error)
        XCTAssertEqual(cache.progress, 0)
        XCTAssertEqual(cache.entry(gameID: "gomoku", profileID: profileID), original)
        let cancelledVerification = try await verifyCacheOnly(baseline, profileID: profileID, fixture: fixture, stage: "after-cancel")
        let cancelledMarkers = try await verifyMarkers(page, profileID: profileID, marker: marker)
        records.append(["stage": "cancel-partial-preparation", "progressBeforeCancel": partialProgress,
                        "oldReceiptRetained": cache.entry(gameID: "gomoku", profileID: profileID) == original,
                        "oldResourcesCacheOnlySHA256Verified": cancelledVerification["allVerified"] as? Bool ?? false,
                        "verification": cancelledVerification, "storageMarkers": cancelledMarkers])
        _ = try await control.set("versionB", runID: runID)
        let updatedManifest = try await control.manifest(endpoint)
        XCTAssertNotEqual(updatedManifest.version, baseline.version)
        XCTAssertEqual(updatedManifest.resources.count, baseline.resources.count + 1)
        var updatedGame = game
        updatedGame.resourceVersion = updatedManifest.version
        fixture.runtime.updateGameCatalog([updatedGame])
        try await download(cache, fixture: fixture, endpoint: endpoint, profileID: profileID)
        XCTAssertNil(cache.error)
        let updated = try XCTUnwrap(cache.entry(gameID: "gomoku", profileID: profileID))
        XCTAssertEqual(updated.version, updatedManifest.version)
        let updatedVerification = try await verifyCacheOnly(updatedManifest, profileID: profileID, fixture: fixture, stage: "version-b")
        let sameBrowser = try await fixture.browser(applicationID: browser.appInfo?.id ?? "gomoku")
        XCTAssertTrue(sameBrowser === browser)
        XCTAssertEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.launchID, launchID)
        XCTAssertEqual(readyCount, 1)
        let pageMarker = try await WebStoragePageFixture.evaluate(in: page, script: "return window.__nativeResourceFaultPage;") as? String
        XCTAssertEqual(pageMarker, marker)
        let laterStones = try await playMove(page, fixture: fixture)
        XCTAssertGreaterThan(laterStones, initialStones)
        let updatedMarkers = try await verifyMarkers(page, profileID: profileID, marker: marker)
        records.append(["stage": "receipt-version-transition-with-active-game", "versionA": baseline.version,
                        "versionB": updated.version, "sameWebViewAndLaunch": true,
                        "engineReadyCount": readyCount, "stonesBefore": initialStones, "stonesAfter": laterStones,
                        "verification": updatedVerification, "storageMarkers": updatedMarkers])
        return (updated, launchID)
    }

    @available(iOS 17, *)
    private func exerciseOnlineReload(_ fixture: NativeGameRuntimeFixture, game: NativeGame, mode: NativeGameMode,
                                     profileID: UUID, previousLaunch: UUID, marker: String) async throws -> [String: Any] {
        var ready = false
        fixture.runtime.onGameReady = { gameID, _, _ in if gameID == "gomoku" { ready = true } }
        let browser = try await fixture.open(game, mode: mode)
        try await fixture.wait(seconds: 90) { ready }
        XCTAssertEqual(try fixture.profile(browser), profileID)
        XCTAssertNotEqual(fixture.runtime.gameSessionStatuses["gomoku"]?.launchID, previousLaunch)
        return try await verifyMarkers(fixture.web(browser), profileID: profileID, marker: marker)
    }

    @available(iOS 17, *)
    private func download(_ cache: NativeGameResourceCache, fixture: NativeGameRuntimeFixture, endpoint: URL, profileID: UUID) async throws {
        cache.download(manifestURL: endpoint, gameID: "gomoku", profileID: profileID, wifiOnly: false)
        do { try await fixture.wait(seconds: 180) { !cache.isBusy } }
        catch { cache.cancel(); throw error }
    }

    @available(iOS 17, *)
    private func verifyMarkers(_ page: WKWebView, profileID: UUID, marker: String) async throws -> [String: Any] {
        let local = try await WebStoragePageFixture.evaluate(in: page, script: "return localStorage.getItem(marker);", arguments: ["marker": marker]) as? String
        XCTAssertEqual(local, "keep")
        let cookies = await WKWebsiteDataStore(forIdentifier: profileID).httpCookieStore.allCookies()
        let cookiePreserved = cookies.contains { $0.name == marker && $0.value == "keep" }
        XCTAssertTrue(cookiePreserved)
        let indexed = try await WebStoragePageFixture.evaluate(in: page, script: """
            const database = await new Promise((resolve, reject) => {
                const request = indexedDB.open(marker, 1);
                // A read must fail if the existing database disappeared; it
                // cannot recreate a missing marker and manufacture success.
                request.onupgradeneeded = () => request.transaction.abort();
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error || Error('Existing IndexedDB marker missing'));
            });
            try {
                return await new Promise((resolve, reject) => {
                    const transaction = database.transaction('fixture', 'readonly');
                    const request = transaction.objectStore('fixture').get('value');
                    transaction.oncomplete = () => resolve(request.result ?? null);
                    transaction.onerror = transaction.onabort = () => reject(transaction.error || Error('IndexedDB marker read failed'));
                });
            } finally { database.close(); }
            """, arguments: ["marker": marker]) as? String
        XCTAssertEqual(indexed, "keep")
        return ["cookiePreserved": cookiePreserved, "localStorageValue": local ?? "",
                "localStoragePreserved": local == "keep", "indexedDBValue": indexed ?? "",
                "indexedDBPreserved": indexed == "keep"]
    }

    private func playMove(_ page: WKWebView, fixture: NativeGameRuntimeFixture) async throws -> Int {
        try await fixture.wait(seconds: 30) {
            (try? await WebStoragePageFixture.evaluate(in: page, script: "return !!document.querySelector('.board-cell[aria-disabled=\"false\"]');")) as? Bool == true
        }
        let beforeValue = try await WebStoragePageFixture.evaluate(in: page, script: "const count = document.querySelectorAll('.gomoku-board .stone').length; document.querySelector('.board-cell[aria-disabled=\"false\"]').click(); return count;")
        let before = try XCTUnwrap(beforeValue as? Int)
        try await fixture.wait(seconds: 30) {
            let count = (try? await WebStoragePageFixture.evaluate(in: page, script: "return document.querySelectorAll('.gomoku-board .stone').length;")) as? Int ?? 0
            let enabled = (try? await WebStoragePageFixture.evaluate(in: page, script: "return !!document.querySelector('.board-cell[aria-disabled=\"false\"]');")) as? Bool ?? false
            return count > before && enabled
        }
        let afterValue = try await WebStoragePageFixture.evaluate(in: page, script: "return document.querySelectorAll('.gomoku-board .stone').length;")
        return try XCTUnwrap(afterValue as? Int)
    }

    @available(iOS 17, *)
    private func reader(profileID: UUID, fixture: NativeGameRuntimeFixture) async throws -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        let reader = WKWebView(frame: .zero, configuration: config)
        reader.loadSimulatedRequest(URLRequest(url: NativeGameHostEnvironment.previewOrigin!), responseHTML: "<title>resource-fault-reader</title>")
        try await fixture.wait { (try? await reader.evaluateJavaScript("document.title")) as? String == "resource-fault-reader" }
        return reader
    }

    @available(iOS 17, *)
    private func verifyCacheOnly(_ manifest: NativeGameResourceManifest, profileID: UUID,
                                 fixture: NativeGameRuntimeFixture, stage: String) async throws -> [String: Any] {
        let page = try await reader(profileID: profileID, fixture: fixture)
        defer { page.stopLoading() }
        let resources: [[String: Any]] = manifest.resources.enumerated().map { index, resource in
            ["index": index, "path": resource.url.path, "url": NativeGameHostEnvironment.transportURL(resource.url).absoluteString,
             "bytes": resource.byteCount, "sha256": resource.sha256]
        }
        let observation = try await WebStoragePageFixture.evaluate(in: page, script: """
            const results = [];
            const check = async r => {
                const result = {index:r.index, path:r.path, status:null, expectedBytes:r.bytes, actualBytes:null,
                    expectedSHA256:r.sha256, actualSHA256:null, contentType:null, error:null, ok:false};
                try {
                    const response = await fetch(r.url, {cache:'only-if-cached', mode:'same-origin', credentials:'same-origin', redirect:'error'});
                    result.status = response.status;
                    result.contentType = response.headers.get('content-type');
                    const data = await response.arrayBuffer();
                    result.actualBytes = data.byteLength;
                    const digest = await crypto.subtle.digest('SHA-256', data);
                    result.actualSHA256 = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2,'0')).join('');
                    result.ok = response.status === 200 && data.byteLength === r.bytes && result.actualSHA256 === r.sha256;
                    if (!result.ok) result.error = response.status !== 200 ? 'HTTP_STATUS' : data.byteLength !== r.bytes ? 'BYTE_COUNT_MISMATCH' : 'SHA256_MISMATCH';
                } catch (error) {
                    result.error = {name:String(error?.name || 'Error').slice(0,80), message:String(error?.message || error).slice(0,200)};
                }
                return result;
            };
            for (let start = 0; start < resources.length; start += 12) {
                const batch = await Promise.all(resources.slice(start, start + 12).map(check));
                results.push(...batch);
            }
            return {batchSize:12, results};
            """, arguments: ["resources": resources]) as? [String: Any]
        let results = observation?["results"] as? [[String: Any]] ?? []
        let passed = results.filter { $0["ok"] as? Bool == true }.count
        let failures = results.filter { $0["ok"] as? Bool != true }
        let allVerified = results.count == resources.count && passed == resources.count
        let summary: [String: Any] = ["allVerified": allVerified, "expectedCount": resources.count,
            "checkedCount": results.count, "passedCount": passed, "failedCount": failures.count, "batchSize": 12]
        let diagnostic: [String: Any] = ["kind": "cache-only-resource-probe", "stage": stage,
            "manifestVersion": manifest.version, "profileID": profileID.uuidString,
            "readerContext": ["credentials": "same-origin", "cookieBlockingRule": false,
                              "networkFallback": false, "sameNamedProfile": true],
            "summary": summary, "resources": results]
        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "native-game-cache-only-\(stage).json"; attachment.lifetime = .keepAlways
            add(attachment)
        }
        guard allVerified else {
            let first = failures.first
            throw NSError(domain: "NativeGameResourceFaults", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Cache-only verification failed at \(stage): \(passed)/\(resources.count) verified; first failure \(first?["path"] as? String ?? "missing result"), status \(first?["status"] ?? "unknown")"])
        }
        return summary
    }

    @available(iOS 17, *)
    private func cacheOnlyStatus(_ url: URL, profileID: UUID, fixture: NativeGameRuntimeFixture) async throws -> Int {
        let page = try await reader(profileID: profileID, fixture: fixture)
        defer { page.stopLoading() }
        return (try await WebStoragePageFixture.evaluate(in: page, script: "try { return (await fetch(url, {cache:'only-if-cached', mode:'same-origin', credentials:'same-origin'})).status; } catch { return 0; }",
            arguments: ["url": NativeGameHostEnvironment.transportURL(url).absoluteString]) as? Int) ?? -1
    }
}

private final class NativeGameResourceFaultControl {
    struct Status: Decodable {
        struct Counts: Decodable { let manifestRequests: Int; let baseAssetRequests: Int; let slowResourceRequests: Int }
        let enabled: Bool
        let scenario: String
        let runID: String?
        let counts: Counts
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: NativeGameResourceFaultNoRedirects(), delegateQueue: nil)
    }()
    func close() { session.invalidateAndCancel() }
    func status() async throws -> Status { try await request(nil) }
    func set(_ scenario: String, runID: UUID) async throws -> Status {
        let value = try await request(["schemaVersion": 1, "scenario": scenario, "gameID": "gomoku", "runID": runID.uuidString])
        guard value.enabled, value.scenario == scenario, value.runID == runID.uuidString else { throw URLError(.badServerResponse) }
        return value
    }
    func manifest(_ canonical: URL) async throws -> NativeGameResourceManifest {
        let target = NativeGameHostEnvironment.transportURL(canonical)
        let (data, raw) = try await session.data(from: target)
        guard let response = raw as? HTTPURLResponse, response.statusCode == 200, response.url == target else { throw URLError(.badServerResponse) }
        return try NativeGameResourceManifest.decode(data, manifestURL: canonical, gameID: "gomoku")
    }
    private func request(_ body: [String: Any]?) async throws -> Status {
        let url = URL(string: "http://127.0.0.1:18146/__native-game-faults/control")!
        var request = URLRequest(url: url)
        request.setValue("resource-cache-v1", forHTTPHeaderField: "X-Yunle-Native-Fault-Fixture")
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse, response.statusCode == 200, response.url == url else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Status.self, from: data)
    }
}

private final class NativeGameResourceFaultNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Explicit opt-in uses the actual local build and actual game lifecycle events.
/// A one-sample preflight is labelled separately and never counts as the N=10 result.
@MainActor
final class NativeGameStartupLiveTests: XCTestCase {
    func testFreshRuntimeStartupBeforeAndAfterResourcePreparation() async throws {
        guard #available(iOS 17, *), NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1" else {
            throw XCTSkip("Start the fixed local preview and explicitly set YUNLEFUN_PLAY_PREVIEW=1")
        }
        let samples = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_SAMPLES"] == "1" ? 1 : 10
        let onlyGame = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_ONLY"]
        guard onlyGame == nil || onlyGame == "gomoku" || onlyGame == "paper-star" else {
            throw NSError(domain: "NativeGameStartupLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "YUNLEFUN_NATIVE_GAME_ONLY must be gomoku or paper-star when specified"])
        }
        let scenes = [("gomoku", "computer"), ("paper-star", "local")].filter { onlyGame == nil || $0.0 == onlyGame }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        let cache = NativeGameResourceCache(defaults: fixture.defaults)
        addTeardownBlock {
            await MainActor.run { cache.cancel() }
            let profiles = await fixture.trackedProfiles()
            for id in profiles { await cache.clear(profileID: id) }
            await fixture.close()
        }
        var results: [[String: Any]] = []
        var completed = false
        defer {
            let report: [String: Any] = ["kind": samples == 1 ? "preflight" : "native-runtime-startup", "samplesPerScene": samples,
                                       "origin": "http://127.0.0.1:18146", "games": scenes.map { $0.0 },
                                       "completed": completed, "results": results]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-game-startup-\(samples == 1 ? "preflight" : "n10").json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        for (gameID, modeID) in scenes {
            let game = try fixture.game(gameID), mode = try fixture.mode(modeID, gameID: gameID)
            let profileID = try fixture.runtime.gameResourceProfile(for: game, catalog: fixture.catalog)
            fixture.track(profileID)
            await cache.clear(profileID: profileID)
            for prepared in [false, true] {
                if prepared {
                    let endpoint = try XCTUnwrap(game.resourceManifestURL.flatMap(URL.init(string:)))
                    cache.download(manifestURL: endpoint, gameID: gameID, profileID: profileID, wifiOnly: false)
                    try await fixture.wait(seconds: 180) { !cache.isBusy }
                    XCTAssertNil(cache.error)
                    _ = try XCTUnwrap(cache.entry(gameID: gameID, profileID: profileID), cache.error ?? "Missing verified resource preparation")
                }
                var values: [Double] = []
                for _ in 0..<samples {
                    values.append(try await startupSample(fixture, game: game, mode: mode, profileID: profileID, prepared: prepared))
                }
                let ordered = values.sorted()
                let p50 = ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.5)) - 1)]
                let p90 = ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.9)) - 1)]
                let stage = prepared ? "prepared" : "cold-resources"
                results.append(["gameId": gameID, "modeId": modeID, "stage": stage, "samples": values,
                                "resourceVersion": game.resourceVersion ?? "", "p50Milliseconds": p50, "p90Milliseconds": p90])
                print("NATIVE_GAME_STARTUP game=\(gameID) mode=\(modeID) stage=\(stage) n=\(values.count) p50-ms=\(p50) p90-ms=\(p90)")
            }
            await fixture.endAll()
            await cache.clear(profileID: profileID)
        }
        completed = true
    }

    @available(iOS 17, *)
    private func startupSample(_ fixture: NativeGameRuntimeFixture, game: NativeGame, mode: NativeGameMode,
                               profileID: UUID, prepared: Bool) async throws -> Double {
        await fixture.endAll()
        if !prepared {
            await WKWebsiteDataStore(forIdentifier: profileID).removeData(ofTypes: NativeGameResourcePolicy.cacheTypes, modifiedSince: .distantPast)
        }
        var measured: Double?
        let tapped = ProcessInfo.processInfo.systemUptime
        fixture.runtime.onGameReady = { observed, _, _ in
            if observed == game.gameId, measured == nil {
                measured = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
            }
        }
        defer { fixture.runtime.onGameReady = nil }
        let browser = try await fixture.open(game, mode: mode)
        XCTAssertEqual(try fixture.profile(browser), profileID, "Preparer and actual runtime must use the same named WebKit store")
        do {
            try await fixture.wait(seconds: 90) { measured != nil }
        } catch {
            await attachStartupDiagnostic(fixture, browser: browser, game: game, mode: mode, prepared: prepared)
            throw error
        }
        return try XCTUnwrap(measured)
    }

    private func attachStartupDiagnostic(_ fixture: NativeGameRuntimeFixture, browser: WebViewController,
                                         game: NativeGame, mode: NativeGameMode, prepared: Bool) async {
        var diagnostic: [String: Any] = ["gameId": game.gameId, "modeId": mode.id,
                                       "stage": prepared ? "prepared" : "cold-resources"]
        if let page = try? fixture.web(browser) {
            let result = NativeGameRuntimeCallback<Result<Any, Error>>()
            page.callAsyncJavaScript("""
                const scrub = window.__nativeGameTestScrub || (value => String(value ?? '').replace(/[?#][^\\s\"'<>]*/g, '').slice(0, 300));
                const url = new URL(window.location.href); url.search = ''; url.hash = '';
                const text = selector => Array.from(document.querySelectorAll(selector)).slice(0, 12).map(node => scrub(node.textContent));
                return {
                  href: url.href,
                  nativeGameState: document.documentElement.dataset.nativeGameState || null,
                  visibilityState: document.visibilityState,
                  canvases: Array.from(document.querySelectorAll('canvas')).map(canvas => ({
                    width: canvas.width, height: canvas.height,
                    clientWidth: canvas.clientWidth, clientHeight: canvas.clientHeight
                  })),
                  loading: text('.paper-star-loading, .paper-star-local__loading'),
                  alerts: text('[role=alert]'),
                  rendererErrors: text('[data-renderer-error], [class*=renderer-error]'),
                  errors: window.__nativeGameTestErrors || []
                };
                """, arguments: [:], in: nil, in: .page) { result.value = $0 }
            let deadline = Date().addingTimeInterval(5)
            while result.value == nil && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
            switch result.value {
            case .success(let value): diagnostic["page"] = value
            case .failure(let error):
                let failure = error as NSError
                diagnostic["evaluationError"] = ["domain": failure.domain, "code": failure.code]
            case nil: diagnostic["evaluationError"] = "No WebKit callback within five seconds"
            }
        } else {
            diagnostic["evaluationError"] = "Runtime WebKit view unavailable"
        }
        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "native-game-startup-timeout-\(game.gameId)-\(mode.id)-\(prepared ? "prepared" : "cold")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

/// Current-build navigation-path comparison, not an old-commit performance baseline.
/// The engine's existing lifecycle message is the only successful end condition.
@MainActor
final class NativeGameEntryComparisonLiveTests: XCTestCase {
    func testSameBuildLegacyEntryAgainstDirectAndPreparedStartup() async throws {
        guard #available(iOS 17, *),
              NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_ENTRY_COMPARISON"] == "1" else {
            throw XCTSkip("Current-build entry comparison requires its explicit opt-in and the fixed Play preview")
        }
        let samples = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_SAMPLES"] == "1" ? 1 : 10
        let only = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_ONLY"]
        guard only == nil || only == "gomoku" || only == "paper-star" else {
            throw NSError(domain: "NativeGameEntryComparison", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "YUNLEFUN_NATIVE_GAME_ONLY must be gomoku or paper-star"])
        }
        let scenes = [("gomoku", "computer"), ("paper-star", "local")].filter { only == nil || only == $0.0 }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        fixture.root.collectResourceTiming = true
        let cache = NativeGameResourceCache(defaults: fixture.defaults)
        addTeardownBlock {
            await MainActor.run { cache.cancel() }
            for id in await fixture.trackedProfiles() { await cache.clear(profileID: id) }
            await fixture.close()
        }
        let firstGame = try fixture.game(try XCTUnwrap(scenes.first?.0))
        let fixedProfile = try fixture.runtime.gameResourceProfile(for: firstGame, catalog: fixture.catalog)
        fixture.track(fixedProfile)
        var groups: [[String: Any]] = []
        var completed = false
        defer {
            let report: [String: Any] = [
                "kind": samples == 1 ? "same-build-entry-comparison-preflight" : "same-build-entry-comparison",
                "historicalCommitBaseline": false, "completed": completed,
                "origin": "http://127.0.0.1:18146", "games": scenes.map { $0.0 },
                "samplesPerStage": samples, "expectedSampleCount": scenes.count * 3 * samples,
                "scope": "Current identical public build; automated Home → detail → mode versus direct mode, with and without verified resource preparation",
                "coldDefinition": "Fresh WKWebView; only this fixture profile's HTTP memory/disk caches cleared before the tap; WebKit process and OS caches are not reset",
                "preparedDefinition": "End the preceding session, clear the same profile's HTTP caches, prepare and verify its current manifest, then open fresh WebViews without clearing the prepared cache",
                "sameNamedProfileAcrossStagesAndGames": true, "legacyAutomationPollMilliseconds": 20,
                "navigationModel": "Poll public visible links every 20 ms and click as soon as their DOM conditions pass; real SPA or full-document navigation is accepted. This is not an average human think-time model.",
                "timingNotes": "Native uptime tap-to-engine-ready and Web performance timing have separate clocks. Native timing includes test observer collection and automated-link polling overhead. Resource timing is main-document-only; parallel duration sums are not wall time; zero transferSize does not prove a cache hit.",
                "resourceCoverage": "Each departing document is frozen immediately before its actual link click, plus the final genuine engine-ready snapshot. Retain the latest snapshot per timeOrigin to avoid SPA double counting. Requests still pending at a cutoff or completing between click and unload may be absent; this is not complete network-path coverage.",
                "results": groups,
            ]
            attach(report, name: "native-game-same-build-entry-comparison-\(samples == 1 ? "preflight" : "n10")")
        }
        for (gameID, modeID) in scenes {
            let game = try fixture.game(gameID), mode = try fixture.mode(modeID, gameID: gameID)
            XCTAssertEqual(try fixture.runtime.gameResourceProfile(for: game, catalog: fixture.catalog), fixedProfile)
            await cache.clear(profileID: fixedProfile)
            for stage in NativeGameEntryStage.allCases {
                if stage == .prepared {
                    await fixture.endAll()
                    await WKWebsiteDataStore(forIdentifier: fixedProfile).removeData(ofTypes: NativeGameResourcePolicy.cacheTypes, modifiedSince: .distantPast)
                    let endpoint = try XCTUnwrap(game.resourceManifestURL.flatMap(URL.init(string:)))
                    cache.download(manifestURL: endpoint, gameID: gameID, profileID: fixedProfile, wifiOnly: false)
                    try await fixture.wait(seconds: 180) { !cache.isBusy }
                    let entry = try XCTUnwrap(cache.entry(gameID: gameID, profileID: fixedProfile), cache.error ?? "Missing verified preparation")
                    XCTAssertEqual(entry.version, game.resourceVersion)
                }
                var records: [[String: Any]] = []
                // Preserve a failed stage's completed observations in the partial report.
                do {
                    for index in 0..<samples {
                        var record = try await comparisonSample(fixture, game: game, mode: mode, profileID: fixedProfile, stage: stage)
                        record["sample"] = index + 1
                        records.append(record)
                    }
                } catch {
                    groups.append(["gameId": gameID, "modeId": modeID, "stage": stage.rawValue,
                                   "resourceVersion": game.resourceVersion ?? "", "completed": false, "samples": records])
                    throw error
                }
                let ordered = records.compactMap { $0["nativeTapToReadyMilliseconds"] as? Double }.sorted()
                let p50 = ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.5)) - 1)]
                let p90 = ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.9)) - 1)]
                groups.append(["gameId": gameID, "modeId": modeID, "stage": stage.rawValue,
                               "resourceVersion": game.resourceVersion ?? "", "completed": true,
                               "p50Milliseconds": p50, "p90Milliseconds": p90, "samples": records])
                print("NATIVE_GAME_ENTRY_COMPARISON current-build game=\(gameID) mode=\(modeID) stage=\(stage.rawValue) n=\(records.count) p50-ms=\(p50) p90-ms=\(p90)")
            }
            await fixture.endAll()
            await cache.clear(profileID: fixedProfile)
        }
        completed = true
    }

    @available(iOS 17, *)
    private func comparisonSample(_ fixture: NativeGameRuntimeFixture, game: NativeGame, mode: NativeGameMode,
                                  profileID: UUID, stage: NativeGameEntryStage) async throws -> [String: Any] {
        await fixture.endAll()
        if stage != .prepared {
            await WKWebsiteDataStore(forIdentifier: profileID).removeData(ofTypes: NativeGameResourcePolicy.cacheTypes, modifiedSince: .distantPast)
        }
        let target = try game.launchURL(for: mode)
        fixture.root.legacyEntry = stage == .legacyCold
            ? NativeGameLegacyEntry(gameID: game.gameId, modeID: mode.id, modePath: target.path) : nil
        var ready: Double?
        let tapped = ProcessInfo.processInfo.systemUptime
        fixture.runtime.onGameReady = { observed, observedMode, _ in
            if observed == game.gameId, observedMode == mode.id, ready == nil {
                ready = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
            }
        }
        defer { fixture.runtime.onGameReady = nil; fixture.root.legacyEntry = nil }
        let browser = try await fixture.open(game, mode: mode)
        let page = try fixture.web(browser)
        XCTAssertEqual(try fixture.profile(browser), profileID)
        var phases: [String: Double] = [:]
        var observations: [[String: Any]] = []
        do {
            if stage == .legacyCold {
                let detailPath = "/games/\(game.gameId)"
                let home = try await clickActualLink(page, currentPath: "/", targetPath: detailPath)
                let homeClick = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
                phases["homeLinkClickedMilliseconds"] = homeClick
                observations.append(["phase": "before-home-to-detail-click", "snapshot": home,
                                     "nativeObservedMilliseconds": homeClick])
                let detail = try await clickActualLink(page, currentPath: detailPath, targetPath: target.path)
                let modeClick = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
                phases["modeLinkClickedMilliseconds"] = modeClick
                observations.append(["phase": "before-detail-to-mode-click", "snapshot": detail,
                                     "nativeObservedMilliseconds": modeClick])
            }
            try await fixture.wait(seconds: 90) { ready != nil }
            let observation = try await NativeGameEntryProbe.evaluate(page, script: """
                const arena = document.querySelector('[data-testid="paper-star-arena"]');
                return { timing: window.__nativeGameReadyTimingSnapshot || null, path: location.pathname,
                         state: document.documentElement.dataset.nativeGameState || null,
                         paperStarPhase: arena?.dataset.phase || null, rendererReady: arena?.dataset.rendererReady || null,
                         rendererReadyObservation: window.__nativePaperStarRendererReadySnapshot || null };
                """) as? [String: Any]
            let actual = try XCTUnwrap(observation)
            XCTAssertEqual(actual["path"] as? String, target.path)
            XCTAssertEqual(actual["state"] as? String, "ready")
            let timing = try XCTUnwrap(actual["timing"] as? [String: Any], "The genuine Web ready event must freeze its own resource timing snapshot")
            if game.gameId == "paper-star" {
                XCTAssertEqual(actual["paperStarPhase"] as? String, "playing")
                XCTAssertEqual(actual["rendererReady"] as? String, "true")
                let renderer = try XCTUnwrap(actual["rendererReadyObservation"] as? [String: Any], "Observe the real renderer transition separately from operability")
                let rendererAt = try XCTUnwrap(renderer["atMilliseconds"] as? NSNumber).doubleValue
                let engineAt = try XCTUnwrap(timing["snapshotAtMilliseconds"] as? NSNumber).doubleValue
                XCTAssertGreaterThanOrEqual(rendererAt, 0)
                XCTAssertLessThanOrEqual(rendererAt, engineAt)
            }
            XCTAssertEqual((timing["overflowCount"] as? NSNumber)?.intValue, 0, "Resource timing must not silently omit full-buffer entries")
            observations.append(["phase": "actual-engine-ready", "snapshot": timing,
                                 "nativeObservedMilliseconds": (ProcessInfo.processInfo.systemUptime - tapped) * 1000])
            let documents = try documentReports(observations)
            return ["nativeTapToReadyMilliseconds": try XCTUnwrap(ready), "navigationPhases": phases,
                    "documentCount": documents.count, "documents": documents,
                    "observedResourcesAcrossDocuments": resourceTotals(documents),
                    "paperStarPhase": actual["paperStarPhase"] ?? NSNull(),
                    "rendererReady": actual["rendererReady"] ?? NSNull(),
                    "rendererReadyObservation": actual["rendererReadyObservation"] ?? NSNull(),
                    "completeNetworkPathCoverage": false]
        } catch {
            var evidence: [String: Any] = ["gameId": game.gameId, "modeId": mode.id, "stage": stage.rawValue,
                                           "navigationPhases": phases]
            if let documents = try? documentReports(observations) { evidence["observedDocuments"] = documents }
            if let pageState = try? await NativeGameEntryProbe.evaluate(page, script: NativeGameEntryProbe.failureSnapshot) {
                evidence["page"] = pageState
            }
            attach(evidence, name: "native-game-entry-comparison-failure-\(game.gameId)-\(stage.rawValue)")
            throw error
        }
    }

    /// Calls the actual rendered anchor once. It never assigns location or calls
    /// the router, and adds no human think time to either navigation step.
    private func clickActualLink(_ page: WKWebView, currentPath: String, targetPath: String) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let result = try await NativeGameEntryProbe.evaluate(page, script: """
                if (location.origin !== 'http://127.0.0.1:18146' || location.pathname !== currentPath || document.documentElement.dataset.appReady !== 'true') return null;
                const game = targetPath.split('/')[2];
                const selector = currentPath === '/'
                  ? `.game-grid .game-card[data-game="${game}"] a.game-card-link[href]`
                  : `.detail-page[data-game="${game}"] .detail-actions a[href]`;
                const link = Array.from(document.querySelectorAll(selector)).find(node => {
                  const url = new URL(node.href, location.href);
                  return url.origin === location.origin && url.pathname === targetPath && !url.search && !url.hash && node.getClientRects().length > 0;
                });
                if (!link) return null;
                if (typeof window.__nativeGameResourceTimingSnapshot !== 'function') throw Error('Missing real-document resource observer');
                const snapshot = window.__nativeGameResourceTimingSnapshot();
                link.click();
                return snapshot;
                """, arguments: ["currentPath": currentPath, "targetPath": targetPath])
            if let snapshot = result as? [String: Any] { return snapshot }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "NativeGameEntryComparison", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "A real visible link was not available on the expected public route"])
    }

    /// A full navigation has a new timeOrigin. SPA snapshots share one timeOrigin
    /// and are cumulative, so only their latest resource counters are retained.
    private func documentReports(_ observations: [[String: Any]]) throws -> [[String: Any]] {
        var snapshots: [Double: [String: Any]] = [:]
        var cutoffs: [Double: [[String: Any]]] = [:]
        for observation in observations {
            let snapshot = try XCTUnwrap(observation["snapshot"] as? [String: Any])
            let origin = try XCTUnwrap((snapshot["timeOrigin"] as? NSNumber)?.doubleValue)
            let cutoff = try XCTUnwrap((snapshot["snapshotAtMilliseconds"] as? NSNumber)?.doubleValue)
            XCTAssertEqual((snapshot["overflowCount"] as? NSNumber)?.intValue, 0)
            cutoffs[origin, default: []].append([
                "phase": observation["phase"] ?? "unknown", "documentPath": snapshot["documentPath"] ?? "unknown",
                "snapshotAtMilliseconds": cutoff,
                "nativeObservedMilliseconds": observation["nativeObservedMilliseconds"] ?? 0,
            ])
            let previous = (snapshots[origin]?["snapshotAtMilliseconds"] as? NSNumber)?.doubleValue ?? -1
            if cutoff >= previous { snapshots[origin] = snapshot }
        }
        return snapshots.keys.sorted().map { origin in
            ["timeOrigin": origin, "observations": cutoffs[origin] ?? [],
             "latestSnapshot": snapshots[origin] ?? [:], "requestsPendingAfterCutoffNotObserved": true]
        }
    }

    private func resourceTotals(_ documents: [[String: Any]]) -> [String: Any] {
        var count = 0
        var transfer = 0.0, encoded = 0.0, duration = 0.0
        for document in documents {
            guard let snapshot = document["latestSnapshot"] as? [String: Any] else { continue }
            count += (snapshot["resourceCount"] as? NSNumber)?.intValue ?? 0
            for group in snapshot["resourceGroups"] as? [[String: Any]] ?? [] {
                transfer += (group["transferSizeBytes"] as? NSNumber)?.doubleValue ?? 0
                encoded += (group["encodedBodySizeBytes"] as? NSNumber)?.doubleValue ?? 0
                duration += (group["resourceDurationSumMilliseconds"] as? NSNumber)?.doubleValue ?? 0
            }
        }
        return ["resourceCount": count, "transferSizeBytes": transfer, "encodedBodySizeBytes": encoded,
                "resourceDurationSumMilliseconds": duration, "latestSnapshotPerDocumentOnly": true,
                "documentNavigationEntriesReportedSeparately": true,
                "parallelDurationSumIsNotWallTime": true, "zeroTransferDoesNotProveCacheHit": true]
    }

    private func attach(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Comparison evidence must remain JSON serializable")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private enum NativeGameEntryStage: String, CaseIterable {
    case legacyCold = "same-build-home-detail-mode-cold"
    case directCold = "direct-mode-cold"
    case prepared = "direct-mode-prepared"
}

/// Measures a retained page's return separately from a fresh startup. The
/// existing one-shot engine-ready event is never replayed to time a resume.
@MainActor
final class NativeGameRetainedResumeLiveTests: XCTestCase {
    func testRetainedGameResumeToVisibleOperableFrameAndAcceptedInput() async throws {
        guard #available(iOS 17, *), NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_RETAINED_RESUME"] == "1" else {
            throw XCTSkip("Retained resume measurement requires the fixed preview and explicit resume opt-in")
        }
        let count = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_SAMPLES"] == "1" ? 1 : 10
        let only = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_ONLY"]
        guard only == nil || only == "gomoku" || only == "paper-star" else {
            throw NSError(domain: "NativeGameRetainedResume", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The optional game filter must be gomoku or paper-star"])
        }
        let scenes = [("gomoku", "local"), ("paper-star", "local")].filter { only == nil || only == $0.0 }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        addTeardownBlock { await fixture.close() }
        var groups: [[String: Any]] = []
        var completed = false
        defer {
            attach(["kind": count == 1 ? "retained-resume-preflight" : "retained-resume-n10",
                    "completed": completed, "origin": "http://127.0.0.1:18146",
                    "samplesPerScene": count, "expectedSampleCount": scenes.count * count,
                    "results": groups,
                    "timingDefinition": "Native uptime starts immediately before public runtime.resumeGame. The first endpoint is a native visible presentation plus two real Web requestAnimationFrames and current operable DOM state. The second endpoint additionally confirms an actual test input changed game state.",
                    "retainedDefinition": "Actual minimize toolbar action and completed dismissal; same live WebView, named profile and launch ID, plus strict JavaScript identity with the retained original document and documentElement objects and random in-memory marker. No cache clearing, manufactured lifecycle event or new ready callback.",
                    "clockObservationDefinition": "Initial and observed performance.timeOrigin values and their raw difference are recorded only as clock observations. Document identity is proved by original object reference equality, not timestamp equality or a numerical tolerance.",
                    "observationOverhead": "The native presentation/DOM observers poll at 50 ms, async JavaScript completion at 20 ms; UIKit animations are disabled by the existing isolated fixture. Endpoints are observed upper bounds, not touch-hardware latency.",
                    "inputScope": "DOM click accepts a Gomoku local move; actual page keyboard handlers accept Space fire in PaperStar local. These are synthetic test inputs through real game handlers, not physical-touch or VoiceOver claims.",
                    "scope": "Same local candidate and isolated fixture only; retained same-process session, not OS suspension, process eviction, app restart or online room recovery."],
                   name: "native-game-retained-resume-\(count == 1 ? "preflight" : "n10").json")
        }
        for (gameID, modeID) in scenes {
            var records: [[String: Any]] = []
            do {
                try await exercise(fixture, gameID: gameID, modeID: modeID, count: count, records: &records)
            } catch {
                groups.append(["gameId": gameID, "modeId": modeID, "completed": false, "samples": records])
                throw error
            }
            let frames = records.compactMap { $0["nativeTapToVisibleOperableFrameMilliseconds"] as? Double }
            let inputs = records.compactMap { $0["nativeTapToAcceptedInputMilliseconds"] as? Double }
            XCTAssertEqual(frames.count, count)
            XCTAssertEqual(inputs.count, count)
            groups.append(["gameId": gameID, "modeId": modeID, "completed": true, "samples": records,
                           "visibleOperableFrameP50Milliseconds": percentile(frames, 0.5),
                           "visibleOperableFrameP90Milliseconds": percentile(frames, 0.9),
                           "acceptedInputP50Milliseconds": percentile(inputs, 0.5),
                           "acceptedInputP90Milliseconds": percentile(inputs, 0.9)])
            await fixture.endAll()
        }
        completed = true
    }

    @available(iOS 17, *)
    private func exercise(_ fixture: NativeGameRuntimeFixture, gameID: String, modeID: String,
                          count: Int, records: inout [[String: Any]]) async throws {
        await fixture.endAll()
        let game = try fixture.game(gameID), mode = try fixture.mode(modeID, gameID: gameID)
        let profileID = try fixture.runtime.gameResourceProfile(for: game, catalog: fixture.catalog)
        fixture.track(profileID)
        var readyCount = 0
        fixture.runtime.onGameReady = { observed, observedMode, _ in
            if observed == gameID, observedMode == modeID { readyCount += 1 }
        }
        defer { fixture.runtime.onGameReady = nil }
        let browser = try await fixture.open(game, mode: mode)
        let page = try fixture.web(browser)
        try await fixture.wait(seconds: 90) { readyCount == 1 }
        let initial = try XCTUnwrap(fixture.runtime.gameSessionStatuses[gameID])
        let marker = UUID().uuidString
        let initialOrigin = try await NativeGameEntryProbe.evaluate(page, script: """
            window.__nativeRetainedResumeIdentity = {
                marker, originalDocument: document, originalDocumentElement: document.documentElement
            };
            return performance.timeOrigin;
            """, arguments: ["marker": marker])
        let initialTimeOrigin = try XCTUnwrap(initialOrigin as? NSNumber).doubleValue
        for index in 0..<count {
            do {
                let items = browser.navigationItem.leftBarButtonItems ?? browser.navigationItem.leftBarButtonItem.map { [$0] } ?? []
                let minimize = try XCTUnwrap(items.first { $0.accessibilityIdentifier == "runtime.minimize" },
                                            "Use the actual visible native minimize control")
                XCTAssertTrue(minimize.isEnabled)
                let action = try XCTUnwrap(minimize.action)
                XCTAssertTrue(UIApplication.shared.sendAction(action, to: minimize.target, from: minimize, for: nil))
                try await fixture.wait(seconds: 10) {
                    fixture.root.presentedViewController == nil && browser.viewIfLoaded?.window == nil
                }
                XCTAssertTrue(fixture.runtime.runningGameIDs.contains(gameID), "Minimize must retain the running session")
                let tapped = ProcessInfo.processInfo.systemUptime
                fixture.runtime.resumeGame(gameID, catalog: fixture.catalog, library: fixture.library)
                let resumed = try await fixture.browser(applicationID: browser.appInfo?.id ?? game.appId)
                XCTAssertTrue(resumed === browser)
                XCTAssertTrue(try fixture.web(resumed) === page)
                XCTAssertEqual(try fixture.profile(resumed), profileID)
                var observed: [String: Any]?
                try await fixture.wait(seconds: 15) {
                    let result = try? await NativeGameEntryProbe.evaluate(page, script: Self.operableFrame,
                        arguments: ["gameID": gameID, "expectedMarker": marker])
                    guard let value = result as? [String: Any], value["operable"] as? Bool == true else { return false }
                    observed = value
                    return true
                }
                let frameMilliseconds = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
                let frame = try XCTUnwrap(observed)
                let observedTimeOrigin = try XCTUnwrap((frame["timeOrigin"] as? NSNumber)?.doubleValue)
                XCTAssertEqual(frame["sameOriginalDocument"] as? Bool, true)
                XCTAssertEqual(frame["sameOriginalDocumentElement"] as? Bool, true)
                XCTAssertEqual(frame["markerMatches"] as? Bool, true)
                XCTAssertEqual(frame["visibilityState"] as? String, "visible")
                XCTAssertTrue(browser.viewIfLoaded?.window === fixture.window)
                let acceptedValue = try await NativeGameEntryProbe.evaluate(page, script: Self.acceptInput,
                    arguments: ["gameID": gameID, "cellIndex": frame["inputCellIndex"] ?? -1])
                let inputMilliseconds = (ProcessInfo.processInfo.systemUptime - tapped) * 1000
                let accepted = try XCTUnwrap(acceptedValue as? [String: Any])
                XCTAssertTrue(accepted["accepted"] as? Bool == true, "A visible stale snapshot is not operability")
                XCTAssertEqual(fixture.runtime.gameSessionStatuses[gameID]?.launchID, initial.launchID)
                XCTAssertEqual(fixture.runtime.gameSessionStatuses[gameID]?.readyMilliseconds, initial.readyMilliseconds)
                XCTAssertEqual(readyCount, 1, "Retained resume must not manufacture a second engine-ready callback")
                records.append(["sample": index + 1, "nativeTapToVisibleOperableFrameMilliseconds": frameMilliseconds,
                                "nativeTapToAcceptedInputMilliseconds": inputMilliseconds,
                                "sameWebView": true, "sameNamedProfile": true, "sameLaunch": true,
                                "engineReadyCount": readyCount,
                                "clockObservation": ["initialTimeOrigin": initialTimeOrigin,
                                                     "observedTimeOrigin": observedTimeOrigin,
                                                     "observedMinusInitialMilliseconds": observedTimeOrigin - initialTimeOrigin],
                                "visibleFrame": frame, "acceptedInput": accepted])
            } catch {
                let snapshot = try? await NativeGameEntryProbe.evaluate(page, script: NativeGameEntryProbe.failureSnapshot)
                attach(["gameId": gameID, "modeId": modeID, "sample": index + 1,
                        "engineReadyCount": readyCount, "nativeViewVisible": browser.viewIfLoaded?.window != nil,
                        "page": snapshot ?? NSNull()], name: "native-game-retained-resume-failure.json")
                throw error
            }
        }
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let ordered = values.sorted()
        guard !ordered.isEmpty else { return -1 }
        return ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * fraction)) - 1)]
    }

    private func attach(_ report: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Retained resume evidence must remain JSON serializable"); return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private static let operableFrame = #"""
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const exposed = element => {
          if (!element) return false;
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
          return style.visibility !== 'hidden' && style.display !== 'none'
            && rect.width > 0 && rect.height > 0 && rect.left >= 0 && rect.top >= 0
            && rect.right <= innerWidth + 1 && rect.bottom <= innerHeight + 1
            && !!hit && (hit === element || element.contains(hit));
        };
        const arena = document.querySelector('[data-testid="paper-star-arena"]');
        const control = gameID === 'gomoku'
          ? Array.from(document.querySelectorAll('.board-cell[aria-disabled="false"]')).find(exposed)
          : document.querySelector('.paper-star-touch__fire');
        const identity = window.__nativeRetainedResumeIdentity;
        const markerMatches = identity?.marker === expectedMarker;
        const sameOriginalDocument = identity?.originalDocument === document;
        const sameOriginalDocumentElement = identity?.originalDocumentElement === document.documentElement;
        const gameStateOperable = gameID === 'gomoku' ? !!control
          : arena?.dataset.phase === 'playing' && arena.dataset.rendererReady === 'true'
            && arena.dataset.menuOpen === 'false' && innerWidth > innerHeight;
        return { operable: markerMatches && sameOriginalDocument && sameOriginalDocumentElement
                   && document.visibilityState === 'visible'
                   && document.documentElement.dataset.nativeGameState === 'ready'
                   && gameStateOperable && exposed(control) && !control.disabled,
                 markerMatches, sameOriginalDocument, sameOriginalDocumentElement, timeOrigin: performance.timeOrigin,
                 visibilityState: document.visibilityState, documentHasFocus: document.hasFocus(),
                 currentPath: location.pathname, phase: arena?.dataset.phase || null,
                 rendererReady: arena?.dataset.rendererReady || null,
                 observedAtDocumentMilliseconds: performance.now(),
                 observedInputControlExposed: exposed(control),
                 inputCellIndex: gameID === 'gomoku' ? Array.from(document.querySelectorAll('.board-cell')).indexOf(control) : -1,
                 viewport: {width: innerWidth, height: innerHeight} };
        """#

    private static let acceptInput = #"""
        const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve));
        if (gameID === 'gomoku') {
          const count = () => document.querySelectorAll('.gomoku-board .stone').length;
          const before = count();
          const target = document.querySelectorAll('.board-cell')[cellIndex];
          if (!target || target.getAttribute('aria-disabled') !== 'false') throw Error('The verified visible Gomoku input is no longer enabled');
          target.click();
          const deadline = performance.now() + 2000;
          while (count() <= before && performance.now() < deadline) await nextFrame();
          const after = count();
          return {kind:'local-board-click', beforeStones:before, afterStones:after, accepted:after > before};
        }
        const arena = document.querySelector('[data-testid="paper-star-arena"]');
        if (arena?.dataset.phase !== 'playing' || arena.dataset.rendererReady !== 'true') throw Error('PaperStar is not playing after resume');
        const before = Number(arena.dataset.fireSequence);
        const beforeTick = Number(arena.dataset.tick);
        const key = type => window.dispatchEvent(new KeyboardEvent(type, {code:'Space', key:' ', bubbles:true, cancelable:true}));
        key('keydown');
        try {
          const deadline = performance.now() + 2000;
          while ((Number(arena.dataset.fireSequence) <= before || Number(arena.dataset.tick) <= beforeTick)
                 && performance.now() < deadline) await nextFrame();
          const after = Number(arena.dataset.fireSequence);
          const afterTick = Number(arena.dataset.tick);
          return {kind:'page-keyboard-space-fire', beforeFireSequence:before, afterFireSequence:after,
                  beforeTick, afterTick, accepted:after > before && afterTick > beforeTick};
        } finally { key('keyup'); }
        """#
}

/// Diagnostic phase stamps only. The original N10 benchmark and product flow stay unchanged.
@MainActor
final class NativeGameStartupPhaseLiveTests: XCTestCase {
    func testPreparedStartupPhaseTraceForTwoGames() async throws {
        guard #available(iOS 17, *),
              NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_PHASE_PROBE"] == "1" else {
            throw XCTSkip("Startup phase diagnostics require their explicit opt-in and the fixed Play preview")
        }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        fixture.root.collectResourceTiming = true
        let cache = NativeGameResourceCache(defaults: fixture.defaults)
        addTeardownBlock {
            await MainActor.run { cache.cancel() }
            for id in await fixture.trackedProfiles() { await cache.clear(profileID: id) }
            await fixture.close()
        }
        var rows: [[String: Any]] = []
        var completed = false
        defer {
            attach(["kind": "native-uptime-startup-resource-phase-diagnostic-v3", "completed": completed,
                    "clock": "ProcessInfo.processInfo.systemUptime for every phase; seconds since boot",
                    "tapDefinition": "Immediately before fixture.open, matching the original N10 API entry point; not a physical UI tap",
                    "origin": "http://127.0.0.1:18146", "samplesPerGame": 3, "expectedSamples": 6,
                    "stage": "prepared-fresh-webview", "results": rows,
                    "UIKitAnimationsEnabledDuringFixture": UIView.areAnimationsEnabled,
                    "presentationAnimatedArgument": "Forwarded unchanged; the existing fixture globally disables UIView animations",
                    "resourceTimingObserverEnabled": true,
                    "documentMilestones": "Passive isolated-world document-start / DOMContentLoaded / window.load messages, stamped only at native receipt after web/frame/world/origin/path/nonce checks",
                    "resourceTimingSnapshot": "The existing collector freezes a main-document snapshot at genuine Web ready; this test retrieves it only after native ready without installing another observer",
                    "resourceTimingClock": "Separate document performance clock; no subtraction from native uptime or server clocks",
                    "launchIDCorrelation": "Canonical launch UUID from browser.url, lowercased UTF-8 SHA256 first 16 lowercase hex; same-run request correlation only, not identity or clock conversion",
                    "limits": ["Diagnostic N3 is not a replacement N10 result, a hardware benchmark or a 30 percent target claim",
                               "Catalog/account fixture state is preloaded; no native SSO or production identity",
                               "Initial-loader prepared marks return after web.load on this successful fresh-game branch, not response, commit or network completion",
                               "Document stages measure native receipt, including WebKit IPC and extra script/handler observation overhead; they are not exact JavaScript execution timestamps",
                               "DOMContentLoaded or window.load may be received after genuine game ready; signed intervals are intentional",
                               "Resource Timing covers completed main-document observations at the existing ready cutoff, not pending/unload/Worker traffic; parallel duration sums are not wall time and zero transferSize alone does not prove cache hit",
                               "Snapshot retrieval, validation and launch-ID hashing occur only after native ready and all nine phase receipts; their overhead is not inserted before the saved ready endpoint",
                               "Callback scheduling, WebKit IPC, observer execution and test machinery remain included; no document clock is subtracted"]],
                   name: "native-game-startup-resource-phase-diagnostic-v3")
        }
        for (gameID, modeID) in [("gomoku", "computer"), ("paper-star", "local")] {
            let game = try fixture.game(gameID), mode = try fixture.mode(modeID, gameID: gameID)
            let profile = try fixture.runtime.gameResourceProfile(for: game, catalog: fixture.catalog)
            fixture.track(profile)
            await fixture.endAll()
            await cache.clear(profileID: profile)
            let endpoint = try XCTUnwrap(game.resourceManifestURL.flatMap(URL.init(string:)))
            cache.download(manifestURL: endpoint, gameID: gameID, profileID: profile, wifiOnly: false)
            try await fixture.wait(seconds: 180) { !cache.isBusy }
            let entry = try XCTUnwrap(cache.entry(gameID: gameID, profileID: profile), cache.error ?? "Missing verified preparation")
            guard let resourceVersion = game.resourceVersion, entry.version == resourceVersion else {
                throw failure("Preparation must match the selected catalog's resource version")
            }
            for sample in 1...3 {
                var row = try await trace(fixture, game: game, mode: mode, expectedProfile: profile)
                row["sample"] = sample
                row["preparationResourceVersion"] = entry.version
                rows.append(row)
            }
            await fixture.endAll()
            await cache.clear(profileID: profile)
        }
        completed = true
    }

    @available(iOS 17, *)
    private func trace(_ fixture: NativeGameRuntimeFixture, game: NativeGame, mode: NativeGameMode,
                       expectedProfile: UUID) async throws -> [String: Any] {
        await fixture.endAll()
        let target = try game.launchURL(for: mode)
        let tapped = ProcessInfo.processInfo.systemUptime
        var points: [(phase: String, uptime: TimeInterval)] = [("tap", tapped)]
        let observe: (String, TimeInterval) -> Void = { phase, uptime in points.append((phase, uptime)) }
        fixture.root.startupPhaseObserver = observe
        var ready = false
        fixture.runtime.onGameReady = { observed, observedMode, _ in
            guard observed == game.gameId, observedMode == mode.id else { return }
            observe("on-game-ready-received", ProcessInfo.processInfo.systemUptime)
            ready = true
        }
        var completed = false
        defer {
            fixture.root.startupPhaseObserver = nil
            fixture.runtime.onGameReady = nil
            fixture.root.clearStartupDocumentProbes()
            if !completed {
                attach(["gameId": game.gameId, "modeId": mode.id, "completed": false,
                        "points": points.map { point -> [String: Any] in ["phase": point.phase, "uptimeSeconds": point.uptime,
                                                 "millisecondsAfterTap": (point.uptime - tapped) * 1000] }],
                       name: "native-game-startup-resource-phase-v3-partial-\(game.gameId)")
            }
        }
        let browser = try await fixture.open(game, mode: mode)
        guard try fixture.profile(browser) == expectedProfile else {
            throw failure("The game must use the verified preparation's named profile")
        }
        let page = try fixture.web(browser)
        try await fixture.wait(seconds: 90) {
            ready && ["present-completed", "document-start-received", "dom-content-loaded-received", "window-load-received"]
                .allSatisfy { phase in points.contains { $0.phase == phase } }
        }
        let observation = try await NativeGameEntryProbe.evaluate(page, script: """
            const arena = document.querySelector('[data-testid="paper-star-arena"]');
            return {state: {
                      path: location.pathname, nativeGameState: document.documentElement.dataset.nativeGameState || null,
                      paperStarPhase: arena?.dataset.phase || null, rendererReady: arena?.dataset.rendererReady || null
                    },
                    readyResourceTimingSnapshot: window.__nativeGameReadyTimingSnapshot || null};
            """) as? [String: Any]
        let payload = try XCTUnwrap(observation)
        let actual = try XCTUnwrap(payload["state"] as? [String: Any])
        let timing = try XCTUnwrap(payload["readyResourceTimingSnapshot"] as? [String: Any],
                                  "The existing real-ready ResourceTiming snapshot must be available")
        guard timing["documentPath"] as? String == target.path,
              timing["mainDocumentOnly"] as? Bool == true,
              (timing["overflowCount"] as? NSNumber)?.intValue == 0,
              let navigation = timing["navigation"] as? [[String: Any]], !navigation.isEmpty,
              timing["resourceGroups"] is [[String: Any]],
              timing["resourceCount"] is NSNumber else {
            throw failure("The ready ResourceTiming snapshot must match this document without silent buffer overflow")
        }
        guard actual["path"] as? String == target.path, actual["nativeGameState"] as? String == "ready" else {
            throw failure("The real game must reach the selected mode and report ready")
        }
        let browserURL = try XCTUnwrap(browser.url)
        let launchItems = URLComponents(url: browserURL, resolvingAgainstBaseURL: false)?.queryItems?.filter {
            $0.name == "ylfLaunchId"
        } ?? []
        guard launchItems.count == 1, let launchID = launchItems.first?.value,
              let parsedLaunchID = UUID(uuidString: launchID),
              parsedLaunchID.uuidString.caseInsensitiveCompare(launchID) == .orderedSame,
              fixture.runtime.gameSessionStatuses[game.gameId]?.launchID == parsedLaunchID else {
            throw failure("Expected one canonical launch UUID matching the actual ready game")
        }
        let launchIDHash = String(SHA256.hash(data: Data(launchID.lowercased().utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(16))
        if game.gameId == "paper-star" {
            guard actual["paperStarPhase"] as? String == "playing", actual["rendererReady"] as? String == "true" else {
                throw failure("PaperStar must be operable after its unchanged opening countdown")
            }
        }
        let phases = ["tap", "present-entered", "initial-loader-entered",
                      "initial-loader-prepared-after-load-call", "present-completed", "on-game-ready-received",
                      "document-start-received", "dom-content-loaded-received", "window-load-received"]
        var stamps: [String: TimeInterval] = [:]
        for phase in phases {
            let matches = points.filter { $0.phase == phase }
            guard matches.count == 1 else { throw failure("Expected one phase stamp: \(phase), got \(matches.count)") }
            stamps[phase] = matches[0].uptime
        }
        let presentation = try XCTUnwrap(stamps["present-entered"])
        let loader = try XCTUnwrap(stamps["initial-loader-entered"])
        let prepared = try XCTUnwrap(stamps["initial-loader-prepared-after-load-call"])
        let presented = try XCTUnwrap(stamps["present-completed"])
        let readyAt = try XCTUnwrap(stamps["on-game-ready-received"])
        let documentStart = try XCTUnwrap(stamps["document-start-received"])
        let domContentLoaded = try XCTUnwrap(stamps["dom-content-loaded-received"])
        let windowLoad = try XCTUnwrap(stamps["window-load-received"])
        guard tapped <= presentation, presentation <= loader, loader <= prepared,
              prepared <= readyAt, presentation <= presented else {
            throw failure("Unexpected native phase order; inspect the partial trace")
        }
        completed = true
        return ["gameId": game.gameId, "modeId": mode.id, "completed": true, "targetPath": target.path,
                "samePreparedProfileVerified": true, "state": actual, "launchIDHash": launchIDHash,
                "readyResourceTimingSnapshot": timing,
                "points": points.map { point -> [String: Any] in ["phase": point.phase, "uptimeSeconds": point.uptime,
                                         "millisecondsAfterTap": (point.uptime - tapped) * 1000] },
                "milliseconds": ["tapToPresentEntry": (presentation - tapped) * 1000,
                                 "presentEntryToInitialLoader": (loader - presentation) * 1000,
                                 "initialLoaderToPrepared": (prepared - loader) * 1000,
                                 "preparedToReady": (readyAt - prepared) * 1000,
                                 "tapToReady": (readyAt - tapped) * 1000,
                                 "tapToPresentationCompleted": (presented - tapped) * 1000,
                                 "readyMinusPresentationCompleted": (readyAt - presented) * 1000,
                                 "preparedToDocumentStartReceipt": (documentStart - prepared) * 1000,
                                 "documentStartReceiptToDOMContentLoadedReceipt": (domContentLoaded - documentStart) * 1000,
                                 "DOMContentLoadedReceiptToWindowLoadReceipt": (windowLoad - domContentLoaded) * 1000,
                                 "documentStartReceiptToReady": (readyAt - documentStart) * 1000,
                                 "DOMContentLoadedReceiptToReady": (readyAt - domContentLoaded) * 1000,
                                 "windowLoadReceiptToReady": (readyAt - windowLoad) * 1000]]
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "NativeGameStartupPhaseProbe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func attach(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Foreground rAF delivery observations through a real game, not GPU presentation or a hardware FPS benchmark.
@MainActor
final class NativeGameFramePerformanceLiveTests: XCTestCase {
    private let logger = Logger(subsystem: "fun.yunle.apps.tests", category: "native-game-frame-probe")

    func testPaperStarLocalForegroundFrameIntervals() async throws {
        guard #available(iOS 17, *), NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_FRAME_PROBE"] == "1" else {
            throw XCTSkip("Foreground frame observations require the fixed preview and explicit frame opt-in")
        }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        addTeardownBlock { await fixture.close() }
        let game = try fixture.game("paper-star"), mode = try fixture.mode("local", gameID: "paper-star")
        var readyCount = 0
        fixture.runtime.onGameReady = { gameID, modeID, _ in
            if gameID == "paper-star", modeID == "local" { readyCount += 1 }
        }
        defer { fixture.runtime.onGameReady = nil }
        let browser = try await fixture.open(game, mode: mode)
        let page = try fixture.web(browser)
        try await fixture.wait(seconds: 90) { readyCount == 1 }
        let original = try XCTUnwrap(fixture.runtime.gameSessionStatuses["paper-star"])
        let profile = try fixture.profile(browser)
        var results: [[String: Any]] = []
        var completed = false
        defer {
            attach(["kind": "paper-star-local-foreground-raf-observation", "completed": completed,
                    "origin": "http://127.0.0.1:18146", "mode": "local", "iterations": 2,
                    "requestedSecondsPerIteration": 10, "maximumIntervalsPerIteration": 1800,
                    "resourceVersion": game.resourceVersion ?? "", "results": results,
                    "UIKitAnimationsEnabledDuringFixture": UIView.areAnimationsEnabled,
                    "clockScope": "Native begin/end use systemUptime only; rAF intervals and document durations use their own document performance clock. No cross-clock subtraction.",
                    "inputScope": "Synthetic KeyboardEvents reach the real window capture handlers. Space fires while ArrowLeft/ArrowRight alternate; preventDefault acknowledges handler capture, and actual tick/fire counters must advance.",
                    "intervalScope": "One continuous rAF collector stays active across native IPC/checkpoint gaps. Raw arrays retain their prefix up to the explicit cap; dropped counts forbid claiming a complete distribution when nonzero.",
                    "limits": ["rAF callback intervals describe JavaScript/main-thread delivery, not GPU-presented frames or physical-display FPS",
                               "No FPS pass threshold, long-task observer, JS heap estimate, renderer settings change, private process API or Swift RSS sampling",
                               "External host/WebContent RSS must stay separate; RSS is neither exclusive allocation nor footprint",
                               "Simulator Debug and test observer/input/JSON overhead are included; existing fixture disables UIKit animations"]], name: "native-paper-star-frame-observation")
        }
        for iteration in 1...2 {
            results.append(try await sample(fixture, browser: browser, page: page, iteration: iteration))
            guard fixture.runtime.gameSessionStatuses["paper-star"]?.launchID == original.launchID,
                  fixture.runtime.gameSessionStatuses["paper-star"]?.readyMilliseconds == original.readyMilliseconds,
                  readyCount == 1, try fixture.profile(browser) == profile else {
                throw failure("Frame observation must keep the same real game, profile and one-shot ready")
            }
        }
        completed = true
    }

    private func sample(_ fixture: NativeGameRuntimeFixture, browser: WebViewController,
                        page: WKWebView, iteration: Int) async throws -> [String: Any] {
        try requireForeground(fixture, browser: browser)
        let token = UUID().uuidString
        let hostPID = ProcessInfo.processInfo.processIdentifier
        let nativeStart = ProcessInfo.processInfo.systemUptime
        var nativeEnd: TimeInterval?
        var checkpoints: [[String: Any]] = []
        var completed = false
        logger.notice("YUNLEFUN_FRAME_PROBE_BEGIN iteration=\(iteration, privacy: .public) hostPID=\(hostPID, privacy: .public) uptimeSeconds=\(nativeStart, privacy: .public)")
        defer {
            let end = nativeEnd ?? ProcessInfo.processInfo.systemUptime
            logger.notice("YUNLEFUN_FRAME_PROBE_END iteration=\(iteration, privacy: .public) hostPID=\(hostPID, privacy: .public) uptimeSeconds=\(end, privacy: .public)")
            if !completed {
                attach(["iteration": iteration, "completed": false, "hostPID": Int(hostPID),
                        "nativeBeginUptime": nativeStart, "nativeEndUptime": end,
                        "checkpoints": checkpoints], name: "native-paper-star-frame-partial-\(iteration)")
            }
        }
        do {
            let installed = try await probe(page, operation: "install", token: token, nextInput: 0)
            try requireValidSnapshot(try XCTUnwrap(installed["snapshot"] as? [String: Any]))
            guard installed["inputAccepted"] as? Bool == true else { throw failure("The real keyboard handlers must capture initial fire and direction input") }
            for checkpoint in 0..<5 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try requireForeground(fixture, browser: browser)
                let observed = try await probe(page, operation: "checkpoint", token: token,
                                               nextInput: checkpoint == 4 ? -1 : checkpoint + 1)
                checkpoints.append(observed)
                try requireValidSnapshot(try XCTUnwrap(observed["snapshot"] as? [String: Any]))
                if checkpoint < 4, observed["inputAccepted"] as? Bool != true {
                    throw failure("Each input checkpoint must pass through the actual keyboard handlers")
                }
            }
            let result = try await probe(page, operation: "stop", token: token, nextInput: -1)
            try requireValidSnapshot(result)
            let initial = try XCTUnwrap(result["initialState"] as? [String: Any])
            let final = try XCTUnwrap(result["state"] as? [String: Any])
            let intervals = try XCTUnwrap(result["intervalsMilliseconds"] as? [NSNumber])
            let observedCount = try XCTUnwrap(result["observedIntervalCount"] as? NSNumber).intValue
            let dropped = try XCTUnwrap(result["droppedIntervalCount"] as? NSNumber).intValue
            guard !intervals.isEmpty, intervals.count <= 1800, observedCount == intervals.count + dropped,
                  result["stopReason"] as? String == "native-completed",
                  (try number(final, "tick")) > (try number(initial, "tick")),
                  (try number(final, "fireSequence")) > (try number(initial, "fireSequence")) else {
                throw failure("The continuous trace must contain real frames, advancing simulation and accepted fire")
            }
            nativeEnd = ProcessInfo.processInfo.systemUptime
            completed = true
            return ["iteration": iteration, "completed": true, "hostPID": Int(hostPID),
                    "nativeBeginUptime": nativeStart, "nativeEndUptime": nativeEnd ?? nativeStart,
                    "nativeScopeDurationSeconds": (nativeEnd ?? nativeStart) - nativeStart,
                    "checkpoints": checkpoints, "trace": result]
        } catch {
            _ = try? await probe(page, operation: "cleanup", token: token, nextInput: -1)
            throw error
        }
    }

    private func requireForeground(_ fixture: NativeGameRuntimeFixture, browser: WebViewController) throws {
        guard browser.viewIfLoaded?.window === fixture.window, !fixture.window.isHidden,
              fixture.window.windowScene?.activationState == .foregroundActive else {
            throw failure("Frame collection requires the actual game container in a foreground scene")
        }
    }

    private func requireValidSnapshot(_ snapshot: [String: Any]) throws {
        guard snapshot["sameOriginalDocument"] as? Bool == true,
              snapshot["sameOriginalDocumentElement"] as? Bool == true,
              snapshot["markerMatches"] as? Bool == true,
              let state = snapshot["state"] as? [String: Any], state["path"] as? String == "/games/paper-star/local",
              state["visibilityState"] as? String == "visible", state["rendererReady"] as? Bool == true,
              state["phase"] as? String == "playing", state["arenaConnected"] as? Bool == true,
              try number(state, "canvasWidth") > 0, try number(state, "canvasHeight") > 0,
              try number(snapshot, "hiddenFrameCount") == 0, try number(snapshot, "notPlayingFrameCount") == 0,
              try number(snapshot, "hiddenVisibilityEventCount") == 0,
              try number(snapshot, "rendererMissingFrameCount") == 0, try number(snapshot, "invalidIntervalCount") == 0 else {
            throw failure("A foreground renderer and playing scene are required; hidden/throttled or invalid traces are not accepted")
        }
    }

    private func probe(_ page: WKWebView, operation: String, token: String, nextInput: Int) async throws -> [String: Any] {
        let value = try await NativeGameEntryProbe.evaluate(page, script: Self.script,
            arguments: ["operation": operation, "token": token, "nextInput": nextInput])
        return try XCTUnwrap(value as? [String: Any])
    }

    private func number(_ value: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(value[key] as? NSNumber, "Expected a real numeric counter: \(key)").doubleValue
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "NativeGameFrameProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func attach(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Frame evidence must remain JSON serializable"); return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private static let script = #"""
        const key = '__nativePaperStarFramePerformanceProbe';
        const existing = window[key];
        if (operation === 'cleanup') {
          if (existing?.token === token) { existing.stop('native-cleanup'); delete window[key]; }
          return {removed: !window[key]};
        }
        if (operation === 'install') {
          if (existing) throw Error('A prior frame probe has not been cleaned up');
          const arena = document.querySelector('[data-testid="paper-star-arena"]');
          if (!arena) throw Error('The real PaperStar arena is required');
          const numeric = name => {
            const value = arena.dataset[name];
            return value !== undefined && value !== '' && Number.isFinite(Number(value)) ? Number(value) : null;
          };
          const state = () => {
            const canvas = arena.querySelector('canvas');
            const rect = canvas?.getBoundingClientRect();
            return {path:location.pathname, visibilityState:document.visibilityState, hasFocus:document.hasFocus(),
              rendererReady:arena.dataset.rendererReady === 'true', phase:arena.dataset.phase,
              arenaConnected:arena.isConnected, canvasWidth:rect?.width ?? 0, canvasHeight:rect?.height ?? 0,
              tick:numeric('tick'), fireSequence:numeric('fireSequence'),
              playerAngle:numeric('playerAngle'), playerX:numeric('playerX')};
          };
          const dispatch = (type, code) => {
            const event = new KeyboardEvent(type, {code, key:code === 'Space' ? ' ' : code,
              bubbles:true, cancelable:true, repeat:false});
            window.dispatchEvent(event);
            return event.defaultPrevented;
          };
          const release = () => { for (const code of ['Space','ArrowLeft','ArrowRight']) dispatch('keyup', code); };
          const c = {token, originalDocument:document, originalDocumentElement:document.documentElement,
            start:performance.now(), end:null, firstRaf:null, lastRaf:null, running:true,
            frameCount:0, intervalCount:0, dropped:0, invalid:0, intervals:[],
            hidden:0, notPlaying:0, missingRenderer:0, visibilityEvents:[], visibilityEventCount:0, hiddenVisibilityEvents:0,
            stopReason:null, raf:0, watchdog:0, initialState:state()};
          c.snapshot = includeIntervals => {
            const result = {sameOriginalDocument:c.originalDocument === document,
              sameOriginalDocumentElement:c.originalDocumentElement === document.documentElement,
              markerMatches:window[key]?.token === token, state:state(), initialState:c.initialState,
              documentStartMilliseconds:c.start, documentEndMilliseconds:c.end ?? performance.now(),
              firstRafTimestampMilliseconds:c.firstRaf, lastRafTimestampMilliseconds:c.lastRaf,
              observedFrameCount:c.frameCount, observedIntervalCount:c.intervalCount,
              retainedIntervalCount:c.intervals.length, droppedIntervalCount:c.dropped,
              invalidIntervalCount:c.invalid, hiddenFrameCount:c.hidden,
              notPlayingFrameCount:c.notPlaying, rendererMissingFrameCount:c.missingRenderer,
              visibilityEventCount:c.visibilityEventCount, hiddenVisibilityEventCount:c.hiddenVisibilityEvents,
              visibilityEvents:c.visibilityEvents.slice(),
              running:c.running, stopReason:c.stopReason};
            if (includeIntervals) result.intervalsMilliseconds = c.intervals.slice();
            return result;
          };
          c.input = step => {
            release();
            if (step < 0) return true;
            const direction = step % 2 === 0 ? 'ArrowLeft' : 'ArrowRight';
            const directionAccepted = dispatch('keydown', direction);
            const fireAccepted = dispatch('keydown', 'Space');
            c.lastInput = {step, direction, fire:'Space', directionAccepted, fireAccepted};
            return directionAccepted && fireAccepted;
          };
          const visibility = () => {
            c.visibilityEventCount++;
            if (document.visibilityState !== 'visible') c.hiddenVisibilityEvents++;
            if (c.visibilityEvents.length < 16)
              c.visibilityEvents.push({atMilliseconds:performance.now(), state:document.visibilityState});
          };
          c.stop = reason => {
            if (c.running) {
              c.running = false; c.end = performance.now(); c.stopReason = reason;
              cancelAnimationFrame(c.raf); clearTimeout(c.watchdog);
              document.removeEventListener('visibilitychange', visibility);
            }
            release();
            return c.snapshot(true);
          };
          const frame = timestamp => {
            if (!c.running) return;
            c.frameCount++;
            if (c.firstRaf === null) c.firstRaf = timestamp;
            if (c.lastRaf !== null) {
              const interval = timestamp - c.lastRaf;
              if (Number.isFinite(interval) && interval >= 0) {
                c.intervalCount++;
                if (c.intervals.length < 1800) c.intervals.push(interval); else c.dropped++;
              } else c.invalid++;
            }
            c.lastRaf = timestamp;
            if (document.visibilityState !== 'visible') c.hidden++;
            if (!arena.isConnected || arena.dataset.phase !== 'playing') c.notPlaying++;
            if (arena.dataset.rendererReady !== 'true') c.missingRenderer++;
            c.raf = requestAnimationFrame(frame);
          };
          window[key] = c;
          document.addEventListener('visibilitychange', visibility);
          c.raf = requestAnimationFrame(frame);
          c.watchdog = setTimeout(() => c.stop('watchdog'), 15000);
          const inputAccepted = c.input(nextInput);
          return {snapshot:c.snapshot(false), inputAccepted, input:c.lastInput};
        }
        const c = window[key];
        if (!c || c.token !== token || c.originalDocument !== document
            || c.originalDocumentElement !== document.documentElement)
          throw Error('The original frame-probe document must still be active');
        if (operation === 'checkpoint') {
          if (!c.running) throw Error('The continuous collector stopped before its checkpoint');
          const snapshot = c.snapshot(false);
          const inputAccepted = c.input(nextInput);
          return {snapshot, inputAccepted, input:c.lastInput ?? null};
        }
        if (operation === 'stop') {
          const result = c.stop('native-completed');
          delete window[key];
          return result;
        }
        throw Error('Unsupported frame-probe operation');
        """#
}

@MainActor
private enum NativeGameEntryProbe {
    static func evaluate(_ page: WKWebView, script: String, arguments: [String: Any] = [:]) async throws -> Any {
        let result = NativeGameRuntimeCallback<Result<Any, Error>>()
        page.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result.value = $0 }
        let deadline = Date().addingTimeInterval(5)
        while result.value == nil && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        return try XCTUnwrap(result.value, "The real WebKit comparison probe did not return").get()
    }

    static let failureSnapshot = #"""
        const scrub = window.__nativeGameTestScrub || (value => String(value ?? '').replace(/[?#][^\s"'<>]*/g, '').slice(0, 300));
        return {
          href: location.origin + location.pathname,
          nativeGameState: document.documentElement.dataset.nativeGameState || null,
          loading: Array.from(document.querySelectorAll('.paper-star-loading, [role=alert]')).map(node => scrub(node.textContent)),
          errors: window.__nativeGameTestErrors || [],
          timing: window.__nativeGameReadyTimingSnapshot || null
        };
        """#
}

@MainActor
private final class NativeGameRuntimeProfileObservation {
    let identifier: UUID
    let label: String
    weak var browser: WebViewController?
    weak var page: WKWebView?
    weak var store: WKWebsiteDataStore?

    init(identifier: UUID, label: String, browser: WebViewController, page: WKWebView) {
        self.identifier = identifier
        self.label = label
        self.browser = browser
        self.page = page
        store = page.configuration.websiteDataStore
    }

    var snapshot: [String: Any] {
        ["identifier": identifier.uuidString, "label": label,
         "browserAlive": browser != nil, "webViewAlive": page != nil, "storeAlive": store != nil]
    }
}

@MainActor
private final class NativeGameRuntimeFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native-game-runtime-" + UUID().uuidString)
    let defaultsName = "native-game-runtime-" + UUID().uuidString
    let defaults: UserDefaults
    let profiles: WebProfileRepository
    let runtime: NativeWebRuntime
    let catalog: CatalogStore
    let library: HomeLibrary
    let games: [NativeGame]
    let root = NativeGameRuntimeHostController()
    let window: UIWindow
    let previous: UIWindow?
    private let animationsWereEnabled: Bool
    private var profileIDs = Set<UUID>()
    private var profileObservations: [NativeGameRuntimeProfileObservation] = []
    private var principalLabel = "guest"
    private var closed = false

    init(simulated: Bool, catalogApplications: [CloudApplication]? = nil, interactionDefaults: UserDefaults? = nil) async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "native-game-catalog-v1", withExtension: "json"))
        games = try NativeGameCatalog.decode(Data(contentsOf: url)).games
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        profiles = WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: "native-game-runtime-fixture")
        let cache = ApplicationCacheStore(repository: ApplicationCacheRepository(directory: directory.appendingPathComponent("archives")), defaults: defaults)
        runtime = NativeWebRuntime(applicationCache: cache, webProfiles: profiles, gameInteractionDefaults: interactionDefaults ?? defaults)
        catalog = CatalogStore(service: NativeGameRuntimeCatalog(items: catalogApplications), cacheURL: directory.appendingPathComponent("catalog.json"))
        library = HomeLibrary(directory: directory.appendingPathComponent("home"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        root.simulated = simulated
        window.rootViewController = root
        window.makeKeyAndVisible()
        runtime.anchor = root
        await catalog.load()
        runtime.updateGameCatalog(games)
        library.add(application("gomoku"))
        try await wait { !self.runtime.isIdentityCleanupPending }
    }

    func game(_ gameID: String) throws -> NativeGame { try XCTUnwrap(games.first { $0.gameId == gameID }) }
    func mode(_ modeID: String, gameID: String) throws -> NativeGameMode { try XCTUnwrap(game(gameID).mode(id: modeID)) }
    func application(_ id: String) -> CloudApplication { catalog.application(id: id) ?? NativeGameRuntimeCatalog.application(id) }
    func track(_ id: UUID) { profileIDs.insert(id) }
    func trackedProfiles() -> Set<UUID> { profileIDs }

    func profile(_ browser: WebViewController) throws -> UUID {
        guard #available(iOS 17, *) else { throw XCTSkip("Named WebKit profiles require iOS 17") }
        let page = try web(browser)
        let id = try XCTUnwrap(page.configuration.websiteDataStore.identifier)
        profileIDs.insert(id)
        if !profileObservations.contains(where: { $0.page === page }) {
            profileObservations.append(NativeGameRuntimeProfileObservation(identifier: id,
                label: principalLabel + "/" + (browser.appInfo?.id ?? "unknown"), browser: browser, page: page))
        }
        return id
    }

    func web(_ browser: WebViewController) throws -> WKWebView {
        try XCTUnwrap(browser.view.subviews.compactMap { $0 as? WKWebView }.first)
    }

    func open(_ game: NativeGame, mode: NativeGameMode) async throws -> WebViewController {
        runtime.openGame(game, mode: mode, catalog: catalog, library: library)
        return try await browser(applicationID: catalog.application(id: game.appId)?.id ?? game.appId)
    }

    func browser(applicationID: String) async throws -> WebViewController {
        do { try await wait {
            guard let navigation = self.root.presentedViewController as? UINavigationController,
                  let browser = navigation.topViewController as? WebViewController else { return false }
            return browser.appInfo?.id == applicationID && !browser.isPreparingInitialContent
                && !navigation.isBeingPresented && !navigation.isBeingDismissed && browser.viewIfLoaded?.window != nil
        } } catch {
            let presented = root.presentedViewController
            let navigation = presented as? UINavigationController
            let browser = navigation?.topViewController as? WebViewController
            var diagnostic: [String: Any] = ["expectedApplication": applicationID,
                "applications": runtime.applications.map(\.id), "issueTitle": runtime.issue?.title ?? "",
                "rootHasWindow": root.viewIfLoaded?.window != nil,
                "presentedType": presented.map { String(describing: type(of: $0)) } ?? "none",
                "actualApplication": browser?.appInfo?.id ?? "none",
                "preparingInitialContent": browser?.isPreparingInitialContent ?? false,
                "browserHasWindow": browser?.viewIfLoaded?.window != nil,
                "beingPresented": navigation?.isBeingPresented ?? false,
                "beingDismissed": navigation?.isBeingDismissed ?? false]
            if let browser, browser.isViewLoaded, let page = try? web(browser),
               let state = try? await NativeGameEntryProbe.evaluate(page, script: NativeGameEntryProbe.failureSnapshot) {
                diagnostic["page"] = state
            }
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
                XCTContext.runActivity(named: "Native fixture browser timeout") { activity in
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "native-runtime-browser-timeout.json"; attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
            }
            throw error
        }
        let navigation = try XCTUnwrap(root.presentedViewController as? UINavigationController)
        let browser = try XCTUnwrap(navigation.topViewController as? WebViewController)
        _ = try profile(browser)
        return browser
    }

    func message(_ status: NativeGameSessionStatus, state: String = "ready") -> [String: Any] {
        ["schemaVersion": 1, "launchId": status.launchID.uuidString, "gameId": status.gameID,
         "modeId": status.modeID, "state": state, "elapsedMilliseconds": 1]
    }

    func document(_ browser: WebViewController, origin: URL, messages: [[String: Any]] = []) async throws {
        let page = try web(browser)
        let signal = NativeGameRuntimeDocumentSignal()
        let name = "nativeGameRuntimeFixture"
        page.configuration.userContentController.add(signal, name: name)
        defer { page.configuration.userContentController.removeScriptMessageHandler(forName: name) }
        let data = try JSONSerialization.data(withJSONObject: messages)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        page.loadSimulatedRequest(URLRequest(url: origin), responseHTML: """
            <html><head><title>Native game runtime fixture</title></head><body>Runtime fixture
            <script>
            for (const message of \(encoded)) window.webkit.messageHandlers.ylfGameLifecycle.postMessage(message);
            window.addEventListener('load', () => window.webkit.messageHandlers.\(name).postMessage('\(signal.token)'), {once:true});
            </script></body></html>
            """)
        guard await XCTWaiter.fulfillment(of: [signal.ready], timeout: 30) == .completed else {
            throw URLError(.timedOut)
        }
        await Task.yield()
    }

    func endAll() async {
        for app in runtime.applications { runtime.end(app) }
        root.stopFixturePages()
        for _ in 0..<100 where root.presentedViewController != nil { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNil(root.presentedViewController, "Fixture dismissal must finish before website data store removal")
    }

    func resetIdentity(_ id: String) async {
        principalLabel = id
        runtime.resetIdentity(to: id)
        root.stopFixturePages()
        for _ in 0..<100 where runtime.isIdentityCleanupPending || root.presentedViewController != nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(runtime.isIdentityCleanupPending)
        XCTAssertNil(root.presentedViewController)
    }

    func wait(seconds: TimeInterval = 15, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "NativeGameRuntimeFixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The real native game runtime did not reach the expected state within \(seconds) seconds"])
    }

    func close() async {
        guard !closed else { return }
        closed = true
        let registry = (try? Data(contentsOf: directory.appendingPathComponent("profiles.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        var lifecycle: [[String: Any]] = []
        func observe(_ phase: String) {
            lifecycle.append(["phase": phase, "uptime": ProcessInfo.processInfo.systemUptime,
                              "pages": autoreleasepool { profileObservations.map(\.snapshot) }])
        }
        observe("before-terminal-stop")
        runtime.onGameReady = nil
        runtime.onGameRoomConfirmed = nil
        // Controllers may disappear during endAll(). Keep only weak page records
        // and stop/detach the fixture's pages before releasing their owners.
        autoreleasepool {
            for observation in profileObservations {
                observation.page?.stopLoading()
                observation.page?.resignFirstResponder()
                observation.page?.removeFromSuperview()
            }
        }
        await endAll()
        autoreleasepool {
            runtime.resetIdentity()
            root.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
            UIView.setAnimationsEnabled(animationsWereEnabled)
        }
        await Task.yield()
        observe("after-terminal-release")
        // Wait for a concrete owner-release condition, not a fixed cleanup delay.
        // A remaining store wrapper is diagnostic; identifier absence is checked
        // through WebKit after removal, even if that wrapper outlives its page.
        let releaseDeadline = Date().addingTimeInterval(5)
        while Date() < releaseDeadline {
            let hasPageOwner = autoreleasepool { profileObservations.contains { $0.browser != nil || $0.page != nil } }
            if !hasPageOwner { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        observe("before-store-removal")
        var cleanupFailed = false
        if #available(iOS 17, *), !profileIDs.isEmpty {
            do {
                // A manifest can fail before any game WebView exists. Initialize
                // WebKit before its identifier-removal API even on that path.
                let keeper = try await NativeGameRuntimeStoreCleanup.initializedKeeper()
                defer { keeper.stopLoading() }
                for id in profileIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                    do {
                        try await NativeGameRuntimeStoreCleanup.remove(id)
                        let remaining = try await NativeGameRuntimeStoreCleanup.identifiers()
                        guard !remaining.contains(id) else {
                            throw NSError(domain: "NativeGameFixtureCleanup", code: 3,
                                          userInfo: [NSLocalizedDescriptionKey: "Removed fixture profile is still enumerated by WebKit"])
                        }
                    }
                    catch {
                        cleanupFailed = true
                        XCTFail("Fixture WebKit profile cleanup failed: \(id): \(error); live fixture owners: \(root.liveFixturePageProfiles())")
                    }
                    observe("after-store-removal-" + id.uuidString)
                }
            } catch {
                cleanupFailed = true
                XCTFail("Could not initialize WebKit for fixture cleanup: \(error)")
            }
        }
        let report: [String: Any] = ["ownedProfiles": profileIDs.map(\.uuidString).sorted(),
            "profileRegistry": registry, "lifecycle": lifecycle, "cleanupFailed": cleanupFailed,
            "scope": "Weak observations of the fixture's actual pages and configured stores; no store is created for diagnostics"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            XCTContext.runActivity(named: "Fixture terminal lifecycle and store cleanup") { activity in
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-game-fixture-cleanup-lifetimes.json"; attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        if cleanupFailed {
            XCTContext.runActivity(named: "Preserved fixture cleanup ownership") { activity in
                let attachment = XCTAttachment(string: "directory=\(directory.path)\ndefaults=\(defaultsName)\nprofiles=\(profileIDs.map(\.uuidString).sorted().joined(separator: ","))")
                attachment.name = "native-game-fixture-cleanup-ownership"; attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        } else {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@available(iOS 17, *)
@MainActor
private enum NativeGameRuntimeStoreCleanup {
    private static var initializationKeeper: WKWebView?
    static func initializedKeeper() async throws -> WKWebView {
        if let initializationKeeper { return initializationKeeper }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let keeper = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        let signal = NativeGameRuntimeDocumentSignal()
        let name = "nativeGameCleanupKeeper"
        keeper.configuration.userContentController.add(signal, name: name)
        defer { keeper.configuration.userContentController.removeScriptMessageHandler(forName: name) }
        keeper.loadSimulatedRequest(URLRequest(url: URL(string: "https://native-game-cleanup.invalid/")!), responseHTML: """
            <html><head><title>Fixture cleanup keeper</title></head><body>
            <script>window.addEventListener('load', () => {
              window.webkit.messageHandlers.\(name).postMessage('\(signal.token)');
            }, {once:true});</script></body></html>
            """)
        guard await XCTWaiter.fulfillment(of: [signal.ready], timeout: 30) == .completed else {
            keeper.stopLoading()
            throw NSError(domain: "NativeGameFixtureCleanup", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The no-network WebKit cleanup keeper did not initialize"])
        }
        initializationKeeper = keeper
        return keeper
    }

    /// Waiting asynchronously lets UIKit autoreleases and the network process
    /// release their references. A missing API callback cannot stall XCTest.
    static func remove(_ identifier: UUID) async throws {
        var lastFailure: Error = URLError(.unknown)
        let deadline = Date().addingTimeInterval(30)
        for seconds in [0, 1, 2, 4, 8, 8] {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > Double(seconds) else { break }
            if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) }
            do {
                try await removeOnce(identifier, timeout: deadline.timeIntervalSinceNow)
                return
            } catch {
                lastFailure = error
                if (error as? URLError)?.code == .timedOut { throw error }
            }
        }
        throw lastFailure
    }

    static func identifiers() async throws -> Set<UUID> {
        let result = NativeGameRuntimeCallback<[UUID]>()
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in result.value = identifiers }
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let identifiers = result.value { return Set(identifiers) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }

    private static func removeOnce(_ identifier: UUID, timeout: TimeInterval) async throws {
        let result = NativeGameRuntimeCallback<Result<Void, Error>>()
        let started = ProcessInfo.processInfo.systemUptime
        WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
            result.value = error.map(Result.failure) ?? .success(())
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            print("NATIVE_GAME_STORE_REMOVAL id=\(identifier.uuidString) elapsed-ms=\(elapsed) success=\(error == nil)")
        }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline {
            if let completion = result.value { return try completion.get() }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }
}

@MainActor
private final class NativeGameRuntimeCallback<Value> {
    var value: Value?
}

private struct NativeGameLegacyEntry {
    let gameID: String
    let modeID: String
    let modePath: String

    func initialNavigation(_ launchURL: URL) throws -> (home: URL, script: String) {
        guard var components = URLComponents(url: launchURL, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.host == "127.0.0.1", components.port == 18146,
              components.user == nil, components.password == nil, components.fragment == nil,
              components.path == modePath,
              let items = components.queryItems, items.count == 3,
              Set(items.map(\.name)) == Set(["ylfLaunchId", "ylfGameId", "ylfMode"]),
              let launchID = items.first(where: { $0.name == "ylfLaunchId" })?.value,
              UUID(uuidString: launchID) != nil,
              items.first(where: { $0.name == "ylfGameId" })?.value == gameID,
              items.first(where: { $0.name == "ylfMode" })?.value == modeID else {
            throw NSError(domain: "NativeGameEntryComparison", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Legacy transport requires the exact runtime-bound preview launch"])
        }
        let configuration: [String: Any] = ["origin": "http://127.0.0.1:18146", "modePath": modePath,
                                          "query": ["ylfLaunchId": launchID, "ylfGameId": gameID, "ylfMode": modeID]]
        let data = try JSONSerialization.data(withJSONObject: configuration)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        components.path = "/"; components.queryItems = nil
        let home = try XCTUnwrap(components.url)
        let script = """
            (() => {
              const expected = \(encoded);
              const augment = input => {
                let target; try { target = new URL(String(input), location.href); } catch { return input; }
                if (target.origin !== expected.origin || target.pathname !== expected.modePath || target.hash || target.username || target.password) return input;
                if (Array.from(target.searchParams.keys()).some(key => !Object.hasOwn(expected.query, key))) return input;
                for (const [key, value] of Object.entries(expected.query)) target.searchParams.set(key, value);
                return target.href;
              };
              const push = history.pushState;
              const replace = history.replaceState;
              history.pushState = function(state, title, url) {
                return push.call(this, state, title, url == null ? url : augment(url));
              };
              history.replaceState = function(state, title, url) {
                return replace.call(this, state, title, url == null ? url : augment(url));
              };
              // A real full-document mode navigation needs the same bound intent
              // before Nuxt mounts. No context is installed on Home or detail.
              if (location.origin === expected.origin && location.pathname === expected.modePath) {
                replace.call(history, history.state, '', augment(location.href));
              }
            })();
            """
        return (home, script)
    }
}

@MainActor
private final class NativeGameRuntimeHostController: UIViewController {
    var simulated = true
    var legacyEntry: NativeGameLegacyEntry?
    var collectResourceTiming = false
    var startupPhaseObserver: ((String, TimeInterval) -> Void)?
    private let intercepted = NSHashTable<WebViewController>.weakObjects()
    private var startupDocumentProbes: [NativeGameStartupDocumentProbe] = []

    func clearStartupDocumentProbes() {
        for probe in startupDocumentProbes { probe.invalidate() }
        startupDocumentProbes.removeAll()
    }

    func stopFixturePages() {
        autoreleasepool {
            for browser in intercepted.allObjects {
                for page in browser.viewIfLoaded?.subviews.compactMap({ $0 as? WKWebView }) ?? [] {
                    page.stopLoading()
                }
            }
        }
        clearStartupDocumentProbes()
    }

    @available(iOS 17, *)
    func liveFixturePageProfiles() -> [String] {
        autoreleasepool {
            intercepted.allObjects.compactMap { browser in
                browser.viewIfLoaded?.subviews.compactMap { $0 as? WKWebView }.first?
                    .configuration.websiteDataStore.identifier?.uuidString
            }
        }
    }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // Capture the observer for this presentation, so a late callback cannot stamp a later sample.
        let observeStartup = startupPhaseObserver
        observeStartup?("present-entered", ProcessInfo.processInfo.systemUptime)
        if let navigation = viewControllerToPresent as? UINavigationController,
           let browser = navigation.viewControllers.first as? WebViewController, !intercepted.contains(browser) {
            XCTAssertFalse(browser.isViewLoaded, "Attach the fixture transport and diagnostics before the initial document")
            if simulated {
                browser.initialContentLoader = { _, _, prepared in prepared() }
            } else {
                let original = browser.initialContentLoader
                let legacy = legacyEntry
                let timing = collectResourceTiming
                browser.initialContentLoader = { [weak self] web, url, prepared in
                    observeStartup?("initial-loader-entered", ProcessInfo.processInfo.systemUptime)
                    web.configuration.userContentController.addUserScript(WKUserScript(
                        source: Self.errorCollector, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    if timing {
                        web.configuration.userContentController.addUserScript(WKUserScript(
                            source: Self.resourceTimingCollector, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    }
                    var initialURL = url
                    if let legacy {
                        do {
                            let navigation = try legacy.initialNavigation(url)
                            web.configuration.userContentController.addUserScript(WKUserScript(
                                source: navigation.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                            initialURL = navigation.home
                        } catch {
                            XCTFail("Invalid fixture-only legacy navigation: \(error)")
                            prepared()
                            return
                        }
                    }
                    if let observeStartup {
                        if let self {
                            self.startupDocumentProbes.append(NativeGameStartupDocumentProbe(
                                web: web, expectedURL: initialURL, observer: observeStartup))
                        }
                        let finishPreparation = {
                            observeStartup("initial-loader-prepared-after-load-call", ProcessInfo.processInfo.systemUptime)
                            prepared()
                        }
                        if let original { original(web, initialURL, finishPreparation) }
                        else { web.load(URLRequest(url: initialURL)); finishPreparation() }
                    } else if let original { original(web, initialURL, prepared) }
                    else { web.load(URLRequest(url: initialURL)); prepared() }
                }
            }
            intercepted.add(browser)
        }
        if let observeStartup {
            super.present(viewControllerToPresent, animated: flag) {
                observeStartup("present-completed", ProcessInfo.processInfo.systemUptime)
                completion?()
            }
        } else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }

    /// Freeze timing when the product emits its real engine-ready event, before
    /// its native message. This observer cannot send or manufacture lifecycle events.
    private static let resourceTimingCollector = #"""
        (() => {
          performance.setResourceTimingBufferSize(2048);
          const captureRendererReady = () => {
            if (window.__nativePaperStarRendererReadySnapshot) return;
            const arena = document.querySelector('[data-testid="paper-star-arena"]');
            if (arena?.dataset.rendererReady !== 'true') return;
            window.__nativePaperStarRendererReadySnapshot = {atMilliseconds: performance.now(), phase: arena.dataset.phase || null};
            rendererObserver.disconnect();
          };
          const rendererObserver = new MutationObserver(captureRendererReady);
          rendererObserver.observe(document, {subtree:true, attributes:true, attributeFilter:['data-renderer-ready']});
          document.addEventListener('DOMContentLoaded', captureRendererReady, {once:true});
          captureRendererReady();
          let overflow = 0;
          performance.addEventListener('resourcetimingbufferfull', () => { overflow++; });
          window.__nativeGameResourceTimingSnapshot = () => {
            const groups = new Map();
            const finite = value => Number.isFinite(value) ? value : 0;
            for (const entry of performance.getEntriesByType('resource')) {
              let origin; try { origin = new URL(entry.name).origin; } catch { origin = 'unparseable'; }
              const scope = origin === location.origin ? 'same-origin' : 'cross-origin';
              const initiator = /^[a-z-]{1,32}$/.test(entry.initiatorType) ? entry.initiatorType : 'other';
              const key = scope + ':' + initiator;
              const group = groups.get(key) || {scope, initiatorType: initiator, count: 0,
                transferSizeBytes: 0, encodedBodySizeBytes: 0, decodedBodySizeBytes: 0,
                resourceDurationSumMilliseconds: 0, resourceDurationMaxMilliseconds: 0,
                zeroTransferSizeCount: 0, transferSizeAvailableCount: 0};
              group.count++;
              group.transferSizeBytes += finite(entry.transferSize);
              group.encodedBodySizeBytes += finite(entry.encodedBodySize);
              group.decodedBodySizeBytes += finite(entry.decodedBodySize);
              group.resourceDurationSumMilliseconds += finite(entry.duration);
              group.resourceDurationMaxMilliseconds = Math.max(group.resourceDurationMaxMilliseconds, finite(entry.duration));
              if ('transferSize' in entry) group.transferSizeAvailableCount++;
              if (entry.transferSize === 0) group.zeroTransferSizeCount++;
              groups.set(key, group);
            }
            return {
              timeOrigin: performance.timeOrigin, snapshotAtMilliseconds: performance.now(),
              documentPath: location.pathname, mainDocumentOnly: true, overflowCount: overflow,
              resourceCount: performance.getEntriesByType('resource').length,
              resourceGroups: Array.from(groups.values()),
              navigation: performance.getEntriesByType('navigation').map(entry => ({
                type: entry.type, durationMilliseconds: finite(entry.duration),
                responseEndMilliseconds: finite(entry.responseEnd), domInteractiveMilliseconds: finite(entry.domInteractive),
                domContentLoadedEventEndMilliseconds: finite(entry.domContentLoadedEventEnd), loadEventEndMilliseconds: finite(entry.loadEventEnd),
                transferSizeBytes: finite(entry.transferSize), encodedBodySizeBytes: finite(entry.encodedBodySize), decodedBodySizeBytes: finite(entry.decodedBodySize)
              }))
            };
          };
          window.addEventListener('ylf:gameLifecycle', event => {
            if (event.detail?.state !== 'ready' || window.__nativeGameReadyTimingSnapshot) return;
            window.__nativeGameReadyTimingSnapshot = window.__nativeGameResourceTimingSnapshot();
          });
        })();
        """#

    /// Test-only, bounded diagnostics. No stack, storage, credentials, or URL
    /// query/fragment is copied into the timeout attachment.
    private static let errorCollector = #"""
        (() => {
          const scrub = value => String(value ?? '')
            .replace(/[?#][^\s"'<>]*/g, '')
            .replace(/\b(token|ticket|cookie|authorization|password|secret|session)\s*[:=]\s*[^\s,;]+/gi, '$1=[redacted]')
            .slice(0, 300);
          window.__nativeGameTestScrub = scrub;
          const errors = window.__nativeGameTestErrors = [];
          const add = record => { if (errors.length < 20) errors.push(record); };
          window.addEventListener('error', event => add({
            kind: 'error', message: scrub(event.message), source: scrub(event.filename),
            line: event.lineno || 0, column: event.colno || 0
          }));
          window.addEventListener('unhandledrejection', event => add({
            kind: 'unhandledrejection', message: scrub(event.reason instanceof Error ? event.reason.message : event.reason)
          }));
        })();
        """#
}

/// Test-only stage transport. It does not observe credentials, mutate the page,
/// replace a navigation delegate, or send any product lifecycle message.
@MainActor
private final class NativeGameStartupDocumentProbe: NSObject, WKScriptMessageHandler {
    private static let handlerName = "nativeGameStartupPhaseProbe"
    private static let contentWorldName = "native-game-startup-document-phase-probe"
    private static let world = WKContentWorld.world(name: contentWorldName)
    private static let stages = [
        "document-start": "document-start-received",
        "dom-content-loaded": "dom-content-loaded-received",
        "window-load": "window-load-received",
    ]
    private weak var web: WKWebView?
    private weak var controller: WKUserContentController?
    private var observer: ((String, TimeInterval) -> Void)?
    private let script: WKUserScript
    private let nonce: String
    private let expectedScheme: String
    private let expectedHost: String
    private let expectedPort: Int
    private let expectedPath: String
    private var active = true

    init(web: WKWebView, expectedURL: URL, observer: @escaping (String, TimeInterval) -> Void) {
        let nonce = UUID().uuidString
        self.nonce = nonce
        self.web = web
        self.controller = web.configuration.userContentController
        self.observer = observer
        expectedScheme = expectedURL.scheme ?? ""
        expectedHost = expectedURL.host?.lowercased() ?? ""
        expectedPort = expectedURL.port ?? (expectedURL.scheme == "https" ? 443 : 80)
        expectedPath = URLComponents(url: expectedURL, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        script = WKUserScript(source: """
            (() => {
              const nonce = '\(nonce)';
              const send = phase => {
                try {
                  window.webkit.messageHandlers.nativeGameStartupPhaseProbe.postMessage({schemaVersion:1, nonce, phase});
                } catch {}
              };
              send('document-start');
              if (document.readyState === 'loading')
                document.addEventListener('DOMContentLoaded', () => send('dom-content-loaded'), {once:true});
              else
                send('dom-content-loaded');
              if (document.readyState === 'complete')
                send('window-load');
              else
                window.addEventListener('load', () => send('window-load'), {once:true});
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world)
        super.init()
        web.configuration.userContentController.add(self, contentWorld: Self.world, name: Self.handlerName)
        web.configuration.userContentController.addUserScript(script)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard active, let web, message.webView === web,
              userContentController === controller, message.name == Self.handlerName,
              message.world.name == Self.contentWorldName, message.frameInfo.isMainFrame,
              origin.protocol == expectedScheme, origin.host.lowercased() == expectedHost,
              origin.port == expectedPort || (origin.port == 0 && expectedPort == (expectedScheme == "https" ? 443 : 80)),
              let request = message.frameInfo.request.url,
              let source = URLComponents(url: request, resolvingAgainstBaseURL: false),
              source.scheme == expectedScheme, source.host?.lowercased() == expectedHost,
              source.user == nil, source.password == nil,
              (source.port ?? (source.scheme == "https" ? 443 : 80)) == expectedPort,
              source.percentEncodedPath == expectedPath,
              let body = message.body as? [String: Any], Set(body.keys) == ["schemaVersion", "nonce", "phase"],
              body["schemaVersion"] as? Int == 1, body["nonce"] as? String == nonce,
              let phase = body["phase"] as? String, let observed = Self.stages[phase] else { return }
        observer?(observed, ProcessInfo.processInfo.systemUptime)
    }

    func invalidate() {
        guard active else { return }
        active = false
        observer = nil
        if let controller {
            controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.world)
            // Remove this unique-nonce script only; preserve product bridge and other fixture scripts.
            let others = controller.userScripts.filter { $0 !== script && $0.source != script.source }
            controller.removeAllUserScripts()
            for other in others { controller.addUserScript(other) }
            XCTAssertFalse(controller.userScripts.contains { $0 === script || $0.source == script.source },
                           "The test-only document probe script must be removed")
        }
        web = nil
        controller = nil
    }
}

private struct NativeGameRuntimeCatalog: CatalogServing {
    var items: [CloudApplication]? = nil
    static func application(_ id: String) -> CloudApplication {
        CloudApplication(id: id, name: "Runtime fixture \(id)",
                         websiteUrl: id == "play" ? "https://play.yunle.fun/" : "https://play.yunle.fun/games/\(id)",
                         accessMode: "public", audience: "public", isPublic: true)
    }
    func applications() async throws -> [CloudApplication] { items ?? ["play", "gomoku", "paper-star"].map(Self.application) }
}

@MainActor
private final class NativeGameRuntimeDocumentSignal: NSObject, WKScriptMessageHandler {
    let token = UUID().uuidString
    let ready = XCTestExpectation(description: "The simulated game document delivered its real WebKit messages")
    private var received = false
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !received, message.frameInfo.isMainFrame, message.body as? String == token else { return }
        received = true
        ready.fulfill()
    }
}

/// Opt-in actual WebKit viewport acceptance for the native landscape container.
/// Layout evidence is collected only after the game's genuine engine-ready event.
@MainActor
final class NativeGameLayoutLiveTests: XCTestCase {
    func testPaperStarControlsAndSceneFitNativeShortLandscape() async throws {
        guard #available(iOS 17, *), NativeGameHostEnvironment.previewOrigin != nil,
              ProcessInfo.processInfo.environment["YUNLEFUN_PLAY_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_LAYOUT"] == "1" else {
            throw XCTSkip("Actual game layout acceptance requires the fixed preview and explicit layout opt-in")
        }
        let requested = ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAME_LAYOUT_MODES"]
        let modes = requested?.split(separator: ",").map(String.init) ?? ["tutorial", "local", "pve"]
        guard !modes.isEmpty, Set(modes).count == modes.count,
              Set(modes).isSubset(of: Set(["tutorial", "local", "pve"])) else {
            throw NSError(domain: "NativeGameLayout", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Layout modes must be a unique subset of tutorial,local,pve"])
        }
        let fixture = try await NativeGameRuntimeFixture(simulated: false)
        addTeardownBlock { await fixture.close() }
        var reports: [[String: Any]] = []
        defer {
            attach(["kind": "native-webkit-layout", "modes": modes, "observations": reports,
                    "scope": "Actual native runtime and WebKit; engine-ready, DOM geometry, hit testing and screenshots; no production identity"],
                   name: "native-paper-star-layout.json")
        }
        for modeID in modes {
            let report = try await observe(fixture, modeID: modeID)
            reports.append(report)
            let viewport = try XCTUnwrap(report["viewport"] as? [String: Any])
            XCTAssertTrue(viewport["landscape"] as? Bool == true, modeID)
            XCTAssertTrue(viewport["coarsePointer"] as? Bool == true, "Must exercise real touch-device media queries")
            XCTAssertLessThanOrEqual(number(viewport, "height"), 600, modeID)
            let canvas = try XCTUnwrap(report["canvas"] as? [String: Any])
            XCTAssertTrue(canvas["inViewport"] as? Bool == true, "The actual rendered scene must fit: \(modeID)")
            XCTAssertGreaterThanOrEqual(number(canvas, "height"), 140, "A thin visible strip is not a playable scene")
            XCTAssertGreaterThanOrEqual(number(canvas, "width"), 300)
            let controls = try XCTUnwrap(report["controls"] as? [[String: Any]])
            let safe = try XCTUnwrap(report["nativeSafeArea"] as? [String: Any])
            XCTAssertEqual(controls.count, 5, "Keep steering, boost, ability and fire available")
            for control in controls {
                let label = control["label"] as? String ?? "unknown"
                XCTAssertTrue(control["inViewport"] as? Bool == true, "Off-screen touch control: \(modeID) / \(label)")
                XCTAssertTrue(control["exposedAtCenter"] as? Bool == true, "Occluded touch control: \(modeID) / \(label)")
                XCTAssertGreaterThanOrEqual(number(control, "width"), 43.5, label)
                XCTAssertGreaterThanOrEqual(number(control, "height"), 43.5, label)
                assertSafeArea(control, viewport: viewport, safe: safe, label: label)
            }
            let menu = try XCTUnwrap(report["menu"] as? [String: Any])
            XCTAssertTrue(menu["inViewport"] as? Bool == true && menu["exposedAtCenter"] as? Bool == true)
            XCTAssertGreaterThanOrEqual(number(menu, "width"), 43.5)
            XCTAssertGreaterThanOrEqual(number(menu, "height"), 43.5)
            assertSafeArea(menu, viewport: viewport, safe: safe, label: "game menu")
            if modeID == "tutorial" {
                let coach = try XCTUnwrap(report["coach"] as? [String: Any])
                XCTAssertTrue(coach["targetVisible"] as? Bool == true, "Keep the current tutorial objective readable")
                XCTAssertTrue(coach["skipVisible"] as? Bool == true, "Tutorial skip must remain reachable")
                XCTAssertTrue(coach["guideVisible"] as? Bool == true, "Detailed guidance must remain reachable")
                let interaction = try XCTUnwrap(report["coachInteraction"] as? [String: Any])
                XCTAssertTrue(interaction["opened"] as? Bool == true)
                XCTAssertTrue(interaction["controlsPaused"] as? Bool == true, "Opening detailed guidance must stop game input")
                XCTAssertTrue(interaction["closeFocused"] as? Bool == true)
                XCTAssertTrue(interaction["closed"] as? Bool == true && interaction["focusReturned"] as? Bool == true)
                XCTAssertTrue(interaction["steeringRestored"] as? Bool == true)
            }
            await fixture.endAll()
        }
    }

    @available(iOS 17, *)
    private func observe(_ fixture: NativeGameRuntimeFixture, modeID: String) async throws -> [String: Any] {
        var ready = false
        fixture.runtime.onGameReady = { game, mode, _ in if game == "paper-star", mode == modeID { ready = true } }
        defer { fixture.runtime.onGameReady = nil }
        let browser = try await fixture.open(try fixture.game("paper-star"), mode: try fixture.mode(modeID, gameID: "paper-star"))
        let page = try fixture.web(browser)
        do {
            try await fixture.wait(seconds: 90) { ready }
            // The real ready frame and the native orientation transition must both settle.
            try await fixture.wait(seconds: 5) {
                let value = try? await NativeGameEntryProbe.evaluate(page, script: "return innerWidth > innerHeight;")
                return value as? Bool == true
            }
            let observation = try await NativeGameEntryProbe.evaluate(page, script: Self.geometryScript)
            var report = try XCTUnwrap(observation as? [String: Any])
            report["mode"] = modeID
            report["nativeSafeArea"] = ["top": Double(page.safeAreaInsets.top), "bottom": Double(page.safeAreaInsets.bottom),
                                         "left": Double(page.safeAreaInsets.left), "right": Double(page.safeAreaInsets.right)]
            let image = UIGraphicsImageRenderer(bounds: browser.view.bounds).image { _ in
                browser.view.drawHierarchy(in: browser.view.bounds, afterScreenUpdates: true)
            }
            let screenshot = XCTAttachment(image: image)
            screenshot.name = "native-paper-star-\(modeID)-viewport"; screenshot.lifetime = .keepAlways; add(screenshot)
            if modeID == "tutorial" {
                report["coachInteraction"] = try await NativeGameEntryProbe.evaluate(page, script: Self.coachInteractionScript)
            }
            return report
        } catch {
            let state = try? await NativeGameEntryProbe.evaluate(page, script: NativeGameEntryProbe.failureSnapshot)
            attach(["mode": modeID, "error": error.localizedDescription, "page": state ?? NSNull()], name: "native-layout-failure-\(modeID).json")
            throw error
        }
    }

    private func number(_ object: [String: Any], _ key: String) -> Double {
        (object[key] as? NSNumber)?.doubleValue ?? -1
    }

    private func assertSafeArea(_ rect: [String: Any], viewport: [String: Any], safe: [String: Any], label: String) {
        XCTAssertGreaterThanOrEqual(number(rect, "left"), number(safe, "left") - 1, label)
        XCTAssertLessThanOrEqual(number(rect, "right"), number(viewport, "width") - number(safe, "right") + 1, label)
        XCTAssertLessThanOrEqual(number(rect, "bottom"), number(viewport, "height") - number(safe, "bottom") + 1, label)
    }

    private func attach(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Layout evidence must remain JSON serializable"); return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private static let geometryScript = #"""
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const measure = element => {
          if (!element) return null;
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          const inViewport = style.display !== 'none' && style.visibility !== 'hidden'
            && rect.width > 0 && rect.height > 0 && rect.left >= -1 && rect.top >= -1
            && rect.right <= innerWidth + 1 && rect.bottom <= innerHeight + 1;
          const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
          return { left: rect.left, top: rect.top, width: rect.width, height: rect.height, right: rect.right, bottom: rect.bottom,
            inViewport, exposedAtCenter: !!hit && (hit === element || element.contains(hit)), disabled: !!element.disabled,
            label: element.getAttribute('aria-label') || (element.textContent || '').trim().slice(0, 60) };
        };
        const target = document.querySelector('.paper-star-coach h1');
        const skip = document.querySelector('[aria-label="跳过此步"]');
        const guide = document.querySelector('[aria-label="查看教程指引"]');
        const visible = element => { const value = measure(element); return !!value?.inViewport && value.exposedAtCenter; };
        const envProbe = document.createElement('div');
        envProbe.style.cssText = 'position:fixed;pointer-events:none;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
        document.body.append(envProbe);
        const envStyle = getComputedStyle(envProbe);
        const cssSafeArea = { top: envStyle.paddingTop, right: envStyle.paddingRight, bottom: envStyle.paddingBottom, left: envStyle.paddingLeft };
        envProbe.remove();
        const padding = selector => { const element = document.querySelector(selector); if (!element) return null;
          const style = getComputedStyle(element); return { left: style.paddingLeft, right: style.paddingRight, bottom: style.paddingBottom }; };
        return {
          href: location.origin + location.pathname,
          state: document.documentElement.dataset.nativeGameState || null,
          viewport: { width: innerWidth, height: innerHeight, landscape: innerWidth > innerHeight,
            coarsePointer: matchMedia('(pointer: coarse)').matches, pixelRatio: devicePixelRatio },
          canvas: measure(document.querySelector('.paper-star-canvas canvas')),
          controls: Array.from(document.querySelectorAll('.paper-star-touch button')).map(measure),
          menu: measure(document.querySelector('[aria-label="打开游戏菜单"]')),
          cssSafeArea, touchPadding: padding('.paper-star-touch'), hudPadding: padding('.paper-star-hud'),
          coach: { targetVisible: visible(target), skipVisible: visible(skip), guideVisible: visible(guide),
            target: target?.textContent?.trim() || null },
          documentSize: { width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight }
        };
        """#

    private static let coachInteractionScript = #"""
        const guide = document.querySelector('[aria-label="查看教程指引"]');
        if (!guide) return { opened: false, reason: 'Guide control missing' };
        const frame = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        guide.click(); await frame();
        const region = document.querySelector('[aria-label="教程指引"]');
        const close = document.querySelector('[aria-label="关闭教程指引"]');
        const controls = Array.from(document.querySelectorAll('.paper-star-touch button'));
        const opened = !!region && guide.getAttribute('aria-expanded') === 'true';
        const controlsPaused = controls.length === 5 && controls.every(button => button.disabled);
        const closeFocused = !!close && document.activeElement === close;
        close?.click(); await frame();
        return { opened, controlsPaused, closeFocused,
          closed: !document.querySelector('[aria-label="教程指引"]') && guide.getAttribute('aria-expanded') === 'false',
          focusReturned: document.activeElement === guide,
          steeringRestored: Array.from(document.querySelectorAll('.paper-star-touch__steer button')).every(button => !button.disabled)
        };
        """#
}
