import Combine
import CryptoKit
import XCTest
@testable import YunleFun

@MainActor
final class DiagnosticLogStoreTests: XCTestCase {
    private var directory: URL!
    private var clock: DiagnosticTestClock!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        clock = DiagnosticTestClock()
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testRedactsCredentialsSignedURLsContactDetailsAndLongIdentifiers() {
        let input = "GET https://api.yunle.fun/private?sign=secret Authorization: Bearer abc.def "
            + "access_token=\"token-value\" refresh-token='rotate-value' password=plain-password "
            + "passwd=other-password secret=private-value cookie='a=one; b=two' session=session-value "
            + "q-signature=signature-value email=user@example.com phone=13800138000 uid=1978032370372050944"
        let redacted = DiagnosticText.redact(input)
        XCTAssertTrue(redacted.contains("[redacted-url:api.yunle.fun]"))
        XCTAssertTrue(redacted.contains("Bearer [redacted]"))
        XCTAssertTrue(redacted.contains("[redacted-email]"))
        XCTAssertTrue(redacted.contains("[redacted-phone]"))
        XCTAssertTrue(redacted.contains("[redacted-id]"))
        for value in ["/private", "sign=secret", "abc.def", "token-value", "rotate-value", "plain-password", "other-password",
                      "private-value", "a=one", "b=two", "session-value", "signature-value", "user@example.com", "13800138000", "1978032370372050944"] {
            XCTAssertFalse(redacted.contains(value), "Must remove \(value)")
        }
        XCTAssertEqual(DiagnosticText.redact(redacted), redacted, "Repeated normalization must not expand redaction placeholders")
    }

    func testRedactsJWTMultilineQuotedValuesAndCompleteURLWithoutItsCredentials() {
        let jwt = "eyJ" + String(repeating: "a", count: 12) + "." + String(repeating: "b", count: 12) + "." + String(repeating: "c", count: 12)
        let input = "jwt \(jwt) PASSWORD: \"first-line\nsecond-line\" URL HTTPS://name:pass@Example.test/a#sensitive),."
        let redacted = DiagnosticText.redact(input)
        XCTAssertTrue(redacted.contains("[redacted-token]"))
        XCTAssertTrue(redacted.contains("PASSWORD: \"[redacted]\""))
        XCTAssertTrue(redacted.contains("[redacted-url:example.test]),."))
        for value in [jwt, "first-line", "second-line", "name:pass", "/a", "#sensitive"] { XCTAssertFalse(redacted.contains(value)) }
    }

    func testUTF16LimitKeepsSurrogatePairsAndJoinedCharactersWhole() throws {
        let almostFull = String(repeating: "a", count: 1499)
        XCTAssertEqual(DiagnosticText.redact(almostFull + "😀tail"), almostFull)
        let fitting = String(repeating: "a", count: 1498) + "😀"
        XCTAssertEqual(DiagnosticText.redact(fitting + "tail"), fitting)
        XCTAssertEqual(DiagnosticText.redact(fitting + "tail").utf16.count, 1500)
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(DiagnosticText.utf16Prefix("a" + family + "z", limit: family.utf16.count), "a")
        XCTAssertEqual(DiagnosticText.utf16Prefix("e\u{301}x", limit: 1), "")
        XCTAssertEqual(DiagnosticText.utf16Prefix("text", limit: 0), "")
        let store = makeStore()
        store.record(.warn, message: fitting + "tail")
        let reopened = makeStore()
        XCTAssertEqual(reopened.entries.first?.message, fitting)
        XCTAssertEqual(reopened.entries.first?.message.utf16.count, 1500)
    }

    func testPersistsOnlyRedactedEntriesAndRestoresThem() throws {
        let store = makeStore()
        store.record(.error, message: "request.failed https://example.test/private?token=private-value email=user@example.com")
        XCTAssertNil(store.storageError)
        let data = try Data(contentsOf: file())
        let disk = try XCTUnwrap(String(data: data, encoding: .utf8))
        for value in ["/private", "private-value", "user@example.com"] { XCTAssertFalse(disk.contains(value)) }
        XCTAssertTrue(disk.contains("redacted-url"))
        let reopened = makeStore()
        XCTAssertEqual(reopened.entries, store.entries)
        XCTAssertNil(reopened.storageError)
        let attributes = try FileManager.default.attributesOfItem(atPath: file().path)
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
            ?? (attributes[.protectionKey] as? String)
        #if targetEnvironment(simulator)
        if let protection {
            XCTAssertEqual(protection, FileProtectionType.completeUnlessOpen.rawValue)
        } else {
            let boundary = XCTAttachment(string: "The simulator did not report NSFileProtectionKey. Redacted persistence and restoration are verified here; the production write requests atomic replacement and completeFileProtectionUnlessOpen, but this simulator result does not prove device encryption or behavior while locked.")
            boundary.name = "diagnostic-file-protection-simulator-coverage-boundary"
            boundary.lifetime = .keepAlways; add(boundary)
        }
        #else
        XCTAssertEqual(protection, FileProtectionType.completeUnlessOpen.rawValue)
        #endif
    }

    func testAccountPartitionsUseHashedPathsAndCannotLoadAnotherScopesEnvelope() throws {
        let store = makeStore()
        store.record(.info, message: "guest.started")
        let guestGeneration = store.scopeGeneration
        let sensitiveUID = "../alice@example.com/private-user"
        store.activateAccount(sensitiveUID)
        XCTAssertNotEqual(store.scopeGeneration, guestGeneration)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.accountID, sensitiveUID)
        store.record(.log, message: "host.started")
        let accountFile = file(accountID: sensitiveUID)
        let accountData = try Data(contentsOf: accountFile)
        XCTAssertFalse(String(decoding: accountData, as: UTF8.self).contains(sensitiveUID))
        XCTAssertEqual(accountFile.lastPathComponent.count, "account-".count + 64 + ".json".count)
        XCTAssertFalse(accountFile.lastPathComponent.contains("alice"))
        let firstAccountGeneration = store.scopeGeneration
        store.activateAccount("another-account")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotEqual(store.scopeGeneration, firstAccountGeneration)
        store.record(.debug, message: "another.started")
        store.activateAccount(sensitiveUID)
        XCTAssertEqual(store.entries.map(\.message), ["host.started"])
        XCTAssertNotEqual(store.scopeGeneration, firstAccountGeneration, "A to B to A must invalidate an older confirmation")
        store.activateAccount(sensitiveUID)
        let sameAccountGeneration = store.scopeGeneration
        store.record(.info, message: "host.ready")
        XCTAssertEqual(store.scopeGeneration, sameAccountGeneration, "Appending must not invalidate a frozen snapshot")
        store.activateAccount(nil)
        XCTAssertEqual(store.entries.map(\.message), ["guest.started"])
        try accountData.write(to: file(accountID: "wrong-owner"))
        store.activateAccount("wrong-owner")
        XCTAssertTrue(store.entries.isEmpty, "A correctly named file with another scope's envelope must not leak its contents")
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(try Data(contentsOf: file(accountID: "wrong-owner")), accountData)
    }

    func testSelectionUsesClosedRangeAndNeverPublishesOrWritesWhilePruningExpiredEntries() throws {
        let store = makeStore()
        clock.milliseconds -= 2000; store.record(.warn, message: "before")
        clock.milliseconds += 1000; store.record(.error, message: "inside-a")
        clock.milliseconds += 1000; store.record(.info, message: "inside-b")
        clock.milliseconds += 1; store.record(.debug, message: "after")
        let end = clock.milliseconds - 1
        XCTAssertEqual(store.select(startTime: end - 1000, endTime: end).map(\.message), ["inside-a", "inside-b"])
        XCTAssertTrue(store.select(startTime: .nan, endTime: end).isEmpty)
        XCTAssertTrue(store.select(startTime: end, endTime: .infinity).isEmpty)
        XCTAssertTrue(store.select(startTime: end + 1, endTime: end).isEmpty)
        let beforeEntries = store.entries, beforeGeneration = store.scopeGeneration
        let beforeDisk = try Data(contentsOf: file())
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        clock.milliseconds += DiagnosticLimits.retentionMilliseconds + 1
        XCTAssertTrue(store.select(startTime: 0, endTime: clock.milliseconds).isEmpty)
        XCTAssertEqual(publications, 0, "SwiftUI may call selection from body")
        XCTAssertEqual(store.entries, beforeEntries)
        XCTAssertEqual(store.scopeGeneration, beforeGeneration)
        XCTAssertEqual(try Data(contentsOf: file()), beforeDisk)
        observation.cancel()
    }

    func testReadAndAppendKeepOnlyNewest500ChronologicalEntries() throws {
        let values = (0..<510).map { index in
            DiagnosticLogEntry(level: .info, message: "entry-\(index)", timestamp: clock.milliseconds - Double(510 - index) * 1000)
        }
        try writeEnvelope(values.reversed())
        let store = makeStore()
        XCTAssertEqual(store.entries.count, 500)
        XCTAssertEqual(store.entries.first?.message, "entry-10")
        XCTAssertEqual(store.entries.last?.message, "entry-509")
        let generation = store.scopeGeneration
        store.record(.info, message: "latest")
        XCTAssertEqual(store.entries.count, 500)
        XCTAssertEqual(store.entries.first?.message, "entry-11")
        XCTAssertEqual(store.entries.last?.message, "latest")
        XCTAssertEqual(store.scopeGeneration, generation)
        XCTAssertEqual(makeStore().entries, store.entries)
    }

    func testReadPrunesExpiredFutureAndEmptyEntriesAndSanitizesDiskBeforeReuse() throws {
        let earliest = clock.milliseconds - DiagnosticLimits.retentionMilliseconds
        let future = clock.milliseconds + DiagnosticLimits.futureClockSkewMilliseconds
        try writeEnvelope([
            DiagnosticLogEntry(level: .info, message: "expired", timestamp: earliest - 1),
            DiagnosticLogEntry(level: .info, message: "old-boundary", timestamp: earliest),
            DiagnosticLogEntry(level: .warn, message: "token=private-token", timestamp: clock.milliseconds + 0.9),
            DiagnosticLogEntry(level: .log, message: "", timestamp: clock.milliseconds),
            DiagnosticLogEntry(level: .error, message: "future-boundary", timestamp: future),
            DiagnosticLogEntry(level: .debug, message: "too-far-future", timestamp: future + 1),
        ])
        let store = makeStore()
        XCTAssertEqual(store.entries.map(\.message), ["old-boundary", "token=[redacted]", "future-boundary"])
        XCTAssertEqual(store.entries[1].timestamp, clock.milliseconds)
        XCTAssertFalse(String(decoding: try Data(contentsOf: file()), as: UTF8.self).contains("private-token"))
        clock.milliseconds += DiagnosticLimits.retentionMilliseconds + DiagnosticLimits.futureClockSkewMilliseconds + 1
        XCTAssertTrue(makeStore().entries.isEmpty)
    }

    func testCorruptAndOversizedFilesRemainUntouchedUntilExplicitClear() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("{broken private fixture".utf8)
        try corrupt.write(to: file())
        let store = makeStore()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.storageError)
        store.record(.error, message: "host.failed")
        XCTAssertEqual(store.entries.map(\.message), ["host.failed"])
        XCTAssertEqual(try Data(contentsOf: file()), corrupt, "Do not replace unreadable evidence without an explicit clear")
        store.clear()
        XCTAssertNil(store.storageError)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file().path))
        let oversized = Data(repeating: 0x20, count: 8 * 1024 * 1024 + 1)
        try oversized.write(to: file())
        store.activateAccount(nil)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.storageError)
        store.record(.info, message: "host.ready")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file().path)[.size] as? NSNumber, NSNumber(value: oversized.count))
        store.clear()
        store.record(.info, message: "host.recovered")
        XCTAssertNil(store.storageError)
        XCTAssertEqual(makeStore().entries.map(\.message), ["host.recovered"])
    }

    func testWriteFailureRetainsMemoryAndRetriesWithoutChangingTheAccountBoundary() throws {
        let store = makeStore()
        let generation = store.scopeGeneration
        try Data("not a directory".utf8).write(to: directory)
        store.record(.error, message: "host.failed")
        XCTAssertEqual(store.entries.map(\.message), ["host.failed"])
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(store.scopeGeneration, generation)
        try FileManager.default.removeItem(at: directory)
        store.record(.info, message: "host.recovered")
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.scopeGeneration, generation)
        XCTAssertEqual(makeStore().entries.map(\.message), ["host.failed", "host.recovered"])
    }

    func testClearFailureClearsMemoryInvalidatesConfirmationAndPreservesUnexpectedDirectory() throws {
        let store = makeStore()
        store.record(.info, message: "host.started")
        let generation = store.scopeGeneration
        try FileManager.default.removeItem(at: file())
        try FileManager.default.createDirectory(at: file(), withIntermediateDirectories: false)
        let marker = file().appendingPathComponent("must-remain")
        try Data("fixture".utf8).write(to: marker)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotEqual(store.scopeGeneration, generation)
        XCTAssertNotNil(store.storageError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "Clear must not recursively remove an unexpected directory")
        store.record(.warn, message: "memory.only")
        XCTAssertEqual(store.entries.map(\.message), ["memory.only"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testSymbolicLinkFileCannotBeReadOrWrittenAndClearDoesNotTouchItsTarget() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("outside-fixture")
        let marker = Data("private target must remain".utf8)
        try marker.write(to: target)
        try FileManager.default.createSymbolicLink(at: file(), withDestinationURL: target)
        let store = makeStore()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.storageError)
        store.record(.warn, message: "host.warning")
        XCTAssertEqual(try Data(contentsOf: target), marker)
        store.clear()
        XCTAssertNil(store.storageError)
        XCTAssertEqual(try Data(contentsOf: target), marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file().path))
        store.record(.info, message: "host.ready")
        XCTAssertNil(store.storageError)
        XCTAssertEqual(makeStore().entries.map(\.message), ["host.ready"])
    }

    func testSymbolicLinkDirectoryAndParentCannotCreateOrEraseOutsideFiles() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let marker = target.appendingPathComponent("must-remain")
        try Data("fixture".utf8).write(to: marker)
        let link = directory.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        for unsafeDirectory in [link, link.appendingPathComponent("nested", isDirectory: true)] {
            let store = DiagnosticLogStore(directory: unsafeDirectory, now: { self.clock.date })
            XCTAssertNotNil(store.storageError)
            store.record(.info, message: "host.ready")
            store.clear()
            XCTAssertNotNil(store.storageError)
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("guest.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("nested").path))
        }
    }

    func testUploadModelsEncodeTheExactThreeLogFieldsAndSixClientFields() throws {
        let client = DiagnosticClientContext(appVersion: "1.0", buildNumber: "2", platform: "ios", route: "/feedback", timezone: "Asia/Shanghai", userAgent: "YunleFun/iOS")
        let payload = DiagnosticUploadPayload(startTime: 1000, endTime: 2000, issueDescription: "host issue",
            logs: [DiagnosticLogEntry(level: .debug, message: "host.started", timestamp: 1500)], client: client)
        let encoded = try JSONEncoder().encode(payload)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticUploadPayload.self, from: encoded), payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let logs = try XCTUnwrap(object["logs"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(logs.first).keys), Set(["level", "message", "timestamp"]))
        let context = try XCTUnwrap(object["client"] as? [String: Any])
        XCTAssertEqual(Set(context.keys), Set(["appVersion", "buildNumber", "platform", "route", "timezone", "userAgent"]))
        let receipt = DiagnosticUploadReceipt(uploadId: "", supportCode: "ABC123DEF456", logCount: 1, expiresAt: 8000)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticUploadReceipt.self, from: JSONEncoder().encode(receipt)), receipt)
        for level in DiagnosticLogLevel.allCases {
            XCTAssertEqual(try JSONDecoder().decode(DiagnosticLogLevel.self, from: JSONEncoder().encode(level)), level)
        }
    }

    private func makeStore() -> DiagnosticLogStore { DiagnosticLogStore(directory: directory, now: { self.clock.date }) }
    private func file(accountID: String? = nil) -> URL {
        let scope = scopeKey(accountID)
        return directory.appendingPathComponent(scope + ".json")
    }
    private func scopeKey(_ id: String?) -> String {
        id.map { "account-" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "guest"
    }
    private func writeEnvelope<S: Sequence>(_ entries: S) throws where S.Element == DiagnosticLogEntry {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = entries.map { ["level": $0.level.rawValue, "message": $0.message, "timestamp": $0.timestamp] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "scope": "guest", "entries": records])
        try data.write(to: file())
    }
}

private final class DiagnosticTestClock {
    var milliseconds: Double = 1_792_230_000_000
    var date: Date { Date(timeIntervalSince1970: milliseconds / 1000) }
}
