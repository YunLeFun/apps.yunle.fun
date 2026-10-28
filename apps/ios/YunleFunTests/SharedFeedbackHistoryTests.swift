import Foundation
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

final class SharedFeedbackHistoryTests: XCTestCase {
    func testFirstShareCanBeAdoptedAfterRestoreAndSameIdentityRetainsReceipts() throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory)
        let context = try history.prepareForShare(channel: .standard)
        let record = sharedFeedbackTestRecord()
        try history.save(record, expected: context)
        try history.activate(userID: "first-account", channel: .standard)
        XCTAssertTrue(try history.isCurrent(context))
        XCTAssertEqual(try history.records(expected: context), [record])
        try SharedFeedbackHistory(directory: directory).activate(userID: "first-account", channel: .testFlight)
        XCTAssertEqual(try history.records(expected: context), [record])
        XCTAssertEqual(try history.rememberedContext()?.channel, .testFlight)
    }

    func testAccountChangesFenceLateSavesAndDestructiveActionsIncludingABA() throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory)
        try history.activate(userID: "a", channel: .standard)
        let original = try XCTUnwrap(history.rememberedContext())
        try history.save(sharedFeedbackTestRecord(), expected: original)
        try history.activate(userID: "b", channel: .standard)
        try history.activate(userID: "a", channel: .standard)
        let current = try XCTUnwrap(history.rememberedContext())
        XCTAssertNotEqual(current.epoch, original.epoch)
        XCTAssertTrue(try history.records(expected: current).isEmpty)
        XCTAssertThrowsError(try history.save(sharedFeedbackTestRecord(), expected: original))
        try history.save(sharedFeedbackTestRecord("fb_new"), expected: current)
        XCTAssertThrowsError(try history.clear(expected: original))
        XCTAssertEqual(try history.records(expected: current).map(\.id), ["fb_new"])
    }

    func testReceiptsAreBoundedDeduplicatedAndContainNoDraftOrCredential() throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory)
        try history.activate(userID: "fixture-private-user-id", channel: .standard)
        let context = try XCTUnwrap(history.rememberedContext())
        for index in 0..<25 { try history.save(sharedFeedbackTestRecord("fb_\(index)"), expected: context) }
        try history.save(sharedFeedbackTestRecord("fb_24"), expected: context)
        let records = try history.records(expected: context)
        XCTAssertEqual(records.count, 20)
        XCTAssertEqual(records.first?.id, "fb_24")
        XCTAssertEqual(Set(records.map(\.id)).count, 20)
        let text = try String(contentsOf: directory.appendingPathComponent("receipts.json"), encoding: .utf8)
        for forbidden in ["fixture-private-user-id", "accessToken", "csrfToken", "description", "screenshots", "base64"] {
            XCTAssertFalse(text.contains(forbidden))
        }
        try history.clear(expected: context)
        XCTAssertTrue(try history.records(expected: context).isEmpty)
    }

    func testCorruptStateAndSymlinksArePreservedAndNeverOverwritten() throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory)
        let file = directory.appendingPathComponent("receipts.json")
        let corrupt = Data("{retained corrupt evidence".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try history.activate(userID: nil, channel: .standard))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        try FileManager.default.removeItem(at: file)
        let target = directory.appendingPathComponent("original.json")
        try corrupt.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try history.prepareForShare(channel: .standard))
        XCTAssertEqual(try Data(contentsOf: target), corrupt)
        try FileManager.default.removeItem(at: file)
        let other = SharedFeedbackHistory(directory: directory.appendingPathComponent("other"))
        try other.activate(userID: "another-owner", channel: .standard)
        let otherContext = try XCTUnwrap(other.rememberedContext())
        try other.save(sharedFeedbackTestRecord("fb_original"), expected: otherContext)
        let validTarget = directory.appendingPathComponent("other/receipts.json")
        let original = try Data(contentsOf: validTarget)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: validTarget)
        XCTAssertThrowsError(try history.prepareForShare(channel: .testFlight))
        XCTAssertEqual(try Data(contentsOf: validTarget), original)
    }

    func testPrivateLinkDomainAndFragmentAreStrictlyValidated() {
        for raw in ["https://evil.example/tickets/fb_test#access=secret", "http://support.yunle.fun/tickets/fb_test#access=secret", "https://support.yunle.fun/tickets/other#access=secret", "https://support.yunle.fun/tickets/fb_test", "https://support.yunle.fun/tickets/fb_test#access=first&access=second"] {
            XCTAssertNil(SupportFeedbackClient.ticketURL(.init(id: "fb_test", productId: "www", ticketId: "fb_test", ticketUrl: raw), requiringGuestAccess: true))
        }
        XCTAssertFalse(SupportFeedbackClient.identifier("accepted\n"))
    }

    func testExtensionChannelUsesContainingReceiptAndDevelopmentOverrides() {
        let test = URL(fileURLWithPath: "/sandboxReceipt"), production = URL(fileURLWithPath: "/receipt")
        XCTAssertEqual(FeedbackChannel.forShareExtension(receiptURL: test, remembered: nil, isDevelopment: false, isSimulator: false), .testFlight)
        XCTAssertEqual(FeedbackChannel.forShareExtension(receiptURL: production, remembered: .testFlight, isDevelopment: false, isSimulator: false), .standard)
        XCTAssertEqual(FeedbackChannel.forShareExtension(receiptURL: nil, remembered: .testFlight, isDevelopment: false, isSimulator: false), .testFlight)
        XCTAssertEqual(FeedbackChannel.forShareExtension(receiptURL: test, remembered: .testFlight, isDevelopment: true, isSimulator: false), .standard)
        XCTAssertEqual(FeedbackChannel.forShareExtension(receiptURL: test, remembered: .testFlight, isDevelopment: false, isSimulator: true), .standard)
    }
}
