import Foundation
import Security
import SwiftUI
import WebKit
import XCTest
@testable import YunleFun

/// Opt-in iOS acceptance: real managed auth/list reads, then a clearly labelled
/// historical-author HTTP replay through the actual list/editor/preview UI.
/// An operator drives the native UI and writes the completion marker only after
/// list -> detail -> editor -> cancel -> preview -> pause -> resume is observed.
@MainActor
final class PublishingCandidateLiveTests: XCTestCase {
    func testHistoricalAuthorListEditorAndOwnerPreview() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUNLEFUN_LIVE_PUBLISHING_CANDIDATE"] == "1" else { throw XCTSkip("Requires explicit owned-simulator acceptance") }
        guard env["YUNLEFUN_OWNED_SIMULATOR_UDID"] == env["SIMULATOR_UDID"], env["SIMULATOR_UDID"] != nil else { return XCTFail("Simulator ownership differs") }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only")
        #endif
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/preflight-account.json")
        let mode = try FileManager.default.attributesOfItem(atPath: input.path)[.posixPermissions] as? NSNumber
        guard mode.map({ $0.intValue & 0o077 == 0 }) == true else { return XCTFail("Input must be private") }
        let data = try Data(contentsOf: input); try FileManager.default.removeItem(at: input)
        let credential = try JSONDecoder().decode(Credential.self, from: data)
        guard credential.id == "production-zero-balance", credential.environment == "production", credential.username == "ylf_prod_zero" else { return XCTFail("Only the managed synthetic identity is allowed") }
        let directory = cache.appendingPathComponent("PublishingCandidate-" + UUID().uuidString)
        let keychain = "fun.yunle.apps.publishing-candidate." + UUID().uuidString
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychain)))
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychain] as CFDictionary) }
        try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
        var phase = "authorization"
        do {
            let identity = try await accounts.authorization(forceRefresh: true)
            phase = "live-list"
            let liveRecords = try await PublishingService().applications(identity: identity)
            phase = "live-access"
            let liveAccess = try await PublishingService().access(identity: identity)
            phase = "historical-replay"
            let host = UUID().uuidString.lowercased() + ".publishing.test"
            var draft = ApplicationDraft()
            draft.name = "历史作者回归样例"; draft.slug = "historical-author"
            draft.websiteUrl = "https://cook.yunle.fun/home"
            draft.privacyPolicyUrl = "https://www.yunle.fun/privacy"; draft.supportUrl = "https://apps.yunle.fun"
            var record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
            record.merge(["_id": "historical-author-fixture", "ownerUid": identity.userID,
                "writeVersion": String(repeating: "a", count: 64), "updatedAt": (Date().timeIntervalSince1970 * 1000).rounded(.down),
                "publicationStatus": "published", "currentRevisionId": "historical-version", "publishedSubmissionId": "historical-version",
                "latestSubmission": ["_id": "historical-version", "appId": "historical-author-fixture", "submitterUid": "historical-publisher",
                    "revision": 1, "reviewStatus": "approved", "snapshot": record]]) { _, new in new }
            CandidatePublishingHTTP.configure(host: host, record: try JSONSerialization.data(withJSONObject: ["items": [record]]))
            defer { CandidatePublishingHTTP.clear() }
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CandidatePublishingHTTP.self]
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let service = PublishingService(session: session, origin: URL(string: "https://" + host)!)
            let records = try await service.applications(identity: identity)
            XCTAssertEqual(records.first?.latestSubmission?.submitterUid, "historical-publisher")
            let library = HomeLibrary(directory: directory.appendingPathComponent("home"))
            library.setAutoSyncEnabled(false)
            let catalog = CatalogStore(cacheURL: directory.appendingPathComponent("catalog.json"))
            let runtime = NativeWebRuntime(webProfiles: WebProfileRepository(fileURL: directory.appendingPathComponent("profiles.json"), namespace: keychain), publishingService: service)
            runtime.configureAuthorization(accounts: accounts)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow)), previous = window.rootViewController
            let controller = UIHostingController(rootView: NavigationStack { MyApplicationsView(service: service) }
                .environmentObject(accounts).environmentObject(runtime).environmentObject(library).environmentObject(catalog))
            window.rootViewController = controller; window.makeKeyAndVisible(); runtime.anchor = controller
            defer { runtime.resetIdentity(); window.rootViewController = previous; window.makeKeyAndVisible(); try? FileManager.default.removeItem(at: directory) }
            let marker = cache.appendingPathComponent("iOSNativeValidation/publishing-journey-done")
            try? FileManager.default.removeItem(at: marker)
            print("PUBLISHING_CANDIDATE_READY_FOR_NATIVE_UI")
            let deadline = Date().addingTimeInterval(300)
            while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { try await Task.sleep(nanoseconds: 200_000_000) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "Native UI journey was not completed")
            try? FileManager.default.removeItem(at: marker)
            XCTAssertTrue(runtime.contains(try XCTUnwrap(records.first).application), "Preview must retain its actual WebKit session")
            XCTAssertNil(runtime.issue)
            XCTAssertEqual(CandidatePublishingHTTP.writeCount, 0)
            let report: [String: Any] = ["liveManagedListCount": liveRecords.count,
                "liveWriteCapabilityVersion": liveAccess.writePreconditionVersion as Any? ?? NSNull(),
                "historicalAuthorRetained": true, "nativePreviewSession": true, "remoteWrites": CandidatePublishingHTTP.writeCount,
                "scope": "Real managed production auth and list reads; historical-author response replay in actual iOS UI, with real Cook page preview. No live work edited/saved/submitted."]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "publishing-candidate-report"; attachment.lifetime = .keepAlways; add(attachment)
        } catch {
            for user in accounts.overview.users { try? await accounts.remove(user.id) }
            if let known = error as? PublishingError { XCTFail("Publishing acceptance failed at \(phase): \(known)") }
            else { XCTFail("Publishing acceptance failed at \(phase); private response and account details omitted") }
            return
        }
        for user in accounts.overview.users { try await accounts.remove(user.id) }
    }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
}

private final class CandidatePublishingHTTP: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var host = ""
    private static var records = Data()
    private static var writes = 0
    static var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
    static func configure(host: String, record: Data) { lock.lock(); defer { lock.unlock() }; self.host = host; records = record; writes = 0 }
    static func clear() { lock.lock(); defer { lock.unlock() }; host = ""; records = Data() }
    override class func canInit(with request: URLRequest) -> Bool { lock.lock(); defer { lock.unlock() }; return request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let isRead = request.httpMethod == "GET"
        if !isRead { Self.writes += 1 }
        let data = request.url?.path == "/api/apps/mine" ? Self.records : Data(#"{"writePreconditionVersion":1,"canSubmitFirstParty":true,"thirdPartyEnabled":false,"thirdPartyMessage":"回归样例，不执行远端写入"}"#.utf8)
        Self.lock.unlock()
        guard isRead, ["/api/apps/mine", "/api/apps/access"].contains(request.url?.path ?? "") else { client?.urlProtocol(self, didFailWithError: URLError(.noPermissionsToReadFile)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
