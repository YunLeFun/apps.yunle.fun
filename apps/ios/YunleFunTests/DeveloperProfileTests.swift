import XCTest
@testable import YunleFun

final class DeveloperProfileServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }

    func testReadsThePersonalEndpointWithoutIdentityAndKeepsCurrentUnlistedPublications() async throws {
        let (service, fixture) = service([(200, try envelope(items: [object(id: "unlisted", name: "作者当前版本")]))])
        let profile = try await service.profile(login: "  YunYouJun  ")
        XCTAssertEqual(profile.ownerLogin, "YunYouJun")
        XCTAssertEqual(profile.items.map(\.id), ["unlisted"])
        XCTAssertEqual(profile.items.first?.name, "作者当前版本")
        XCTAssertEqual(profile.items.first?.personalMarketOwnerLogin, "YunYouJun")
        XCTAssertEqual(profile.displayName, "云游君")
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/api/markets/personal/YunYouJun")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSameUIDCanHaveAnEmptyOrHistoricalPerApplicationLogin() async throws {
        var alias = object(id: "old-alias"); alias["ownerLogin"] = "historical-alias"
        var missing = object(id: "no-login"); missing.removeValue(forKey: "ownerLogin")
        let (service, _) = service([(200, try envelope(login: "YUNYOUJUN", items: [alias, missing]))])
        let profile = try await service.profile(login: "YunYouJun")
        XCTAssertEqual(profile.items.count, 2)
        XCTAssertEqual(profile.items.map(\.personalMarketOwnerLogin), ["YUNYOUJUN", "YUNYOUJUN"])
    }

    func testOnlyAnExplicitValidEmptyProfileBecomesAnEmptySuccess() async throws {
        let (service, _) = service([(200, try envelope(items: [])), (200, "{}"), (200, #"{"ownerLogin":"YunYouJun"}"#),
                                    (200, #"{"items":[]}"#), (200, #"{"ownerLogin":"Other","items":[]}"#), (200, "<html>fallback</html>")])
        let empty = try await service.profile(login: "YunYouJun")
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(empty.displayName, "YunYouJun")
        for _ in 0..<5 { await expectFailure(.invalidResponse) { _ = try await service.profile(login: "YunYouJun") } }
    }

    func testPrivateScopedDuplicateAndForgedProvenanceRecordsAreRejected() async throws {
        var invalid: [[String: Any]] = []
        for (field, value) in [("audience", "owner"), ("audience", "workshop"), ("accessOwnerID", "owner"),
                                ("accessWorkshopID", "ABC234"), ("personalMarketOwnerLogin", "Other")] {
            var app = object(); app[field] = value; invalid.append(app)
        }
        var notPublic = object(); notPublic["isPublic"] = false; invalid.append(notPublic)
        var missingPublic = object(); missingPublic.removeValue(forKey: "isPublic"); invalid.append(missingPublic)
        var invalidID = object(); invalidID["_id"] = "../other"; invalid.append(invalidID)
        var invalidPrice = object(); invalidPrice["coinCost"] = -1; invalid.append(invalidPrice)
        let replies = try invalid.map { (200, try envelope(items: [$0])) } + [(200, try envelope(items: [object(), object()]))]
        let (service, _) = service(replies)
        for _ in replies { await expectFailure(.invalidResponse) { _ = try await service.profile(login: "YunYouJun") } }
    }

    func testRestrictedPublicRecordsRemainVisibleWithoutBecomingGuestPermissions() async throws {
        var paid = object(id: "paid"); paid["coinCost"] = 5
        var member = object(id: "member"); member["requiresMembership"] = true
        var invited = object(id: "invited"); invited["accessMode"] = "invite_only"
        var future = object(id: "future"); future["accessMode"] = "future_access_mode"
        let (service, _) = service([(200, try envelope(items: [paid, member, invited, future]))])
        let profile = try await service.profile(login: "YunYouJun")
        XCTAssertEqual(profile.items.count, 4)
        XCTAssertTrue(profile.items.allSatisfy { !$0.canOpenAsGuest })
    }

    func testFailuresAndHTMLMIMEAreNotEmptyProfiles() async throws {
        let (service, _) = service([(404, "{}"), (429, "{}"), (503, "{}"), (302, "{}")])
        for expected in [DeveloperProfileError.notFound, .throttled, .unavailable, .unavailable] {
            await expectFailure(expected) { _ = try await service.profile(login: "YunYouJun") }
        }
        let (html, _) = self.service([(200, try envelope(items: []))], contentType: "text/html")
        await expectFailure(.invalidResponse) { _ = try await html.profile(login: "YunYouJun") }
    }

    func testMalformedLoginNeverBecomesARequest() async {
        let (service, fixture) = service([])
        for login in ["", ".", "..", "a/b", "a?token=value", "a#fragment", "a%2Fb", "a b", String(repeating: "a", count: 65)] {
            await expectFailure(.invalidLogin) { _ = try await service.profile(login: login) }
        }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testDefaultPublicTransportDoesNotCarryHostIdentityOrPersistentCaches() {
        let service = DeveloperProfileService(), config = service.session.configuration
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
        XCTAssertNil(config.httpCookieStorage); XCTAssertNil(config.urlCredentialStorage); XCTAssertNil(config.urlCache)
        XCTAssertNotNil(service.session.delegate)
    }

    private func service(_ replies: [(Int, String)], contentType: String = "application/json") -> (DeveloperProfileService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies, contentType: contentType); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (DeveloperProfileService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
    private func object(id: String = "current", name: String = "作者作品") -> [String: Any] {
        ["_id": id, "name": name, "ownerLogin": "YunYouJun", "developerName": "云游君", "websiteUrl": "https://example.invalid/current",
         "audience": "public", "isPublic": true, "accessMode": "public"]
    }
    private func envelope(login: String = "YunYouJun", items: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["ownerLogin": login, "items": items]), as: UTF8.self)
    }
    private func expectFailure(_ expected: DeveloperProfileError, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? DeveloperProfileError, expected) }
    }
}

@MainActor
final class DeveloperProfileStoreTests: XCTestCase {
    func testRefreshPreservesSameAuthorContentButReportsFailureAndSupportsRetry() async throws {
        let service = DeveloperProfileFixture(replies: [.success(profile()), .failure(.unavailable), .success(profile(name: "更新版本"))])
        let store = DeveloperProfileStore(service: service)
        await store.refresh(login: "Author")
        XCTAssertEqual(store.profile?.items.first?.name, "当前版本")
        await store.refresh(login: "Author")
        XCTAssertEqual(store.profile?.items.first?.name, "当前版本")
        XCTAssertNotNil(store.error)
        await store.refresh(login: "Author")
        XCTAssertNil(store.error); XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.profile?.items.first?.name, "更新版本")
    }

    func testLateLoadForPreviousAuthorCannotReplaceTheNewAuthor() async {
        let gate = DeveloperProfileGate()
        let service = DeveloperProfileFixture(replies: [.success(profile()), .success(profile(login: "Other"))], gate: gate)
        let store = DeveloperProfileStore(service: service)
        let old = Task { await store.refresh(login: "Author") }
        await fulfillment(of: [gate.entered], timeout: 3)
        await store.refresh(login: "Other")
        XCTAssertEqual(store.profile?.ownerLogin, "Other")
        await gate.open(); await old.value
        XCTAssertEqual(store.profile?.ownerLogin, "Other"); XCTAssertNil(store.error); XCTAssertFalse(store.isLoading)
    }

    func testLeavingThePageRejectsLateSuccessAndCancellationDoesNotDisplayAnError() async {
        let gate = DeveloperProfileGate(), store = DeveloperProfileStore(service: DeveloperProfileFixture(replies: [.success(profile())], gate: gate))
        let old = Task { await store.refresh(login: "Author") }
        await fulfillment(of: [gate.entered], timeout: 3)
        old.cancel(); store.cancel()
        await gate.open(); await old.value
        XCTAssertNil(store.profile); XCTAssertNil(store.error); XCTAssertFalse(store.isLoading)
    }

    func testChangingAuthorClearsPreviouslyLoadedContentEvenWhenTheNewLoadFails() async {
        let store = DeveloperProfileStore(service: DeveloperProfileFixture(replies: [.success(profile()), .failure(.notFound)]))
        await store.refresh(login: "Author")
        await store.refresh(login: "Other")
        XCTAssertNil(store.profile); XCTAssertNotNil(store.error)
    }

    func testAnInvalidLoginClearsPreviousStateWithoutAnotherServiceRequest() async {
        let service = DeveloperProfileFixture(replies: [.success(profile())]), store = DeveloperProfileStore(service: service)
        await store.refresh(login: "Author"); await store.refresh(login: "../Other")
        XCTAssertNil(store.profile); XCTAssertFalse(store.isLoading); XCTAssertNotNil(store.error)
        let calls = await service.logins
        XCTAssertEqual(calls, ["Author"])
    }

    private func profile(login: String = "Author", name: String = "当前版本") -> DeveloperProfile {
        DeveloperProfile(ownerLogin: login, items: [CloudApplication(id: "current", name: name, audience: "public", isPublic: true, personalMarketOwnerLogin: login)])
    }
}

final class PersonalMarketVersionTests: XCTestCase {
    func testCurrentMetadataAndWebsiteSurviveMarketRefreshWhileOtherMarketEntriesStillRefresh() throws {
        let current = personalApp()
        let market = CloudApplication(id: current.id, name: "获批旧版", slug: "ai-sfc", websiteUrl: "https://old.invalid", accessMode: "public")
        XCTAssertEqual(current.refreshingPublicMetadata(with: market), current)
        XCTAssertEqual(current.launchURL?.absoluteString, "https://new.invalid/current")
        XCTAssertEqual(market.launchURL?.absoluteString, "https://ai-sfc.yunle.fun/")
        XCTAssertEqual(CloudApplication(id: current.id, name: "旧缓存").refreshingPublicMetadata(with: market), market)
        XCTAssertNotEqual(current.runtimeScope, market.runtimeScope, "The runtime must replace an existing market session when the personal source is opened")
    }

    func testPersonalRevisionCannotExtendBridgeHostsAndSharesAnAuthorRouteRatherThanTheMarketVersion() throws {
        var current = personalApp(); current.trustedHosts = ["new.invalid"]
        XCTAssertTrue(current.runtimeTrustedHosts.isEmpty)
        var market = current; market.personalMarketOwnerLogin = nil
        XCTAssertEqual(market.runtimeTrustedHosts, ["new.invalid"])
        XCTAssertEqual(current.shareURL.absoluteString, "https://apps.yunle.fun/developer/Author")
        XCTAssertEqual(NativeLink.destination(current.shareURL), .developer("Author"))
        XCTAssertEqual(market.shareURL.absoluteString, "https://apps.yunle.fun/app/current")
    }

    func testReturningToARunningApplicationRequiresBothTheSameIDAndPublicationSource() {
        let personal = personalApp(), market = CloudApplication(id: personalApp().id, name: "市场版本", websiteUrl: "https://market.invalid/")
        let marketMenu = RuntimeMenuContext(applicationID: market.id, launchURL: market.launchURL, dismiss: {})
        XCTAssertTrue(marketMenu.represents(market))
        XCTAssertFalse(marketMenu.represents(personal), "The author detail must not return to a different market revision just because the app ID matches")
        let authorMenu = RuntimeMenuContext(applicationID: personal.id, runtimeScope: personal.runtimeScope, launchURL: personal.launchURL, dismiss: {})
        XCTAssertTrue(authorMenu.represents(personal)); XCTAssertFalse(authorMenu.represents(market))
        var updated = personal; updated.websiteUrl = "https://new.invalid/another-version"
        XCTAssertFalse(authorMenu.represents(updated), "A newer author publication URL cannot return to the previous website session")
        XCTAssertFalse(RuntimeMenuContext(applicationID: personal.id, runtimeScope: personal.runtimeScope, launchURL: nil, dismiss: {}).represents(personal),
                       "A missing represented URL must not act as a wildcard")
        XCTAssertFalse(authorMenu.represents(CloudApplication(id: "another", name: "其他作品", personalMarketOwnerLogin: "Author")))
    }

    func testAuthorLinksUseTheSameStrictOriginAndSingleSegmentRulesAsOtherNativeRoutes() {
        XCTAssertEqual(NativeLink.destination(URL(string: "yunlefun://developer/Author.Name-1")!), .developer("Author.Name-1"))
        for value in ["http://apps.yunle.fun/developer/Author", "https://apps.yunle.fun.evil.invalid/developer/Author",
                      "https://apps.yunle.fun:444/developer/Author", "https://user:password@apps.yunle.fun/developer/Author",
                      "https://apps.yunle.fun/developer/Author?token=secret", "https://apps.yunle.fun/developer/Author#secret",
                      "https://apps.yunle.fun/developer/Author/other", "https://apps.yunle.fun/developer/%2E%2E",
                      "https://apps.yunle.fun/developer/Author%2Fother", "https://apps.yunle.fun/developer/Author%20Name"] {
            XCTAssertNil(NativeLink.destination(URL(string: value)!), value)
        }
    }

    func testLaunchRevalidatesTheCurrentPublicRevisionInsteadOfTrustingTheCachedURL() async throws {
        var fresh = personalApp(); fresh.websiteUrl = "https://fresh.invalid/now"
        let service = DeveloperProfileFixture(replies: [.success(DeveloperProfile(ownerLogin: "Author", items: [fresh]))])
        let resolved = try await PersonalMarketLaunchAuthorization(service: service).resolve(personalApp())
        XCTAssertEqual(resolved.launchURL?.absoluteString, "https://fresh.invalid/now")
        let calls = await service.logins
        XCTAssertEqual(calls, ["Author"])
    }

    func testCachedProvenanceCannotAuthorizeWithdrawnOrNewlyRestrictedPublications() async throws {
        var variants = [CloudApplication]()
        var paid = personalApp(); paid.coinCost = 1; variants.append(paid)
        var member = personalApp(); member.requiresMembership = true; variants.append(member)
        var login = personalApp(); login.accessMode = "login_required"; variants.append(login)
        var invited = personalApp(); invited.accessMode = "invite_only"; variants.append(invited)
        var privateApp = personalApp(); privateApp.audience = "owner"; variants.append(privateApp)
        for app in variants {
            let service = DeveloperProfileFixture(replies: [.success(DeveloperProfile(ownerLogin: "Author", items: [app]))])
            do { _ = try await PersonalMarketLaunchAuthorization(service: service).resolve(personalApp()); XCTFail() }
            catch { XCTAssertEqual(error as? DeveloperProfileError, .restricted) }
        }
        let missing = DeveloperProfileFixture(replies: [.success(DeveloperProfile(ownerLogin: "Author", items: []))])
        do { _ = try await PersonalMarketLaunchAuthorization(service: missing).resolve(personalApp()); XCTFail() }
        catch { XCTAssertEqual(error as? DeveloperProfileError, .notFound) }
    }

    func testMarketAcquisitionReceiptCannotBeReusedAsAnAuthorRevisionGrant() {
        let quote = ApplicationAcquisitionQuote(userId: "member", application: personalApp(), state: .allowed, reason: "free", coinCost: 0, balance: 0)
        XCTAssertThrowsError(try quote.validate(appID: "current", uid: "member"))
    }

    @MainActor func testSavedAuthorMetadataSurvivesRestartAndMarketCatalogUpdatesWithoutChangingTheSyncID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory), current = personalApp()
        library.add(current)
        library.updateCatalog([CloudApplication(id: current.id, name: "市场旧版", websiteUrl: "https://old.invalid")])
        let restored = HomeLibrary(directory: directory)
        XCTAssertEqual(restored.snapshot.applications.first?.name, current.name)
        XCTAssertEqual(restored.snapshot.applications.first?.personalMarketOwnerLogin, "Author")
        XCTAssertEqual(restored.snapshot.configuration.installedApps.map(\.appId), [current.id], "Local provenance must not invent a new cloud home identifier")
    }

    @MainActor func testSuccessfulMarketUseReplacesSavedAuthorSourceAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory), personal = personalApp()
        let market = CloudApplication(id: personal.id, name: "用户选择的市场版本", websiteUrl: "https://market.invalid/approved",
                                      accessMode: "public", audience: "public", isPublic: true)
        library.add(personal)
        library.setPinned(personal, true)
        library.recordUse(market)

        let restored = HomeLibrary(directory: directory)
        XCTAssertNil(restored.storageError)
        for saved in restored.snapshot.applications + restored.snapshot.dockApplications + restored.snapshot.recentApplications {
            XCTAssertEqual(saved.name, market.name)
            XCTAssertNil(saved.personalMarketOwnerLogin)
            XCTAssertEqual(saved.runtimeScope, "public")
            XCTAssertEqual(saved.launchURL, market.launchURL)
        }
        XCTAssertEqual(restored.snapshot.configuration.installedApps.map(\.appId), [personal.id])
        XCTAssertEqual(restored.snapshot.configuration.dockApps.map(\.appId), [personal.id])
        XCTAssertEqual(restored.snapshot.recentIDs, [personal.id])
    }

    @MainActor func testSuccessfulAuthorUseSelectsItsSourceAndPassiveCatalogRefreshCannotUndoIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory), personal = personalApp()
        let market = CloudApplication(id: personal.id, name: "市场版本", websiteUrl: "https://market.invalid/approved")
        let other = CloudApplication(id: "other", name: "其他市场版本", websiteUrl: "https://other.invalid/old")
        library.add(market)
        library.add(other)
        library.recordUse(personal)
        var updatedMarket = market; updatedMarket.name = "被动更新的市场资料"
        var updatedOther = other; updatedOther.name = "其他市场新资料"; updatedOther.websiteUrl = "https://other.invalid/new"
        library.updateCatalog([updatedMarket, updatedOther])

        let restored = HomeLibrary(directory: directory)
        XCTAssertNil(restored.storageError)
        let saved = try XCTUnwrap(restored.snapshot.applications.first { $0.id == personal.id })
        XCTAssertEqual(saved.name, personal.name)
        XCTAssertEqual(saved.personalMarketOwnerLogin, "Author")
        XCTAssertEqual(saved.launchURL, personal.launchURL)
        XCTAssertEqual(restored.snapshot.recentApplications.first?.runtimeScope, personal.runtimeScope)
        XCTAssertEqual(restored.snapshot.applications.first { $0.id == other.id }?.name, updatedOther.name)
        XCTAssertEqual(restored.snapshot.applications.first { $0.id == other.id }?.launchURL, updatedOther.launchURL)
        XCTAssertEqual(restored.snapshot.configuration.installedApps.map(\.appId), [personal.id, other.id])
    }

    private func personalApp() -> CloudApplication {
        CloudApplication(id: "current", name: "作者当前版本", slug: "ai-sfc", websiteUrl: "https://new.invalid/current", accessMode: "public",
                         audience: "public", isPublic: true, personalMarketOwnerLogin: "Author")
    }
}

private actor DeveloperProfileFixture: DeveloperProfileServing {
    private var replies: [Result<DeveloperProfile, DeveloperProfileError>]
    private let gate: DeveloperProfileGate?
    private(set) var logins: [String] = []
    init(replies: [Result<DeveloperProfile, DeveloperProfileError>], gate: DeveloperProfileGate? = nil) { self.replies = replies; self.gate = gate }
    func profile(login: String) async throws -> DeveloperProfile {
        logins.append(login)
        let reply = replies.removeFirst(), shouldWait = logins.count == 1
        if shouldWait, let gate { await gate.wait() }
        return try reply.get()
    }
}

private actor DeveloperProfileGate {
    nonisolated let entered = XCTestExpectation(description: "Personal profile read started")
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered.fulfill(); await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}
