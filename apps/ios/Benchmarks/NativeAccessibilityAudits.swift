import XCTest

@MainActor
final class NativeAccessibilityAudits: XCTestCase {
    func testHomeAtStandardText() throws { try audit(tab: "云居", large: false) }
    func testHomeAtLargestText() throws { try audit(tab: "云居", large: true) }
    func testDiscoveryAtStandardText() throws { try audit(tab: "寻乐", large: false) }
    func testDiscoveryAtLargestText() throws { try audit(tab: "寻乐", large: true) }
    func testCatalogAtStandardText() throws { try audit(tab: "工坊", large: false) }
    func testCatalogAtLargestText() throws { try audit(tab: "工坊", large: true) }
    func testMeAtStandardText() throws { try audit(tab: "我", large: false) }
    func testMeAtLargestText() throws { try audit(tab: "我", large: true) }

    private func audit(tab: String, large: Bool) throws {
        guard ProcessInfo.processInfo.environment["YLF_ACCESSIBILITY_AUDIT"] == "1" else {
            throw XCTSkip("Enable the explicit guest accessibility audit separately from daily tests")
        }
        guard #available(iOS 17, *) else { throw XCTSkip("Apple accessibility audits require iOS 17 or later") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "fun.yunle.apps.benchmark-dev")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if let appearance = ProcessInfo.processInfo.environment["YLF_ACCESSIBILITY_APPEARANCE"] {
            XCTAssertTrue(["system", "light", "dark"].contains(appearance))
            app.launchArguments += ["-appearance", appearance]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我"].tap()
        guard app.buttons["me.login"].waitForExistence(timeout: 5) else {
            throw XCTSkip("This audit requires a guest Benchmark app; do not sign out an existing account")
        }
        XCTAssertTrue(app.buttons["me.login"].label.hasPrefix("登录云乐坊"))
        if tab != "我" { app.tabBars.buttons[tab].tap() }
        XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        if tab == "寻乐" {
            XCTAssertTrue(app.staticTexts["发现一点小乐趣"].waitForExistence(timeout: 15), "Audit the loaded public catalog")
        } else if tab == "工坊" {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "全部应用 · ")).firstMatch
                .waitForExistence(timeout: 15), "Audit the loaded public catalog")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "accessibility-\(tab)-\(large ? "largest" : "standard")"
        screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "accessibility-tree-\(tab)-\(large ? "largest" : "standard")"
        tree.lifetime = .keepAlways; add(tree)
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element.flatMap { $0.exists ? $0 : nil }
            let description = """
            type=\(issue.auditType.rawValue)
            \(issue.compactDescription)
            \(issue.detailedDescription)
            elementProvided=\(issue.element != nil)
            element=\(element?.label ?? "none")
            identifier=\(element?.identifier ?? "none")
            frame=\(element.map { String(describing: $0.frame) } ?? "none")
            hittable=\(element.map { String($0.isHittable) } ?? "none")
            window=\(app.frame)
            """
            let attachment = XCTAttachment(string: description)
            attachment.name = "accessibility-issue-\(tab)-\(large ? "largest" : "standard")"
            attachment.lifetime = .keepAlways; self.add(attachment)
            return false
        }
    }
}
