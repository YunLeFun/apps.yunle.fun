import CoreGraphics
import Foundation
import ImageIO
import XCTest
import SwiftUI
import UIKit
@testable import YunleFun

final class PublishingServiceTests: XCTestCase {
    private var hosts: [String] = []
    private let identity = AuthorizedAccount(userID: "owner", accessToken: "test-owner")
    override func tearDown() { hosts.forEach(AuthHTTPProtocol.unregister); super.tearDown() }
    func testOwnedListRejectsMissingDataWrongOwnersAndConflictingLegacyOwnership() async throws {
        let (service, _) = service([(200, "{}"), (200, try publishingJSON(["items": []])),
            (200, try publishingJSON(["items": [publishingRecord(owner: "other", legacy: "owner")]])),
            (200, try publishingJSON(["items": [publishingRecord(owner: nil, legacy: "owner")]]))])
        do { _ = try await service.applications(identity: identity); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
        let empty = try await service.applications(identity: identity); XCTAssertTrue(empty.isEmpty)
        do { _ = try await service.applications(identity: identity); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
        let legacy = try await service.applications(identity: identity)
        XCTAssertEqual(legacy.first?.application.accessOwnerID, "owner")
        XCTAssertFalse(try XCTUnwrap(legacy.first).application.canOpenAsGuest)
    }
    func testSavingCreatesARevisionWithoutInventingApprovalOrPublishingToTheMarket() async throws {
        let record = publishingRecord(revision: "revision-two")
        let (service, fixture) = service([(200, try publishingJSON(["app": record, "submission": record["latestSubmission"]!]))])
        let app = try await service.save(id: nil, draft: publishingDraft(), identity: identity)
        XCTAssertEqual(app.publicationStatus, .published); XCTAssertEqual(app.latestSubmission?.reviewStatus, .draft)
        XCTAssertEqual(app.marketState.label, "尚未投稿"); XCTAssertEqual(app.marketState.action, .submit)
        XCTAssertEqual(app.application.accessOwnerID, "owner")
        let request = try XCTUnwrap(fixture.requests.first), body = try publishingBody(request)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/apps/submissions")
        XCTAssertEqual(body["kind"] as? String, "first_party")
        XCTAssertEqual(body["audience"] as? String, "public")
        for key in ["ownerUid", "_openid", "submitterUid", "reviewStatus", "publicationStatus", "isOfficial", "coinCost"] { XCTAssertNil(body[key], key) }
        XCTAssertNil(request.url?.query); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-owner")
    }
    func testMismatchedSaveReceiptCannotBecomeASuccessfulEdit() async throws {
        let record = publishingRecord(owner: "other", revision: "revision-two")
        let (service, _) = service([(200, try publishingJSON(["app": record, "submission": record["latestSubmission"]!]))])
        do { _ = try await service.save(id: "app-one", draft: publishingDraft(), identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
    }
    func testMarketSubmissionAndDelistingNeedMatchingPositiveReceipts() async throws {
        let (service, fixture) = service([(200, #"{"appId":"app-one","submissionId":"revision-two","reviewStatus":"pending"}"#),
            (200, #"{"appId":"different","submissionId":"revision-two","reviewStatus":"pending"}"#), (200, #"{"success":false}"#), (200, #"{"success":true}"#)])
        let receipt = try await service.submit(id: "app-one", makePublic: true, shortName: "my-app", identity: identity)
        XCTAssertEqual(receipt.reviewStatus, .pending)
        let body = try publishingBody(XCTUnwrap(fixture.requests.first))
        XCTAssertEqual(body["makePublic"] as? Bool, true); XCTAssertEqual(body["shortName"] as? String, "my-app")
        XCTAssertEqual(body.count, 2)
        do { _ = try await service.submit(id: "app-one", makePublic: false, shortName: "my-app", identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
        do { try await service.delist(id: "app-one", identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
        try await service.delist(id: "app-one", identity: identity)
    }
    func testIconUploadUsesMultipartPNGAndRequiresAnOwnedResourceReceiptShape() async throws {
        let png = try await ApplicationIconNormalizer().normalize(publishingImage(width: 120, height: 120), role: .appIcon)
        let fileID = publishingFileID
        let (service, fixture) = service([(200, try publishingJSON(["fileID": fileID, "role": "app-icon", "width": 1024, "height": 1024])),
            (200, try publishingJSON(["fileID": "https://external.invalid/arbitrary", "role": "mark", "width": 1024, "height": 1024]))])
        let result = try await service.upload(png: png, role: .appIcon, identity: identity)
        XCTAssertEqual(result, fileID)
        let request = try XCTUnwrap(fixture.requests.first), raw = publishingRawBody(request)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertNotNil(raw.range(of: png)); XCTAssertNotNil(raw.range(of: Data("name=\"assetRole\"\r\n\r\napp-icon".utf8)))
        XCTAssertNil(raw.range(of: Data("test-owner".utf8))); XCTAssertNil(request.url?.query)
        do { _ = try await service.upload(png: png, role: .mark, identity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .invalidResponse) }
    }
    func testInvalidInputsAndRestrictedErrorsDoNotSendOrPretendToSucceed() async throws {
        let (service, fixture) = service([(401, "{}"), (403, "{}"), (409, "{}"), (429, "{}"), (503, "{}")])
        var draft = publishingDraft(); draft.name = String(repeating: "😀", count: 26)
        XCTAssertFalse(draft.isValid)
        do { _ = try await service.save(id: nil, draft: draft, identity: identity); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .invalidInput) }
        do { try await service.delist(id: "../other", identity: identity); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .invalidInput) }
        XCTAssertTrue(fixture.requests.isEmpty)
        for expected in [PublishingError.unauthorized, .forbidden, .conflict, .throttled, .unavailable] {
            do { try await service.delist(id: "app-one", identity: identity); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, expected) }
        }
    }
    func testVisibilityAndMarketRevisionPresentationRemainIndependent() throws {
        let previous = ["appId": "app-one", "status": "listed", "approvedRevisionId": "revision-old", "activeSubmissionId": "revision-one"]
        let app = try publishingManaged(record: publishingRecord(review: "pending", listing: previous))
        XCTAssertEqual(app.marketState.label, "等待审核")
        XCTAssertTrue(app.marketState.detail.contains("上一批准版本")); XCTAssertNil(app.marketState.action)
        let approved = try publishingManaged(record: publishingRecord(review: "approved", listing: previous))
        XCTAssertEqual(approved.marketState.label, "审核通过"); XCTAssertNil(approved.marketState.action)
        let privateApp = try publishingManaged(record: publishingRecord(audience: "owner"))
        XCTAssertEqual(privateApp.marketState.action, .makePublic)
        let delisted = try publishingManaged(record: publishingRecord(publication: "delisted"))
        XCTAssertNil(delisted.marketState.action)
        var form = publishingDraft(); form.websiteUrl = "https://external.invalid/app"; XCTAssertFalse(form.isValid)
        form.audience = .workshop; form.tags = ["tag", ""]; form.trustedHosts = [""]
        XCTAssertTrue(form.isValid)
    }
    func testNewCurrentVersionIsNotMistakenForAnOlderPendingReview() throws {
        var record = publishingRecord(revision: "current-new")
        record["latestSubmission"] = publishingRecord(revision: "older-review", review: "pending")["latestSubmission"]
        let app = try publishingManaged(record: record)
        XCTAssertEqual(app.marketState.label, "新版未投稿")
        XCTAssertEqual(app.marketState.detail, "另一个版本仍在审核；当前版本尚未投稿。")
        XCTAssertEqual(app.marketState.action, .submit)
        XCTAssertFalse(app.hasCurrentMetadata, "Older servers must not let a stale review snapshot become the edit form")
        record["ownerMetadataRevisionId"] = "current-new"
        XCTAssertTrue(try publishingManaged(record: record).hasCurrentMetadata)
    }
    private func service(_ replies: [(Int, String)]) -> (PublishingService, AuthHTTPFixture) {
        let host = UUID().uuidString.lowercased() + ".invalid"; hosts.append(host)
        let fixture = AuthHTTPFixture(replies: replies); AuthHTTPProtocol.register(host, fixture: fixture)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        return (PublishingService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), fixture)
    }
}
@MainActor
final class PublishingStoreTests: XCTestCase {
    func testGuestNeverReadsPrivatePublishingData() async {
        let accounts = PublishingAccounts(nil), service = PublishingFixture(), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let reads = await service.reads
        XCTAssertEqual(reads, 0); XCTAssertTrue(store.applications.isEmpty); XCTAssertNil(store.publishingAccess)
    }
    func testPreflightReadCannotSendAWriteAfterAccountSwitch() async throws {
        let accounts = PublishingAccounts("owner"), gate = PublishingGate(), service = PublishingFixture(preflightGate: gate)
        let store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first)), generation = accounts.identityGeneration
        let save = Task { try await store.save(publishingDraft(), base: base, generation: generation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("other"); await gate.open()
        do { _ = try await save.value; XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .identityChanged) }
        let writes = await service.writes; XCTAssertEqual(writes, 0); XCTAssertTrue(store.applications.isEmpty)
    }
    func testRemoteRevisionChangeKeepsTheDraftAndStopsSaveBeforeMutation() async throws {
        let accounts = PublishingAccounts("owner"), service = PublishingFixture(), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first))
        try await service.changeRevision()
        do { _ = try await store.save(publishingDraft(), base: base, generation: accounts.identityGeneration); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .conflict) }
        let writes = await service.writes; XCTAssertEqual(writes, 0)
    }
    func testLateSaveAcknowledgementCannotAppearInAnotherAccount() async throws {
        let accounts = PublishingAccounts("owner"), gate = PublishingGate(), service = PublishingFixture(writeGate: gate)
        let store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first)), generation = accounts.identityGeneration
        let save = Task { try await store.save(publishingDraft(), base: base, generation: generation) }
        await fulfillment(of: [gate.entered], timeout: 3)
        accounts.select("other"); await gate.open()
        do { _ = try await save.value; XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .identityChanged) }
        XCTAssertTrue(store.applications.isEmpty); XCTAssertNil(store.notice)
    }
    func testABASwitchInvalidatesOldRowsAndCapturedDestructiveConfirmations() async throws {
        let accounts = PublishingAccounts("owner"), service = PublishingFixture(), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first)), generation = accounts.identityGeneration
        accounts.select("other"); accounts.select("owner")
        XCTAssertTrue(store.applications.isEmpty)
        do { try await store.delist(base: base, generation: generation); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .identityChanged) }
        let writes = await service.writes; XCTAssertEqual(writes, 0)
    }
    func testUnconfirmedWritesAreNotAutomaticallyReplayedOrPublishedLocally() async throws {
        let accounts = PublishingAccounts("owner"), service = PublishingFixture(failWrites: true), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first))
        do { try await store.delist(base: base, generation: accounts.identityGeneration); XCTFail() } catch { XCTAssertEqual(error as? PublishingError, .unavailable) }
        XCTAssertEqual(store.applications.count, 1); XCTAssertNil(store.notice)
        let writes = await service.writes; XCTAssertEqual(writes, 1)
    }
    func testAcknowledgedPublicConversionCannotKeepShowingTheOldPrivateStateWhenReloadFails() async throws {
        let accounts = PublishingAccounts("owner"), service = PublishingFixture(audience: "owner", failReload: true), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let base = ApplicationEditBase(try XCTUnwrap(store.applications.first))
        try await store.submit(base: base, makePublic: true, shortName: "my-app", generation: accounts.identityGeneration)
        XCTAssertNil(store.application(id: base.id)); XCTAssertTrue(try XCTUnwrap(store.pending(id: base.id)).madePublic)
        XCTAssertNotNil(store.error); XCTAssertTrue(try XCTUnwrap(store.notice).contains("设为公开"))
    }
    func testOwnerPreviewRevalidatesTheCurrentIdentityAndPreservesItsOwnURL() async throws {
        let accounts = PublishingAccounts("owner"), service = PublishingFixture()
        var cached = try publishingManaged().application; cached.accessOwnerID = "owner"; cached.websiteUrl = "https://old.invalid"
        let boundary = AccountRequestBoundary(uid: "owner", generation: accounts.identityGeneration)
        let current = try await OwnerPreviewAuthorization(accounts: accounts, service: service).resolve(cached, boundary: boundary)
        XCTAssertEqual(current.launchURL?.host, "sample.yunle.fun"); XCTAssertFalse(current.canOpenAsGuest)
        accounts.select("other")
        do { _ = try await OwnerPreviewAuthorization(accounts: accounts, service: service).resolve(cached, boundary: boundary); XCTFail() }
        catch { XCTAssertEqual(error as? PublishingError, .identityChanged) }
    }
}
@MainActor
final class ApplicationDraftAndIconTests: XCTestCase {
    func testDraftsStayPerAccountAndDoNotOverwriteCorruptFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ApplicationDraftVault(directory: directory), saved = SavedApplicationDraft(draft: publishingDraft(), baseRevision: "old", baseUpdatedAt: 1_800_000_000_000)
        try vault.save(saved, owner: "owner", appID: nil)
        XCTAssertEqual(try vault.load(owner: "owner", appID: nil), saved)
        XCTAssertNil(try vault.load(owner: "other", appID: nil)); XCTAssertNil(try vault.load(owner: "owner", appID: "app-one"))
        let corrupt = Data("preserved corruption".utf8); try corrupt.write(to: vault.file(owner: "owner", appID: nil))
        XCTAssertThrowsError(try vault.save(saved, owner: "owner", appID: nil))
        XCTAssertThrowsError(try vault.remove(owner: "owner", appID: nil))
        XCTAssertEqual(try Data(contentsOf: vault.file(owner: "owner", appID: nil)), corrupt)
        XCTAssertLessThan(vault.file(owner: String(repeating: "长", count: 256), appID: String(repeating: "x", count: 256)).lastPathComponent.utf8.count, 255)
    }
    func testOlderDraftCannotLoseItsConflictMarkerBySavingAndReopeningLocally() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ApplicationDraftVault(directory: directory), accounts = PublishingAccounts("owner"), store = PublishingStore(accounts: accounts, service: PublishingFixture())
        let current = try publishingManaged(record: publishingRecord(revision: "new"))
        try vault.save(SavedApplicationDraft(draft: publishingDraft(), baseRevision: "old", baseUpdatedAt: current.updatedAt - 1), owner: "owner", appID: current.id)
        let first = ApplicationEditorModel(application: current, accounts: accounts, store: store, vault: vault)
        first.restoreDraft(); XCTAssertTrue(first.hasOlderDraft); try first.saveLocalDraft()
        let second = ApplicationEditorModel(application: current, accounts: accounts, store: store, vault: vault)
        second.restoreDraft(); XCTAssertTrue(second.hasOlderDraft)
        second.useDraftOnCurrentVersion(); try second.saveLocalDraft()
        XCTAssertEqual(try vault.load(owner: "owner", appID: current.id)?.baseRevision, "new")
    }
    func testNormalizerEnforcesSquareIconsAndProducesReal1024PNG() async throws {
        let normalizer = ApplicationIconNormalizer()
        let output = try await normalizer.normalize(publishingImage(width: 120, height: 120), role: .appIcon)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1024); XCTAssertEqual(image.height, 1024)
        do { _ = try await normalizer.normalize(publishingImage(width: 120, height: 60), role: .appIcon); XCTFail() }
        catch { XCTAssertEqual(error as? IconNormalizationError, .notSquare) }
    }
    func testTransparentMarkIsRejectedAndSafeAreaIsPreserved() async throws {
        let normalizer = ApplicationIconNormalizer()
        do { _ = try await normalizer.normalize(publishingImage(width: 80, height: 80, transparent: true), role: .mark); XCTFail() }
        catch { XCTAssertEqual(error as? IconNormalizationError, .empty) }
        let output = try await normalizer.normalize(publishingImage(width: 120, height: 60), role: .mark)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil)), image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let pixels = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        XCTAssertEqual(image.width, 1024); XCTAssertEqual(image.height, 1024)
        XCTAssertEqual(pixels[3], 0)
        XCTAssertEqual(pixels[512 * 4096 + 512 * 4 + 3], 255)
        XCTAssertEqual(pixels[512 * 4096 + 10 * 4 + 3], 0)
    }
}
private final class PublishingAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser?
    var identityGeneration = UUID()
    init(_ uid: String?) { user = uid.map { AccountUser(id: $0) } }
    func select(_ uid: String?) { user = uid.map { AccountUser(id: $0) }; identityGeneration = UUID() }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        guard let user else { throw AccountError.signedOut }; return AuthorizedAccount(userID: user.id, accessToken: "test-" + user.id)
    }
}
private actor PublishingGate {
    let entered = XCTestExpectation(description: "publishing operation entered")
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
private actor PublishingFixture: PublishingServing {
    var reads = 0, writes = 0
    var record: ManagedApplication
    let preflightGate: PublishingGate?, writeGate: PublishingGate?
    let failWrites: Bool, failReload: Bool
    init(preflightGate: PublishingGate? = nil, writeGate: PublishingGate? = nil, failWrites: Bool = false, audience: String = "public", failReload: Bool = false) {
        self.preflightGate = preflightGate; self.writeGate = writeGate; self.failWrites = failWrites; self.failReload = failReload
        record = try! publishingManaged(record: publishingRecord(audience: audience))
    }
    func changeRevision() throws { record = try publishingManaged(record: publishingRecord(revision: "revision-changed", timestamp: 1_800_000_000_001)) }
    func access(identity: AuthorizedAccount) async throws -> PublishingAccess { PublishingAccess(canSubmitFirstParty: true, thirdPartyEnabled: false, thirdPartyMessage: "第三方应用入驻敬请期待") }
    func applications(identity: AuthorizedAccount) async throws -> [ManagedApplication] {
        reads += 1; if reads == 2 { await preflightGate?.wait() }
        if failReload && writes > 0 { throw PublishingError.unavailable }
        return [record]
    }
    func save(id: String?, draft: ApplicationDraft, identity: AuthorizedAccount) async throws -> ManagedApplication {
        writes += 1; await writeGate?.wait(); if failWrites { throw PublishingError.unavailable }
        record = try publishingManaged(record: publishingRecord(revision: "revision-two")); return record
    }
    func submit(id: String, makePublic: Bool, shortName: String, identity: AuthorizedAccount) async throws -> MarketSubmissionReceipt {
        writes += 1; if failWrites { throw PublishingError.unavailable }
        return MarketSubmissionReceipt(appId: id, submissionId: "revision-two", reviewStatus: .pending)
    }
    func delist(id: String, identity: AuthorizedAccount) async throws { writes += 1; if failWrites { throw PublishingError.unavailable } }
    func upload(png: Data, role: ApplicationIconRole, identity: AuthorizedAccount) async throws -> String { writes += 1; return publishingFileID }
}
private let publishingFileID = "cloud://env.bucket/app-icons/aaaaaaaaaaaaaaaa/11111111-1111-1111-1111-111111111111.png"
private func publishingDraft() -> ApplicationDraft {
    var draft = ApplicationDraft(); draft.name = "我的作品"; draft.slug = "my-app"; draft.websiteUrl = "https://sample.yunle.fun/"
    draft.privacyPolicyUrl = "https://sample.yunle.fun/privacy"; draft.supportUrl = "https://sample.yunle.fun/support"
    return draft
}
private func publishingRecord(owner: String? = "owner", legacy: String? = nil, audience: String = "public", revision: String = "revision-one", review: String = "draft", publication: String = "published", listing: [String: String]? = nil, timestamp: Double = 1_800_000_000_000) -> [String: Any] {
    var snapshot = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(publishingDraft())) as! [String: Any]
    snapshot["audience"] = audience; snapshot["isPublic"] = audience == "public"
    var app = snapshot; app["_id"] = "app-one"; app["updatedAt"] = timestamp; app["publicationStatus"] = publication
    app["currentRevisionId"] = revision; app["publishedSubmissionId"] = revision
    app["latestSubmission"] = ["_id": revision, "appId": "app-one", "submitterUid": "owner", "revision": 1, "reviewStatus": review, "snapshot": snapshot]
    if let owner { app["ownerUid"] = owner }; if let legacy { app["_openid"] = legacy }; if let listing { app["yunlefunListing"] = listing }
    return app
}
private func publishingManaged(record: [String: Any] = publishingRecord()) throws -> ManagedApplication {
    try JSONDecoder().decode(ManagedApplication.self, from: Data(publishingJSON(record).utf8))
}
private func publishingJSON(_ value: [String: Any]) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
private func publishingRawBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }; var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); guard size > 0 else { break }; data.append(buffer, count: size) }
    return data
}
private func publishingBody(_ request: URLRequest) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: publishingRawBody(request)) as? [String: Any]) }
private func publishingImage(width: Int, height: Int, transparent: Bool = false) throws -> Data {
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    if !transparent { context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    let data = NSMutableData(), image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
}

@MainActor
final class PublishingVisualFixtureTests: XCTestCase {
    func testBlankCreateFormWithNativeComponents() async throws { try await render(editing: false, largeDark: false) }
    func testEditFormAtAccessibilitySizeInDarkMode() async throws { try await render(editing: true, largeDark: true) }
    private func render(editing: Bool, largeDark: Bool) async throws {
        let host = UUID().uuidString.lowercased() + ".invalid"
        let fixture = AuthHTTPFixture(replies: [(200, #"{"sub":"owner","name":"视觉测试账号","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: fixture); defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState()
        state.activeID = "owner"; state.accounts = [SavedAccount(user: AccountUser(id: "owner"), credential: AccountCredential(accessToken: "visual-only", refreshToken: "not-used", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: config), origin: URL(string: "https://\(host)")!), vault: PublishingVisualVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        let service = PublishingFixture(), store = PublishingStore(accounts: accounts, service: service)
        await store.refresh()
        let application = editing ? try publishingManaged() : nil
        let draftDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }
        let content = ApplicationEditorView(application: application, store: store, accounts: accounts, draftVault: ApplicationDraftVault(directory: draftDirectory))
            .environment(\.dynamicTypeSize, largeDark ? .accessibility3 : .large)
            .preferredColorScheme(largeDark ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 250_000_000)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = largeDark ? "publishing-fixture-edit-dark-accessibility" : "publishing-fixture-create-light"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
        let writes = await service.writes; XCTAssertEqual(writes, 0, "Rendering a fixture must not submit or upload anything")
    }
}
private struct PublishingVisualVault: AccountVault {
    let data: Data
    func read() throws -> Data? { data }
    func write(_ data: Data) throws {}
}
