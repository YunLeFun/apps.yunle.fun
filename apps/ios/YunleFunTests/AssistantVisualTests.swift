import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class AssistantVisualTests: XCTestCase {
    func testNativeReplyAndCardsInLightMode() async throws { try await render(accessibility: false) }
    func testNativeReplySupportsDarkAccessibilityText() async throws { try await render(accessibility: true) }
    func testWelcomeInLightMode() async throws { try await render(accessibility: false, conversation: false) }
    func testWelcomeInDarkMode() async throws { try await render(accessibility: false, conversation: false, colorScheme: .dark) }
    func testWelcomeSupportsDarkAccessibilityText() async throws { try await render(accessibility: true, conversation: false) }
    func testSignupTemplateAndCanvasRenderInTheSameHost() async throws {
        let host = UUID().uuidString.lowercased() + ".cards.test"
        let auth = AuthHTTPFixture(replies: [(200, #"{"sub":"alice","status":"ACTIVE"}"#)])
        AuthHTTPProtocol.register(host, fixture: auth)
        defer { AuthHTTPProtocol.unregister(host) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState()
        state.activeID = "alice"
        state.accounts = [SavedAccount(user: AccountUser(id: "alice"), credential: AccountCredential(
            accessToken: "fixture-only", refreshToken: "fixture-only", expiresAt: Date().addingTimeInterval(3600)))]
        let accounts = AccountStore(session: AccountSession(
            api: CloudbaseAuthService(session: URLSession(configuration: configuration), origin: URL(string: "https://" + host)!),
            vault: BillingMemoryVault(data: try JSONEncoder().encode(state))
        ))
        await accounts.restore()
        let signup = try XCTUnwrap(ConversationCardReference(type: "team.signup", instanceID: "0ebd1cfc-e4cf-4a50-bf48-55c77709c04a"))
        let board = try XCTUnwrap(ConversationCardReference(type: "play.board", instanceID: "9fad9eef-b0da-4b0f-8161-79bfc59c88bc"))
        let service = try VisualNativeCardService(signup: signup, board: board)
        let chat = AssistantStore(accounts: accounts, cardService: service)
        let controller = UIHostingController(rootView: ScrollView {
            VStack(spacing: 12) {
                NativeConversationCardView(reference: signup, fallback: "报名摘要")
                NativeConversationCardView(reference: board, fallback: "棋盘摘要")
            }.padding(16)
        }
        .environmentObject(accounts).environmentObject(chat)
        .environment(\.scenePhase, .active).preferredColorScheme(.light))
        let image = try await snapshot(controller)
        let subscriptions = await service.subscriptions
        XCTAssertEqual(subscriptions, Set([signup, board]))
        let attachment = XCTAttachment(image: image)
        attachment.name = "native-conversation-cards"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHistorySheetListsSavedConversations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = AssistantHistory(directory: directory)
        let questions = ["有没有适合整理灵感的工具？", "推荐几个好玩的应用", "找一个适合写代码的开发工具"]
        for (index, question) in questions.enumerated() {
            history.save(try XCTUnwrap(AssistantHistory.conversation(id: "thread-\(index)", messages: [
                AssistantMessage(id: "q\(index)", role: .user, content: question),
                AssistantMessage(id: "a\(index)", role: .assistant, content: "回复")
            ], now: Date().addingTimeInterval(Double(-3600 * 26 * index)))), accountID: "alice")
        }
        let chat = AssistantStore(accounts: BillingAccounts(), service: AssistantVisualService(), wallet: AssistantWalletFixture(), history: history)
        XCTAssertEqual(chat.history.count, 3)
        let controller = UIHostingController(rootView: AssistantHistoryView { _, _ in true }.environmentObject(chat))
        let image = try await snapshot(controller)
        let attachment = XCTAttachment(image: image)
        attachment.name = "assistant-history-sheet"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func snapshot(_ controller: UIViewController) async throws -> UIImage {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000); controller.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
    private func render(accessibility: Bool, conversation: Bool = true, colorScheme: ColorScheme? = nil) async throws {
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
        if conversation { chat.draft = "有没有适合整理灵感的工具？"; await chat.send()?.value }
        else { await chat.refreshAccess() }
        let catalog = CatalogStore(service: AssistantVisualCatalog(), cacheURL: directory.appendingPathComponent("catalog.json"))
        await catalog.load()
        let library = HomeLibrary(directory: directory.appendingPathComponent("home"), accountID: "alice")
        let runtime = NativeWebRuntime(), wallet = WalletStore(accounts: accounts, service: walletService)
        let log = BillingLog()
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet, service: walletService,
            commerce: BillingCommerceFixture(log: log, gate: nil, outcome: .cancelled, unfinished: []),
            journal: PurchaseOwnershipJournal(vault: BillingMemoryVault()))
        let appearance = colorScheme ?? (accessibility ? .dark : .light)
        let content = NavigationStack { AssistantView() }
            .environmentObject(chat).environmentObject(accounts).environmentObject(catalog)
            .environmentObject(library).environmentObject(runtime).environmentObject(wallet).environmentObject(purchases)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .preferredColorScheme(appearance)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000); controller.view.layoutIfNeeded()
        XCTAssertNil(chat.error)
        if conversation {
            XCTAssertEqual(chat.messages.last?.status, .done)
            XCTAssertEqual(chat.messages.last?.cards.count, 1)
            XCTAssertNotNil(chat.messages.last?.cards.first?.resolve(in: catalog.applications))
        } else {
            XCTAssertTrue(chat.messages.isEmpty)
            XCTAssertTrue(chat.draft.isEmpty)
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        let screen = conversation ? "reply" : "welcome"
        let variant = appearance == .dark ? "dark" : "light"
        attachment.name = "assistant-\(screen)-\(variant)\(accessibility ? "-accessibility" : "")"
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


private actor VisualNativeCardService: NativeConversationCardServing {
    let documents: [ConversationCardReference: NativeConversationCardSnapshot]
    private(set) var subscriptions: Set<ConversationCardReference> = []

    init(signup: ConversationCardReference, board: ConversationCardReference) throws {
        let signupJSON = """
        {"schemaVersion":1,"reference":{"type":"team.signup","instanceId":"\(signup.instanceId)"},
        "revision":2,"finished":false,"fallbackText":"报名摘要","template":{"schemaVersion":1,"components":[
        {"kind":"text","field":"event"},{"kind":"title","field":"title"},{"kind":"seats","filled":"count","total":"capacity"},
        {"kind":"button","action":"signup.join"}]},"data":{"event":"周末一起玩","title":"联机组队","count":1,"capacity":4},
        "actions":{"signup.join":{"label":"报名","enabled":true}}}
        """
        let boardJSON = """
        {"schemaVersion":1,"reference":{"type":"play.board","instanceId":"\(board.instanceId)"},
        "revision":3,"finished":false,"fallbackText":"棋盘摘要","template":{"schemaVersion":1,"components":[
        {"kind":"title","field":"title"},{"kind":"gomoku","field":"board","action":"board.place"}]},
        "data":{"title":"联机五子棋","board":{"schemaVersion":1,"boardId":"\(board.instanceId)","scene":{"schemaVersion":1,"size":9,
        "palette":{"board":"#e4b578","grid":"#583820","black":"#242027","white":"#fff7e9"},"interaction":{"gesture":"drag-to-place","action":"place"}},
        "revision":3,"status":"playing","seat":"white","turn":"white","winner":null,"pieces":[{"row":4,"column":4,"color":"black"}]}},
        "actions":{"board.place":{"label":"落子","enabled":true}}}
        """
        let signupDocument = try JSONDecoder().decode(NativeConversationCardSnapshot.self, from: Data(signupJSON.utf8))
        let boardDocument = try JSONDecoder().decode(NativeConversationCardSnapshot.self, from: Data(boardJSON.utf8))
        try signupDocument.validate(for: signup)
        try boardDocument.validate(for: board)
        documents = [signup: signupDocument, board: boardDocument]
    }

    func load(_ reference: ConversationCardReference, identity: AuthorizedAccount) async throws -> NativeConversationCardSnapshot {
        guard let document = documents[reference], identity.userID == "alice" else { throw NativeConversationCardError.missing }
        return document
    }

    func act(_ action: NativeConversationCardAction, on reference: ConversationCardReference, identity: AuthorizedAccount)
        async throws -> NativeConversationCardSnapshot { throw NativeConversationCardError.unavailable }

    func events(_ reference: ConversationCardReference, identity: AuthorizedAccount)
        async throws -> AsyncThrowingStream<NativeConversationCardSnapshot, Error> {
        let document = try await load(reference, identity: identity)
        subscriptions.insert(reference)
        return AsyncThrowingStream { continuation in
            continuation.yield(document)
            continuation.finish()
        }
    }
}
