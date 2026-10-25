import SwiftUI
import UIKit
import XCTest
@testable import YunleFun

@MainActor
final class ScreenshotFeedbackCoordinatorTests: XCTestCase {
    // These exercise the notification adapter and actual UIKit controls in an
    // isolated window. Posting a notification does not take a system screenshot
    // or reproduce the operating system's screenshot editor.
    func testScreenshotNotificationOnlyAddsDelayedNonModalAccessoryAndLeavesPageTappable() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        let originalLogs = fixture.logs.entries
        let originalFile = try Data(contentsOf: fixture.logFile)

        fixture.postScreenshot()
        XCTAssertNil(fixture.capsule, "The invitation must not appear in the screenshot notification callback")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(fixture.capsule, "Keep the initial screenshot interaction free of an immediate accessory")
        let capsule = try await fixture.waitForCapsule()
        let rootSafeArea = fixture.root.view.convert(fixture.root.view.safeAreaLayoutGuide.layoutFrame, to: fixture.window)
        let capsuleInWindow = capsule.convert(capsule.bounds, to: fixture.window)
        XCTAssertEqual(capsuleInWindow.maxY, rootSafeArea.maxY - 80, accuracy: 1,
                       "Without a keyboard, the invitation belongs above the bottom safe area rather than at the top")
        XCTAssertNil(fixture.root.presentedViewController, "A screenshot alone must not present the feedback form")
        XCTAssertFalse(capsule.accessibilityViewIsModal)
        XCTAssertTrue(fixture.window.isKeyWindow)
        XCTAssertTrue(fixture.window.hitTest(fixture.root.view.center, with: nil) === fixture.root.view,
                      "Touches outside the small accessory must reach the existing page")
        fixture.postScreenshot()
        XCTAssertTrue(fixture.capsule === capsule, "Consecutive screenshots must reuse one invitation")
        XCTAssertEqual(fixture.logs.entries, originalLogs)
        XCTAssertEqual(try Data(contentsOf: fixture.logFile), originalFile)
        XCTAssertTrue(fixture.authHTTP.requests.isEmpty)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
        fixture.capture("screenshot-feedback-light", test: self)
    }

    func testCloseButtonSuppressesFurtherInvitationsForThisCoordinatorSession() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        try fixture.button("screenshot-feedback.close").sendActions(for: .touchUpInside)
        XCTAssertNil(fixture.capsule)
        fixture.postScreenshot()
        fixture.configure(enabled: true)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(fixture.capsule, "An unchanged enabled preference must not undo the user's close action")
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
    }

    func testDisablingPreferenceImmediatelyRemovesInvitationAndRejectsFurtherScreenshots() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        fixture.configure(enabled: false)
        XCTAssertNil(fixture.capsule)
        fixture.postScreenshot()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(fixture.capsule)
        XCTAssertNil(fixture.root.presentedViewController)

        fixture.configure(enabled: true)
        XCTAssertNil(fixture.capsule, "Enabling the preference must not replay screenshots taken while disabled")
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
    }

    func testOpenButtonPresentsExistingFeedbackAndCloseActionHandlerReturnsToRoot() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        try fixture.button("screenshot-feedback.open").sendActions(for: .touchUpInside)
        let feedback = try await fixture.waitForFeedback(presentedBy: fixture.root)
        XCTAssertNil(fixture.capsule)
        XCTAssertTrue(String(reflecting: type(of: feedback)).contains("UIHostingController"))
        XCTAssertTrue(String(reflecting: type(of: feedback)).contains("ScreenshotFeedbackSheet"),
                      "The explicit action must open the existing native FeedbackView wrapper")
        XCTAssertNil(feedback.presentedViewController, "Opening feedback must not open upload consent or a contact composer")
        XCTAssertNil(fixture.accounts.user)
        XCTAssertTrue(fixture.authHTTP.requests.isEmpty)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
        fixture.capture("screenshot-feedback-existing-form", test: self)

        fixture.postScreenshot()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(fixture.capsule, "Screenshots of the feedback form must not invite feedback again")
        // Exercise the same close handler used by the SwiftUI Done button;
        // standard SwiftUI button bridging is outside this unit-host test.
        fixture.coordinator.closeFeedback()
        try await fixture.waitForDismissal(from: fixture.root)
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertTrue(fixture.window.rootViewController === fixture.root)
        XCTAssertTrue(fixture.window.isKeyWindow)
    }

    func testFeedbackAppearsOverFullScreenNavigationAndCloseActionHandlerPreservesItsNavigationStack() async throws {
        let fixture = try await ScreenshotFeedbackFixture(dark: true, largestText: true)
        defer { fixture.close() }
        let cloudApp = UIViewController()
        cloudApp.title = "正在使用的云应用"
        cloudApp.view.backgroundColor = .systemBackground
        let navigation = UINavigationController(rootViewController: cloudApp)
        navigation.modalPresentationStyle = .fullScreen
        fixture.root.present(navigation, animated: false)
        try await fixture.settle()
        XCTAssertTrue(ScreenshotFeedbackCoordinator.feedbackPresenter(in: fixture.window) === navigation)

        fixture.postScreenshot()
        let capsule = try await fixture.waitForCapsule()
        let open = try fixture.button("screenshot-feedback.open")
        let close = try fixture.button("screenshot-feedback.close")
        let navigationSafeArea = navigation.view.convert(navigation.view.safeAreaLayoutGuide.layoutFrame, to: fixture.window)
        let capsuleInWindow = capsule.convert(capsule.bounds, to: fixture.window)
        XCTAssertEqual(capsuleInWindow.maxY, navigationSafeArea.maxY - 80, accuracy: 1,
                       "The invitation must stay above the active full-screen presenter's bottom safe area at the largest text size")
        XCTAssertGreaterThanOrEqual(open.bounds.height, 44)
        XCTAssertGreaterThanOrEqual(close.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(close.bounds.height, 44)
        XCTAssertTrue(fixture.window.bounds.contains(capsule.frame),
                      "The large-text invitation must remain inside the window: capsule=\(capsule.frame), window=\(fixture.window.bounds)")
        XCTAssertFalse(open.frame.intersects(close.frame), "The two actions must not overlap at accessibility text sizes")
        fixture.capture("screenshot-feedback-dark-largest-text", test: self)

        open.sendActions(for: .touchUpInside)
        _ = try await fixture.waitForFeedback(presentedBy: navigation)
        XCTAssertTrue(fixture.root.presentedViewController === navigation)
        XCTAssertNil(fixture.capsule)
        fixture.coordinator.closeFeedback()
        try await fixture.waitForDismissal(from: navigation)
        XCTAssertTrue(fixture.root.presentedViewController === navigation)
        XCTAssertTrue(navigation.topViewController === cloudApp)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
    }

    func testCancellingRootOwnedLoginRestoresTheUnchangedGuestFeedbackDraft() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        try fixture.button("screenshot-feedback.open").sendActions(for: .touchUpInside)
        let originalFeedback = try await fixture.waitForFeedback(presentedBy: fixture.root)
        let draft = "截屏后页面仍然空白。\n重试两次后希望保留这份反馈 🧩"
        let editor = try await fixture.textEditor(in: originalFeedback)
        editor.text = draft
        editor.delegate?.textViewDidChange?(editor)
        let generation = fixture.accounts.identityGeneration
        let root = fixture.root
        var loginDescriptions: [String] = []
        fixture.configure(enabled: true, requestLogin: { text in
            XCTAssertNil(root.presentedViewController, "Dismiss the feedback sheet before transferring login to the root")
            loginDescriptions.append(text)
            return true
        })

        fixture.coordinator.requestLoginFromFeedback(text: draft)
        for _ in 0..<40 {
            if !loginDescriptions.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(loginDescriptions, [draft])
        try await fixture.waitForDismissal(from: root)
        XCTAssertNil(root.presentedViewController, "An accepted login request must wait for the root-owned login to close")
        XCTAssertNil(fixture.accounts.user)
        XCTAssertEqual(fixture.accounts.identityGeneration, generation)

        // Simulate the root login sheet's cancellation callback; no login or
        // account transition occurs in this guest fixture.
        fixture.coordinator.loginDidDismiss()
        let restoredFeedback = try await fixture.waitForFeedback(presentedBy: root)
        XCTAssertFalse(restoredFeedback === originalFeedback)
        let restoredEditor = try await fixture.textEditor(in: restoredFeedback)
        XCTAssertEqual(restoredEditor.text, draft, "Cancelling login must restore the actual TextEditor's draft")
        XCTAssertNil(fixture.capsule)
        XCTAssertTrue(fixture.authHTTP.requests.isEmpty)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
        fixture.capture("screenshot-feedback-login-cancelled-draft", test: self)
    }

    func testDeclinedLoginRequestImmediatelyRestoresTheGuestFeedbackDraft() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        try fixture.button("screenshot-feedback.open").sendActions(for: .touchUpInside)
        let originalFeedback = try await fixture.waitForFeedback(presentedBy: fixture.root)
        let draft = "登录入口暂不可用时也不要丢失反馈"
        let root = fixture.root
        var loginDescriptions: [String] = []
        fixture.configure(enabled: true, requestLogin: { text in
            XCTAssertNil(root.presentedViewController)
            loginDescriptions.append(text)
            return false
        })

        fixture.coordinator.requestLoginFromFeedback(text: draft)
        for _ in 0..<40 {
            if !loginDescriptions.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(loginDescriptions, [draft])
        let restoredFeedback = try await fixture.waitForFeedback(presentedBy: root)
        XCTAssertFalse(restoredFeedback === originalFeedback)
        let restoredEditor = try await fixture.textEditor(in: restoredFeedback)
        XCTAssertEqual(restoredEditor.text, draft)
        XCTAssertNil(fixture.accounts.user)
        XCTAssertTrue(fixture.authHTTP.requests.isEmpty)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
    }

    func testNavigatingAwayDuringLoginDiscardsDraftAndDoesNotReopenFeedback() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        try fixture.button("screenshot-feedback.open").sendActions(for: .touchUpInside)
        _ = try await fixture.waitForFeedback(presentedBy: fixture.root)
        let draft = "用户稍后已转向其他页面的旧反馈"
        let root = fixture.root
        var loginDescriptions: [String] = []
        fixture.configure(enabled: true, requestLogin: { text in
            XCTAssertNil(root.presentedViewController)
            loginDescriptions.append(text)
            return true
        })

        fixture.coordinator.requestLoginFromFeedback(text: draft)
        for _ in 0..<40 {
            if !loginDescriptions.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(loginDescriptions, [draft])
        try await fixture.waitForDismissal(from: root)
        // A new navigation intent invalidates the root-owned login flow before
        // its dismissal callback arrives; the old draft must not cover that page.
        fixture.coordinator.cancelPendingLogin()
        fixture.coordinator.loginDidDismiss()
        try await fixture.settle()
        XCTAssertNil(root.presentedViewController)
        XCTAssertNil(fixture.capsule)
        XCTAssertNil(fixture.accounts.user)
        XCTAssertTrue(fixture.authHTTP.requests.isEmpty)
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
    }

    func testSheetAndAlertDelayInvitationUntilTheExistingModalCloses() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        let sheet = UIHostingController(rootView: Text("现有表单"))
        sheet.modalPresentationStyle = .pageSheet
        fixture.root.present(sheet, animated: false)
        try await fixture.settle()
        XCTAssertNil(ScreenshotFeedbackCoordinator.feedbackPresenter(in: fixture.window))
        fixture.postScreenshot()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(fixture.capsule)
        XCTAssertTrue(fixture.root.presentedViewController === sheet)
        fixture.root.dismiss(animated: false)
        _ = try await fixture.waitForCapsule()
        fixture.coordinator.discard()

        let alert = UIAlertController(title: "现有提醒", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "完成", style: .default))
        fixture.root.present(alert, animated: false)
        try await fixture.settle()
        XCTAssertNil(ScreenshotFeedbackCoordinator.feedbackPresenter(in: fixture.window))
        fixture.postScreenshot()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(fixture.capsule)
        XCTAssertTrue(fixture.root.presentedViewController === alert)
        fixture.root.dismiss(animated: false)
        _ = try await fixture.waitForCapsule()
        XCTAssertEqual(ScreenshotFeedbackUploadProtocol.requestCount, 0)
    }

    func testSceneNotificationAdapterSuspendsThenResumesAndBackgroundDiscardsPendingInvitation() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
        // The real scene stays active. These posts only verify adapter routing
        // and cancellation; device screenshot-preview behavior needs a device.
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: fixture.scene)
        XCTAssertNil(fixture.capsule)
        fixture.postScreenshot()
        try await Task.sleep(nanoseconds: 850_000_000)
        XCTAssertNil(fixture.capsule, "A screenshot received while deactivated must not re-add the accessory")
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: fixture.scene)
        XCTAssertNil(fixture.capsule, "Returning to the scene keeps the initial presentation delay")
        _ = try await fixture.waitForCapsule()

        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: fixture.scene)
        XCTAssertNil(fixture.capsule)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: fixture.scene)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(fixture.capsule, "A later app visit must not revive an invitation from before backgrounding")
        fixture.postScreenshot()
        _ = try await fixture.waitForCapsule()
    }

    func testAccessibilityFocusAdapterKeepsInvitationAvailableAndStillHonorsDisabledPreference() async throws {
        let fixture = try await ScreenshotFeedbackFixture()
        defer { fixture.close() }
        fixture.postScreenshot()
        let capsule = try await fixture.waitForCapsule()
        let open = try fixture.button("screenshot-feedback.open")
        NotificationCenter.default.post(name: UIAccessibility.elementFocusedNotification, object: nil,
            userInfo: [UIAccessibility.focusedElementUserInfoKey: open])
        // This verifies the focus adapter without enabling or moving VoiceOver.
        try await Task.sleep(nanoseconds: 8_250_000_000)
        XCTAssertTrue(fixture.capsule === capsule, "Do not remove a control while an assistive-technology user is focused on it")
        fixture.configure(enabled: false)
        XCTAssertNil(fixture.capsule, "Focus must not override the user's disabled preference")
        XCTAssertNil(fixture.root.presentedViewController)
    }
}

@MainActor
private final class ScreenshotFeedbackFixture {
    let scene: UIWindowScene
    let window: UIWindow
    let root = UIViewController()
    let coordinator = ScreenshotFeedbackCoordinator()
    let logs: DiagnosticLogStore
    let accounts: AccountStore
    let authHTTP: AuthHTTPFixture
    let logFile: URL
    private let directory: URL
    private let authHost: String
    private let previous: UIWindow?
    private let animationsWereEnabled: Bool

    init(dark: Bool = false, largestText: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-feedback-" + UUID().uuidString, isDirectory: true)
        let logDirectory = directory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let authHost = UUID().uuidString.lowercased() + ".screenshot-feedback-auth.test"
        let authHTTP = AuthHTTPFixture(replies: [])
        AuthHTTPProtocol.register(authHost, fixture: authHTTP)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthHTTPProtocol.self]
        let accounts = AccountStore(session: AccountSession(api: CloudbaseAuthService(
            session: URLSession(configuration: configuration), origin: URL(string: "https://\(authHost)")!), vault: BillingMemoryVault()))
        await accounts.restore()
        let logs = DiagnosticLogStore(directory: logDirectory)
        logs.record(.info, message: "host.screenshot-feedback.fixture.ready")
        self.scene = scene; self.directory = directory; self.authHost = authHost
        self.authHTTP = authHTTP; self.accounts = accounts; self.logs = logs
        logFile = logDirectory.appendingPathComponent("guest.json")
        previous = scene.windows.first(where: \.isKeyWindow)
        animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        ScreenshotFeedbackUploadProtocol.reset()
        URLProtocol.registerClass(ScreenshotFeedbackUploadProtocol.self)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if #available(iOS 17, *), largestText {
            window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
        coordinator.attach(to: window)
        configure(enabled: true)
        await Task.yield()
        window.layoutIfNeeded()
    }

    var capsule: UIView? { window.subviews.first { $0.accessibilityIdentifier == "screenshot-feedback.prompt" } }

    func configure(enabled: Bool, requestLogin: @escaping (String) -> Bool = { _ in
            XCTFail("A screenshot or feedback entry must not implicitly start login")
            return false
        }) {
        coordinator.configure(enabled: enabled, logs: logs, accounts: accounts, requestLogin: requestLogin)
    }

    func postScreenshot() { NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil) }

    func button(_ identifier: String) throws -> UIButton {
        try XCTUnwrap(views(in: window).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == identifier })
    }

    func waitForCapsule() async throws -> UIView {
        for _ in 0..<40 {
            if let capsule { window.layoutIfNeeded(); return capsule }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(capsule, "The invitation did not appear after the delay in an active unobstructed window")
    }

    func waitForFeedback(presentedBy presenter: UIViewController) async throws -> UIViewController {
        for _ in 0..<40 {
            if let feedback = presenter.presentedViewController {
                try await settle()
                return feedback
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(presenter.presentedViewController, "The explicit feedback action did not present the form")
    }

    func waitForDismissal(from presenter: UIViewController) async throws {
        for _ in 0..<40 {
            if presenter.presentedViewController == nil { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(presenter.presentedViewController, "The feedback close action handler must dismiss its own sheet")
    }

    func textEditor(in feedback: UIViewController) async throws -> UITextView {
        for _ in 0..<40 {
            let editors: [UITextView] = views(in: feedback.view).compactMap { $0 as? UITextView }
            if let editor = editors.first { return editor }
            try await settle()
        }
        let editor: UITextView? = views(in: feedback.view).compactMap { $0 as? UITextView }.first
        return try XCTUnwrap(editor, "The existing FeedbackView must render its native issue-description TextEditor")
    }

    func settle() async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        window.layoutIfNeeded()
    }

    func capture(_ name: String, test: XCTestCase) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; test.add(attachment)
        let presenter = ScreenshotFeedbackCoordinator.feedbackPresenter(in: window)
        let presenterSafeArea = presenter.map { $0.view.convert($0.view.safeAreaLayoutGuide.layoutFrame, to: window) }
        let presenterKeyboard = presenter.map { $0.view.convert($0.view.keyboardLayoutGuide.layoutFrame, to: window) }
        let geometry = "window.bounds=\(window.bounds) safeArea=\(window.safeAreaInsets) windowKeyboard=\(window.keyboardLayoutGuide.layoutFrame) presenterSafeArea=\(String(describing: presenterSafeArea)) presenterKeyboard=\(String(describing: presenterKeyboard)) capsule=\(String(describing: capsule?.frame))"
        let layout = XCTAttachment(string: geometry)
        layout.name = name + "-layout"; layout.lifetime = .keepAlways; test.add(layout)
    }

    func close() {
        coordinator.discard()
        root.dismiss(animated: false)
        window.isHidden = true; window.rootViewController = nil
        previous?.makeKey()
        UIView.setAnimationsEnabled(animationsWereEnabled)
        URLProtocol.unregisterClass(ScreenshotFeedbackUploadProtocol.self)
        AuthHTTPProtocol.unregister(authHost)
        try? FileManager.default.removeItem(at: directory)
    }

    private func views(in view: UIView) -> [UIView] { [view] + view.subviews.flatMap { views(in: $0) } }
}

/// Observe only the diagnostic upload endpoint used by the production sheet's
/// default service. Unexpected uploads fail locally instead of reaching a server.
private final class ScreenshotFeedbackUploadProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); defer { lock.unlock() }; count = 0 }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.path == "/api/diagnostics/logs" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}
