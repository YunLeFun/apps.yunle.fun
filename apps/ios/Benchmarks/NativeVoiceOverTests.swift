import XCTest
import UIKit

@MainActor
final class NativeVoiceOverTests: XCTestCase {
    private final class SpeechLog { var lines: [String] = [] }
    private let transcript = SpeechLog()
    private var transcriptName = ""
    private var inspectedApp: XCUIApplication?
    private var originalVoiceOverState: Bool?
    private var isDeveloperProfileJourney = false

    override func tearDownWithError() throws {
        if #available(iOS 27, *), let originalVoiceOverState {
            let service = XCUIDevice.shared.voiceOverService
            if service.isEnabled != originalVoiceOverState {
                if originalVoiceOverState { try service.enable() } else { try service.disable() }
            }
            transcript.lines.append("restoredEnabled: \(service.isEnabled); expected: \(originalVoiceOverState)")
            XCTAssertEqual(service.isEnabled, originalVoiceOverState, "Restore the original VoiceOver state")
        }
        let attachment = XCTAttachment(string: transcript.lines.joined(separator: "\n"))
        attachment.name = "voiceover-speech-\(transcriptName)"; attachment.lifetime = .keepAlways; add(attachment)
        if inspectedApp != nil {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "voiceover-return-screen-\(transcriptName)"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        if isDeveloperProfileJourney, let inspectedApp {
            let tree = XCTAttachment(string: inspectedApp.debugDescription)
            tree.name = "voiceover-complete-ax-\(transcriptName)"; tree.lifetime = .keepAlways; add(tree)
        }
        try super.tearDownWithError()
    }

    func testMeAtStandardText() throws { try checkMe(large: false) }
    func testMeAtLargestText() throws { try checkMe(large: true) }
    func testCatalogAtStandardText() throws { try checkCatalog(large: false) }
    func testCatalogAtLargestText() throws { try checkCatalog(large: true) }
    func testLoginAtStandardText() throws { try checkLogin(large: false) }
    func testLoginAtLargestText() throws { try checkLogin(large: true) }
    func testCatalogApplicationAtStandardText() throws { try checkCatalogApplication(large: false) }
    func testCatalogApplicationAtLargestText() throws { try checkCatalogApplication(large: true) }
    func testDiscoveryFeaturedAtStandardText() throws { try checkDiscoveryApplication(large: false, featured: true) }
    func testDiscoveryFeaturedAtLargestText() throws { try checkDiscoveryApplication(large: true, featured: true) }
    func testDiscoveryApplicationAtStandardText() throws { try checkDiscoveryApplication(large: false, featured: false) }
    func testDiscoveryApplicationAtLargestText() throws { try checkDiscoveryApplication(large: true, featured: false) }
    func testApplicationDetailAtStandardText() throws { try checkApplicationDetail(large: false) }
    func testApplicationDetailAtLargestText() throws { try checkApplicationDetail(large: true) }
    func testHelpAtStandardText() throws { try checkHelp(large: false) }
    func testHelpAtLargestText() throws { try checkHelp(large: true) }
    func testFeedbackAtStandardText() throws { try checkFeedback(large: false) }
    func testFeedbackAtLargestText() throws { try checkFeedback(large: true) }
    func testDeveloperProfileAtStandardText() throws { try checkDeveloperProfile(large: false) }
    func testDeveloperProfileAtLargestText() throws { try checkDeveloperProfile(large: true) }

    private func checkDeveloperProfile(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let environment = ProcessInfo.processInfo.environment
        guard environment["YLF_VOICEOVER_VALIDATION"] == "1", environment["YLF_DEVELOPER_PROFILE_VOICEOVER"] == "1" else {
            throw XCTSkip("Enable the real public author-profile VoiceOver journey explicitly")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("The author-profile VoiceOver journey only uses an owned simulator")
        #else
        continueAfterFailure = false
        executionTimeAllowance = 120
        guard let owned = environment["YLF_OWNED_BENCHMARK_SIMULATOR_UDID"], !owned.isEmpty,
              owned == environment["SIMULATOR_UDID"], environment["YLF_DEVELOPER_PROFILE_FRESH_GUEST_FIXTURE"] == "1",
              environment["YLF_BENCHMARK_TARGET"] != "legacy", UIDevice.current.userInterfaceIdiom == .phone,
              let appearance = environment["YLF_ACCESSIBILITY_APPEARANCE"], ["light", "dark"].contains(appearance) else {
            throw DeveloperProfileFailure(description: "Declare this owned iPhone simulator's fresh guest and explicit light/dark author fixture")
        }
        let app = try guestApp(tab: "我", large: large)
        let restoredGuest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["me.login"].exists && !app.progressIndicators["正在检查登录状态"].exists
        }, object: nil)
        guard XCTWaiter.wait(for: [restoredGuest], timeout: 15) == .completed else {
            throw DeveloperProfileFailure(description: "Account restoration must finish while the author fixture remains a guest")
        }
        try selectTab("云居", in: app)
        guard app.buttons["去工坊看看"].waitForExistence(timeout: 10), !app.buttons["home.running"].exists,
              !app.webViews.firstMatch.exists,
              app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).count == 0 else {
            throw DeveloperProfileFailure(description: "The author VoiceOver journey requires a real empty guest home with no running application")
        }
        isDeveloperProfileJourney = true
        inspectedApp = app
        transcriptName = "developer-profile-\(large ? "largest" : "standard")-\(appearance)"
        let requestedLogin = "YunYouJun"
        app.open(try XCTUnwrap(URL(string: "yunlefun://developer/\(requestedLogin)")))
        let names = app.staticTexts.matching(identifier: "developer.name")
        let counts = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ 个公开作品$"))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "developer.application."))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard counts.firstMatch.exists else { return false }
            let count = Int(counts.firstMatch.label.components(separatedBy: " ").first ?? "") ?? 0
            return app.state == .runningForeground && self.developerNavigationBar(in: app, login: requestedLogin).exists
                && names.count == 1 && count > 0 && rows.firstMatch.exists
                && !app.descendants(matching: .any).matching(identifier: "developer.loading").firstMatch.exists
                && !app.descendants(matching: .any).matching(identifier: "developer.error").firstMatch.exists
        }, object: nil)
        guard XCTWaiter.wait(for: [loaded], timeout: 25) == .completed else {
            throw DeveloperProfileFailure(description: "The real anonymous author page must load a name, count and public work")
        }
        let navigation = developerNavigationBar(in: app, login: requestedLogin)
        let ownerLogin = navigation.identifier.isEmpty ? navigation.label : navigation.identifier
        let authorName = names.firstMatch, countElement = counts.firstMatch, row = rows.firstMatch
        let displayName = authorName.label, countLabel = countElement.label
        let count = try XCTUnwrap(Int(countLabel.components(separatedBy: " ").first ?? ""))
        let identifier = row.identifier, rowLabel = row.label
        let content = row.staticTexts.matching(NSPredicate(format: "label != %@ AND label != ''", rowLabel))
        guard ownerLogin.caseInsensitiveCompare(requestedLogin) == .orderedSame, !displayName.isEmpty, count > 0,
              !identifier.isEmpty, content.count >= 2 else {
            throw DeveloperProfileFailure(description: "Read the author identity and the real child title/summary from the actual public row")
        }
        let title = content.element(boundBy: 0).label, summary = content.element(boundBy: 1).label
        guard !title.isEmpty, !summary.isEmpty, normalized(rowLabel).contains(normalized(title)),
              normalized(rowLabel).contains(normalized(summary)) else {
            throw DeveloperProfileFailure(description: "The actual row must expose its complete title and summary without parsing a fabricated label")
        }
        captureDeveloperProfile(app, phase: "loaded")
        try withVoiceOver(app: app, name: transcriptName) { voiceOver, speech in
            speech.lines.append("observed UI (not speech): owner=\(ownerLogin); name=\(displayName); count=\(countLabel); row=\(identifier)")
            speech.lines.append("expected complete row from UI (not speech): \(rowLabel)")
            speech.lines.append("scope: real anonymous public profile; no login/acquire/open/share; no system accessibility audit")
            try seek(displayName, service: voiceOver, speech: speech, labelBoundary: true, requiredSpeech: "标题")
            XCTAssertTrue(normalized(try voiceOver.currentSpeech().utterance).contains(normalized(displayName)),
                          "Read the complete observed author name as a heading")
            try expectDeveloperContent([authorName], in: app, navigation: navigation)
            let handle = app.staticTexts["@\(ownerLogin)"]
            if displayName != ownerLogin {
                XCTAssertTrue(handle.exists, "The public identifier must exist when it differs from the displayed author name")
                try seek(ownerLogin, service: voiceOver, speech: speech)
                XCTAssertTrue(normalized(try voiceOver.currentSpeech().utterance).contains(normalized(ownerLogin)),
                              "Read the actual public author identifier")
                try expectDeveloperContent([handle], in: app, navigation: navigation)
            }
            try seek("个公开作品", service: voiceOver, speech: speech)
            let countSpeech = try voiceOver.currentSpeech().utterance
            speech.lines.append("observed count speech: \(countSpeech)")
            XCTAssertNotNil(normalized(countSpeech).range(of: "(?<![0-9])\(count)个公开作品", options: .regularExpression),
                            "VoiceOver must read the actual dynamic count, not merely expose it in the AX tree")
            try expectDeveloperContent([countElement], in: app, navigation: navigation)
            captureDeveloperProfile(app, phase: "spoken-author")

            try seek(title, service: voiceOver, speech: speech)
            let workSpeech = try voiceOver.currentSpeech().utterance
            speech.lines.append("observed complete work speech: \(workSpeech)")
            XCTAssertTrue(normalized(workSpeech).contains(normalized(rowLabel)), "Read the complete observed work title, summary and any access condition")
            XCTAssertTrue(workSpeech.contains("按钮"), "The spoken public work must be the actionable native NavigationLink")
            let selected = app.buttons[identifier]
            XCTAssertTrue(selected.exists && selected.isHittable)
            try expectDeveloperContent([selected.staticTexts[title], selected.staticTexts[summary]], in: app, navigation: navigation)
            captureDeveloperProfile(app, phase: "spoken-work")
            selected.doubleTap()
            let detail = app.navigationBars[title]
            XCTAssertTrue(detail.waitForExistence(timeout: 5))
            XCTAssertFalse(app.webViews.firstMatch.exists, "VoiceOver double-tap must enter native detail without running the application")
            XCTAssertTrue(detail.buttons["分享作者主页"].exists)
            try seek("作者公开发布的版本", service: voiceOver, speech: speech, labelBoundary: true)
            XCTAssertTrue(normalized(try voiceOver.currentSpeech().utterance).contains(normalized("作者公开发布的版本")))
            try expectDeveloperContent([app.staticTexts["作者公开发布的版本"]], in: app, navigation: detail)
            captureDeveloperProfile(app, phase: "detail")

            let back = detail.buttons.element(boundBy: 0)
            let backLabel = back.label
            XCTAssertTrue(back.exists && (backLabel.caseInsensitiveCompare(ownerLogin) == .orderedSame
                || backLabel.contains("返回") || backLabel.lowercased() == "back"))
            try seek(backLabel, service: voiceOver, speech: speech, forward: false, labelBoundary: true, requiredSpeech: "返回")
            XCTAssertTrue(back.isHittable)
            back.doubleTap()
            XCTAssertTrue(developerNavigationBar(in: app, login: ownerLogin).waitForExistence(timeout: 5))
            expectFocus(title, service: voiceOver, speech: speech, completeText: [rowLabel])
            let returnedSpeech = try voiceOver.currentSpeech().utterance
            speech.lines.append("observed restored complete work speech: \(returnedSpeech)")
            XCTAssertTrue(returnedSpeech.contains("按钮"))
            XCTAssertTrue(app.buttons[identifier].exists && app.buttons[identifier].isHittable)
            try expectDeveloperContent([app.buttons[identifier].staticTexts[title], app.buttons[identifier].staticTexts[summary]],
                                       in: app, navigation: developerNavigationBar(in: app, login: ownerLogin))
            XCTAssertTrue(app.state == .runningForeground && !app.webViews.firstMatch.exists)
            captureDeveloperProfile(app, phase: "restored-work-focus")
        }
        #endif
    }

    private func developerNavigationBar(in app: XCUIApplication, login: String) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@ OR label ==[c] %@", login, login)).firstMatch
    }

    private func expectDeveloperContent(_ elements: [XCUIElement], in app: XCUIApplication, navigation: XCUIElement) throws {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard app.state == .runningForeground, navigation.exists, app.tabBars.firstMatch.exists else { return false }
            let top = navigation.frame.maxY, bottom = app.tabBars.firstMatch.frame.minY
            let window = app.windows.firstMatch.frame
            return elements.allSatisfy { $0.exists && $0.isHittable && $0.frame.minY >= top - 1 && $0.frame.maxY <= bottom + 1
                && $0.frame.minX >= window.minX - 1 && $0.frame.maxX <= window.maxX + 1 }
        }, object: nil)
        guard XCTWaiter.wait(for: [visible], timeout: 5) == .completed else {
            throw DeveloperProfileFailure(description: "VoiceOver must reveal the actual complete focused author/work text between the native bars")
        }
    }

    private func captureDeveloperProfile(_ app: XCUIApplication, phase: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "voiceover-\(transcriptName)-\(phase)-screen"; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "voiceover-\(transcriptName)-\(phase)-complete-ax"; tree.lifetime = .keepAlways; add(tree)
    }

    private struct DeveloperProfileFailure: Error, CustomStringConvertible { let description: String }

    private func guestApp(tab: String, large: Bool) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["YLF_VOICEOVER_VALIDATION"] == "1" else {
            throw XCTSkip("Enable the explicit guest VoiceOver journeys separately from daily tests")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fun.yunle.apps.benchmark-dev")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if let appearance = ProcessInfo.processInfo.environment["YLF_ACCESSIBILITY_APPEARANCE"] {
            XCTAssertTrue(["system", "light", "dark"].contains(appearance))
            app.launchArguments += ["-appearance", appearance]
        }
        app.launch()
        try selectTab("我", in: app)
        XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
        guard app.buttons["me.login"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Use a guest Benchmark app; do not sign out an existing account")
        }
        if tab != "我" { try selectTab(tab, in: app) }
        XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        if tab == "工坊" {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "全部应用 · ")).firstMatch.waitForExistence(timeout: 15))
        } else if tab == "寻乐" {
            XCTAssertTrue(app.staticTexts["发现一点小乐趣"].waitForExistence(timeout: 15))
        }
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication) throws {
        let symbols = ["云居": "house", "寻乐": "safari", "工坊": "square.grid.2x2", "我": "person.crop.circle"]
        let symbol = try XCTUnwrap(symbols[title])
        let phoneTab = app.tabBars.buttons[title]
        // iPad's native floating tabs expose symbol-identified buttons outside a TabBar.
        let floatingTab = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", symbol, title)).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            phoneTab.exists || floatingTab.exists
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        XCTAssertEqual(result, .completed, "The native tab must exist before selecting it")
        guard result == .completed else { throw NavigationError.missingTab }
        let button = phoneTab.exists ? phoneTab : floatingTab
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private enum NavigationError: Error { case missingTab }

    private func checkHelp(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "我", large: large)
        try withVoiceOver(app: app, name: "help-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("使用帮助", service: voiceOver, speech: speech, labelBoundary: true)
            let help = app.buttons["me.help"]
            XCTAssertTrue(help.exists)
            XCTAssertTrue(help.isHittable, "VoiceOver must reveal the actual native help entry")
            help.doubleTap()
            XCTAssertTrue(app.navigationBars["帮助"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.webViews.firstMatch.exists, "First-party help must remain native")

            let question = "云乐坊是什么？"
            try seek("云乐坊是什么", service: voiceOver, speech: speech)
            let faq = app.buttons["help.faq.what"]
            XCTAssertTrue(faq.exists)
            XCTAssertTrue(faq.isHittable, "VoiceOver must reveal the real FAQ disclosure control")
            XCTAssertTrue(normalized(try voiceOver.currentSpeech().utterance).contains(normalized(question)))
            faq.doubleTap()
            let answer = "云乐坊汇集各类云应用和实用工具。你可以在工坊发现应用，在云居保存入口，打开后直接使用。"
            XCTAssertTrue(app.staticTexts[answer].waitForExistence(timeout: 5))
            try seek("云乐坊汇集各类云应用和实用工具", service: voiceOver, speech: speech)
            XCTAssertTrue(normalized(try voiceOver.currentSpeech().utterance).contains(normalized(answer)),
                          "VoiceOver must read the complete expanded native FAQ answer")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voiceover-help-expanded-faq-\(large ? "largest" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)

            try seek("我", service: voiceOver, speech: speech, forward: false, labelBoundary: true)
            app.navigationBars["帮助"].buttons.element(boundBy: 0).doubleTap()
            XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
            expectFocus("使用帮助", service: voiceOver, speech: speech)
        }
    }

    private func checkFeedback(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "我", large: large)
        try withVoiceOver(app: app, name: "feedback-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("反馈与建议", service: voiceOver, speech: speech, labelBoundary: true)
            let feedback = app.buttons["me.feedback"]
            XCTAssertTrue(feedback.exists)
            XCTAssertTrue(feedback.isHittable, "VoiceOver must reveal the actual native feedback entry")
            feedback.doubleTap()
            XCTAssertTrue(app.navigationBars["反馈与建议"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.webViews.firstMatch.exists, "First-party feedback must remain native")

            try seek("问题描述", service: voiceOver, speech: speech, labelBoundary: true)
            let description = app.textViews["feedback.description"]
            XCTAssertTrue(description.exists)
            XCTAssertTrue(description.isHittable, "VoiceOver must expose the native multiline description editor")
            XCTAssertTrue(try voiceOver.currentSpeech().utterance.contains("文本"),
                          "Read the actual editable text field rather than its section heading")
            let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
            editorScreenshot.name = "voiceover-feedback-description-\(large ? "largest" : "standard")"
            editorScreenshot.lifetime = .keepAlways; add(editorScreenshot)

            try seek("复制邮箱", service: voiceOver, speech: speech, labelBoundary: true)
            let copyEmail = app.buttons["support.feedback.copy-email"]
            XCTAssertTrue(copyEmail.exists)
            XCTAssertTrue(copyEmail.isHittable, "Contacting support must remain available to a guest without sending mail")
            XCTAssertTrue(try voiceOver.currentSpeech().utterance.contains("kf@yunle.fun"),
                          "Read which support address the fallback action copies")
            copyEmail.doubleTap()
            let notice = app.staticTexts["support.feedback.notice"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertTrue(notice.label.contains("邮箱已复制"))
            expectFocus("邮箱已复制", service: voiceOver, speech: speech)
            let copiedScreenshot = XCTAttachment(screenshot: app.screenshot())
            copiedScreenshot.name = "voiceover-feedback-copy-email-\(large ? "largest" : "standard")"
            copiedScreenshot.lifetime = .keepAlways; add(copiedScreenshot)

            try seek("我", service: voiceOver, speech: speech, forward: false, labelBoundary: true)
            app.navigationBars["反馈与建议"].buttons.element(boundBy: 0).doubleTap()
            XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
            expectFocus("反馈与建议", service: voiceOver, speech: speech)
        }
    }

    private func checkMe(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "我", large: large)
        try withVoiceOver(app: app, name: "me-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("登录云乐坊", service: voiceOver, speech: speech)
            for label in ["云居中的应用", "钱包", "云乐坊会员", "我的应用", "个人工坊", "账号管理", "设置"] {
                try next(label, service: voiceOver, speech: speech)
            }
            app.buttons["设置"].doubleTap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            try seek("显示模式", service: voiceOver, speech: speech)
            try seek("我", service: voiceOver, speech: speech, forward: false, labelBoundary: true)
            app.navigationBars["设置"].buttons.element(boundBy: 0).doubleTap()
            XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
            expectFocus("设置", service: voiceOver, speech: speech)
            for label in ["关于云乐坊", "支持", "我的举报", "使用帮助", "反馈与建议"] {
                try next(label, service: voiceOver, speech: speech)
            }
        }
    }

    private func checkLogin(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "我", large: large)
        try withVoiceOver(app: app, name: "login-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("登录云乐坊", service: voiceOver, speech: speech)
            app.buttons["me.login"].doubleTap()
            XCTAssertTrue(app.navigationBars["账号"].waitForExistence(timeout: 5))
            let phoneField = app.textFields["login.phone"]
            XCTAssertTrue(phoneField.exists)
            try seek("手机号", service: voiceOver, speech: speech, labelBoundary: true)
            let utterance = try voiceOver.currentSpeech().utterance
            XCTAssertTrue(utterance.contains("文本栏"), "Read the phone text field, not the login-method picker: \(utterance)")
            XCTAssertTrue(phoneField.isHittable, "VoiceOver must reveal the actual phone field")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voiceover-login-field-\(large ? "largest" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)
            try seek("取消", service: voiceOver, speech: speech, forward: false)
            app.buttons["取消"].doubleTap()
            XCTAssertTrue(app.navigationBars["我"].waitForExistence(timeout: 5))
            expectFocus("登录云乐坊", service: voiceOver, speech: speech)
        }
    }

    private func checkCatalogApplication(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "工坊", large: large)
        try withVoiceOver(app: app, name: "catalog-application-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("FC 红白机", service: voiceOver, speech: speech)
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "catalog.application.", "FC 红白机")).firstMatch
            XCTAssertTrue(row.exists)
            let utterance = try voiceOver.currentSpeech().utterance
            XCTAssertTrue(normalized(utterance).contains(normalized(row.label)), "Read the full application title and summary")
            let title = app.staticTexts["FC 红白机"]
            let summary = app.staticTexts["基于 JSNES 与 Vue 实现的红白机 FC"]
            let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard title.exists, summary.exists else { return false }
                let top = app.navigationBars["工坊"].frame.maxY
                let bottom = app.tabBars.firstMatch.frame.minY
                return title.frame.minY >= top - 1 && summary.frame.maxY <= bottom + 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 5), .completed,
                           "VoiceOver must reveal the focused title and summary between the system bars")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voiceover-application-revealed-\(large ? "largest" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }

    private func checkDiscoveryApplication(large: Bool, featured: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "寻乐", large: large)
        let title = featured ? "今天来做菜" : "云栈"
        let summary = featured ? "好的，今天我们来做菜！可以根据所选食材筛选菜谱" : "面向 Valaxy、VitePress 与 Git 内容站点的轻量内容工作台"
        try withVoiceOver(app: app, name: "discovery-\(featured ? "featured" : "application")-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek(title, service: voiceOver, speech: speech)
            let row = featured ? app.buttons["discovery.featured"] : app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "discovery.application.", title)).firstMatch
            XCTAssertTrue(row.exists)
            let utterance = try voiceOver.currentSpeech().utterance
            XCTAssertTrue(normalized(utterance).contains(normalized(title)))
            XCTAssertTrue(normalized(utterance).contains(normalized(summary)), "Read the full public application summary")
            var content = [row.staticTexts[title], row.staticTexts[summary]]
            if !featured {
                XCTAssertTrue(utterance.contains("需要邀请"), "Read the access condition together with the application")
                content.append(row.staticTexts["需要邀请"])
            }
            let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let top = app.navigationBars["寻乐"].frame.maxY
                let bottom = app.tabBars.firstMatch.frame.minY
                return content.allSatisfy { $0.exists && $0.frame.minY >= top - 1 && $0.frame.maxY <= bottom + 1 }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 5), .completed,
                           "VoiceOver must reveal the complete application text between the system bars")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voiceover-discovery-revealed-\(featured ? "featured" : "application")-\(large ? "largest" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }

    private func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private func checkApplicationDetail(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "寻乐", large: large)
        let title = "今天来做菜"
        try withVoiceOver(app: app, name: "application-detail-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek(title, service: voiceOver, speech: speech)
            app.buttons["discovery.featured"].doubleTap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["获取"].exists || app.buttons["打开"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 5), .completed)
            let primary = app.buttons["获取"].exists ? app.buttons["获取"] : app.buttons["打开"]
            try seek(primary.label, service: voiceOver, speech: speech, labelBoundary: true)
            XCTAssertTrue(try voiceOver.currentSpeech().utterance.contains("按钮"), "Read the actual primary action")
            XCTAssertTrue(primary.isHittable)
            let bottomTabBar = app.tabBars.firstMatch
            XCTAssertTrue(bottomTabBar.exists || UIDevice.current.userInterfaceIdiom == .pad,
                          "The iPhone detail must retain its native bottom TabBar")
            let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                // iPad's native floating tabs are above the content, with no bottom TabBar.
                let bottom = bottomTabBar.exists ? bottomTabBar.frame.minY : app.windows.firstMatch.frame.maxY
                return primary.frame.minY >= app.navigationBars[title].frame.maxY - 1
                    && primary.frame.maxY <= bottom + 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 5), .completed,
                           "VoiceOver must reveal the focused action below navigation and above any bottom TabBar")
            if primary.label == "获取" {
                try next("试用", service: voiceOver, speech: speech)
                XCTAssertTrue(app.buttons["试用"].isHittable)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voiceover-detail-action-\(large ? "largest" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)
            try seek("寻乐", service: voiceOver, speech: speech, forward: false, labelBoundary: true)
            app.navigationBars[title].buttons.element(boundBy: 0).doubleTap()
            XCTAssertTrue(app.navigationBars["寻乐"].waitForExistence(timeout: 5))
            expectFocus(title, service: voiceOver, speech: speech)
        }
    }

    private func checkCatalog(large: Bool) throws {
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let app = try guestApp(tab: "工坊", large: large)
        try withVoiceOver(app: app, name: "catalog-\(large ? "largest" : "standard")") { voiceOver, speech in
            try seek("搜索应用", service: voiceOver, speech: speech)
            for label in ["我的应用", "个人工坊", "打开个人工坊"] {
                try next(label, service: voiceOver, speech: speech)
            }
            app.buttons["打开个人工坊"].doubleTap()
            XCTAssertTrue(app.navigationBars["打开个人工坊"].waitForExistence(timeout: 5))
            try seek("工坊编号或链接", service: voiceOver, speech: speech)
            try next("打开工坊", service: voiceOver, speech: speech)
            XCTAssertFalse(app.buttons["workshop.lookup.open"].isEnabled)
            try seek("工坊", service: voiceOver, speech: speech, forward: false, labelBoundary: true)
            app.navigationBars["打开个人工坊"].buttons.element(boundBy: 0).doubleTap()
            XCTAssertTrue(app.navigationBars["工坊"].waitForExistence(timeout: 5))
            expectFocus("打开个人工坊", service: voiceOver, speech: speech)
        }
    }

    @available(iOS 27, *)
    private func withVoiceOver(app: XCUIApplication, name: String,
                               body: (XCUIVoiceOverService, SpeechLog) throws -> Void) throws {
        let service = XCUIDevice.shared.voiceOverService
        originalVoiceOverState = service.isEnabled
        inspectedApp = app; transcriptName = name
        transcript.lines = ["initiallyEnabled: \(service.isEnabled)"]
        if !service.isEnabled { try service.enable() }
        XCTAssertTrue(service.isEnabled)
        transcript.lines.append("initial: \(try service.currentSpeech().utterance)")
        try body(service, transcript)
    }

    @available(iOS 27, *)
    private func expectFocus(_ label: String, service: XCUIVoiceOverService, speech: SpeechLog, completeText: [String] = []) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let output = try? service.currentSpeech() else { return false }
            let line = "return: \(output.utterance)"
            if speech.lines.last != line { speech.lines.append(line) }
            return output.utterance.contains(label) && completeText.allSatisfy { self.normalized(output.utterance).contains(self.normalized($0)) }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "Returning must restore VoiceOver focus to \(label)")
        XCTAssertTrue(service.isEnabled)
    }

    @available(iOS 27, *)
    private func seek(_ label: String, service: XCUIVoiceOverService, speech: SpeechLog,
                      forward: Bool = true, labelBoundary: Bool = false, requiredSpeech: String? = nil) throws {
        var previous: String?
        var repeated = 0
        for _ in 0..<25 {
            let utterance = try service.currentSpeech().utterance
            speech.lines.append("focus: \(utterance)")
            if utterance.contains(label) && (!labelBoundary || utterance == label || utterance.hasPrefix(label + " ") || utterance.hasPrefix(label + "，") || utterance.hasPrefix(label + ","))
                && (requiredSpeech.map { utterance.contains($0) } ?? true) { return }
            repeated = previous == utterance ? repeated + 1 : 0
            if repeated == 3 { break }
            previous = utterance
            let moved = try forward ? service.moveForward() : service.moveBackward()
            speech.lines.append("\(forward ? "next" : "previous"): \(moved.utterance)")
        }
        XCTFail("VoiceOver could not reach \(label)")
    }

    @available(iOS 27, *)
    private func next(_ label: String, service: XCUIVoiceOverService, speech: SpeechLog) throws {
        let utterance = try service.moveForward().utterance
        speech.lines.append("next: \(utterance)")
        XCTAssertTrue(utterance.contains(label), "Expected the next VoiceOver stop to be \(label); heard \(utterance)")
    }
}
