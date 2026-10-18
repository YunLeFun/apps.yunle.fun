import XCTest
@testable import YunleFun

@MainActor
final class DiagnosticUploadStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPrepareFreezesRedactedPayloadAndAppendingLogsDoesNotChangeConfirmation() async throws {
        let rig = rig(); defer { rig.close() }
        let confirmation = try prepare(rig, description: "访问 https://example.com/private?token=abc 联系 user@example.com")
        XCTAssertFalse(confirmation.payload.issueDescription.contains("token=abc"))
        XCTAssertFalse(confirmation.payload.issueDescription.contains("user@example.com"))
        XCTAssertEqual(confirmation.payload.logs.count, 1)
        XCTAssertEqual(confirmation.sizeBytes, try DiagnosticUploadRules.sizeBytes(confirmation.payload))
        rig.logs.record(.info, message: "host.next.event")
        XCTAssertTrue(rig.store.isValid(confirmation), "Appending must not change the prepared snapshot")
        expectTrue(await rig.store.upload(confirmation))
        let calls = await rig.service.calls
        XCTAssertEqual(calls.count, 1); XCTAssertEqual(calls[0].payload, confirmation.payload)
        XCTAssertEqual(rig.store.receipt?.logCount, 1)
        expectFalse(await rig.store.upload(confirmation), "A confirmed ID is consumed exactly once")
        expectEqual(await rig.service.callCount, 1)
    }

    func testRedactionAtDescriptionLimitLeavesANewConfirmationValidAndUploadsItsExactPayload() async throws {
        let rig = rig(); defer { rig.close() }
        let raw = String(repeating: "x", count: 482) + " token=a y"
        let confirmation = try prepare(rig, description: raw)
        XCTAssertEqual(confirmation.payload.issueDescription, String(repeating: "x", count: 482) + " token=[redacted]")
        XCTAssertTrue(rig.store.isValid(confirmation), "Preparing a valid description must not produce an immediately stale confirmation")
        expectTrue(await rig.store.upload(confirmation))
        let calls = await rig.service.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.payload, confirmation.payload)
    }

    func testEditingCancellingClearingAndIdentityRoundTripsInvalidateConfirmationWithoutRequests() async throws {
        let rig = rig(); defer { rig.close() }
        let edited = try prepare(rig); rig.store.invalidateConfirmation()
        expectFalse(await rig.store.upload(edited))
        let cancelled = try prepare(rig); rig.store.cancelUpload()
        expectFalse(await rig.store.upload(cancelled))
        let cleared = try prepare(rig); rig.logs.clear()
        XCTAssertFalse(rig.store.isValid(cleared)); expectFalse(await rig.store.upload(cleared))
        rig.logs.record(.info, message: "host.new.scope")
        let switched = try prepare(rig)
        rig.accounts.select("other"); rig.accounts.select("fixture-user")
        XCTAssertFalse(rig.store.isValid(switched)); expectFalse(await rig.store.upload(switched))
        expectEqual(await rig.service.callCount, 0)
        XCTAssertNil(rig.store.receipt)
    }

    func testGuestMismatchedLogOwnerAndEmptyRangeCannotPrepare() throws {
        let rig = rig(); defer { rig.close() }
        rig.accounts.select(nil)
        XCTAssertThrowsError(try prepare(rig)) { XCTAssertEqual($0 as? DiagnosticError, .identityChanged) }
        rig.accounts.select("other")
        XCTAssertThrowsError(try prepare(rig)) { XCTAssertEqual($0 as? DiagnosticError, .identityChanged) }
        rig.accounts.select("fixture-user"); rig.logs.clear()
        XCTAssertThrowsError(try prepare(rig)) { XCTAssertEqual($0 as? DiagnosticError, .emptyLogs) }
    }

    func testAConfirmationIDCannotAuthorizeAChangedPayload() async throws {
        let rig = rig(); defer { rig.close() }
        let original = try prepare(rig)
        let changed = DiagnosticUploadPayload(startTime: original.payload.startTime, endTime: original.payload.endTime,
            issueDescription: "未经确认的修改", logs: original.payload.logs, client: original.payload.client)
        let forged = DiagnosticUploadConfirmation(id: original.id, payload: changed, boundary: original.boundary,
            logScopeGeneration: original.logScopeGeneration, sizeBytes: original.sizeBytes)
        XCTAssertFalse(rig.store.isValid(forged))
        expectFalse(await rig.store.upload(forged))
        expectEqual(await rig.service.callCount, 0)
    }

    func testDuplicateClicksAndLateReceiptAfterAccountSwitchCannotPublishSuccess() async throws {
        let gate = DiagnosticUploadGate(), rig = rig(gate: gate); defer { rig.close() }
        let snapshot = try prepare(rig)
        let pending = Task { await rig.store.upload(snapshot) }
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertTrue(rig.store.isUploading)
        expectFalse(await rig.store.upload(snapshot))
        expectEqual(await rig.service.callCount, 1)
        rig.accounts.select("other"); rig.logs.activateAccount("other"); rig.store.identityChanged()
        XCTAssertFalse(rig.store.isUploading); XCTAssertNil(rig.store.error)
        await gate.open()
        expectFalse(await pending.value)
        XCTAssertNil(rig.store.receipt); XCTAssertNil(rig.store.error)
        rig.accounts.select("fixture-user"); rig.logs.activateAccount("fixture-user"); rig.store.identityChanged()
        XCTAssertNil(rig.store.receipt, "A late cancelled result must not be persisted under the old account either")
    }

    func testCancellationAfterDispatchShowsUnconfirmedOutcomeAndDiscardsLateSuccess() async throws {
        let gate = DiagnosticUploadGate(), rig = rig(gate: gate); defer { rig.close() }
        let pending = Task { await rig.store.upload(try prepare(rig)) }
        await fulfillment(of: [gate.entered], timeout: 3)
        rig.store.cancelUpload()
        XCTAssertFalse(rig.store.isUploading)
        XCTAssertTrue(rig.store.error?.contains("服务器可能已收到") == true)
        await gate.open()
        expectFalse(try await pending.value)
        XCTAssertNil(rig.store.receipt)
        expectEqual(await rig.service.callCount, 1)
    }

    func testClearingDuringUploadRejectsReceiptAndDoesNotRefreshOrUploadAgain() async throws {
        let gate = DiagnosticUploadGate(), rig = rig(failures: [.unauthorized], gate: gate); defer { rig.close() }
        let snapshot = try prepare(rig)
        let pending = Task { await rig.store.upload(snapshot) }
        await fulfillment(of: [gate.entered], timeout: 3)
        rig.logs.clear()
        await gate.open()
        expectFalse(await pending.value)
        XCTAssertNil(rig.store.receipt)
        XCTAssertEqual(rig.accounts.refreshes, [false])
        expectEqual(await rig.service.callCount, 1)
    }

    func test401RefreshesOnceAndResendsTheExactSameFrozenPayload() async throws {
        let rig = rig(failures: [.unauthorized]); defer { rig.close() }
        let snapshot = try prepare(rig)
        expectTrue(await rig.store.upload(snapshot))
        XCTAssertEqual(rig.accounts.refreshes, [false, true])
        let calls = await rig.service.calls
        XCTAssertEqual(calls.map(\.payload), [snapshot.payload, snapshot.payload])
        XCTAssertEqual(calls.map(\.token), ["original-token", "refreshed-token"])
        let invalid = self.rig(failures: [.unauthorized, .unauthorized]); defer { invalid.close() }
        expectFalse(await invalid.store.upload(try prepare(invalid)))
        XCTAssertEqual(invalid.accounts.refreshes, [false, true])
        expectEqual(await invalid.service.callCount, 2)
        XCTAssertNil(invalid.store.receipt)
    }

    func testForbiddenAndAmbiguousNetworkFailureNeverRefreshOrAutomaticallyResubmit() async throws {
        for failure in [DiagnosticError.forbidden, .outcomeUnknown] {
            let rig = rig(failures: [failure]); defer { rig.close() }
            let snapshot = try prepare(rig)
            expectFalse(await rig.store.upload(snapshot))
            expectFalse(await rig.store.upload(snapshot))
            XCTAssertEqual(rig.accounts.refreshes, [false])
            expectEqual(await rig.service.callCount, 1)
            XCTAssertNil(rig.store.receipt)
            if failure == .outcomeUnknown { XCTAssertTrue(rig.store.error?.contains("尚未确认") == true) }
        }
    }

    func testReceiptsSurvivePageRecreationButStayAccountScopedAndExpire() async throws {
        let rig = rig(); defer { rig.close() }
        expectTrue(await rig.store.upload(try prepare(rig)))
        let copy = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
                                         receiptDirectory: rig.receiptDirectory, now: { self.now })
        XCTAssertEqual(copy.receipt, rig.store.receipt)
        rig.accounts.select("other")
        XCTAssertNil(copy.receipt, "Computed projection must hide old receipt even before identityChanged arrives")
        copy.identityChanged(); XCTAssertNil(copy.receipt)
        rig.accounts.select("fixture-user"); copy.identityChanged()
        XCTAssertEqual(copy.receipt?.supportCode, "ABCDEF012345")
        let expired = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
            receiptDirectory: rig.receiptDirectory, now: { self.now.addingTimeInterval(7 * 24 * 60 * 60 + 1) })
        XCTAssertNil(expired.receipt)
        let files = try FileManager.default.contentsOfDirectory(at: rig.receiptDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty)
    }

    func testCorruptReceiptAndWriteFailureDoNotClaimStoredSuccessOrHideNewReceipt() async throws {
        let rig = rig(); defer { rig.close() }
        expectTrue(await rig.store.upload(try prepare(rig)))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: rig.receiptDirectory, includingPropertiesForKeys: nil).first)
        let raw = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(raw.contains("host.screen.ready")); XCTAssertFalse(raw.contains("界面没有响应"))
        XCTAssertFalse(raw.contains("original-token")); XCTAssertFalse(raw.contains("fixture-user"))
        try Data("broken".utf8).write(to: file)
        let corrupt = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
                                            receiptDirectory: rig.receiptDirectory, now: { self.now })
        XCTAssertNil(corrupt.receipt); XCTAssertNotNil(corrupt.storageNotice)
        let another = try corrupt.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: "再次确认", client: diagnosticClient())
        expectTrue(await corrupt.upload(another))
        XCTAssertNotNil(corrupt.receipt); XCTAssertNotNil(corrupt.storageNotice)
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8), "A newly received code stays in memory rather than overwriting corrupt evidence")
        let blocked = rig.directory.appendingPathComponent("blocked")
        try Data("file-instead-of-directory".utf8).write(to: blocked)
        let memoryOnly = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
                                               receiptDirectory: blocked, now: { self.now })
        let snapshot = try memoryOnly.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: "界面没有响应", client: diagnosticClient())
        expectTrue(await memoryOnly.upload(snapshot))
        XCTAssertNotNil(memoryOnly.receipt); XCTAssertTrue(memoryOnly.storageNotice?.contains("未能保存") == true)
    }

    func testReceiptVaultRefusesParentSymlinksWithoutReadingOrCreatingBehindThem() async throws {
        let rig = rig(); defer { rig.close() }
        expectTrue(await rig.store.upload(try prepare(rig)))
        let original = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: rig.receiptDirectory, includingPropertiesForKeys: nil).first)
        let originalData = try Data(contentsOf: original)
        let alias = rig.directory.appendingPathComponent("receipt-parent-link")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: rig.directory)
        let aliased = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
            receiptDirectory: alias.appendingPathComponent("receipts"), now: { self.now })
        XCTAssertNil(aliased.receipt, "The matching account's receipt behind a parent symlink must not be read")
        XCTAssertNotNil(aliased.storageNotice)
        let confirmation = try aliased.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: "重新确认", client: diagnosticClient())
        expectTrue(await aliased.upload(confirmation))
        XCTAssertNotNil(aliased.receipt); XCTAssertNotNil(aliased.storageNotice)
        XCTAssertEqual(try Data(contentsOf: original), originalData)

        let missing = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
            receiptDirectory: alias.appendingPathComponent("must-not-be-created/receipts"), now: { self.now })
        let second = try missing.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: "再次确认", client: diagnosticClient())
        expectTrue(await missing.upload(second))
        XCTAssertNotNil(missing.receipt); XCTAssertNotNil(missing.storageNotice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.directory.appendingPathComponent("must-not-be-created").path),
                       "Directory creation must stop before following the app-controlled parent symlink")
    }

    func testReceiptLeafSymlinkCannotReadOrOverwriteItsTarget() async throws {
        let rig = rig(); defer { rig.close() }
        expectTrue(await rig.store.upload(try prepare(rig)))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: rig.receiptDirectory, includingPropertiesForKeys: nil).first)
        let target = rig.directory.appendingPathComponent("retained-receipt.json")
        try FileManager.default.moveItem(at: file, to: target)
        let retained = try Data(contentsOf: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let linked = DiagnosticUploadStore(accounts: rig.accounts, logs: rig.logs, service: rig.service,
            receiptDirectory: rig.receiptDirectory, now: { self.now })
        XCTAssertNil(linked.receipt); XCTAssertNotNil(linked.storageNotice)
        let snapshot = try linked.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: "再次确认", client: diagnosticClient())
        expectTrue(await linked.upload(snapshot))
        XCTAssertNotNil(linked.storageNotice)
        XCTAssertEqual(try Data(contentsOf: target), retained)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    func testAnExistingReceiptDoesNotTurnANewFailureIntoSuccess() async throws {
        let rig = rig(); defer { rig.close() }
        expectTrue(await rig.store.upload(try prepare(rig)))
        let previous = rig.store.receipt
        await rig.service.failNext(.outcomeUnknown)
        expectFalse(await rig.store.upload(try prepare(rig)))
        XCTAssertEqual(rig.store.receipt, previous)
        XCTAssertTrue(rig.store.error?.contains("尚未确认") == true)
    }

    func testStoreAlsoValidatesReceiptFromAnInjectedService() async throws {
        let rig = rig(); defer { rig.close() }
        await rig.service.invalidateReceipt()
        expectFalse(await rig.store.upload(try prepare(rig)))
        XCTAssertNil(rig.store.receipt)
        XCTAssertTrue(rig.store.error?.contains("回执未能确认") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.receiptDirectory.path))
    }

    private func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(value, message, file: file, line: line)
    }
    private func expectFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(value, message, file: file, line: line)
    }
    private func expectEqual<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, file: file, line: line)
    }

    private func prepare(_ rig: DiagnosticRig, description: String = "界面没有响应") throws -> DiagnosticUploadConfirmation {
        try rig.store.prepare(start: now.addingTimeInterval(-60), end: now, issueDescription: description, client: diagnosticClient())
    }
    private func rig(failures: [DiagnosticError] = [], gate: DiagnosticUploadGate? = nil) -> DiagnosticRig {
        DiagnosticRig(now: now, failures: failures, gate: gate)
    }
}

@MainActor
private final class DiagnosticRig {
    let directory: URL, receiptDirectory: URL
    let accounts = DiagnosticAccounts()
    let logs: DiagnosticLogStore
    let service: DiagnosticStoreFixture
    let store: DiagnosticUploadStore
    init(now: Date, failures: [DiagnosticError], gate: DiagnosticUploadGate?) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        receiptDirectory = directory.appendingPathComponent("receipts")
        logs = DiagnosticLogStore(directory: directory.appendingPathComponent("logs"), now: { now })
        logs.activateAccount("fixture-user"); logs.record(.info, message: "host.screen.ready")
        service = DiagnosticStoreFixture(now: now, failures: failures, gate: gate)
        store = DiagnosticUploadStore(accounts: accounts, logs: logs, service: service, receiptDirectory: receiptDirectory, now: { now })
    }
    func close() { store.cancelUpload(); try? FileManager.default.removeItem(at: directory) }
}
@MainActor
private final class DiagnosticAccounts: IdentityScopedAccountAuthorizing {
    var user: AccountUser? = AccountUser(id: "fixture-user")
    var identityGeneration = UUID()
    private(set) var refreshes: [Bool] = []
    func select(_ uid: String?) { user = uid.map { AccountUser(id: $0) }; identityGeneration = UUID() }
    func authorization(forceRefresh: Bool) async throws -> AuthorizedAccount {
        refreshes.append(forceRefresh)
        guard let user else { throw AccountError.signedOut }
        return AuthorizedAccount(userID: user.id, accessToken: forceRefresh ? "refreshed-token" : "original-token")
    }
}
private actor DiagnosticUploadGate {
    let entered = XCTestExpectation(description: "diagnostic request entered")
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
private actor DiagnosticStoreFixture: DiagnosticServing {
    struct Call { let payload: DiagnosticUploadPayload; let token: String }
    private(set) var calls: [Call] = []
    private var failures: [DiagnosticError]
    private var invalidReceipt = false
    private let now: Date
    private let gate: DiagnosticUploadGate?
    var callCount: Int { calls.count }
    init(now: Date, failures: [DiagnosticError], gate: DiagnosticUploadGate?) { self.now = now; self.failures = failures; self.gate = gate }
    func upload(_ payload: DiagnosticUploadPayload, identity: AuthorizedAccount) async throws -> DiagnosticUploadReceipt {
        calls.append(Call(payload: payload, token: identity.accessToken))
        await gate?.wait()
        if !failures.isEmpty { throw failures.removeFirst() }
        return DiagnosticUploadReceipt(uploadId: "upload-one", supportCode: "ABCDEF012345", logCount: payload.logs.count + (invalidReceipt ? 1 : 0),
                                       expiresAt: now.timeIntervalSince1970 * 1000 + DiagnosticUploadRules.retention)
    }
    func failNext(_ failure: DiagnosticError) { failures.append(failure) }
    func invalidateReceipt() { invalidReceipt = true }
}
