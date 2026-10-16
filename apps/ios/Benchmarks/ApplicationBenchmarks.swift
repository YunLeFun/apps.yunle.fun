import XCTest

/// Opt-in simulator benchmarks. The compatibility app must be installed
/// separately. Never install either variant over the user's production app.
@MainActor
final class ApplicationBenchmarks: XCTestCase {
    private var isLegacy: Bool {
        ProcessInfo.processInfo.environment["YLF_BENCHMARK_TARGET"] == "legacy"
    }
    private var app: XCUIApplication {
        XCUIApplication(bundleIdentifier: isLegacy ? "fun.yunle.apps" : "fun.yunle.apps.benchmark-dev")
    }

    func testPublicScreenInventory() throws {
        continueAfterFailure = false
        let app = app
        app.launch()
        let home = app.staticTexts["云居"].firstMatch
        let visible = home.waitForExistence(timeout: 20)
        attach(app, name: "home")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "public-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(visible, "A first frame is not enough: the home UI must render")
        for title in ["寻乐", "工坊", "我"] {
            let tab = isLegacy ? app.webViews.buttons[title].firstMatch : app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab: \(title)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "The requested tab must actually become selected")
            attach(app, name: title)
        }
    }

    func testLaunchResponsiveFrame() throws {
        try requireMetrics()
        let app = app
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        // This system metric ends at a responsive first frame. Web content,
        // network-loaded catalog data and WebKit memory are separate measures.
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            app.terminate()
        }
    }

    func testHomeEntryBecomesAccessible() throws {
        try requireMetrics()
        let app = app
        app.terminate()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            app.launch()
            let entry = isLegacy ? app.webViews.staticTexts["云空调"].firstMatch : app.buttons["打开云空调"]
            XCTAssertTrue(entry.waitForExistence(timeout: 15), "Measure a rendered home entry, not an empty WebView")
            stopMeasuring()
            app.terminate()
        }
    }

    func testPrepareNativeHomeWithCloudAir() throws {
        guard !isLegacy else { throw XCTSkip("The compatibility app already has its own default cloud-air entry") }
        let app = app
        prepareNativeHome(app)
        attach(app, name: "prepared-home")
    }

    func testNativeCloudAirCanMinimizeRestoreAndEnd() throws {
        guard !isLegacy else { throw XCTSkip("This journey verifies the native runtime integration") }
        continueAfterFailure = false
        let app = app
        prepareNativeHome(app)
        let open = app.buttons["打开云空调"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Prepare the same real cloud-air entry before this journey")
        open.tap()
        let minimize = app.buttons["收起应用"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        let content = app.webViews.staticTexts["便携小空调"].firstMatch
        let rendered = content.waitForExistence(timeout: 20)
        attach(app, name: "cloud-air-open")
        XCTAssertTrue(rendered, "The real web document must render")
        minimize.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "正在运行")).firstMatch
        XCTAssertTrue(running.exists)
        attach(app, name: "cloud-air-minimized")
        open.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        attach(app, name: "cloud-air-restored")
        app.buttons["更多操作"].tap()
        let end = app.buttons["结束"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(running.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        attach(app, name: "cloud-air-ended")
    }

    func testNativeGuestAuthorizationLoginCanBeCancelled() throws {
        guard !isLegacy else { throw XCTSkip("Verifies the native host broker") }
        continueAfterFailure = false
        let app = app
        app.launch()
        app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊"))
            .firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("This journey requires a guest simulator; never signs out a real account")
        }
        app.tabBars.buttons["工坊"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("AI 春联")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AI 春联")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let get = app.buttons["获取"]
        if get.waitForExistence(timeout: 2) { get.tap() }
        let open = app.buttons["打开"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let login = app.navigationBars["登录并继续"]
        if !login.waitForExistence(timeout: 4) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "registered-app-before-login"
            tree.lifetime = .keepAlways
            add(tree)
            attach(app, name: "registered-app-before-login")
            let webLogin = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "登录")).firstMatch
            XCTAssertTrue(webLogin.waitForExistence(timeout: 15))
            webLogin.tap()
        }
        let shown = login.waitForExistence(timeout: 15)
        attach(app, name: "registered-app-native-login")
        XCTAssertTrue(shown)
        XCTAssertTrue(app.staticTexts["login.authorization-context"].exists)
        XCTAssertTrue(app.staticTexts["login.authorization-context"].label.contains("AI 春联"))
        XCTAssertTrue(app.textFields["手机号"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["收起应用"].waitForExistence(timeout: 5))
        XCTAssertFalse(login.exists)
        XCTAssertTrue(app.webViews.firstMatch.exists)
        attach(app, name: "registered-app-login-cancelled")
        let retry = app.webViews.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "登录", "同步失败")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 15), "Cancel must settle the request so the same page can try again")
        attach(app, name: "registered-app-login-retried")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["收起应用"].waitForExistence(timeout: 5))
    }

    func testNativeCloudApplicationMenuRoutesAndCommands() throws {
        guard !isLegacy else { throw XCTSkip("Verifies the native menu") }
        continueAfterFailure = false
        let app = app
        prepareNativeHome(app)
        app.buttons["打开云空调"].tap()
        let document = app.webViews.staticTexts["便携小空调"].firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 20))
        let documentCount = app.webViews.count
        func showMenu() {
            app.buttons["更多操作"].tap()
            XCTAssertTrue(app.navigationBars["更多操作"].waitForExistence(timeout: 5))
            if !app.buttons["结束"].exists || !app.buttons["结束"].isHittable { app.swipeUp() }
        }
        showMenu(); attach(app, name: "cloud-menu-native")
        app.buttons["应用详情"].tap()
        XCTAssertTrue(app.staticTexts["关于这个应用"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.webViews.count, documentCount, "First-party details must stay native above the same cloud app")
        attach(app, name: "cloud-menu-details")
        app.buttons["返回应用"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        showMenu()
        app.buttons["评分与评价"].tap()
        XCTAssertTrue(app.navigationBars["评分与评价"].waitForExistence(timeout: 5))
        attach(app, name: "cloud-menu-reviews")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["runtime.menu.author"].tap()
        XCTAssertTrue(app.staticTexts["公开作品"].waitForExistence(timeout: 5))
        attach(app, name: "cloud-menu-author")
        app.buttons["完成"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        showMenu(); app.buttons["复制链接"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        showMenu(); app.buttons["在浏览器中打开"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(safari.webViews.staticTexts["便携小空调"].firstMatch.waitForExistence(timeout: 20))
        attach(safari, name: "cloud-menu-external-browser")
        app.activate()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        showMenu(); app.buttons["分享"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        attach(app, name: "cloud-menu-system-share")
        // iOS 27 exposes an outside-dismiss region instead of a Close button.
        let dismissShare = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissShare.exists)
        dismissShare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        showMenu(); app.buttons["重新载入"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 20))
        showMenu(); app.buttons["结束"].tap()
        XCTAssertTrue(app.buttons["打开云空调"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testNativeCloudApplicationSystemTitleMenu() throws {
        guard !isLegacy else { throw XCTSkip("Verifies the system navigation controller") }
        continueAfterFailure = false
        let app = app
        prepareNativeHome(app)
        app.buttons["打开云空调"].tap()
        let document = app.webViews.staticTexts["便携小空调"].firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 20))
        let bar = app.navigationBars["云空调"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["收起应用"].exists)
        XCTAssertTrue(bar.buttons["更多操作"].exists)
        attach(app, name: "cloud-system-navigation")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "收起应用")).count, 1)
        bar.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "云空调")).firstMatch.tap()
        XCTAssertTrue(app.buttons["应用详情"].waitForExistence(timeout: 5))
        attach(app, name: "cloud-system-title-menu")
        app.buttons["应用详情"].tap()
        XCTAssertTrue(app.staticTexts["关于这个应用"].waitForExistence(timeout: 5))
        attach(app, name: "cloud-system-title-detail")
        XCTAssertTrue(app.buttons["完成"].exists)
        app.buttons["返回应用"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        bar.buttons["更多操作"].tap()
        XCTAssertTrue(app.buttons["结束"].waitForExistence(timeout: 5))
        app.buttons["结束"].tap()
        XCTAssertTrue(app.buttons["打开云空调"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testNativeCanSwitchApplicationsFromAuthorDetailsAndRestore() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native session ownership across application switches") }
        continueAfterFailure = false
        let app = app
        prepareNativeHome(app)
        app.buttons["打开云空调"].tap()
        let airDocument = app.webViews.staticTexts["便携小空调"].firstMatch
        XCTAssertTrue(airDocument.waitForExistence(timeout: 20))

        func openFromAuthor(_ name: String) {
            app.buttons["更多操作"].tap()
            let author = app.buttons["runtime.menu.author"]
            XCTAssertTrue(author.waitForExistence(timeout: 5)); author.tap()
            XCTAssertTrue(app.staticTexts["公开作品"].waitForExistence(timeout: 5))
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            for _ in 0..<5 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.exists && row.isHittable); row.tap()
            XCTAssertTrue(app.staticTexts["关于这个应用"].waitForExistence(timeout: 5))
            attach(app, name: "switch-author-detail-\(name)")
            let open = app.buttons["打开"]
            if open.waitForExistence(timeout: 2) { open.tap() }
            else {
                let trial = app.buttons["试用"]
                XCTAssertTrue(trial.exists); trial.tap()
            }
        }

        openFromAuthor("AI 春联")
        let login = app.navigationBars["登录并继续"]
        if login.waitForExistence(timeout: 3) { app.buttons["取消"].tap() }
        let springDocument = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "登录")).firstMatch
        XCTAssertTrue(springDocument.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "收起应用")).count, 1)
        XCTAssertFalse(app.staticTexts["公开作品"].exists)
        attach(app, name: "switch-second-application")

        openFromAuthor("云空调")
        XCTAssertTrue(airDocument.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "收起应用")).count, 1)
        XCTAssertFalse(app.staticTexts["公开作品"].exists)
        attach(app, name: "switch-original-restored")
        app.buttons["更多操作"].tap()
        app.buttons["结束"].tap()
        XCTAssertTrue(app.buttons["打开云空调"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "正在运行")).firstMatch
        XCTAssertTrue(running.exists); running.tap()
        let spring = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AI 春联")).firstMatch
        XCTAssertTrue(spring.waitForExistence(timeout: 5)); spring.tap()
        XCTAssertTrue(app.buttons["收起应用"].waitForExistence(timeout: 5))
        app.buttons["更多操作"].tap(); app.buttons["结束"].tap()
        XCTAssertTrue(app.navigationBars["正在运行"].waitForExistence(timeout: 5))
        XCTAssertFalse(spring.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testNativeGuestCanReadReviewsAndReachReports() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native community screens") }
        continueAfterFailure = false
        let app = app
        app.launch()
        app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊"))
            .firstMatch.waitForExistence(timeout: 5) else { throw XCTSkip("Requires a guest simulator") }
        app.tabBars.buttons["工坊"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("AI 春联")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AI 春联")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["评分与评价"].tap()
        XCTAssertTrue(app.navigationBars["评分与评价"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已发布评价"].waitForExistence(timeout: 15))
        attach(app, name: "reviews-guest")
        app.buttons["登录后写评价"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["login.continuation-context"].exists)
        attach(app, name: "reviews-login")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["评分与评价"].waitForExistence(timeout: 5))
        app.buttons["举报应用"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["我的举报"].tap()
        XCTAssertTrue(app.navigationBars["我的举报"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录后查看举报记录"].exists)
        attach(app, name: "reports-guest")
        app.buttons["登录云乐坊"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["我的举报"].waitForExistence(timeout: 5))
    }

    func testNativeGuestWorkshopEntryAndInvalidLink() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native personal workshop screens") }
        continueAfterFailure = false
        let app = app
        app.launch()
        app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊"))
            .firstMatch.waitForExistence(timeout: 5) else { throw XCTSkip("Requires a guest simulator") }
        app.tabBars.buttons["工坊"].tap()
        app.buttons["个人工坊"].tap()
        XCTAssertTrue(app.navigationBars["个人工坊"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["和同好一起使用应用"].exists)
        XCTAssertFalse(app.buttons["创建个人工坊"].exists)
        attach(app, name: "workshops-guest")
        app.buttons["登录云乐坊"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["login.continuation-context"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["个人工坊"].waitForExistence(timeout: 5))
        app.buttons["输入工坊编号或链接"].tap()
        XCTAssertTrue(app.navigationBars["打开个人工坊"].waitForExistence(timeout: 5))
        let field = app.textFields["workshop.lookup.input"]
        field.tap(); field.typeText("https://external.invalid/w/ABC234")
        app.buttons["workshop.lookup.open"].tap()
        XCTAssertTrue(app.staticTexts["无法识别这个工坊编号或链接，请检查后重试。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["打开个人工坊"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        attach(app, name: "workshop-invalid-link")
    }

    func testNativePhotoScanOpensPublicApplicationAndCanRepeat() throws {
        guard !isLegacy, ProcessInfo.processInfo.environment["YLF_SCAN_PHOTO_JOURNEY"] == "1" else {
            throw XCTSkip("Requires the generated application QR image imported into the test simulator")
        }
        continueAfterFailure = false
        let app = app
        app.launch()
        app.tabBars.buttons["云居"].tap()
        app.buttons["home.scan"].tap()
        XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["scanner.camera.unavailable"].waitForExistence(timeout: 5))
        attach(app, name: "scanner-no-camera")
        app.buttons["scanner.photos"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 10))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 5))
        for attempt in 1...2 {
            app.buttons["scanner.photos"].tap()
            let image = app.images.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "照片", "Photo")).firstMatch
            let loaded = image.waitForExistence(timeout: 40)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "scanner-system-photo-picker-tree-\(attempt)"; tree.lifetime = .keepAlways; add(tree)
            attach(app, name: "scanner-system-photo-picker-\(attempt)")
            XCTAssertTrue(loaded, "The imported QR image must actually appear in the native picker")
            image.tap()
            let result = app.buttons["scanner.result.destination"]
            XCTAssertTrue(result.waitForExistence(timeout: 30), "Decode the selected image through the actual PhotosPicker transfer and native decoder")
            XCTAssertTrue(app.staticTexts["识别结果"].exists)
            attach(app, name: "scanner-photo-result-\(attempt)")
            if attempt == 1 {
                result.tap()
                XCTAssertTrue(app.navigationBars["AI 春联"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["评分与评价"].exists)
                attach(app, name: "scanner-linked-application")
                app.navigationBars["AI 春联"].buttons["扫一扫"].tap()
                XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 5))
                app.buttons["scanner.continue"].tap()
            }
        }
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["云居"].waitForExistence(timeout: 5))
        app.tabBars.buttons["工坊"].tap()
        app.buttons["catalog.scan"].tap()
        XCTAssertTrue(app.navigationBars["扫描工坊二维码"].waitForExistence(timeout: 5))
        app.buttons["scanner.photos"].tap()
        let applicationQR = app.images.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "照片", "Photo")).firstMatch
        XCTAssertTrue(applicationQR.waitForExistence(timeout: 30)); applicationQR.tap()
        XCTAssertTrue(app.staticTexts["未识别到工坊链接，请扫描云乐坊个人工坊二维码。"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["scanner.result.destination"].exists)
        attach(app, name: "scanner-workshop-rejects-app-code")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["工坊"].waitForExistence(timeout: 5))
    }

    func testNativeAppAndWorkshopLinkReception() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native URL reception") }
        guard #available(iOS 16.4, *) else { throw XCTSkip("XCTest URL launch requires iOS 16.4") }
        continueAfterFailure = false
        let app = app
        app.terminate()
        app.open(URL(string: "yunlefun://app/ai-sfc")!)
        XCTAssertTrue(app.navigationBars["AI 春联"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.buttons["工坊"].isSelected)
        XCTAssertTrue(app.buttons["评分与评价"].exists)
        attach(app, name: "link-public-application")
        app.open(URL(string: "yunlefun://workshop/ABC234")!)
        XCTAssertTrue(app.navigationBars["个人工坊"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["这个工坊已不存在或暂不可访问。"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["重试"].exists)
        XCTAssertFalse(app.buttons["申请加入"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        attach(app, name: "link-unavailable-workshop")
    }

    func testNativeAssistantGuestPromptSurvivesLoginCancellation() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native assistant UI") }
        continueAfterFailure = false
        let app = app
        app.terminate(); app.launch(); app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊")).firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator; never signs out a real account")
        }
        app.tabBars.buttons["云居"].tap()
        XCTAssertTrue(app.buttons["home.assistant"].waitForExistence(timeout: 5))
        app.buttons["home.assistant"].tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 5))
        let prompt = "找一个适合写代码的开发工具"
        XCTAssertTrue(app.buttons[prompt].exists); app.buttons[prompt].tap()
        let input = app.textViews["assistant.input"].exists ? app.textViews["assistant.input"] : app.textFields["assistant.input"]
        XCTAssertTrue(input.exists)
        XCTAssertEqual(input.value as? String, prompt)
        app.buttons["发送问题"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录后继续使用 AI 助手，发送前会核对会员状态。"].exists)
        attach(app, name: "assistant-guest-native-login")
        app.navigationBars["登录并继续"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, prompt)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        attach(app, name: "assistant-guest-prompt-restored")
        app.navigationBars["AI 助手"].buttons["云居"].tap()
        XCTAssertTrue(app.navigationBars["云居"].waitForExistence(timeout: 5))
        app.buttons["home.assistant"].tap()
        XCTAssertTrue(app.navigationBars["AI 助手"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, prompt)
        attach(app, name: "assistant-guest-reopened")
    }

    func testNativeGuestAcquisitionLoginCanBeCancelled() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native acquisition UI") }
        guard #available(iOS 16.4, *) else { throw XCTSkip("XCTest URL launch requires iOS 16.4") }
        continueAfterFailure = false
        let app = app
        app.launch(); app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊")).firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator")
        }
        app.open(URL(string: "yunlefun://app/yunjian")!)
        XCTAssertTrue(app.navigationBars["云栈"].waitForExistence(timeout: 20))
        app.buttons["获取"].tap()
        XCTAssertTrue(app.navigationBars["获取应用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录后确认会员、云币与已购权益。"].exists)
        XCTAssertFalse(app.buttons["使用云币获取"].exists)
        attach(app, name: "acquisition-guest")
        app.buttons["登录云乐坊"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        app.navigationBars["登录并继续"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["获取应用"].waitForExistence(timeout: 5))
        app.navigationBars["获取应用"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["云栈"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        // A dismissed UIKit-hosted sheet must not block the next acquisition.
        app.buttons["获取"].tap()
        XCTAssertTrue(app.navigationBars["获取应用"].waitForExistence(timeout: 5))
        app.navigationBars["获取应用"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["云栈"].waitForExistence(timeout: 5))
    }

    func testNativeGuestWalletAndMembershipLoginCanBeCancelled() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native wallet screens") }
        continueAfterFailure = false
        let app = app
        app.launch(); app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊")).firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator")
        }
        for title in ["钱包", "云乐坊会员"] {
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["登录后查看云币与会员"].exists)
            XCTAssertFalse(app.buttons["恢复购买"].exists)
            attach(app, name: title == "钱包" ? "wallet-guest" : "membership-guest")
            app.buttons["登录云乐坊"].tap()
            XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
            app.buttons["取消"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.navigationBars[title].buttons.firstMatch.tap()
        }
    }

    func testNativePublicBrandIconDetail() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native icon rendering") }
        guard #available(iOS 16.4, *) else { throw XCTSkip("XCTest URL launch requires iOS 16.4") }
        continueAfterFailure = false
        let app = app
        app.terminate()
        app.open(URL(string: "yunlefun://app/cook")!)
        XCTAssertTrue(app.navigationBars["今天来做菜"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["评分与评价"].waitForExistence(timeout: 5))
        // The icon is deliberately hidden from VoiceOver; inspect the retained screenshot, not an extra accessibility stop.
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "live-native-cook-icon-detail")
    }

    func testNativeGuestCanReachApplicationManagementAndCancelLogin() throws {
        guard !isLegacy else { throw XCTSkip("Verifies native application publishing screens") }
        continueAfterFailure = false
        let app = app
        app.launch()
        app.tabBars.buttons["我"].tap()
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "登录云乐坊")).firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a guest simulator")
        }
        app.buttons["我的应用"].tap()
        XCTAssertTrue(app.navigationBars["我的应用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["发布你的云应用"].exists)
        XCTAssertFalse(app.buttons["创建应用"].exists)
        attach(app, name: "publishing-guest")
        app.buttons["登录云乐坊"].tap()
        XCTAssertTrue(app.navigationBars["登录并继续"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["login.continuation-context"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["我的应用"].waitForExistence(timeout: 5))
        app.tabBars.buttons["工坊"].tap()
        app.buttons["我的应用"].tap()
        XCTAssertTrue(app.navigationBars["我的应用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["发布你的云应用"].exists)
        XCTAssertFalse(app.buttons["保存版本"].exists)
    }

    private func prepareNativeHome(_ app: XCUIApplication) {
        app.launch()
        app.tabBars.buttons["云居"].tap()
        if app.buttons["打开云空调"].exists { return }
        app.tabBars.buttons["工坊"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("云空调")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "云空调")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let get = app.buttons["获取"]
        if get.waitForExistence(timeout: 3) { get.tap() }
        XCTAssertTrue(app.buttons["打开"].waitForExistence(timeout: 5))
        app.tabBars.buttons["云居"].tap()
        XCTAssertTrue(app.buttons["打开云空调"].waitForExistence(timeout: 5))
    }

    private func requireMetrics() throws {
        guard ProcessInfo.processInfo.environment["YLF_BENCHMARK_METRICS"] == "1" else {
            throw XCTSkip("Enable metrics explicitly after the public-screen readiness check passes")
        }
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = (isLegacy ? "legacy-" : "native-") + name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
