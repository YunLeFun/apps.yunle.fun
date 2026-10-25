import AppKit
import Network
import WebKit
import XCTest
@testable import YunleFunMac

@MainActor
final class MacWebPersistenceTests: XCTestCase {
    private var directory: URL!
    private var window: NSWindow?
    private var page: WKWebView?
    private var storeIDs = Set<UUID>()
    private var heldStores: [UUID: WKWebsiteDataStore] = [:]
    private static var storesUntilProcessExit: [WKWebsiteDataStore] = []
    private var server: CookieFixtureServer?
    private var resume: ResumeState?
    private var keepForRelaunch = false
    private let storageKey = "mac_profile_fixture"
    private var phase: String? { ProcessInfo.processInfo.environment["MAC_WEB_STORAGE_PHASE"] }

    private struct ResumeState: Codable {
        let processID: Int32
        let port: UInt16
        let identifiers: [UUID]
    }

    private var application: CloudApplication {
        CloudApplication(id: "mac-storage-fixture", name: "Storage fixture", websiteUrl: "https://profiles.invalid/")
    }

    override func setUp() async throws {
        // Initialize WebKit's main run loop before invoking its class-level
        // removal API; macOS 26.6.2 crashes if removal is its very first call.
        autoreleasepool {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let bootstrap = WKWebView(frame: .zero, configuration: configuration)
            bootstrap.stopLoading()
        }
        if let phase {
            guard ["seed", "restore", "cleanup"].contains(phase),
                  let rawID = ProcessInfo.processInfo.environment["MAC_WEB_STORAGE_RUN_ID"],
                  let runID = UUID(uuidString: rawID) else { throw FixtureFailure.invalidPhase }
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacWebPersistence-" + runID.uuidString)
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacWebPersistence-" + UUID().uuidString)
        }
        if phase == "cleanup" {
            try await recoverPendingCleanup(at: directory)
            return
        }
        if phase == "seed", FileManager.default.fileExists(atPath: directory.path) {
            throw FixtureFailure.existingRun
        }
        if phase == "restore" {
            resume = try JSONDecoder().decode(ResumeState.self, from: Data(contentsOf: directory.appendingPathComponent("resume.json")))
            storeIDs = Set(try XCTUnwrap(resume).identifiers)
        }
        let fixtureServer = try CookieFixtureServer(port: resume?.port)
        server = fixtureServer
        try await fixtureServer.start()
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        host.title = "WebKit storage test"
        host.isReleasedWhenClosed = false
        host.orderFront(nil)
        window = host
    }

    override func tearDown() async throws {
        // Release every WebView before removing its named data store. Never
        // enumerate profiles: only identifiers allocated by this test are used.
        await releasePage()
        window?.contentView = nil
        window?.close()
        window = nil
        server?.stop()
        server = nil
        if keepForRelaunch {
            // Keep only the data stores alive until this test-host process exits.
            // The explicit restore phase owns cleanup via the saved manifest.
            Self.storesUntilProcessExit = Array(heldStores.values)
            print("[Storage fixture] seed retained for next process at \(directory.path)")
            heldStores.removeAll()
            return
        }
        heldStores.removeAll()
        var pending = storeIDs
        for identifier in storeIDs {
            if await removeStore(identifier) { pending.remove(identifier) }
        }
        if pending.isEmpty {
            storeIDs.removeAll()
            if let directory, FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } else {
            // Keep an explicit ownership record when cleanup fails or times out.
            // A follow-up may delete these UUIDs without enumerating user stores.
            try persistCleanupRecord(pending)
            XCTFail("WebKit cleanup remains pending; exact UUIDs retained at \(cleanupRecord.path)")
        }
        directory = nil
    }

    func testAccountsAndGuestKeepIndependentStorageAcrossWebViewRecreation() async throws {
        // The verification script uses this explicit cleanup operation only if
        // a paired seed/restore run is interrupted. Normal tests never skip.
        if phase == "cleanup" { return }
        let repository = makeRepository()
        let identities: [(WebProfileRepository.Principal, String)] = [
            (.account("fixture-account-a"), "account-a-value"),
            (.account("fixture-account-b"), "account-b-value"),
            (.guest, "guest-value"),
        ]
        var selectedIDs: [UUID] = []

        if let resume {
            XCTAssertNotEqual(resume.processID, ProcessInfo.processInfo.processIdentifier, "The restore phase must run in a separate test-host process")
            print("[Storage fixture] cross-process restore PID \(resume.processID) -> \(ProcessInfo.processInfo.processIdentifier)")
            selectedIDs = resume.identifiers
        } else {
            for (principal, value) in identities {
                let selection = try repository.select(principal, application: application)
                selectedIDs.append(selection.identifier)
                try await loadPage(selection.identifier)
                let empty = try await contents()
                XCTAssertEqual(empty, "", "Another identity's localStorage must not be visible")
                let initialCookie = try await fixtureCookie()
                XCTAssertNil(initialCookie, "Another identity's persistent cookie must not be visible")
                let written = try await contents(writing: value)
                XCTAssertEqual(written, value)
                try await navigate(path: "/seed?value=" + value)
                try await assertPersistentCookie(value: value)
                let documentCookie = try await cookieVisibleToPage()
                XCTAssertEqual(documentCookie, value)
                await releasePage()
            }
            XCTAssertEqual(Set(selectedIDs).count, identities.count)
            if phase == "seed" {
                let port = try XCTUnwrap(server?.port)
                let state = ResumeState(processID: ProcessInfo.processInfo.processIdentifier, port: port, identifiers: selectedIDs)
                try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("resume.json"), options: .atomic)
                keepForRelaunch = true
                return
            }
        }

        // Recreate both the repository and each WKWebView/configuration. This
        // in-process path retains stores for WebKit's asynchronous persistence,
        // as the runtime does. The paired seed/restore script additionally
        // proves disk recovery after a normal test-host process exit.
        let restoredRepository = makeRepository()
        for (index, identity) in identities.enumerated() {
            let (principal, value) = identity
            let restored = try restoredRepository.select(principal, application: application)
            XCTAssertEqual(restored.identifier, selectedIDs[index])
            try await loadPage(restored.identifier)
            let saved = try await contents()
            XCTAssertEqual(saved, value)
            try await assertPersistentCookie(value: value)
            let documentCookie = try await cookieVisibleToPage()
            XCTAssertEqual(documentCookie, value)
            await releasePage()
        }
    }

    private func makeRepository() -> WebProfileRepository {
        WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: "mac-storage-test")
    }

    private var cleanupRecord: URL { directory.appendingPathComponent("pending-webkit-stores.json") }

    private func recoverPendingCleanup(at folder: URL) async throws {
        // Only inspect the requested run's ownership manifest. Never enumerate
        // WebKit profiles or remove another potentially running test's stores.
        let record = folder.appendingPathComponent("pending-webkit-stores.json")
        guard FileManager.default.fileExists(atPath: record.path) else { return }
        let raw = try JSONDecoder().decode([String].self, from: Data(contentsOf: record))
        let identifiers = try raw.map { try XCTUnwrap(UUID(uuidString: $0)) }
        var remaining: [String] = []
        for identifier in identifiers {
            if !(await removeStore(identifier)) { remaining.append(identifier.uuidString) }
        }
        if remaining.isEmpty {
            try FileManager.default.removeItem(at: folder)
        } else {
            try JSONEncoder().encode(remaining).write(to: record, options: .atomic)
            XCTFail("Fixture cleanup remains pending at \(record.path)")
            throw FixtureFailure.previousCleanupFailed
        }
    }

    private func removeStore(_ identifier: UUID) async -> Bool {
        let removed = XCTestExpectation(description: "Remove test-owned WebKit profile \(identifier)")
        var removalError: Error?
        WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
            removalError = error
            removed.fulfill()
        }
        let result = await XCTWaiter.fulfillment(of: [removed], timeout: 10)
        XCTAssertEqual(result, .completed, "WebKit profile cleanup must finish: \(identifier)")
        if result == .completed { XCTAssertNil(removalError, "Could not remove test-owned WebKit profile \(identifier)") }
        return result == .completed && removalError == nil
    }

    private func persistCleanupRecord(_ identifiers: Set<UUID>) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(identifiers.map(\.uuidString).sorted()).write(to: cleanupRecord, options: .atomic)
    }

    private func loadPage(_ identifier: UUID) async throws {
        XCTAssertNil(page, "Release the previous page before rebuilding WebKit")
        storeIDs.insert(identifier)
        try persistCleanupRecord(storeIDs)
        let configuration = WKWebViewConfiguration()
        let store = heldStores[identifier] ?? WKWebsiteDataStore(forIdentifier: identifier)
        heldStores[identifier] = store
        configuration.websiteDataStore = store
        configuration.preferences.inactiveSchedulingPolicy = .none
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 420), configuration: configuration)
        XCTAssertTrue(configuration.websiteDataStore.isPersistent)
        page = web
        window?.contentView = web
        try await navigate(path: "/")
    }

    private func navigate(path: String) async throws {
        let web = try XCTUnwrap(page)
        let probe = FixtureNavigation()
        web.navigationDelegate = probe
        defer { web.navigationDelegate = nil }
        let baseURL = try XCTUnwrap(server?.baseURL)
        web.load(URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: baseURL))))
        guard await XCTWaiter.fulfillment(of: [probe.finished], timeout: 5) == .completed else {
            throw FixtureFailure.navigationTimedOut
        }
        if let error = probe.error { throw error }
    }

    private func contents(writing value: String? = nil) async throws -> String {
        let web = try XCTUnwrap(page)
        let result = try await WebStoragePageFixture.evaluate(in: web, script: """
        if (value !== null) {
          localStorage.setItem(key, value);
        }
        return localStorage.getItem(key) || '';
        """, arguments: ["key": storageKey, "value": value as Any? ?? NSNull()])
        return try XCTUnwrap(result as? String)
    }

    private func cookieVisibleToPage() async throws -> String {
        let result = try await WebStoragePageFixture.evaluate(in: XCTUnwrap(page), script: """
        return document.cookie.split('; ').find(item => item.startsWith(key + '='))?.split('=')[1] || '';
        """, arguments: ["key": storageKey])
        return try XCTUnwrap(result as? String)
    }

    private func fixtureCookie() async throws -> HTTPCookie? {
        let cookieStore = try XCTUnwrap(page?.configuration.websiteDataStore.httpCookieStore)
        let completed = XCTestExpectation(description: "Read synthetic profile cookies")
        var cookies: [HTTPCookie] = []
        // Keep the callback API so the waiter can bound an unresponsive WebKit
        // process; awaiting allCookies() directly has no cancellation timeout.
        cookieStore.getAllCookies { result in
            cookies = result
            completed.fulfill()
        }
        guard await XCTWaiter.fulfillment(of: [completed], timeout: 5) == .completed else {
            throw FixtureFailure.cookieReadTimedOut
        }
        return cookies.first { $0.name == storageKey && $0.domain == "127.0.0.1" }
    }

    private func assertPersistentCookie(value: String) async throws {
        let saved = try await fixtureCookie()
        let cookie = try XCTUnwrap(saved)
        XCTAssertEqual(cookie.value, value)
        XCTAssertFalse(cookie.isSessionOnly)
        XCTAssertFalse(cookie.isSecure, "The fixture uses loopback HTTP without modifying production TLS policy")
        XCTAssertGreaterThan(try XCTUnwrap(cookie.expiresDate), Date())
    }

    private func releasePage() async {
        let released = WeakPageReference(page)
        page?.stopLoading()
        page?.navigationDelegate = nil
        page?.uiDelegate = nil
        page?.removeFromSuperview()
        window?.contentView = nil
        page = nil
        // WebKit/Objective-C may release a page at the next run-loop turn.
        // Bound that wait instead of retaining a page solely for teardown.
        for _ in 0..<100 {
            if released.value == nil { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(released.value, "The previous WKWebView must be destroyed before reconstruction or store removal")
    }

    private final class WeakPageReference {
        weak var value: WKWebView?
        init(_ value: WKWebView?) { self.value = value }
    }

    private enum FixtureFailure: Error { case cookieReadTimedOut, navigationTimedOut, previousCleanupFailed, invalidPhase, existingRun }
}

@MainActor
private final class FixtureNavigation: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Loopback storage fixture loaded")
    private(set) var error: Error?
    private var completed = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { complete(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { complete(error) }

    private func complete(_ error: Error? = nil) {
        guard !completed else { return }
        completed = true
        self.error = error
        finished.fulfill()
    }
}

/// The Testing host alone has network.server. Bind only to loopback on a
/// system-assigned port and serve a fixed HTML response with synthetic cookies.
private final class CookieFixtureServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mac-web-persistence-fixture")
    private var connections: [UUID: NWConnection] = [:]

    var baseURL: URL? { listener.port.flatMap { URL(string: "http://127.0.0.1:\($0.rawValue)/") } }
    var port: UInt16? { listener.port?.rawValue }

    init(port: UInt16? = nil) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        let readiness = ListenerReadiness()
        listener.stateUpdateHandler = { state in readiness.receive(state) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard await XCTWaiter.fulfillment(of: [readiness.ready], timeout: 5) == .completed else { throw Failure.startTimedOut }
        try XCTUnwrap(readiness.result).get()
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let value = URLComponents(string: "http://localhost" + target)?.queryItems?.first(where: { $0.name == "value" })?.value
            let body = "<!doctype html><meta charset=utf-8><title>mac-storage-probe</title><p>Local WebKit storage fixture</p>"
            var headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n"
            if target.hasPrefix("/seed?"), let value, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) {
                headers += "Set-Cookie: mac_profile_fixture=\(value); Max-Age=86400; Path=/; SameSite=Lax\r\n"
            }
            let response = headers + "Content-Length: \(body.utf8.count)\r\n\r\n" + body
            connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
                connection.cancel()
                self?.connections.removeValue(forKey: id)
            })
        }
    }

    private enum Failure: Error { case startTimedOut }
}

/// NWListener delivers states on its queue while start() resumes on a Swift
/// executor. Protect that one shared result and fulfill readiness exactly once.
private final class ListenerReadiness: @unchecked Sendable {
    let ready = XCTestExpectation(description: "Loopback HTTP fixture is listening")
    private let lock = NSLock()
    private var outcome: Result<Void, NWError>?

    var result: Result<Void, NWError>? {
        lock.lock(); defer { lock.unlock() }
        return outcome
    }

    func receive(_ state: NWListener.State) {
        let next: Result<Void, NWError>
        switch state {
        case .ready: next = .success(())
        case .failed(let error): next = .failure(error)
        default: return
        }
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = next
        lock.unlock()
        ready.fulfill()
    }
}
