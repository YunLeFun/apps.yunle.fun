import CryptoKit
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import YunleFun

@MainActor
final class SupportViewTests: XCTestCase {
    // These verify production rendering and native scrolling. Consent and
    // cancellation interactions require the separate UI runner.
    func testCorruptEmptyLogStorageKeepsClearTextReachableWithoutDeletingEvidence() async throws {
        let fixture = try await SupportViewFixture(corruptLogs: true)
        defer { fixture.close() }
        XCTAssertTrue(fixture.logs.entries.isEmpty)
        XCTAssertNotNil(fixture.logs.storageError)
        let corrupt = try Data(contentsOf: fixture.logFile)
        let screen = try await fixture.readScreen(named: "support-corrupt-log-clear", containing: "清除本地日志", scrollToFind: true, startAt: .logs, test: self)
        XCTAssertTrue(screen.contains("清除本地日志"))
        XCTAssertEqual(try Data(contentsOf: fixture.logFile), corrupt, "Rendering the recovery action must not delete the preserved file")
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty)
    }

    func testSignedInFeedbackRendersPreviewEntryWithoutDispatchingHTTP() async throws {
        let fixture = try await SupportViewFixture(signedIn: true)
        defer { fixture.close() }
        XCTAssertNotNil(fixture.accounts.user)
        XCTAssertEqual(fixture.logs.entries.count, 1)
        let original = fixture.logs.entries
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty)
        let screen = try await fixture.readScreen(named: "support-signed-in-preview-entry", containing: "预览并上传日志", scrollToFind: true, startAt: .bottom, test: self)
        XCTAssertTrue(screen.contains("预览并上传日志"))
        XCTAssertFalse(fixture.hasPresentedSheet, "Rendering FeedbackView must not automatically open consent or a contact composer")
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty, "Rendering the upload entry must not submit logs")
        XCTAssertEqual(fixture.logs.entries, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receiptDirectory.path))
    }

    func testCorruptSavedReceiptRendersReadFailureWithoutReplacingEvidence() async throws {
        let fixture = try await SupportViewFixture(signedIn: true, corruptReceipt: true)
        defer { fixture.close() }
        let file = try XCTUnwrap(fixture.receiptFile)
        let corrupt = try Data(contentsOf: file)
        // The retained screenshot shows the full sentence; Vision can omit the
        // preceding grammatical particle. Keep the complete read-failure clause.
        // This is the final section. Materialize the native list bottom before
        // OCR so scanning unrelated contact rows cannot consume its deadline.
        let expected = "支持编号暂时无法读取"
        let text = try await fixture.readScreen(named: "support-corrupt-receipt-read-failure",
            containing: expected, scrollToFind: true, startAt: .bottom, test: self)
        XCTAssertTrue(text.contains(expected), "A missing usable receipt must not hide its disk-read failure")
        XCTAssertEqual(try Data(contentsOf: file), corrupt, "Displaying a receipt error must retain the damaged evidence")
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty)
        XCTAssertFalse(fixture.hasPresentedSheet)
    }

    func testLargestTextHelpCanScrollToNativeFeedbackEntry() async throws {
        let fixture = try await SupportViewFixture(screen: .help, size: .accessibility5)
        defer { fixture.close() }
        // This entry is near the list's end. Materialize the bottom before OCR
        // so unrelated FAQ rows cannot exhaust the unchanged scan deadline.
        let text = try await fixture.readScreen(named: "support-help-largest-feedback-entry", containing: "反馈与建议", scrollToFind: true, startAt: .bottom, test: self)
        XCTAssertTrue(text.contains("反馈与建议"), "Native scrolling must reveal the feedback destination at the requested text size")
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty)
    }

    func testLargestTextFeedbackKeepsContactAndEmptyLogExplanationReachable() async throws {
        let fixture = try await SupportViewFixture(size: .accessibility5)
        defer { fixture.close() }
        let contact = try await fixture.readScreen(named: "support-feedback-largest-copy", containing: "复制反馈内容", scrollToFind: true, test: self)
        XCTAssertTrue(contact.contains("复制反馈内容"), "Mail-independent feedback must remain visible at the largest text size")
        let empty = try await fixture.readScreen(named: "support-feedback-largest-empty-logs", containing: "所选时间内没有本地日志", scrollToFind: true, startAt: .logs, test: self)
        XCTAssertTrue(empty.contains("所选时间内没有本地日志"))
        XCTAssertTrue(fixture.uploadHTTP.requests.isEmpty)
    }
}

@MainActor
private final class SupportViewFixture {
    enum Screen { case feedback, help }
    enum ScanStart { case top, bottom, logs }
    let directory: URL
    let receiptDirectory: URL
    let receiptFile: URL?
    let logFile: URL
    let logs: DiagnosticLogStore
    let accounts: AccountStore
    let uploadHTTP: AuthHTTPFixture
    let window: UIWindow
    private let controller: UIViewController
    private let previous: UIWindow?
    private let animationsWereEnabled: Bool
    private let authHost: String
    private let uploadHost: String

    init(screen: Screen = .feedback, signedIn: Bool = false, corruptLogs: Bool = false, corruptReceipt: Bool = false,
         size: DynamicTypeSize = .large) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logDirectory = directory.appendingPathComponent("logs", isDirectory: true)
        let receiptDirectory = directory.appendingPathComponent("receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logFile = logDirectory.appendingPathComponent("guest.json")
        if corruptLogs { try Data("{broken support fixture".utf8).write(to: logFile) }
        let authHost = UUID().uuidString.lowercased() + ".support-view-auth.test"
        let uploadHost = UUID().uuidString.lowercased() + ".support-view-upload.test"
        let authHTTP = AuthHTTPFixture(replies: [(200, #"{"sub":"support-view-user","name":"支持页夹具","status":"ACTIVE"}"#)])
        let uploadHTTP = AuthHTTPFixture(replies: [])
        AuthHTTPProtocol.register(authHost, fixture: authHTTP)
        AuthHTTPProtocol.register(uploadHost, fixture: uploadHTTP)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthHTTPProtocol.self]
        var state = AccountVaultState()
        if signedIn {
            state.activeID = "support-view-user"
            state.accounts = [SavedAccount(user: AccountUser(id: "support-view-user"), credential: AccountCredential(
                accessToken: "support-render-fixture-only", refreshToken: "unused-fixture", expiresAt: Date().addingTimeInterval(3600)))]
        }
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(session: URLSession(configuration: configuration),
            origin: URL(string: "https://\(authHost)")!), vault: BillingMemoryVault(data: try JSONEncoder().encode(state))))
        await accounts.restore()
        let receiptFile: URL?
        if corruptReceipt {
            let owner = try XCTUnwrap(accounts.user?.id)
            try FileManager.default.createDirectory(at: receiptDirectory, withIntermediateDirectories: true)
            let key = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = receiptDirectory.appendingPathComponent(key + ".json")
            try Data("{broken retained support receipt".utf8).write(to: file)
            receiptFile = file
        } else { receiptFile = nil }
        let logs = DiagnosticLogStore(directory: logDirectory)
        if signedIn {
            logs.activateAccount(accounts.user?.id)
            logs.record(.info, message: "host.support.preview.ready")
        }
        let service = DiagnosticService(session: URLSession(configuration: configuration), origin: URL(string: "https://\(uploadHost)")!)
        let content: AnyView
        switch screen {
        case .feedback:
            content = AnyView(NavigationStack {
                FeedbackView(logs: logs, accounts: accounts, service: service, receiptDirectory: receiptDirectory,
                             sharedHistory: SharedFeedbackHistory(directory: directory.appendingPathComponent("shared-feedback")))
            })
        case .help:
            content = AnyView(NavigationStack { HelpView(logs: logs, accounts: accounts, navigateTab: { _ in }) })
        }
        let hosting = UIHostingController(rootView: content.environment(\.dynamicTypeSize, size).preferredColorScheme(.light))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        self.directory = directory; self.receiptDirectory = receiptDirectory; self.receiptFile = receiptFile; self.logFile = logFile
        self.logs = logs; self.accounts = accounts; self.uploadHTTP = uploadHTTP
        self.authHost = authHost; self.uploadHost = uploadHost; controller = hosting
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        animationsWereEnabled = UIView.areAnimationsEnabled; UIView.setAnimationsEnabled(false)
        window.rootViewController = hosting; window.makeKeyAndVisible()
        try await settle()
    }

    var hasPresentedSheet: Bool { controller.presentedViewController != nil }

    func readScreen(named name: String, containing expected: String, scrollToFind: Bool, startAt: ScanStart = .top,
                    test: XCTestCase) async throws -> String {
        // Keep the content assertion intact while allowing multiple slow OCR
        // passes to scroll through an accessibility-sized form on CI.
        let deadline = Date().addingTimeInterval(scrollToFind ? 30 : 10)
        let fromBottom = startAt == .bottom
        var image: UIImage?, lines: [String] = []
        var scan: [String] = []
        var sample = 0, candidateScreenshots = 0
        if scrollToFind, startAt == .logs {
            // These guest fixtures have no receipt: their final two native
            // sections are logs and upload. Start at the first log row so OCR
            // does not spend its deadline on unrelated contact rows or on the
            // tall upload explanation at accessibility5. The unchanged text
            // assertion still requires the complete target in a visible frame.
            XCTAssertNil(receiptFile)
            XCTAssertNil(accounts.user)
            let collection = try XCTUnwrap(scrollView(in: controller.view) as? UICollectionView)
            controller.view.layoutIfNeeded()
            let sections = (0..<collection.numberOfSections).filter {
                collection.numberOfItems(inSection: $0) > 0
            }
            let section = try XCTUnwrap(sections.dropLast().last)
            scan.append("Materialize first log item: section=\(section) item=0")
            collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .top, animated: false)
            try await settle()
        }
        if scrollToFind, fromBottom, let scroll = scrollView(in: controller.view) {
            // List estimates unloaded row heights. Materialize its final item
            // before using contentSize to start the upward scan.
            controller.view.layoutIfNeeded()
            if let collection = scroll as? UICollectionView,
               let section = (0..<collection.numberOfSections).reversed().first(where: {
                   collection.numberOfItems(inSection: $0) > 0
               }) {
                let item = collection.numberOfItems(inSection: section) - 1
                scan.append("Materialize last native item: section=\(section) item=\(item)")
                collection.scrollToItem(at: IndexPath(item: item, section: section), at: .bottom, animated: false)
            }
            repeat {
                controller.view.layoutIfNeeded()
                let requestedBottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: requestedBottom), animated: false)
                try await settle()
                let laidOutBottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scan.append("Bottom layout: requested=\(requestedBottom) actual=\(laidOutBottom) offset=\(scroll.contentOffset) viewport=\(scroll.bounds.size) contentSize=\(scroll.contentSize)")
                if abs(laidOutBottom - requestedBottom) < 1, abs(scroll.contentOffset.y - laidOutBottom) < 1 { break }
            } while Date() < deadline
        }
        repeat {
            try await settle()
            let view = controller.view!
            let rendered = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            image = rendered
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(rendered.cgImage)).perform([request])
            lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let visible = Self.normalized(lines.joined())
            let geometry: String
            if let scroll = scrollView(in: view) {
                geometry = "scroll=\(String(reflecting: type(of: scroll))) offset=\(scroll.contentOffset) viewport=\(scroll.bounds.size) contentSize=\(scroll.contentSize) adjustedInset=\(scroll.adjustedContentInset)"
            } else { geometry = "No native scroll view; viewport=\(view.bounds.size)" }
            scan.append("Sample \(sample): \(geometry)\n" + lines.joined(separator: "\n"))
            if fromBottom, candidateScreenshots < 8,
               ["所选", "本地", "0条"].contains(where: { visible.contains($0) }) {
                let candidate = XCTAttachment(image: rendered)
                candidate.name = name + "-candidate-\(sample)"
                candidate.lifetime = .keepAlways; test.add(candidate)
                candidateScreenshots += 1
            }
            sample += 1
            if visible.contains(Self.normalized(expected)) { break }
            if scrollToFind, let scroll = scrollView(in: view) {
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                // Keep half a viewport of overlap so the complete expected
                // clause fits between samples, including at accessibility5.
                // Quarter-page steps spend the scan deadline on the large
                // upload footer before the preceding log text becomes visible.
                let step = max(100, (scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom) / 2)
                let next = fromBottom ? max(scroll.contentOffset.y - step, top) : min(scroll.contentOffset.y + step, bottom)
                scan.append("Requested next offset.y=\(next)")
                guard next != scroll.contentOffset.y else { break }
                scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
            }
        } while Date() < deadline
        if let image {
            let screenshot = XCTAttachment(image: image); screenshot.name = name; screenshot.lifetime = .keepAlways; test.add(screenshot)
        }
        let text = XCTAttachment(string: lines.joined(separator: "\n")); text.name = name + "-visible-text"; text.lifetime = .keepAlways; test.add(text)
        let trace = XCTAttachment(string: scan.joined(separator: "\n\n"))
        trace.name = name + "-viewport-scan"; trace.lifetime = .keepAlways; test.add(trace)
        return Self.normalized(lines.joined())
    }

    func close() {
        controller.dismiss(animated: false)
        window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
        UIView.setAnimationsEnabled(animationsWereEnabled)
        AuthHTTPProtocol.unregister(authHost); AuthHTTPProtocol.unregister(uploadHost)
        try? FileManager.default.removeItem(at: directory)
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.view.layoutIfNeeded()
    }
    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
    private static func normalized(_ value: String) -> String {
        value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }
            .map(String.init).joined()
    }
}
