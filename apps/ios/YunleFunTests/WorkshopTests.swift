import XCTest
@testable import YunleFun

final class WorkshopServiceTests: XCTestCase {
    private var hosts: [String] = []
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }
    private let identity = AuthorizedAccount(userID: "owner", accessToken: "test-token")

    func testMissingOrMalformedMineIsNotTreatedAsPermissionToCreate() async throws {
        let (service, _) = service([(200, #"{"management":null}"#), (200, "{}"), (200, "<html>fallback</html>"),
                                    (200, try workshopJSON(["management": ["workshop": workshopObject(owner: "another"), "pending": [], "guests": [], "blocked": []]]))])
        let empty = try await service.mine(identity: identity)
        XCTAssertNil(empty)
        for _ in 0..<3 {
            do { _ = try await service.mine(identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? WorkshopError, .invalidResponse) }
        }
    }
    func testPublicLookupNeverAcceptsPrivateAppsOrFabricatedMembership() async throws {
        let (service, fixture) = service([(200, try workshopJSON(["surface": "workshop", "access": "anonymous", "workshop": workshopObject(), "apps": []]))])
        let page = try await service.page(id: "ABC234", identity: nil)
        XCTAssertEqual(page.access, .anonymous)
        XCTAssertNil(fixture.requests.first?.value(forHTTPHeaderField: "Authorization"))
        for access in [WorkshopAccess.none, .pending, .blocked, .anonymous] {
            let invalid = WorkshopPage(surface: "workshop", access: access, workshop: workshop(), apps: [workshopApp()])
            XCTAssertThrowsError(try invalid.validate(id: "ABC234", identity: access == .anonymous ? nil : identity))
        }
        let invalidOwner = WorkshopPage(surface: "workshop", access: .owner, workshop: workshop(), apps: [])
        XCTAssertThrowsError(try invalidOwner.validate(id: "ABC234", identity: nil))
    }
    func testScopedCatalogKeepsItsCurrentRevisionAndCannotBecomeAGuestLaunch() async throws {
        let (service, _) = service([(200, try workshopJSON(["surface": "workshop", "access": "active", "workshop": workshopObject(),
                                                        "apps": [["_id": "app-one", "name": "工坊当前版本", "audience": "workshop", "accessMode": "public", "websiteUrl": "https://example.invalid/new"]]]))])
        let page = try await service.page(id: "ABC234", identity: identity)
        let app = try XCTUnwrap(page.apps.first)
        XCTAssertEqual(app.accessWorkshopID, "ABC234")
        XCTAssertEqual(app.name, "工坊当前版本")
        XCTAssertFalse(app.canOpenAsGuest)
        XCTAssertTrue(app.canRequestWorkshopLaunch)
        let ownerOnly = CloudApplication(id: "private", name: "私有应用", websiteUrl: "https://example.invalid", audience: "owner")
        XCTAssertFalse(ownerOnly.canOpenAsGuest)
        let invalid = WorkshopPage(surface: "workshop", access: .active, workshop: workshop(), apps: [ownerOnly])
        XCTAssertThrowsError(try invalid.validate(id: "ABC234", identity: identity))
    }
    func testCreationNeverSendsOwnerStatusOrJoiningPolicy() async throws {
        let (service, fixture) = service([(200, try workshopJSON(["workshop": workshopObject(owner: "owner")]))])
        var draft = WorkshopDraft(); draft.name = "  同好的工坊  "; draft.description = "  一起使用应用  "; draft.joinPolicy = .open
        _ = try await service.create(draft: draft, identity: identity)
        let request = try XCTUnwrap(fixture.requests.first), body = try requestFields(request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body["name"] as? String, "同好的工坊")
        XCTAssertEqual(body["description"] as? String, "一起使用应用")
        XCTAssertEqual(Set(body.keys), ["name", "description"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        draft.name = String(repeating: "😀", count: 21)
        XCTAssertFalse(draft.isValid)
        do { _ = try await service.create(draft: draft, identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .invalidInput) }
        XCTAssertEqual(fixture.requests.count, 1)
    }
    func testMemberUIDIsOneEncodedSegmentAndReceiptMustMatchActionAndTarget() async throws {
        let uid = "member/../other?x#尾"
        let row = member(uid: uid, status: .pending)
        let (service, fixture) = service([(200, try workshopJSON(["membership": memberObject(uid: uid, status: "active")])),
                                         (200, try workshopJSON(["membership": memberObject(uid: "wrong", status: "active")])),
                                         (200, try workshopJSON(["membership": memberObject(uid: uid, status: "pending")]))])
        let receipt = try await service.decide(id: "ABC234", member: row, action: .approve, identity: identity)
        XCTAssertEqual(receipt.userUid, uid)
        let request = try XCTUnwrap(fixture.requests.first)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.percentEncodedPath, "/api/workshops/ABC234/members/member%2F..%2Fother%3Fx%23%E5%B0%BE")
        XCTAssertNil(parts.query); XCTAssertNil(parts.fragment)
        XCTAssertEqual(try requestFields(request)["action"] as? String, "approve")
        XCTAssertEqual(try requestFields(request).count, 1)
        for _ in 0..<2 {
            do { _ = try await service.decide(id: "ABC234", member: row, action: .approve, identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? WorkshopError, .invalidResponse) }
        }
    }
    func testPendingJoinAndLeaveMustHaveConsistentAcknowledgements() async throws {
        let (service, _) = service([(200, #"{"status":"pending","joined":false}"#), (200, #"{"status":"pending","joined":true}"#),
                                   (200, try workshopJSON(["membership": memberObject(uid: "someone-else", status: "left")]))])
        let pending = try await service.join(id: "ABC234", identity: identity)
        XCTAssertFalse(pending.joined)
        do { _ = try await service.join(id: "ABC234", identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .invalidResponse) }
        do { _ = try await service.leave(id: "ABC234", identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .invalidResponse) }
    }
    func testPermissionConflictRateLimitAndOutageAreNotReportedAsSuccess() async throws {
        let (service, _) = service([(401, "{}"), (403, "{}"), (409, "{}"), (429, "{}"), (503, "{}")])
        for expected in [WorkshopError.unauthorized, .forbidden, .conflict, .throttled, .unavailable] {
            do { _ = try await service.join(id: "ABC234", identity: identity); XCTFail() }
            catch { XCTAssertEqual(error as? WorkshopError, expected) }
        }
    }
    func testWorkshopLinksRejectExternalOriginsCredentialsAndAmbiguousPaths() {
        XCTAssertEqual(WorkshopLink.parse(" abc234 "), "ABC234")
        XCTAssertEqual(WorkshopLink.parse("https://apps.yunle.fun/w/abc234/"), "ABC234")
        for value in ["ABC012", "https://apps.yunle.fun.evil.test/w/ABC234", "http://apps.yunle.fun/w/ABC234",
                      "https://user:password@apps.yunle.fun/w/ABC234", "https://apps.yunle.fun:444/w/ABC234",
                      "https://apps.yunle.fun/w/ABC234?redirect=evil", "https://apps.yunle.fun/w/ABC234#token",
                      "https://apps.yunle.fun/w/ABC234/another", "https://apps.yunle.fun/w/%2FABC234"] {
            XCTAssertNil(WorkshopLink.parse(value), value)
        }
    }
    private func service(_ replies: [(Int, String)]) -> (WorkshopService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (WorkshopService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
    private func requestFields(_ request: URLRequest) throws -> [String: Any] {
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
final class WorkshopStoreTests: XCTestCase {
    func testGuestManagementDoesNotRequestPrivateEndpoints() async {
        let accounts = WorkshopAccounts(nil), service = WorkshopFixture(), store = MyWorkshopsStore(accounts: accounts, service: service)
        await store.refresh()
        let calls = await service.privateReads
        XCTAssertEqual(calls, 0); XCTAssertTrue(accounts.refreshes.isEmpty)
        XCTAssertNil(store.management); XCTAssertTrue(store.joined.isEmpty); XCTAssertFalse(store.hasLoaded)
    }
    func testLateManagementLoadCannotAppearInAnotherAccount() async {
        let accounts = WorkshopAccounts("owner"), gate = WorkshopGate(), service = WorkshopFixture(loadGate: gate)
        let store = MyWorkshopsStore(accounts: accounts, service: service)
        let loading = Task { await store.refresh() }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("another")
        await gate.open(); await loading.value
        XCTAssertNil(store.management); XCTAssertTrue(store.joined.isEmpty); XCTAssertFalse(store.hasLoaded)
    }
    func testCoalescedAccountSwitchInvalidatesBothPrivateRowsAndConfirmations() async throws {
        let accounts = WorkshopAccounts("owner"), service = WorkshopFixture(), store = MyWorkshopsStore(accounts: accounts, service: service)
        await store.refresh()
        let initial = try XCTUnwrap(store.management), generation = accounts.identityGeneration
        accounts.select("another"); accounts.select("owner")
        XCTAssertNil(store.management); XCTAssertTrue(store.joined.isEmpty)
        do { try await store.decide(member: initial.pending[0], action: .approve, generation: generation); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .identityChanged) }
        var draft = WorkshopDraft(); draft.name = "旧表单"
        do { try await store.save(draft, expectedID: "ABC234", generation: generation); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .identityChanged) }
        let writes = await service.writes; XCTAssertEqual(writes, 0)
    }
    func testLateSaveCannotPublishAnAcknowledgementOrNewWorkshopIntoAnotherAccount() async throws {
        let accounts = WorkshopAccounts("owner"), gate = WorkshopGate(), service = WorkshopFixture(writeGate: gate)
        let store = MyWorkshopsStore(accounts: accounts, service: service)
        await store.refresh()
        var draft = WorkshopDraft(); draft.name = "修改后的工坊"
        let saving = Task { try await store.save(draft, expectedID: "ABC234", generation: accounts.identityGeneration) }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("another")
        await gate.open()
        do { try await saving.value; XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .identityChanged) }
        XCTAssertNil(store.management); XCTAssertNil(store.notice)
    }
    func testMemberDecisionRequiresTheLatestLoadedMembership() async throws {
        let accounts = WorkshopAccounts("owner"), service = WorkshopFixture(), store = MyWorkshopsStore(accounts: accounts, service: service)
        await store.refresh()
        let original = try XCTUnwrap(store.management?.pending.first)
        try await store.decide(member: original, action: .approve, generation: accounts.identityGeneration)
        XCTAssertTrue(try XCTUnwrap(store.management).pending.isEmpty)
        XCTAssertEqual(store.management?.guests.first?.status, .active)
        do { try await store.decide(member: original, action: .reject, generation: accounts.identityGeneration); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .conflict) }
        let writes = await service.writes; XCTAssertEqual(writes, 1)
    }
    func testUnconfirmedWriteIsNotRetriedAndDoesNotOptimisticallyRemoveMembership() async throws {
        let accounts = WorkshopAccounts("owner"), service = WorkshopFixture(failWrites: true)
        let store = WorkshopPageStore(id: "ABC234", accounts: accounts, service: service)
        await store.refresh()
        do { try await store.leave(generation: accounts.identityGeneration); XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .unavailable) }
        XCTAssertEqual(store.page?.access, .active); XCTAssertNil(store.notice)
        let writes = await service.writes; XCTAssertEqual(writes, 1)
    }
    func testJoiningAcknowledgementSurvivesFailedReloadWithoutInventingApps() async throws {
        let accounts = WorkshopAccounts("owner"), service = WorkshopFixture(initialAccess: .none, failPageAfterWrite: true)
        let store = WorkshopPageStore(id: "ABC234", accounts: accounts, service: service)
        await store.refresh()
        try await store.join(generation: accounts.identityGeneration)
        XCTAssertEqual(store.page?.access, .pending); XCTAssertTrue(try XCTUnwrap(store.page).apps.isEmpty)
        XCTAssertEqual(store.notice, "申请已提交，等待坊主审批"); XCTAssertNotNil(store.error)
    }
    func testExpiredWorkshopRequestRefreshesOnlyOnceForTheSameIdentity() async {
        let accounts = WorkshopAccounts("owner"), service = WorkshopFixture(unauthorizedPageOnce: true)
        let store = WorkshopPageStore(id: "ABC234", accounts: accounts, service: service)
        await store.refresh()
        XCTAssertEqual(accounts.refreshes, [false, true]); XCTAssertEqual(store.page?.access, .active)
        XCTAssertNil(store.error)
    }
    func testSavedWorkshopScopeCannotBeReplacedByPublicMarketMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = HomeLibrary(directory: directory, accountID: "owner")
        var app = workshopApp(); app.accessWorkshopID = "ABC234"
        library.add(app)
        library.updateCatalog([CloudApplication(id: app.id, name: "公开旧版本", websiteUrl: "https://example.invalid/old")])
        let restored = HomeLibrary(directory: directory, accountID: "owner")
        let entry = try XCTUnwrap(restored.snapshot.applications.first)
        XCTAssertEqual(entry.accessWorkshopID, "ABC234"); XCTAssertEqual(entry.name, app.name)
        XCTAssertFalse(entry.canOpenAsGuest)
    }
    func testWorkshopLaunchUsesFreshURLAndRejectsRevokedOrPaidAccess() async throws {
        let accounts = WorkshopAccounts("owner")
        var cached = workshopApp(); cached.accessWorkshopID = "ABC234"; cached.websiteUrl = "https://example.invalid/old"
        let boundary = AccountRequestBoundary(uid: "owner", generation: accounts.identityGeneration)
        let current = try await WorkshopLaunchAuthorization(accounts: accounts, service: WorkshopFixture()).resolve(cached, boundary: boundary)
        XCTAssertEqual(current.launchURL?.absoluteString, "https://example.invalid/current")
        for service in [WorkshopFixture(initialAccess: .none), WorkshopFixture(disabled: true), WorkshopFixture(paid: true), WorkshopFixture(membershipRequired: true)] {
            do { _ = try await WorkshopLaunchAuthorization(accounts: accounts, service: service).resolve(cached, boundary: boundary); XCTFail() }
            catch { XCTAssertEqual(error as? WorkshopError, .forbidden) }
        }
    }
    func testAccountSwitchWhileCheckingWorkshopPermissionCancelsLaunchProof() async throws {
        let accounts = WorkshopAccounts("owner"), gate = WorkshopGate(), service = WorkshopFixture(pageGate: gate)
        var cached = workshopApp(); cached.accessWorkshopID = "ABC234"
        let boundary = AccountRequestBoundary(uid: "owner", generation: accounts.identityGeneration)
        let pending = Task { try await WorkshopLaunchAuthorization(accounts: accounts, service: service).resolve(cached, boundary: boundary) }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("another"); await gate.open()
        do { _ = try await pending.value; XCTFail() }
        catch { XCTAssertEqual(error as? WorkshopError, .identityChanged) }
    }
}
@MainActor
private final class WorkshopAccounts: IdentityScopedAccountAuthorizing {
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
private actor WorkshopGate {
    let entered = XCTestExpectation(description: "Workshop request entered")
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
private actor WorkshopFixture: WorkshopServing {
    var privateReads = 0
    var writes = 0
    let loadGate: WorkshopGate?, writeGate: WorkshopGate?, pageGate: WorkshopGate?
    let failWrites: Bool, failPageAfterWrite: Bool, initialAccess: WorkshopAccess, disabled: Bool, paid: Bool, membershipRequired: Bool
    var unauthorizedPageOnce: Bool
    init(loadGate: WorkshopGate? = nil, writeGate: WorkshopGate? = nil, pageGate: WorkshopGate? = nil, failWrites: Bool = false,
         initialAccess: WorkshopAccess = .active, failPageAfterWrite: Bool = false, unauthorizedPageOnce: Bool = false,
         disabled: Bool = false, paid: Bool = false, membershipRequired: Bool = false) {
        self.loadGate = loadGate; self.writeGate = writeGate; self.pageGate = pageGate; self.failWrites = failWrites
        self.initialAccess = initialAccess; self.failPageAfterWrite = failPageAfterWrite; self.unauthorizedPageOnce = unauthorizedPageOnce
        self.disabled = disabled; self.paid = paid; self.membershipRequired = membershipRequired
    }
    func mine(identity: AuthorizedAccount) async throws -> WorkshopManagement? {
        privateReads += 1; await loadGate?.wait()
        return WorkshopManagement(workshop: workshop(owner: identity.userID), pending: [member(status: .pending)], guests: [], blocked: [])
    }
    func joined(identity: AuthorizedAccount) async throws -> [PersonalWorkshop] { privateReads += 1; return [workshop()] }
    func page(id: String, identity: AuthorizedAccount?) async throws -> WorkshopPage {
        await pageGate?.wait()
        if unauthorizedPageOnce { unauthorizedPageOnce = false; throw WorkshopError.unauthorized }
        if failPageAfterWrite && writes > 0 { throw WorkshopError.unavailable }
        var app = workshopApp(); app.coinCost = paid ? 10 : nil; app.requiresMembership = membershipRequired
        app.accessWorkshopID = id
        return WorkshopPage(surface: "workshop", access: initialAccess, workshop: workshop(status: disabled ? .disabled : .active), apps: initialAccess == .active && !disabled ? [app] : [])
    }
    func create(draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop { try await update(id: "ABC234", draft: draft, identity: identity) }
    func update(id: String, draft: WorkshopDraft, identity: AuthorizedAccount) async throws -> PersonalWorkshop {
        writes += 1; await writeGate?.wait(); if failWrites { throw WorkshopError.unavailable }
        return workshop(owner: identity.userID, name: draft.name)
    }
    func join(id: String, identity: AuthorizedAccount) async throws -> WorkshopJoinResult {
        writes += 1; if failWrites { throw WorkshopError.unavailable }; return WorkshopJoinResult(status: .pending, joined: false)
    }
    func leave(id: String, identity: AuthorizedAccount) async throws -> WorkshopMembership {
        writes += 1; if failWrites { throw WorkshopError.unavailable }; return member(uid: identity.userID, status: .left)
    }
    func decide(id: String, member row: WorkshopMembership, action: WorkshopDecision, identity: AuthorizedAccount) async throws -> WorkshopMembership {
        writes += 1; await writeGate?.wait(); if failWrites { throw WorkshopError.unavailable }; return member(uid: row.userUid, status: action.result)
    }
}
private func workshop(owner: String? = nil, name: String = "同好的工坊", status: WorkshopStatus = .active) -> PersonalWorkshop {
    PersonalWorkshop(id: "ABC234", ownerName: "坊主", ownerAvatar: nil, name: name, description: "一起使用应用", joinPolicy: .approval, status: status, ownerUid: owner)
}
private func workshopApp() -> CloudApplication { CloudApplication(id: "app-one", name: "工坊当前版本", websiteUrl: "https://example.invalid/current", accessMode: "public", audience: "workshop") }
private func member(uid: String = "member", status: WorkshopMembershipStatus) -> WorkshopMembership {
    WorkshopMembership(workshopId: "ABC234", userUid: uid, userName: "同好", userAvatar: nil, status: status, requestedAt: nil, joinedAt: nil, updatedAt: 1_800_000_000_000)
}
private func workshopObject(owner: String? = nil) -> [String: Any] {
    var result: [String: Any] = ["_id": "ABC234", "ownerName": "坊主", "name": "同好的工坊", "description": "一起使用应用", "joinPolicy": "approval", "status": "active"]
    if let owner { result["ownerUid"] = owner }; return result
}
private func memberObject(uid: String, status: String) -> [String: Any] { ["workshopId": "ABC234", "userUid": uid, "status": status, "updatedAt": 1_800_000_000_000] }
private func workshopJSON(_ value: [String: Any]) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
