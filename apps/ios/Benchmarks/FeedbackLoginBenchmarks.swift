import Darwin
import Foundation
import UIKit
import XCTest

/// Explicit simulator journeys against the real Benchmark app and auth service.
/// Run the canary alone and audit its complete xcresult before enabling real input.
@MainActor
final class FeedbackLoginBenchmarks: XCTestCase {
    private let draft = "Feedback continuation 🧩\nSteps: open feedback, then sign in.\nExpected: preserve every line.\nActual: return to a fresh feedback page."
    // Non-secret audit marker. Never submit this value to authentication.
    private let canary = "YLF_Feedback_Canary_20261017_Aa9!"
    private let username = "ylf_prod_zero"
    private var passwordSavePromptAtLaunch = false
    private var passwordSavePromptObserved = false
    private var passwordSavePromptDeclined = false

    func testSecurePasswordCanaryWithoutSubmittingAuthentication() throws {
        try requireOptIn("YLF_FEEDBACK_LOGIN_CANARY")
        let app = try launchFreshGuest()
        var phase = "prepare feedback login"
        do {
            try prepareFeedbackLogin(app)
            phase = "enter non-secret canary"
            try fillPasswordForm(app, username: "feedback-canary", password: canary)
            capture(app, name: "feedback-canary-secure-field", allowCanarySecureTree: true)
            // Do not tap login.submit or press Return. This audits the same
            // local-paste channel that the later real journey uses.
            phase = "cancel and verify guest draft"
            try cancelLogin(app)
            try verifyDraft(app, expectedRange: "24 小时")
            try returnToMe(app)
            try revealMeIdentity(app)
            try require(app.buttons["me.login"].exists, "Canary cancellation must remain a guest")
            capture(app, name: "feedback-canary-cancelled")
            report(["canaryOnly": true, "authenticationSubmitted": false,
                    "credentialFileRead": false, "guestDraftRetained": true,
                    "inputChannel": "local-paste-v1",
                    "inputChannelAudit": "Pending complete xcresult and host pasteboard changeCount audit"])
        } catch {
            let detail = (error as? JourneyFailure)?.message ?? "Unclassified validation failure; details omitted"
            var failure = "Canary failed during \(phase): \(detail)"
            // This method has only used a public non-secret canary. Preserve the
            // actual failing modal/AX hierarchy before attempting cancellation.
            capture(app, name: "feedback-canary-failure", allowCanarySecureTree: true)
            if app.navigationBars["登录并继续"].exists {
                do { try cancelLogin(app) }
                catch { failure += "; native login cancellation was not verified" }
            }
            report(["canaryOnly": true, "authenticationSubmitted": false,
                    "credentialFileRead": false, "failure": failure])
            throw JourneyFailure(message: failure)
        }
    }

    func testManagedGuestLoginResumesFreshFeedbackOnlyOnce() throws {
        try requireOptIn("YLF_FEEDBACK_LOGIN_UI")
        guard ProcessInfo.processInfo.environment["YLF_FEEDBACK_LOGIN_CANARY_AUDITED"] == "local-paste-v1" else {
            throw XCTSkip("Audit local-paste-v1 activities, attachments and host clipboard isolation before real input")
        }
        let app = try launchFreshGuest()
        var phase = "prepare guest feedback"
        var failure: String?
        var submitted = false
        var resumed = false
        var consumed = false
        var removed = false
        do {
            try prepareFeedbackLogin(app)
            phase = "consume one-shot runner input"
            // No master pool access, environment secrets, app hooks or Store calls.
            // This is deliberately after all opt-ins and the real form preflight.
            let credential = try consumeCredential { consumed = true }
            phase = "enter approved credentials"
            try fillPasswordForm(app, username: credential.username, password: credential.password)
            try dismissKeyboard(app)
            let submit = app.buttons["login.submit"]
            try reveal(submit, in: app)
            try require(submit.isEnabled, "The real login submit action must be enabled")
            phase = "submit real LoginView"
            submitted = true
            submit.tap()
            // The old feedback was scoped to the guest NavigationStack. Seeing
            // the exact text plus a fresh range after the actual sheet is gone
            // exercises root.onDismiss; no model dismissal is invoked here.
            try disappeared(app.navigationBars["登录并继续"], timeout: 40,
                            message: "The actual login sheet did not disappear after submission")
            phase = "observe fresh feedback destination"
            try require(app.navigationBars["反馈与建议"].waitForExistence(timeout: 10),
                        "Successful login must return to a feedback destination")
            try dismissObservedPasswordSavePrompt(app)
            try verifyDraft(app, expectedRange: "1 小时")
            try require(!app.buttons["feedback.confirmation.upload"].exists && !app.alerts["日志已上传"].exists,
                        "Continuation must not restore upload consent or show an upload success alert")
            resumed = true
            capture(app, name: "feedback-real-login-resumed")
            phase = "consume continuation only once"
            try returnToMe(app)
            try revealMeIdentity(app)
            try require(activeIdentity(in: app).exists && !app.buttons["me.login"].exists,
                        "The published account must be the approved synthetic identity")
            try openFeedback(app)
            let editor = app.textViews["feedback.description"]
            try reveal(editor, in: app, upward: false)
            try require((editor.value as? String) == "", "Back then a new feedback entry must have an empty draft")
            try verifyRange("1 小时", in: app)
            capture(app, name: "feedback-real-login-new-entry-empty")
        } catch let error as JourneyFailure {
            failure = "\(phase): \(error.message)"
        } catch {
            // Never interpolate decoder errors, credential values or auth responses.
            failure = "\(phase): validation failed; sensitive details omitted"
        }

        if submitted {
            do {
                removed = try removeOwnedAccount(app)
                if !removed {
                    failure = (failure.map { $0 + "; " } ?? "") + "Native account cleanup was not verified: no owned published account was removed"
                }
            }
            catch { failure = (failure.map { $0 + "; " } ?? "") + "Native account cleanup was not verified" }
        } else if app.navigationBars["登录并继续"].exists {
            // Input/preflight failures must not leave a credential form open.
            do { try cancelLogin(app) }
            catch { failure = (failure.map { $0 + "; " } ?? "") + "Login cancellation was not verified" }
        }
        report(["canaryOnly": false, "credentialInputConsumed": consumed,
                "authenticationSubmitted": submitted, "freshFeedbackResumed": resumed,
                "nativeAccountRemoved": removed,
                "remoteSignOutEvidence": removed
                    ? "Native removal requested revocation; no failure notice during the auth timeout window. No independent HTTP acknowledgement observed."
                    : "Not verified; inspect the cleanup and failure stage",
                "uploadEvidence": "No upload/consent action tapped; this UI journey does not intercept all HTTP",
                "failure": failure ?? "none"])
        if let failure { XCTFail(failure) }
    }

    private func requireOptIn(_ flag: String) throws {
        guard ProcessInfo.processInfo.environment[flag] == "1" else {
            throw XCTSkip("Requires explicit opt-in for the isolated feedback login journey")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("Feedback login validation is restricted to an owned iOS simulator")
        #else
        let environment = ProcessInfo.processInfo.environment
        try require(environment["YLF_BENCHMARK_TARGET"] != "legacy", "This journey only targets the native Benchmark app")
        guard let owned = environment["YLF_OWNED_BENCHMARK_SIMULATOR_UDID"], !owned.isEmpty,
              owned == environment["SIMULATOR_UDID"], environment["YLF_FEEDBACK_LOGIN_FRESH_GUEST_FIXTURE"] == "1" else {
            throw JourneyFailure(message: "Requires this newly created simulator's explicit owned fresh-guest fixture declaration")
        }
        try require(environment["YLF_FEEDBACK_LOGIN_PASTEBOARD_ISOLATED"] == "1",
                    "Root must isolate Simulator's host pasteboard bridge and monitor host changeCount before local paste")
        try require(UIDevice.current.userInterfaceIdiom == .phone, "This bounded journey currently covers an iPhone simulator")
        continueAfterFailure = true // Throw controlled failures so post-submit cleanup still runs.
        executionTimeAllowance = 240
        #endif
    }

    private func launchFreshGuest() throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "fun.yunle.apps.benchmark-dev")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        try dismissObservedPasswordSavePrompt(app)
        passwordSavePromptAtLaunch = passwordSavePromptObserved
        passwordSavePromptObserved = false
        passwordSavePromptDeclined = false
        try require(app.buttons["去工坊看看"].waitForExistence(timeout: 15), "Requires a fresh empty home")
        try require(!app.buttons["home.running"].exists && !app.webViews.firstMatch.exists
                    && app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).count == 0,
                    "The owned fixture must contain no installed or running application")
        let me = app.tabBars.buttons["我"]
        try require(me.waitForExistence(timeout: 10), "Requires the native iPhone tab bar")
        me.tap()
        try require(app.navigationBars["我"].waitForExistence(timeout: 5), "The Me destination must appear")
        try require(app.buttons["me.login"].waitForExistence(timeout: 10), "Never run against an existing signed-in account")
        try disappeared(app.progressIndicators["正在检查登录状态"], timeout: 15, message: "Initial restore has not completed")
        return app
    }

    private func openFeedback(_ app: XCUIApplication) throws {
        let entry = app.buttons["me.feedback"]
        try reveal(entry, in: app)
        entry.tap()
        try require(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5), "The native feedback destination must appear")
    }

    private func prepareFeedbackLogin(_ app: XCUIApplication) throws {
        try openFeedback(app)
        let editor = app.textViews["feedback.description"]
        try reveal(editor, in: app, upward: false)
        editor.tap(); editor.typeText(draft)
        try dismissKeyboard(app)
        try require((editor.value as? String) == draft, "The real TextEditor must retain the exact multiline emoji fixture")
        let range = rangePicker(in: app)
        try reveal(range, in: app); range.tap()
        let day = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "24 小时")).firstMatch
        try require(day.waitForExistence(timeout: 5) && day.isHittable, "The native range picker must offer 24 hours")
        day.tap()
        try verifyRange("24 小时", in: app)
        capture(app, name: "feedback-guest-range-before-login")
        let login = app.buttons["feedback.login"]
        try reveal(login, in: app); login.tap()
        try require(app.navigationBars["登录并继续"].waitForExistence(timeout: 5), "The real root login sheet must appear")
        try require(app.staticTexts["login.continuation-context"].exists, "The sheet must explain feedback continuation")
        let passwordMethod = app.segmentedControls.buttons["密码"]
        try require(passwordMethod.waitForExistence(timeout: 5), "The standard-text login method must offer password sign-in")
        passwordMethod.tap()
        try require(app.textFields["login.username"].waitForExistence(timeout: 5)
                    && app.secureTextFields["login.password"].exists, "The actual password form must be ready")
    }

    private func fillPasswordForm(_ app: XCUIApplication, username: String, password: String) throws {
        let identifier = app.textFields["login.username"]
        try reveal(identifier, in: app, upward: false)
        identifier.tap(); identifier.typeText(username)
        let secure = app.secureTextFields["login.password"]
        try reveal(secure, in: app)
        secure.tap()
        // Named pasteboards cannot supply the native Paste action. The general
        // board here is only the owned simulator's board, written by the runner.
        // localOnly disables Handoff; the separate opt-in is required because
        // Simulator's host bridge must also be isolated and audited externally.
        let board = UIPasteboard.general
        board.setObjects([password as NSString], localOnly: true, expirationDate: Date().addingTimeInterval(45))
        let writtenChange = board.changeCount
        defer {
            // Do not erase a later writer's contents or read/restore any user's
            // previous clipboard data. Expiration also bounds failed UI input.
            if board.changeCount == writtenChange { board.setItems([], options: [.localOnly: true]) }
        }
        secure.press(forDuration: 1.0)
        let labels = NSPredicate(format: "label == %@ OR label == %@", "粘贴", "Paste")
        let button = app.buttons.matching(labels).firstMatch
        let item = app.menuItems.matching(labels).firstMatch
        let paste = button.waitForExistence(timeout: 2) ? button : item
        try require(paste.waitForExistence(timeout: 3) && paste.isHittable,
                    "The native secure-field Paste action must be available")
        paste.tap()
        // No password is passed to an XCUI text-input action, queried as a value
        // or attached. The canary still has to prove that snapshots/events do
        // not disclose it and that the Mac pasteboard never changes.
    }

    private func dismissKeyboard(_ app: XCUIApplication) throws {
        let dismiss = app.buttons["login.dismiss-keyboard"].exists
            ? app.buttons["login.dismiss-keyboard"] : app.buttons["feedback.dismiss-keyboard"]
        if dismiss.exists { try require(dismiss.isHittable, "The keyboard dismissal action must be visible"); dismiss.tap() }
        try disappeared(app.keyboards.firstMatch, timeout: 5, message: "The keyboard must actually disappear")
    }

    private func cancelLogin(_ app: XCUIApplication) throws {
        let cancel = app.navigationBars["登录并继续"].buttons["取消"]
        try require(cancel.exists && cancel.isHittable, "The native login cancellation action must be available")
        cancel.tap()
        try disappeared(app.navigationBars["登录并继续"], timeout: 10, message: "Login cancellation must dismiss its actual sheet")
        try require(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5), "Cancellation must return to the guest feedback")
        try dismissObservedPasswordSavePrompt(app)
    }

    private func verifyDraft(_ app: XCUIApplication, expectedRange: String) throws {
        try dismissObservedPasswordSavePrompt(app)
        let editor = app.textViews["feedback.description"]
        try reveal(editor, in: app, upward: false)
        try require((editor.value as? String) == draft, "Feedback must contain the exact original multiline emoji text")
        try verifyRange(expectedRange, in: app)
    }

    private func rangePicker(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "feedback.range").firstMatch
    }

    private func verifyRange(_ expected: String, in app: XCUIApplication) throws {
        let range = rangePicker(in: app)
        try reveal(range, in: app)
        try require((range.value as? String) == expected || range.label.contains(expected)
                    || range.descendants(matching: .any).matching(NSPredicate(format: "label == %@", expected)).firstMatch.exists,
                    "The feedback range must match the expected native picker selection")
    }

    private func returnToMe(_ app: XCUIApplication) throws {
        if app.navigationBars["反馈与建议"].exists {
            let back = app.navigationBars["反馈与建议"].buttons["我"]
            try require(back.exists && back.isHittable, "The resumed feedback must have Me as its Back destination")
            back.tap()
        }
        try require(app.navigationBars["我"].waitForExistence(timeout: 10), "Back must reveal the actual Me root")
    }

    private func activeIdentity(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "@" + username)).firstMatch
    }

    private func dismissObservedPasswordSavePrompt(_ app: XCUIApplication) throws {
        // The first canary recording shows this exact system card after Cancel.
        // It intercepts every scroll while leaving the feedback navigation bar
        // visible. Never save synthetic or real credentials into Passwords.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let title = NSPredicate(format: "label == %@ OR label == %@", "保存密码？", "Save Password?")
        for surface in [app, springboard] {
            let prompt = surface.descendants(matching: .any).matching(title).firstMatch
            if prompt.waitForExistence(timeout: 1) {
                passwordSavePromptObserved = true
                let later = surface.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "以后", "Not Now")).firstMatch
                try require(later.exists && later.isHittable, "The observed password-save card must offer Not Now")
                later.tap()
                try disappeared(prompt, timeout: 5, message: "The password-save card must actually disappear")
                passwordSavePromptDeclined = true
                return
            }
        }
    }

    private func revealMeIdentity(_ app: XCUIApplication) throws {
        for _ in 0..<24 {
            if app.buttons["me.login"].isHittable || activeIdentity(in: app).isHittable { return }
            app.swipeDown()
        }
        throw JourneyFailure(message: "The expected guest or approved identity could not be reached")
    }

    private func removeOwnedAccount(_ app: XCUIApplication) throws -> Bool {
        if app.navigationBars["登录并继续"].exists {
            // A committed account can outlive an unsuccessful UI continuation;
            // do not require the old guest destination during cleanup.
            let cancel = app.navigationBars["登录并继续"].buttons["取消"]
            try require(cancel.exists && cancel.isHittable, "Cleanup needs the native login cancellation action")
            cancel.tap()
            try disappeared(app.navigationBars["登录并继续"], timeout: 10, message: "Cleanup could not dismiss the login sheet")
            try dismissObservedPasswordSavePrompt(app)
        }
        try returnToMe(app)
        try revealMeIdentity(app)
        if app.buttons["me.login"].exists { return false } // No published account; do not invent a remote sign-out result.
        try require(activeIdentity(in: app).exists, "Refuse to remove an account other than the approved synthetic identity")
        let management = app.buttons["账号管理"]
        try reveal(management, in: app); management.tap()
        try require(app.navigationBars["账号管理"].waitForExistence(timeout: 5), "The real account management page must appear")
        try require(activeIdentity(in: app).exists, "The owned identity must still be present before removal")
        let logout = app.buttons["退出当前账号"]
        try reveal(logout, in: app); logout.tap()
        let confirm = app.buttons["退出并移除"]
        try require(confirm.waitForExistence(timeout: 5) && confirm.isHittable, "Native removal requires its explicit confirmation")
        confirm.tap()
        try require(app.navigationBars["我"].waitForExistence(timeout: 10)
                    && app.buttons["me.login"].waitForExistence(timeout: 5), "Local identity reset must return to guest Me")
        // Me.id resets before AccountStore.remove finishes its remote request.
        // Observe the existing 30s auth resource timeout plus delivery margin;
        // absence of notice is reported separately from an HTTP acknowledgement.
        let failureNotice = app.staticTexts["已在此设备退出，暂时未能同步退出状态。"]
        let failure = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: failureNotice)
        failure.isInverted = true
        try require(XCTWaiter.wait(for: [failure], timeout: 35) == .completed,
                    "Native removal reported that remote sign-out did not finish")
        try require(app.buttons["me.login"].exists, "The fixture must remain signed out")
        capture(app, name: "feedback-real-login-account-removed")
        return true
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) throws {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        throw JourneyFailure(message: "A required native control could not be reached by scrolling")
    }

    private func disappeared(_ element: XCUIElement, timeout: TimeInterval, message: String) throws {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        try require(XCTWaiter.wait(for: [gone], timeout: timeout) == .completed, message)
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw JourneyFailure(message: message) }
    }

    private func capture(_ app: XCUIApplication, name: String, includeTree: Bool = true, allowCanarySecureTree: Bool = false) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        if includeTree, allowCanarySecureTree || !app.secureTextFields["login.password"].exists {
            let hierarchy = app.debugDescription + (allowCanarySecureTree
                ? "\nSYSTEM SURFACE:\n" + XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription : "")
            let tree = XCTAttachment(string: hierarchy)
            tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
        }
    }

    private func report(_ values: [String: Any]) {
        var observation = values
        observation["passwordSavePromptAtLaunch"] = passwordSavePromptAtLaunch
        observation["passwordSavePromptObservedAfterInput"] = passwordSavePromptObserved
        observation["passwordSavePromptDeclinedAfterInput"] = passwordSavePromptDeclined
        guard let data = try? JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "feedback-login-ui-scope"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private struct JourneyFailure: Error { let message: String }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }

    private func consumeCredential(onConsumed: () -> Void) throws -> Credential {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iOSNativeValidation", isDirectory: true)
        let folder = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw JourneyFailure(message: "The runner's private one-shot input directory is unavailable") }
        defer { Darwin.close(folder) }
        var folderInfo = stat()
        try require(fstat(folder, &folderInfo) == 0 && folderInfo.st_uid == geteuid()
                    && folderInfo.st_mode & mode_t(0o7777) == mode_t(0o700), "The runner input directory must be owner-only 0700")
        let file = openat(folder, "feedback-login-account.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw JourneyFailure(message: "The runner's one-shot credential input is unavailable") }
        defer { Darwin.close(file) }
        var info = stat()
        try require(fstat(file, &info) == 0 && info.st_uid == geteuid() && info.st_nlink == 1
                    && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                    && info.st_mode & mode_t(0o7777) == mode_t(0o600)
                    && info.st_size > 0 && info.st_size <= 65_536,
                    "Input must be a bounded owner-only 0600 regular file without links")
        // Consume the verified open inode before reading/parsing. Even malformed
        // input leaves no pathname behind, and no second test can read it again.
        try require(unlinkat(folder, "feedback-login-account.json", 0) == 0, "One-shot input could not be consumed")
        onConsumed()
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            try require(count >= 0 && data.count + max(0, count) <= 65_536, "One-shot input could not be read safely")
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        let pool: Pool
        do { pool = try JSONDecoder().decode(Pool.self, from: data) }
        catch { throw JourneyFailure(message: "One-shot input is malformed; values omitted") }
        guard pool.accounts.count == 1, let credential = pool.accounts.first,
              credential.id == "production-zero-balance", credential.environment == "production",
              credential.username == username, !credential.password.isEmpty, credential.password.utf8.count <= 1024,
              credential.password.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw JourneyFailure(message: "Only the fixed zero-balance synthetic identity may be used")
        }
        return credential
    }
}
