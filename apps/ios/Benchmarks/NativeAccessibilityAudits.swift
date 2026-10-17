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

    func testDiscoveryAtStandardTextWithCloudStackRevealed() throws {
        guard ProcessInfo.processInfo.environment["YLF_ACCESSIBILITY_OFFSET_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Enable the explicit scroll-offset diagnostic separately from the baseline audits")
        }
        try audit(tab: "寻乐", large: false) { app in
            try self.revealCloudStackForAudit(app)
        }
    }

    func testDiscoveryAtStandardTextAfterScrollRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["YLF_ACCESSIBILITY_ROUND_TRIP_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Enable the explicit scroll round-trip diagnostic separately from the baseline audits")
        }
        try audit(tab: "寻乐", large: false) { app in
            try self.restoreDiscoveryAfterScrollRoundTrip(app)
        }
    }

    private func audit(tab: String, large: Bool,
                       prepareForAudit: ((XCUIApplication) throws -> Void)? = nil) throws {
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
        try prepareForAudit?(app)
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

    private func revealCloudStackForAudit(_ app: XCUIApplication) throws {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "discovery.application.", "云栈")).firstMatch
        let navigationBar = app.navigationBars["寻乐"]
        let tabBar = app.tabBars.firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The diagnostic requires the real public 云栈 application")
        XCTAssertTrue(tabBar.exists, "This diagnostic compares the native iPhone navigation and bottom TabBar")
        XCTAssertTrue(list.exists)
        let content = [row.staticTexts["云栈"],
                       row.staticTexts["面向 Valaxy、VitePress 与 Git 内容站点的轻量内容工作台"],
                       row.staticTexts["需要邀请"]]
        content.forEach { XCTAssertTrue($0.exists, "Keep the complete real title, summary and access condition") }

        func attachState(_ phase: String, step: Int) {
            let description = """
            phase=\(phase)
            scrollSteps=\(step)
            window=\(app.frame)
            navigationBar=\(navigationBar.frame)
            tabBar=\(tabBar.frame)
            row=\(row.frame)
            \(content.map { "label=\($0.label); frame=\($0.frame); hittable=\($0.isHittable)" }.joined(separator: "\n"))
            """
            let geometry = XCTAttachment(string: description)
            geometry.name = "accessibility-offset-\(phase)-geometry"
            geometry.lifetime = .keepAlways; add(geometry)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "accessibility-offset-\(phase)-screen"
            screenshot.lifetime = .keepAlways; add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "accessibility-offset-\(phase)-tree"
            tree.lifetime = .keepAlways; add(tree)
        }

        attachState("before", step: 0)
        var scrollSteps = 0
        // Leave clearance from the native scroll-edge material, without changing its appearance.
        let edgeClearance: CGFloat = 64
        func isRevealed() -> Bool {
            let top = navigationBar.frame.maxY + edgeClearance
            let bottom = tabBar.frame.minY - edgeClearance
            return content.allSatisfy { $0.exists && $0.isHittable && $0.frame.minY >= top && $0.frame.maxY <= bottom }
        }
        while !isRevealed() && scrollSteps < 6 {
            let top = navigationBar.frame.maxY + edgeClearance
            let bottom = tabBar.frame.minY - edgeClearance
            let bounds = content.reduce(CGRect.null) { $0.union($1.frame) }
            let displacement = min(max(bounds.midY - (top + bottom) / 2, -160), 160)
            guard abs(displacement) >= 1 else { break }
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: (top + bottom) / 2))
            let end = start.withOffset(CGVector(dx: 0, dy: -displacement))
            start.press(forDuration: 0.05, thenDragTo: end)
            scrollSteps += 1
        }
        attachState("after", step: scrollSteps)
        XCTAssertTrue(isRevealed(), "Reveal the complete real application text between the system bars before auditing")
    }

    private func restoreDiscoveryAfterScrollRoundTrip(_ app: XCUIApplication) throws {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "discovery.application.", "云栈")).firstMatch
        let featured = app.buttons["discovery.featured"]
        let navigationBar = app.navigationBars["寻乐"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The round trip requires the real public 云栈 application")
        XCTAssertTrue(featured.exists)
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(tabBar.exists, "This diagnostic retains the native iPhone bottom TabBar")
        let content = [row.staticTexts["云栈"],
                       row.staticTexts["面向 Valaxy、VitePress 与 Git 内容站点的轻量内容工作台"],
                       row.staticTexts["需要邀请"]]
        content.forEach { XCTAssertTrue($0.exists, "Keep the complete real application text throughout the round trip") }
        let originalRowLabel = row.label
        let originalFeaturedLabel = featured.label

        func geometry() -> [String: CGRect] {
            ["window": app.frame, "navigationBar": navigationBar.frame, "tabBar": tabBar.frame,
             "featuredRow": featured.frame, "cloudStackRow": row.frame,
             "title": content[0].frame, "summary": content[1].frame, "accessCondition": content[2].frame]
        }
        let original = geometry()
        func isRestored() -> Bool {
            guard row.exists, featured.exists, navigationBar.exists, tabBar.exists,
                  row.label == originalRowLabel, featured.label == originalFeaturedLabel,
                  content.allSatisfy({ $0.exists }) else { return false }
            let actual = geometry()
            return original.allSatisfy { entry in
                guard let frame = actual[entry.key] else { return false }
                let expected = entry.value
                return abs(frame.minX - expected.minX) <= 1 && abs(frame.minY - expected.minY) <= 1
                    && abs(frame.width - expected.width) <= 1 && abs(frame.height - expected.height) <= 1
            }
        }
        func attachState(_ phase: String, returnSteps: Int) {
            let current = geometry()
            let description = """
            phase=\(phase)
            returnScrollSteps=\(returnSteps)
            restoredWithinOnePoint=\(isRestored())
            \(original.keys.sorted().map { "\($0): original=\(original[$0]!); actual=\(current[$0]!)" }.joined(separator: "\n"))
            """
            let attachment = XCTAttachment(string: description)
            attachment.name = "accessibility-round-trip-\(phase)-geometry"
            attachment.lifetime = .keepAlways; add(attachment)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "accessibility-round-trip-\(phase)-screen"
            screenshot.lifetime = .keepAlways; add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "accessibility-round-trip-\(phase)-tree"
            tree.lifetime = .keepAlways; add(tree)
        }

        attachState("original-a", returnSteps: 0)
        try revealCloudStackForAudit(app)
        attachState("revealed-b", returnSteps: 0)
        XCTAssertEqual(row.label, originalRowLabel)
        XCTAssertEqual(featured.label, originalFeaturedLabel)
        XCTAssertGreaterThan(abs(content[0].frame.minY - original["title"]!.minY), 1,
                             "The revealed B state must actually move the same application text away from A")
        var returnSteps = 0
        while !isRestored() && returnSteps < 6 {
            let remaining = original["title"]!.minY - content[0].frame.minY
            // A short remainder still needs a drag, rather than a tap on a navigation row.
            let distance = max(40, min(abs(remaining), 160)) * (remaining < 0 ? -1 : 1)
            let top = navigationBar.frame.maxY
            let bottom = tabBar.frame.minY
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
            returnSteps += 1
        }
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in isRestored() }, object: nil)
        let restoration = XCTWaiter.wait(for: [restored], timeout: 5)
        attachState("returned-a", returnSteps: returnSteps)
        XCTAssertEqual(restoration, .completed,
                       "Restore the original content, text rectangles and native bars within one point before auditing")
    }
}
