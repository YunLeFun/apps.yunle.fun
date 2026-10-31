import XCTest
import UIKit

@MainActor
final class NativeGamesUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testGamesTabShowsNativeGamesAndRejectsInvalidRoomInput() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let tab = app.tabBars.buttons["寻乐"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        XCTAssertTrue(app.navigationBars["寻乐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["games.launch.gomoku.computer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["games.launch.gomoku.computer"].isEnabled)
        capture(app, "native-games-discovery")

        let join = app.buttons["games.join-room"]
        XCTAssertTrue(join.waitForExistence(timeout: 10)); join.tap()
        let field = app.textFields["games.room-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("BAD")
        app.buttons["games.room-submit"].tap()
        XCTAssertTrue(app.staticTexts["games.room-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["加入房间"].exists)
        capture(app, "native-games-invalid-room")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["寻乐"].waitForExistence(timeout: 5))
    }

    func testWorkshopContainsAIFinderAndSearchFocusesOnResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let tab = app.tabBars.buttons["工坊"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        let assistant = app.buttons["catalog.assistant"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 5))
        capture(app, "native-workshop-discovery")
        assistant.tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons["工坊"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        XCTAssertTrue(assistant.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("native-no-match-fixture")
        XCTAssertTrue(assistant.waitForNonExistence(timeout: 5), "A focused search must not force users past recommendations")
        capture(app, "native-workshop-search")
    }

    func testGuestCanCancelRoomLoginAndReturnToGames() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        guard app.buttons["me.login"].waitForExistence(timeout: 5) else {
            throw XCTSkip("This journey requires a guest; never signs out an existing account")
        }
        app.tabBars.buttons["寻乐"].tap()
        let join = app.buttons["games.join-room"]
        XCTAssertTrue(join.waitForExistence(timeout: 5)); join.tap()
        let input = app.textFields["games.room-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("ABC234")
        app.buttons["games.room-submit"].tap()
        XCTAssertTrue(app.staticTexts["login.continuation-context"].waitForExistence(timeout: 10))
        capture(app, "native-games-room-login")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["寻乐"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["login.continuation-context"].exists)
        XCTAssertTrue(app.buttons["games.join-room"].exists)
        capture(app, "native-games-room-login-cancelled")
    }

    func testMaximumAccessibilityTextSizeAuditsNativeGamesAndWorkshop() throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAMES_ACCESSIBILITY_AUDIT"] == "1" else {
            throw XCTSkip("Opt in with YUNLEFUN_NATIVE_GAMES_ACCESSIBILITY_AUDIT=1")
        }
        guard #available(iOS 17, *) else { throw XCTSkip("XCTest accessibility auditing requires iOS 17") }
        let originalContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true // Audit both tabs even when the first has genuine accessibility issues.
        defer { continueAfterFailure = originalContinueAfterFailure }
        let category = "UICTContentSizeCategoryAccessibilityXXXL"
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
        app.launch()
        defer { app.terminate() }

        let screens = [(name: "寻乐", anchor: "games.launch.gomoku.computer", spokenName: "五子棋"),
                       (name: "工坊", anchor: "catalog.assistant", spokenName: "AI")]
        for screen in screens {
            let tab = app.tabBars.buttons[screen.name]
            guard tab.waitForExistence(timeout: 10) else {
                XCTFail("The native \(screen.name) tab must be available for its accessibility audit")
                continue
            }
            tab.tap()
            guard app.navigationBars[screen.name].waitForExistence(timeout: 5) else {
                XCTFail("The native \(screen.name) screen did not open")
                continue
            }
            let control = app.buttons[screen.anchor]
            _ = control.waitForExistence(timeout: 10)
            for _ in 0..<6 {
                if control.exists && control.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(control.exists, "The primary native control must remain accessible at the maximum text size")
            if control.exists {
                XCTAssertEqual(control.elementType, .button)
                XCTAssertTrue(control.label.contains(screen.spokenName), "VoiceOver needs a meaningful control name")
                XCTAssertNotEqual(control.label, screen.anchor, "An implementation identifier is not a spoken name")
                XCTAssertTrue(control.isHittable, "The primary control must remain reachable by scrolling")
            }
            auditAccessibility(app, screen: screen.name, requestedCategory: category)
        }
    }

    @MainActor
    func testVoiceOverNavigatesModesInviteValidationAndWorkshopReturn() throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAMES_VOICEOVER"] == "1" else {
            throw XCTSkip("Opt in with YUNLEFUN_NATIVE_GAMES_VOICEOVER=1")
        }
        guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver service requires iOS 27") }
        let originalContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = originalContinueAfterFailure }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let motion = settings.switches.matching(NSPredicate(format: "label CONTAINS %@", "减弱动态效果")).firstMatch
        // The labeled Settings row is also exposed as a switch, but only its
        // child UISwitch is the actual touch control (confirmed by the AX tree).
        let motionControl = motion.children(matching: .switch).firstMatch
        var originalMotion: String?
        defer {
            if let originalMotion {
                settings.activate()
                if motion.waitForExistence(timeout: 5) {
                    if motion.value as? String != originalMotion { motionControl.tap() }
                    XCTAssertEqual(motion.value as? String, originalMotion, "Restore the shared simulator's original Reduce Motion setting")
                    capture(settings, "native-reduce-motion-restored")
                } else {
                    XCTFail("Could not restore Reduce Motion; the prepared Settings > 无障碍 > 动态效果 page is unavailable")
                }
            }
        }
        if ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAMES_REDUCE_MOTION"] == "1" {
            // The opt-in journey is prepared on the actual system Motion page.
            // Read and change the system control, never a launch-argument substitute.
            settings.activate()
            guard motion.waitForExistence(timeout: 5), motionControl.waitForExistence(timeout: 5), let value = motion.value as? String,
                  ["0", "1"].contains(value) else {
                XCTFail("Prepare Settings > 无障碍 > 动态效果 before the Reduce Motion journey")
                return
            }
            originalMotion = value
            capture(settings, "native-reduce-motion-before")
            if value == "0" { motionControl.tap() }
            XCTAssertEqual(motion.value as? String, "1")
            capture(settings, "native-reduce-motion-enabled")
        }
        try exerciseVoiceOverNavigation()
    }

    @available(iOS 27, *)
    @MainActor
    private func exerciseVoiceOverNavigation() throws {
        let originalContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true // Throw through Swift so cleanup restores the shared device setting.
        defer { continueAfterFailure = originalContinueAfterFailure }
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                XCTFail(message)
                throw NSError(domain: "NativeVoiceOverJourney", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["YUNLEFUN_PLAY_PREVIEW"] = "1"
        app.launch()
        defer { app.terminate() }
        try require(app.tabBars.buttons["寻乐"].waitForExistence(timeout: 10), "The Games tab must exist")
        app.tabBars.buttons["寻乐"].tap() // Setup only; the journey below uses VoiceOver focus.
        try require(app.buttons["games.join-room"].waitForExistence(timeout: 10), "The invite action must exist")

        let service = XCUIDevice.shared.voiceOverService
        let originallyEnabled = service.isEnabled
        var transcript: [[String: String]] = []
        var completed = false
        defer {
            if !originallyEnabled && service.isEnabled {
                do { try service.disable() }
                catch { XCTFail("Could not restore the original VoiceOver setting: \(error)") }
            }
            let report: [String: Any] = ["kind": "native-voiceover-navigation", "completed": completed,
                "originallyEnabled": originallyEnabled, "enabledAfterCleanup": service.isEnabled,
                "reduceMotionEnabled": UIAccessibility.isReduceMotionEnabled,
                "events": transcript,
                "scope": "Actual XCUIVoiceOverService focus/speech with XCTest double-tap directed at the identified control; input text is injected into the VoiceOver-selected field; this does not test blind gesture placement, production identity, or game-content screen-reader support"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-voiceover-navigation.json"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        if ProcessInfo.processInfo.environment["YUNLEFUN_NATIVE_GAMES_REDUCE_MOTION"] == "1" {
            try require(UIAccessibility.isReduceMotionEnabled, "The system Reduce Motion setting must actually be enabled")
        }
        if !originallyEnabled { try service.enable() }
        try require(service.isEnabled, "VoiceOver must actually be enabled")

        @discardableResult
        func findSpeech(_ phase: String, backwards: Bool = false, limit: Int = 60,
                        matching predicate: (String) -> Bool) throws -> String {
            var speech = try service.currentSpeech().utterance
            transcript.append(["phase": phase, "action": "current", "utterance": speech])
            if predicate(speech) { return speech }
            var unchangedCount = 0
            var movingBackwards = backwards
            var reversedAtEdge = false
            for _ in 0..<limit {
                let next = try (movingBackwards ? service.moveBackward() : service.moveForward()).utterance
                unchangedCount = next == speech ? unchangedCount + 1 : 0
                speech = next
                transcript.append(["phase": phase, "action": movingBackwards ? "previous" : "next", "utterance": speech])
                if predicate(speech) { return speech }
                if unchangedCount >= 3 {
                    if reversedAtEdge { break }
                    movingBackwards.toggle(); reversedAtEdge = true; unchangedCount = 0
                    transcript.append(["phase": phase, "action": "reverse-at-screen-edge", "utterance": speech])
                }
            }
            XCTFail("VoiceOver could not reach \(phase) within \(limit) focus movements")
            throw NSError(domain: "NativeVoiceOverJourney", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unreachable VoiceOver control: \(phase)"])
        }

        func requireReturnContext(_ phase: String, header: String, control: String, maxForwardSteps: Int) throws {
            let deadline = Date().addingTimeInterval(3)
            repeat {
                let speech = try service.currentSpeech().utterance
                transcript.append(["phase": phase, "action": "current-without-navigation", "utterance": speech])
                if speech.contains(control) { return }
                if speech.contains(header) {
                    for _ in 0..<maxForwardSteps {
                        let next = try service.moveForward().utterance
                        transcript.append(["phase": phase, "action": "next-from-returned-header", "utterance": next])
                        if next.contains(control) { return }
                    }
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            } while Date() < deadline
            try require(false, "Returning must expose the \(header) context and make \(control) reachable within \(maxForwardSteps) VoiceOver steps")
        }

        try findSpeech("read-mode") { $0.contains("五子棋") && $0.contains("电脑对手") }
        try findSpeech("join-room", backwards: true) { $0.contains("加入房间") }
        capture(app, "native-voiceover-before-invite-activation")
        app.buttons["games.join-room"].doubleTap()
        let input = app.textFields["games.room-input"]
        try require(input.waitForExistence(timeout: 5), "VoiceOver activation must open the invite form")
        try findSpeech("room-input") { $0.contains("六位房间号或邀请链接") }
        input.doubleTap()
        input.typeText("BAD")
        try findSpeech("submit-invalid-room") { $0.contains("继续") }
        app.buttons["games.room-submit"].doubleTap()
        let error = app.staticTexts["games.room-error"]
        try require(error.waitForExistence(timeout: 5), "The invalid invite must show its error")
        let errorLabel = error.label
        try require(!errorLabel.isEmpty, "The invite error needs a spoken description")
        try findSpeech("read-room-error", backwards: true) { $0.contains(errorLabel) }
        capture(app, "native-voiceover-room-validation")

        try findSpeech("cancel-room", backwards: true) { $0.contains("取消") }
        app.buttons["取消"].doubleTap()
        try require(input.waitForNonExistence(timeout: 5), "VoiceOver activation must cancel the form")
        try requireReturnContext("invite-return-focus", header: "寻乐", control: "加入房间", maxForwardSteps: 1)

        try findSpeech("launch-computer-mode") { $0.contains("五子棋") && $0.contains("电脑对手") }
        app.buttons["games.launch.gomoku.computer"].doubleTap()
        try require(app.buttons["runtime.minimize"].waitForExistence(timeout: 20), "The actual game container must open")
        try findSpeech("minimize-game", backwards: true) { $0.contains("收起应用") }
        app.buttons["runtime.minimize"].doubleTap()
        try require(app.navigationBars["寻乐"].waitForExistence(timeout: 5), "Minimizing must return to Games")
        try require(app.buttons["games.resume.gomoku"].waitForExistence(timeout: 10), "The retained game needs a real resume entry")
        try findSpeech("resume-game", backwards: true) { $0.contains("五子棋") && $0.contains("恢复正在运行的游戏") }
        app.buttons["games.resume.gomoku"].doubleTap()
        try require(app.buttons["runtime.minimize"].waitForExistence(timeout: 10), "Resume must present the retained container")
        try findSpeech("minimize-resumed-game", backwards: true) { $0.contains("收起应用") }
        app.buttons["runtime.minimize"].doubleTap()
        try require(app.navigationBars["寻乐"].waitForExistence(timeout: 5), "The resumed game must minimize again")

        try findSpeech("workshop-tab", limit: 100) { $0.contains("工坊") }
        app.tabBars.buttons["工坊"].doubleTap()
        try require(app.navigationBars["工坊"].waitForExistence(timeout: 5), "VoiceOver activation must open Workshop")
        // iOS retains focus in the tab bar after selecting a tab. Touch exploration
        // of the visible heading starts reading the new page without disabling VO.
        let workshopHeading = app.navigationBars["工坊"].staticTexts["工坊"]
        try require(workshopHeading.waitForExistence(timeout: 5), "The Workshop heading must support touch exploration")
        workshopHeading.tap()
        transcript.append(["phase": "workshop-touch-exploration", "action": "single-tap-visible-heading",
                           "utterance": try service.currentSpeech().utterance])
        try findSpeech("ai-finder") { $0.contains("AI 找应用") }
        app.buttons["catalog.assistant"].doubleTap()
        try require(app.navigationBars["AI 助手"].waitForExistence(timeout: 5), "VoiceOver activation must open the AI finder")
        try findSpeech("assistant-back", backwards: true) { $0.contains("工坊") }
        app.navigationBars.buttons["工坊"].firstMatch.doubleTap()
        try require(app.navigationBars["工坊"].waitForExistence(timeout: 5), "VoiceOver activation must return to Workshop")
        try requireReturnContext("assistant-return-focus", header: "工坊", control: "AI 找应用", maxForwardSteps: 6)
        capture(app, "native-voiceover-workshop-return")
        completed = true
    }

    @available(iOS 17, *)
    private func auditAccessibility(_ app: XCUIApplication, screen: String, requestedCategory: String) {
        XCTContext.runActivity(named: "Maximum accessibility text: \(screen)") { activity in
            let types: XCUIAccessibilityAuditType = [.sufficientElementDescription, .trait, .textClipped, .dynamicType, .hitRegion]
            var issues: [[String: Any]] = []
            capture(app, "native-maximum-text-\(screen)")
            do {
                try app.performAccessibilityAudit(for: types) { issue in
                    issues.append(["type": issue.auditType.rawValue,
                                   "description": issue.compactDescription,
                                   "detail": issue.detailedDescription])
                    return false // Record every real issue through XCTest; no filtering or suppression.
                }
            } catch {
                XCTFail("Accessibility audit could not run for \(screen): \(error)")
            }
            let report: [String: Any] = ["screen": screen, "requestedContentSizeCategory": requestedCategory,
                "auditTypes": ["sufficientElementDescription", "trait", "textClipped", "dynamicType", "hitRegion"],
                "issues": issues,
                "scope": "Native visible viewport and reachable primary control; automated semantic audit, not a VoiceOver gesture journey"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-maximum-text-\(screen)-audit.json"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
