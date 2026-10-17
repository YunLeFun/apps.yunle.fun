import Foundation
import UIKit
import XCTest

/// Explicit, anonymous UI journeys against the real public author endpoint.
/// This file belongs only to the independent Benchmark test target.
@MainActor
final class DeveloperProfileBenchmarks: XCTestCase {
    private var inspectedApp: XCUIApplication?
    private var evidenceName = "developer-profile"
    private var observations: [String: String] = [:]

    override func tearDownWithError() throws {
        // Only a verified guest enters this journey. Never dump an unexpected
        // signed-in account's hierarchy when the initial fixture check fails.
        if let inspectedApp {
            capture(inspectedApp, name: "\(evidenceName)-final")
            if let data = try? JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                let attachment = XCTAttachment(string: text)
                attachment.name = "\(evidenceName)-observations"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        try super.tearDownWithError()
    }

    func testAnonymousAuthorProfileAtStandardText() throws { try checkAuthorProfile(large: false) }
    func testAnonymousAuthorProfileAtLargestText() throws { try checkAuthorProfile(large: true) }

    private func checkAuthorProfile(large: Bool) throws {
        let appearance = try requireOwnedFreshGuest()
        guard #available(iOS 16.4, *) else { throw XCTSkip("Opening the native author URL requires iOS 16.4 or later") }
        let app = XCUIApplication(bundleIdentifier: "fun.yunle.apps.benchmark-dev")
        let size = large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        evidenceName = "developer-profile-\(large ? "largest" : "standard")-\(appearance)"
        observations = ["textSize": size, "appearance": appearance,
                        "dataSource": "Real anonymous author page, observed through XCUIAutomation",
                        "acquireActionTapped": "false", "openActionTapped": "false", "authenticationSubmitted": "false"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", size, "-appearance", appearance]
        app.launch()
        let me = app.tabBars.buttons["我"]
        try require(me.waitForExistence(timeout: 10) && me.isHittable, "Requires the real native iPhone tab bar")
        me.tap()
        try require(app.navigationBars["我"].waitForExistence(timeout: 5), "The Me page must appear before checking the guest")
        try require(app.buttons["me.login"].waitForExistence(timeout: 10), "Never use an existing signed-in account")
        try waitUntil(timeout: 15, message: "Initial account restoration must finish while remaining a guest") {
            !app.progressIndicators["正在检查登录状态"].exists && app.buttons["me.login"].exists
        }
        let home = app.tabBars.buttons["云居"]
        try require(home.exists && home.isHittable, "Requires the native Home tab")
        home.tap()
        try require(app.buttons["去工坊看看"].waitForExistence(timeout: 10), "Requires the explicitly declared fresh empty guest home")
        try require(!app.buttons["home.running"].exists && !app.webViews.firstMatch.exists
                    && app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).count == 0,
                    "The fixture must not contain installed or running cloud applications")
        inspectedApp = app
        capture(app, name: "\(evidenceName)-fresh-guest")

        let requestedLogin = "YunYouJun"
        let route = try XCTUnwrap(URL(string: "yunlefun://developer/\(requestedLogin)"))
        observations["requestedRoute"] = route.absoluteString
        // This uses the application URL entry point and NativeDestinationView,
        // not a production debug hook or a model/service fixture.
        app.open(route)
        try require(app.state == .runningForeground, "The native author destination must remain in the Benchmark app")
        try waitUntil(timeout: 25, message: "The real author profile must load at least one public work") {
            let count = self.publicWorkCountElement(in: app)
            return self.authorNavigationBar(in: app, login: requestedLogin).exists
                && count.exists && self.publicWorkCount(from: count.label).map { $0 > 0 } == true
                && !app.descendants(matching: .any).matching(identifier: "developer.loading").firstMatch.exists
                && !app.descendants(matching: .any).matching(identifier: "developer.error").firstMatch.exists
        }
        let profile = try observeProfile(in: app, requestedLogin: requestedLogin)
        observations["observedOwnerLogin"] = profile.ownerLogin
        observations["observedInitialPublicWorkCount"] = String(profile.count)
        try require(!app.webViews.firstMatch.exists, "The author profile must be a native destination")
        capture(app, name: "\(evidenceName)-loaded-author")

        let selection = try visibleWork(in: app)
        let selectedIdentifier = selection.row.identifier
        observations["selectedApplicationIdentifier"] = selectedIdentifier
        observations["selectedApplicationTitle"] = selection.title
        observations["selectedApplicationLabel"] = selection.row.label
        capture(app, name: "\(evidenceName)-selected-public-work")
        selection.titleElement.tap()
        let detail = app.navigationBars[selection.title]
        try require(detail.waitForExistence(timeout: 5), "The selected real work must open its own native detail")
        try require(!app.webViews.firstMatch.exists, "Entering detail must not launch a cloud application")
        let share = detail.buttons["分享作者主页"]
        try require(share.exists && share.isHittable, "The personal revision must display the author-profile ShareLink")
        let provenance = app.staticTexts["作者公开发布的版本"]
        try reveal(provenance, in: app)
        try require(app.staticTexts["此版本可能与云乐坊上架版本不同。"].exists,
                    "The native detail must explain the distinction from the market revision")
        capture(app, name: "\(evidenceName)-personal-revision-detail")

        // Only activate the system Back button. No acquire/open/share action is tapped.
        let back = detail.buttons.element(boundBy: 0)
        try require(back.exists && back.isHittable, "The native detail must expose an actionable system Back button")
        let backLabel = back.label
        try require(backLabel.caseInsensitiveCompare(profile.ownerLogin) == .orderedSame
                        || backLabel.contains("返回") || backLabel.lowercased() == "back",
                    "The leading native navigation button must return to the observed author page")
        observations["observedSystemBackLabel"] = backLabel
        back.tap()
        try require(authorNavigationBar(in: app, login: profile.ownerLogin).waitForExistence(timeout: 5),
                    "System Back must return to the same real author profile")
        try require(app.buttons[selectedIdentifier].waitForExistence(timeout: 5),
                    "Back must retain the actual selected public work")
        // A native List can preserve a scrolled position on Back. Reveal the
        // actual header again instead of requiring offscreen cells to exist.
        try reveal(publicWorkCountElement(in: app), in: app, upward: false)
        let returned = try observeProfile(in: app, requestedLogin: profile.ownerLogin)
        observations["observedReturnedOwnerLogin"] = returned.ownerLogin
        observations["observedReturnedPublicWorkCount"] = String(returned.count)
        try require(returned.count > 0 && !app.webViews.firstMatch.exists,
                    "Returning must retain a native public profile without running a cloud application")
        capture(app, name: "\(evidenceName)-returned-author")

        home.tap()
        try require(app.buttons["去工坊看看"].waitForExistence(timeout: 5)
                    && !app.buttons["home.running"].exists
                    && app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开")).count == 0,
                    "Reading a public profile and detail must not acquire or run an application")
        me.tap()
        try require(app.buttons["me.login"].waitForExistence(timeout: 5), "The complete read-only journey must remain anonymous")
        observations["completed"] = "true"
    }

    private func requireOwnedFreshGuest() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["YLF_DEVELOPER_PROFILE_UI"] == "1" else {
            throw XCTSkip("Enable the real anonymous author-page Benchmark explicitly")
        }
        #if !targetEnvironment(simulator)
        throw XCTSkip("This journey only uses an explicitly owned iOS simulator")
        #else
        try require(environment["YLF_BENCHMARK_TARGET"] != "legacy", "This journey only targets the native Benchmark bundle")
        guard let owned = environment["YLF_OWNED_BENCHMARK_SIMULATOR_UDID"], !owned.isEmpty,
              owned == environment["SIMULATOR_UDID"], environment["YLF_DEVELOPER_PROFILE_FRESH_GUEST_FIXTURE"] == "1" else {
            throw JourneyFailure(description: "Requires this owned simulator's explicit fresh-guest fixture declaration")
        }
        try require(UIDevice.current.userInterfaceIdiom == .phone, "This bounded first journey currently covers iPhone")
        try require(!UIAccessibility.isVoiceOverRunning, "This touch/layout journey must not change an existing VoiceOver state")
        let appearance = environment["YLF_ACCESSIBILITY_APPEARANCE"] ?? "light"
        try require(["light", "dark"].contains(appearance), "Choose an explicit light or dark app appearance")
        continueAfterFailure = false
        executionTimeAllowance = 120
        return appearance
        #endif
    }

    private func authorNavigationBar(in app: XCUIApplication, login: String) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@ OR label ==[c] %@", login, login)).firstMatch
    }

    private func publicWorkCountElement(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ 个公开作品$")).firstMatch
    }

    private func publicWorkCount(from label: String) -> Int? {
        Int(label.components(separatedBy: " ").first ?? "")
    }

    private func observeProfile(in app: XCUIApplication, requestedLogin: String) throws -> (ownerLogin: String, count: Int) {
        let navigation = authorNavigationBar(in: app, login: requestedLogin)
        try require(navigation.exists, "Read the actual author navigation title")
        let ownerLogin = navigation.identifier.isEmpty ? navigation.label : navigation.identifier
        try require(ownerLogin.caseInsensitiveCompare(requestedLogin) == .orderedSame,
                    "The rendered profile must belong to the requested author")
        let countElement = publicWorkCountElement(in: app)
        let count = try XCTUnwrap(publicWorkCount(from: countElement.label), "Read the real rendered public-work count")
        try require(count > 0, "The observed profile must contain public work; the count is not a fixed fixture")
        return (ownerLogin, count)
    }

    private func visibleWork(in app: XCUIApplication) throws -> (row: XCUIElement, titleElement: XCUIElement, title: String) {
        for step in 0...6 {
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "developer.application."))
            for row in rows.allElementsBoundByIndex where row.isHittable {
                // ApplicationRow currently has a combined StaticText plus its
                // real child Texts. Read the actual title, not the combined label.
                let title = row.staticTexts.matching(NSPredicate(format: "label != %@ AND label != ''", row.label)).firstMatch
                if title.exists && title.isHittable && isBetweenBars(title, in: app) {
                    return (row, title, title.label)
                }
            }
            if step < 6 { try scroll(in: app, upward: true) }
        }
        throw JourneyFailure(description: "No real public work became observable within six native scrolls")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) throws {
        for step in 0...6 {
            if element.exists && element.isHittable && isBetweenBars(element, in: app) { return }
            if step < 6 { try scroll(in: app, upward: upward) }
        }
        throw JourneyFailure(description: "The requested complete native text was not visible within six scrolls")
    }

    private func isBetweenBars(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let navigation = app.navigationBars.firstMatch
        let tab = app.tabBars.firstMatch
        guard navigation.exists, tab.exists else { return false }
        return element.frame.minY >= navigation.frame.maxY - 1 && element.frame.maxY <= tab.frame.minY + 1
    }

    private func scroll(in app: XCUIApplication, upward: Bool) throws {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        try require(list.exists, "Use the real native author/detail list to reveal content")
        if upward { list.swipeUp() } else { list.swipeDown() }
    }

    private func waitUntil(timeout: TimeInterval, message: String, condition: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        try require(XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed, message)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-screen"; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-complete-ax"; tree.lifetime = .keepAlways; add(tree)
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw JourneyFailure(description: message) }
    }

    private struct JourneyFailure: Error, CustomStringConvertible { let description: String }
}
