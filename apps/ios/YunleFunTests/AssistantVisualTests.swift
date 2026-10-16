import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class AssistantVisualTests: XCTestCase {
    func testNativeReplyAndCardsInLightMode() async throws { try await render(accessibility: false) }
    func testNativeReplySupportsDarkAccessibilityText() async throws { try await render(accessibility: true) }
    private func render(accessibility: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID().uuidString.lowercased() + ".assistant.test"
        let fixture = AuthHTTPFixture(replies: [(200, #"{"sub":"alice","name":"样例账号","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: fixture); defer { AuthHTTPProtocol.unregister(host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState(); state.activeID = "alice"
        state.accounts = [SavedAccount(user: AccountUser(id: "alice"), credential: AccountCredential(
            accessToken: "visual-only", refreshToken: "not-used", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: config),
            origin: URL(string: "https://\(host)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        let walletService = AssistantWalletFixture()
        let chat = AssistantStore(accounts: accounts, service: AssistantVisualService(), wallet: walletService)
        chat.draft = "有没有适合整理灵感的工具？"; await chat.send()?.value
        let catalog = CatalogStore(service: AssistantVisualCatalog(), cacheURL: directory.appendingPathComponent("catalog.json"))
        await catalog.load()
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"), accountID: "alice")
        let runtime = NativeWebRuntime(), wallet = WalletStore(accounts: accounts, service: walletService)
        let log = BillingLog()
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: walletService,
            commerce: BillingCommerceFixture(log: log, gate: nil, outcome: .cancelled, unfinished: []),
            journal: PurchaseOwnershipJournal(vault: BillingMemoryVault()))
        let content = NavigationStack { AssistantView() }
            .environmentObject(chat).environmentObject(accounts).environmentObject(catalog)
            .environmentObject(library).environmentObject(runtime).environmentObject(wallet).environmentObject(purchases)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .preferredColorScheme(accessibility ? .dark : .light)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000); controller.view.layoutIfNeeded()
        XCTAssertEqual(chat.messages.last?.status, .done); XCTAssertNil(chat.error)
        XCTAssertEqual(chat.messages.last?.cards.count, 1)
        XCTAssertNotNil(chat.messages.last?.cards.first?.resolve(in: catalog.applications))
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = accessibility ? "assistant-fixture-dark-accessibility" : "assistant-fixture-light"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(library.snapshot.applications.isEmpty, "Viewing a suggestion must not install it")
        XCTAssertTrue(runtime.applications.isEmpty)
    }
}
private struct AssistantVisualCatalog: CatalogServing {
    func applications() async throws -> [CloudApplication] {
        [CloudApplication(id: "visual-notes", name: "灵感笔记", marketShortName: "visual-notes",
                          description: "随手记录，慢慢整理。", emoji: "📝", isPublic: true)]
    }
}
private struct AssistantVisualService: AssistantServing {
    func events(input: AssistantRunInput, identity: AuthorizedAccount) async throws -> AsyncThrowingStream<AssistantEvent, Error> {
        let text = "## 把灵感留住\n可以先试试**灵感笔记**，把零散想法记下来，再慢慢整理。"
        let events = try [
            assistantEvent(["type": "RUN_STARTED", "threadId": input.threadId, "runId": input.runId]),
            assistantEvent(["type": "TEXT_MESSAGE_START", "messageId": "reply", "role": "assistant"]),
            assistantEvent(["type": "TEXT_MESSAGE_CONTENT", "messageId": "reply", "delta": text]),
            assistantEvent(["type": "TOOL_CALL_START", "toolCallId": "search", "toolCallName": "search_apps"]),
            assistantEvent(["type": "TOOL_CALL_RESULT", "toolCallId": "search", "content": #"{"apps":[{"id":"visual-notes","slug":"visual-notes","name":"灵感笔记","reason":"适合随手记下想法。"}]}"#]),
            assistantEvent(["type": "TEXT_MESSAGE_END", "messageId": "reply"]),
            assistantEvent(["type": "RUN_FINISHED", "threadId": input.threadId, "runId": input.runId]),
        ]
        return AsyncThrowingStream { continuation in events.forEach { continuation.yield($0) }; continuation.finish() }
    }
    func search(query: String, identity: AuthorizedAccount) async throws -> [AssistantAppCard] { [] }
}
