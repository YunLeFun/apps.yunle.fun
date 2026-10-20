import XCTest
@testable import YunleFun

final class AssistantHistoryTests: XCTestCase {
    private var directory: URL!
    private var history: AssistantHistory!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        history = AssistantHistory(directory: directory)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private func conversation(_ id: String, at seconds: Double, question: String = "找工具") -> AssistantConversation {
        AssistantHistory.conversation(id: id, messages: [
            AssistantMessage(id: id + "-q", role: .user, content: question),
            AssistantMessage(id: id + "-a", role: .assistant, content: "回复",
                             cards: [AssistantAppCard(applicationID: "app", slug: "app", name: "应用", reason: nil)])
        ], now: Date(timeIntervalSince1970: seconds))!
    }

    func testSaveAndLoadRoundTripsNewestFirst() {
        history.save(conversation("old", at: 100), accountID: "alice")
        history.save(conversation("new", at: 200), accountID: "alice")
        let loaded = history.load(accountID: "alice")
        XCTAssertEqual(loaded.map(\.id), ["new", "old"])
        XCTAssertEqual(loaded.first?.messages.last?.cards.first?.name, "应用")
        XCTAssertEqual(loaded.first?.updatedAt, Date(timeIntervalSince1970: 200))
    }
    func testSavingAnExistingConversationReplacesIt() {
        history.save(conversation("a", at: 100), accountID: "alice")
        history.save(conversation("a", at: 300, question: "改过的问题"), accountID: "alice")
        XCTAssertEqual(history.load(accountID: "alice").map(\.title), ["改过的问题"])
    }
    func testKeepsOnlyTheNewestTwentyConversations() {
        for index in 0..<25 { history.save(conversation("c\(index)", at: Double(index)), accountID: "alice") }
        let loaded = history.load(accountID: "alice")
        XCTAssertEqual(loaded.count, AssistantHistory.limit)
        XCTAssertEqual(loaded.first?.id, "c24"); XCTAssertEqual(loaded.last?.id, "c5")
    }
    func testAccountsAreIsolatedAndFilesDoNotNameTheAccount() {
        history.save(conversation("a", at: 1), accountID: "alice")
        history.save(conversation("b", at: 2), accountID: "bob")
        XCTAssertEqual(history.load(accountID: "alice").map(\.id), ["a"])
        XCTAssertEqual(history.load(accountID: "bob").map(\.id), ["b"])
        XCTAssertFalse(history.fileURL(accountID: "alice").lastPathComponent.contains("alice"))
        XCTAssertNotEqual(history.fileURL(accountID: "alice"), history.fileURL(accountID: "bob"))
        let excluded = try? history.fileURL(accountID: "alice").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }
    func testDeleteAndDeleteAllOnlyTouchOneAccount() {
        history.save(conversation("a1", at: 1), accountID: "alice")
        history.save(conversation("a2", at: 2), accountID: "alice")
        history.save(conversation("b", at: 3), accountID: "bob")
        XCTAssertEqual(history.delete("a2", accountID: "alice").map(\.id), ["a1"])
        history.deleteAll(accountID: "alice")
        XCTAssertTrue(history.load(accountID: "alice").isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.fileURL(accountID: "alice").path))
        XCTAssertEqual(history.load(accountID: "bob").map(\.id), ["b"])
    }
    func testSnapshotDropsInFlightStateAndNeedsAQuestion() throws {
        XCTAssertNil(AssistantHistory.conversation(id: "t", messages: []))
        let saved = try XCTUnwrap(AssistantHistory.conversation(id: "t", messages: [
            AssistantMessage(id: "q", role: .user, content: "  一个\n很长的问题  " + String(repeating: "长", count: 60)),
            AssistantMessage(id: "a", role: .assistant, content: "半截", status: .streaming, toolStatus: "正在检索应用"),
            AssistantMessage(id: "f", role: .assistant, content: "", status: .failed)
        ]))
        XCTAssertEqual(saved.messages.map(\.status), [.done, .stopped, .failed])
        XCTAssertNil(saved.messages[1].toolStatus)
        XCTAssertEqual(saved.title.count, AssistantHistory.titleLength)
        XCTAssertTrue(saved.title.hasPrefix("一个 很长的问题"))
    }
}

@MainActor
final class AssistantStoreHistoryTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    func testFinishedRunIsSavedForTheSignedInAccountOnly() async {
        let accounts = BillingAccounts(), history = AssistantHistory(directory: directory)
        let store = AssistantStore(accounts: accounts, service: AssistantFixture(), wallet: AssistantWalletFixture(), history: history)
        store.draft = "找写代码的工具"; await store.send()?.value
        XCTAssertEqual(store.history.map(\.id), [store.threadID])
        XCTAssertEqual(store.history.first?.title, "找写代码的工具")
        XCTAssertEqual(history.load(accountID: "alice").first?.messages.map(\.role), [.user, .assistant])
        accounts.select("bob"); store.identityChanged()
        XCTAssertTrue(store.history.isEmpty, "Another account never sees the previous account's history")
        XCTAssertTrue(history.load(accountID: "bob").isEmpty)
        accounts.select(nil); store.identityChanged()
        XCTAssertTrue(store.history.isEmpty)
        accounts.select("alice"); store.identityChanged()
        XCTAssertEqual(store.history.count, 1)
    }
    func testOpenContinuesTheSavedThreadAndUnchangedConversationsKeepTheirOrder() async throws {
        let accounts = BillingAccounts(), history = AssistantHistory(directory: directory)
        let store = AssistantStore(accounts: accounts, service: AssistantFixture(), wallet: AssistantWalletFixture(), history: history)
        store.draft = "第一个问题"; await store.send()?.value
        let first = store.threadID
        store.reset()
        store.draft = "第二个问题"; await store.send()?.value
        XCTAssertEqual(store.history.map(\.title), ["第二个问题", "第一个问题"])
        store.open(first)
        XCTAssertEqual(store.threadID, first)
        XCTAssertEqual(store.messages.first?.content, "第一个问题")
        store.stop(); store.reset()
        XCTAssertEqual(store.history.map(\.title), ["第二个问题", "第一个问题"], "Opening without changes must not reorder history")
    }
    func testDeleteAndDeleteAll() async {
        let accounts = BillingAccounts(), history = AssistantHistory(directory: directory)
        let store = AssistantStore(accounts: accounts, service: AssistantFixture(), wallet: AssistantWalletFixture(), history: history)
        store.draft = "问题一"; await store.send()?.value; store.reset()
        store.draft = "问题二"; await store.send()?.value
        store.delete(store.history.last!.id)
        XCTAssertEqual(store.history.map(\.title), ["问题二"])
        store.deleteAll()
        XCTAssertTrue(store.history.isEmpty)
        store.stop()
        XCTAssertTrue(history.load(accountID: "alice").isEmpty, "Leaving after clearing must not save the open conversation again")
    }
    func testDeletingTheOpenConversationDuringAReplyNeverRestoresIt() async throws {
        try await deleteDuringActiveReply(clearAll: false)
    }
    func testClearingHistoryDuringAReplyNeverRestoresIt() async throws {
        try await deleteDuringActiveReply(clearAll: true)
    }
    private func deleteDuringActiveReply(clearAll: Bool) async throws {
        let accounts = BillingAccounts(), history = AssistantHistory(directory: directory)
        let first = AssistantStore(accounts: accounts, service: AssistantFixture(), wallet: AssistantWalletFixture(), history: history)
        first.draft = "问题一"; await first.send()?.value
        let thread = first.threadID
        let service = AssistantFixture(automatic: false)
        let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture(), history: history)
        store.open(thread)
        store.draft = "追问"; let run = store.send()
        await fulfillment(of: [service.started], timeout: 5)
        XCTAssertTrue(store.running)
        if clearAll { store.deleteAll() } else { store.delete(thread) }
        XCTAssertFalse(store.running, "Deleting the open conversation ends its reply")
        if let input = await service.inputs.last { try await service.emitAndFinish(input) }
        await run?.value
        store.stop()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(history.load(accountID: "alice").isEmpty, "A late reply must not save the deleted conversation again")
    }
    func testOpeningTheOldestConversationWhileANewReplyStreams() async throws {
        let accounts = BillingAccounts(), history = AssistantHistory(directory: directory)
        for index in 0..<AssistantHistory.limit {
            history.save(try XCTUnwrap(AssistantHistory.conversation(id: "t\(index)",
                messages: [AssistantMessage(id: "q\(index)", role: .user, content: "问题\(index)")],
                now: Date(timeIntervalSince1970: Double(index)))), accountID: "alice")
        }
        let service = AssistantFixture(automatic: false)
        let store = AssistantStore(accounts: accounts, service: service, wallet: AssistantWalletFixture(), history: history)
        XCTAssertEqual(store.history.last?.id, "t0")
        store.draft = "新问题"; _ = store.send()
        await fulfillment(of: [service.started], timeout: 5)
        store.open("t0")
        XCTAssertEqual(store.threadID, "t0", "Saving the stopped reply must not lose the selected conversation")
        XCTAssertEqual(store.messages.first?.content, "问题0")
    }
    func testGuestsAndStoresWithoutHistoryNeverWrite() async {
        let accounts = BillingAccounts(); accounts.select(nil)
        let history = AssistantHistory(directory: directory)
        let store = AssistantStore(accounts: accounts, service: AssistantFixture(), wallet: AssistantWalletFixture(), history: history)
        store.draft = "问题"; await store.send()?.value; store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

final class AssistantComposerTests: XCTestCase {
    func testOnlyASingleTypedNewlineSubmits() {
        XCTAssertEqual(AssistantComposer.submission(from: "记账", to: "记账\n"), "记账")
        XCTAssertEqual(AssistantComposer.submission(from: "记账工具", to: "记账\n工具"), "记账工具", "Return in the middle of the text")
        XCTAssertEqual(AssistantComposer.submission(from: "", to: "\n"), "")
        XCTAssertNil(AssistantComposer.submission(from: "记", to: "记账"), "Typing another character")
        XCTAssertNil(AssistantComposer.submission(from: "", to: "粘贴的问题\n"), "A paste ending in a newline stays a draft")
        XCTAssertNil(AssistantComposer.submission(from: "第一行\n", to: "第一行"), "Deleting a newline")
        XCTAssertNil(AssistantComposer.submission(from: "ab", to: "a\nc"))
    }
}
