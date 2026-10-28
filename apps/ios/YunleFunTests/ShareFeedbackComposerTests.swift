import Foundation
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

@MainActor
final class ShareFeedbackComposerTests: XCTestCase {
    func testOpeningAndTestFlightGuidanceNeverConnectOrSubmitImplicitly() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory)
        let context = try history.prepareForShare(channel: .testFlight)
        let importer = ShareImportFixture(image: try FeedbackScreenshot.prepare(sharedFeedbackTestImage()))
        let service = ShareSubmitFixture()
        let model = ShareFeedbackComposer(context: context, history: history, service: service, importer: importer, version: "0.2.0 (4)")
        await model.load([])
        XCTAssertFalse(model.usesGeneralFeedback)
        let initialImports = importer.calls, initialConnections = await service.connections
        XCTAssertEqual(initialImports, 0); XCTAssertEqual(initialConnections, 0)
        model.chooseGeneralFeedback(); await model.load([])
        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.screenshots.count, 1)
        let afterImports = importer.calls, afterConnections = await service.connections
        XCTAssertEqual(afterImports, 1); XCTAssertEqual(afterConnections, 0)
        let keys = await service.keys
        XCTAssertTrue(keys.isEmpty)
    }

    func testExplicitSubmissionFreezesContentAndSavesOnlyTheReceipt() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory), service = ShareSubmitFixture()
        let context = try history.prepareForShare(channel: .standard)
        let image = try FeedbackScreenshot.prepare(sharedFeedbackTestImage())
        let model = ShareFeedbackComposer(context: context, history: history, service: service,
            importer: ShareImportFixture(image: image), version: "0.2.0 (4)")
        await model.load([]); model.description = "Reviewed synthetic screenshot description"
        let reviewed = try XCTUnwrap(model.reviewedSubmission())
        model.description = "Changed after the review snapshot"; model.remove(image.id)
        await model.submit(reviewed)
        let submitted = await service.inputs
        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted.first?.description, "Reviewed synthetic screenshot description")
        XCTAssertEqual(submitted.first?.images, [image.data])
        XCTAssertEqual(model.phase, .received); XCTAssertTrue(model.recordWasSaved)
        XCTAssertTrue(model.screenshots.isEmpty); XCTAssertEqual(model.description, "")
        XCTAssertEqual(try history.records(expected: context).count, 1)
        let disk = try String(contentsOf: directory.appendingPathComponent("receipts.json"), encoding: .utf8)
        XCTAssertFalse(disk.contains(image.data.base64EncodedString()))
        XCTAssertFalse(disk.contains("Reviewed synthetic"))
    }

    func testTimeoutPreservesDraftAndManualRetryReusesSessionAndKey() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory), service = ShareSubmitFixture(failures: 1)
        let context = try history.prepareForShare(channel: .standard)
        let model = ShareFeedbackComposer(context: context, history: history, service: service,
            importer: ShareImportFixture(image: try FeedbackScreenshot.prepare(sharedFeedbackTestImage())), version: "0.2.0 (4)")
        await model.load([]); model.description = "Retained synthetic screenshot description"
        let reviewed = try XCTUnwrap(model.reviewedSubmission())
        await model.submit(reviewed)
        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.screenshots.count, 1); XCTAssertEqual(model.description, reviewed.description)
        XCTAssertNil(model.record); XCTAssertNotNil(model.error)
        let firstKeys = await service.keys
        XCTAssertEqual(firstKeys.count, 1)
        await model.submit(reviewed)
        let keys = await service.keys, connections = await service.connections
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(keys[0], keys[1]); XCTAssertEqual(connections, 1)
        XCTAssertEqual(model.phase, .received)
    }

    func testEditingTheReviewedImagesChangesTheSubmissionKey() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory), service = ShareSubmitFixture(failures: 2)
        let context = try history.prepareForShare(channel: .standard)
        let image = try FeedbackScreenshot.prepare(sharedFeedbackTestImage())
        let model = ShareFeedbackComposer(context: context, history: history, service: service,
            importer: ShareImportFixture(image: image), version: "0.2.0 (4)")
        await model.load([]); model.description = "Synthetic screenshot issue"
        await model.submit(try XCTUnwrap(model.reviewedSubmission()))
        model.remove(image.id)
        await model.submit(try XCTUnwrap(model.reviewedSubmission()))
        let keys = await service.keys
        XCTAssertEqual(keys.count, 2); XCTAssertNotEqual(keys[0], keys[1])
    }

    func testLateSubmissionCannotPersistAcrossAccountChangesIncludingABA() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory), service = ShareSubmitFixture(blocks: true)
        try history.activate(userID: "a", channel: .standard)
        let context = try XCTUnwrap(history.rememberedContext())
        let model = ShareFeedbackComposer(context: context, history: history, service: service,
            importer: ShareImportFixture(image: try FeedbackScreenshot.prepare(sharedFeedbackTestImage())), version: "0.2.0 (4)")
        await model.load([]); model.description = "Synthetic identity boundary issue"
        let reviewed = try XCTUnwrap(model.reviewedSubmission())
        let task = Task { await model.submit(reviewed) }
        await service.waitForSubmission()
        try history.activate(userID: "b", channel: .standard); try history.activate(userID: "a", channel: .standard)
        await service.release(); await task.value
        XCTAssertNil(model.record); XCTAssertFalse(model.recordWasSaved)
        XCTAssertEqual(model.screenshots.count, 1)
        let current = try XCTUnwrap(history.rememberedContext())
        XCTAssertTrue(try history.records(expected: current).isEmpty)
        await model.submit(reviewed)
        let keys = await service.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testCancellingAnInFlightSubmissionDiscardsItsLateReceipt() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let history = SharedFeedbackHistory(directory: directory), service = ShareSubmitFixture(blocks: true)
        let context = try history.prepareForShare(channel: .standard)
        let model = ShareFeedbackComposer(context: context, history: history, service: service,
            importer: ShareImportFixture(image: try FeedbackScreenshot.prepare(sharedFeedbackTestImage())), version: "0.2.0 (4)")
        await model.load([]); model.description = "Synthetic cancellation issue"
        let reviewed = try XCTUnwrap(model.reviewedSubmission())
        let task = Task { await model.submit(reviewed) }
        await service.waitForSubmission(); model.cancelWork()
        await service.release(); await task.value
        XCTAssertEqual(model.phase, .editing); XCTAssertNil(model.record)
        XCTAssertTrue(try history.records(expected: context).isEmpty)
        XCTAssertEqual(model.screenshots.count, 1)
    }
}

private final class ShareImportFixture: SharedScreenshotImporting, @unchecked Sendable {
    let image: FeedbackScreenshot
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(image: FeedbackScreenshot) { self.image = image }
    func load(_ providers: [NSItemProvider]) async throws -> [FeedbackScreenshot] { recordCall(); return [image] }
    private func recordCall() { lock.lock(); count += 1; lock.unlock() }
}

private actor ShareSubmitFixture: SupportFeedbackSubmitting {
    var connections = 0
    var keys: [String] = []
    var inputs: [SupportFeedbackSubmission] = []
    private var failures: Int
    private let blocks: Bool
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    init(failures: Int = 0, blocks: Bool = false) { self.failures = failures; self.blocks = blocks }
    func connectGuest() async throws -> SupportFeedbackAccess {
        connections += 1; return .init(csrfToken: "fixture-csrf", cookies: [])
    }
    func submit(_ submission: SupportFeedbackSubmission, key: String, access: SupportFeedbackAccess) async throws -> SupportFeedbackReceipt {
        keys.append(key); inputs.append(submission); entered = true; entry?.resume(); entry = nil
        if blocks { await withCheckedContinuation { gate = $0 } }
        if failures > 0 { failures -= 1; throw URLError(.timedOut) }
        return sharedFeedbackTestRecord().receipt
    }
    func waitForSubmission() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func release() { gate?.resume(); gate = nil }
}
