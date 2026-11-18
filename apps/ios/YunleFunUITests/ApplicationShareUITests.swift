import XCTest

@MainActor
final class ApplicationShareUITests: XCTestCase {
    func testSlugPreviewAndDirectoryGenerationReachTheSystemFilePicker() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("URL launch requires iOS 16.4") }
        continueAfterFailure = false
        executionTimeAllowance = 300
        let app = XCUIApplication(); app.launch()
        openPublicApplication("dayun-kicker", in: app)
        let directory = app.buttons["application.share.catalog"]
        XCTAssertTrue(directory.waitForExistence(timeout: 10)); directory.tap()
        let slug = app.textFields["share.catalog.slug"]
        XCTAssertTrue(slug.waitForExistence(timeout: 10))
        XCTAssertEqual(slug.value as? String, "dayun-kicker")
        app.buttons["share.catalog.preview"].tap()
        let image = waitForSharePreview(in: app)
        XCTAssertTrue(image.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertTrue(image.label.contains("暴力电驴"))
        let done = try XCTUnwrap(app.navigationBars.matching(identifier: "分享应用").buttons.matching(identifier: "完成").allElementsBoundByIndex.first(where: \.isHittable))
        done.tap()
        let generate = app.buttons["share.catalog.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10)); generate.tap()
        let ready = app.staticTexts["share.catalog.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 90))
        XCTAssertEqual(ready.label, "已生成 1 张卡片")
        app.buttons["share.catalog.save"].tap()
        let save = localFilesSaveButton(in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-directory-system-picker"; attachment.lifetime = .keepAlways; add(attachment)
        save.tap()
        XCTAssertTrue(app.staticTexts["目录已存储"].waitForExistence(timeout: 20), "The Files copy must finish successfully")
    }

    /// The export sheet is the system Files picker. Its copy follows the simulator
    /// language, and a freshly created simulator opens on the last-used location,
    /// which does not exist yet. Require the on-device provider either way:
    /// 「我的iPhone」 on a Chinese simulator, 「On My iPhone」 on the English CI image.
    private let localFilesProviderTitles = ["我的iPhone", "On My iPhone"]

    private func localFilesSaveButton(in app: XCUIApplication) -> XCUIElement {
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        if !showingLocalFilesProvider(in: app) { openLocalFilesProvider(in: app) }
        XCTAssertTrue(showingLocalFilesProvider(in: app), "Use the local Files provider for this export. \(documentPickerState(app))")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "The local Files save action must be enabled. \(documentPickerState(app))")
        return save
    }

    private func showingLocalFilesProvider(in app: XCUIApplication) -> Bool {
        let bars = app.navigationBars
        let titled = NSPredicate(format: "label IN %@ OR identifier IN %@", localFilesProviderTitles, localFilesProviderTitles)
        return bars.matching(NSPredicate(format: "identifier IN %@", localFilesProviderTitles)).firstMatch.exists
            || bars.staticTexts.matching(titled).firstMatch.exists
            || bars.buttons.matching(titled).firstMatch.exists
    }

    private func openLocalFilesProvider(in app: XCUIApplication) {
        let row = NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.On My '")
        let back = NSPredicate(format: "identifier == 'BackButton' OR label IN %@", ["BackButton", "Back", "返回", "Browse", "浏览"])
        let title = NSPredicate(format: "label IN %@", localFilesProviderTitles)
        for _ in 0..<5 {
            let location = app.cells.matching(row).firstMatch
            if location.exists, location.isHittable {
                location.tap()
                if app.navigationBars.staticTexts.matching(title).firstMatch.waitForExistence(timeout: 5) { return }
                if showingLocalFilesProvider(in: app) { return }
            }
            let up = app.buttons.matching(back).firstMatch
            guard up.exists, up.isHittable else { return }
            up.tap()
        }
    }

    /// The public catalog and card renderer both wait on apps.yunle.fun.
    /// A cold runner can miss the first attempt; the error state offers 重试.
    @available(iOS 16.4, *)
    private func openPublicApplication(_ slug: String, in app: XCUIApplication) {
        let share = app.buttons["detail.share"]
        app.open(URL(string: "yunlefun://app/\(slug)")!)
        if !share.waitForExistence(timeout: 40) {
            tapRetry(in: app)
            if !share.waitForExistence(timeout: 20) {
                app.terminate(); app.launch()
                app.open(URL(string: "yunlefun://app/\(slug)")!)
            }
        }
        XCTAssertTrue(share.waitForExistence(timeout: 40), "Public catalog must load the application detail")
        share.tap()
    }

    private func waitForSharePreview(in app: XCUIApplication) -> XCUIElement {
        let image = app.images["share.catalog.application.preview"]
        // Detail fetch can use the full catalog timeout, then the icon load follows.
        let deadline = Date().addingTimeInterval(110)
        while Date() < deadline {
            if image.exists { return image }
            tapRetry(in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(image.waitForExistence(timeout: 5), "The share card preview must finish rendering")
        return image
    }

    private func tapRetry(in app: XCUIApplication) {
        let retry = app.buttons["重试"]
        if retry.exists, retry.isHittable { retry.tap() }
    }

    private func documentPickerState(_ app: XCUIApplication) -> String {
        let bars = app.navigationBars.allElementsBoundByIndex.prefix(3).map { bar in
            let labels = bar.staticTexts.allElementsBoundByIndex.prefix(4).map(\.label)
            return "\(bar.identifier) \(labels)"
        }
        return "navigation=\(bars.joined(separator: " | "))"
    }

    func testPublicLinkOpensDetailAndExportsBothAppearances() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("URL launch requires iOS 16.4") }
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication(); app.launch()
        openPublicApplication("air-conditioner", in: app)
        let export = app.buttons["application.share.image"]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        XCTAssertTrue(export.wait(for: \.isEnabled, toEqual: true, timeout: 70))
        let picker = app.segmentedControls["application.share.appearance"]
        for title in ["浅色", "深色"] {
            picker.buttons[title].tap()
            XCTAssertTrue(export.wait(for: \.isEnabled, toEqual: true, timeout: 60))
            let preview = app.images["application.share.preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 10))
            let card = XCTAttachment(screenshot: preview.screenshot())
            card.name = "live-share-preview-\(title)"; card.lifetime = .keepAlways; add(card)
        }
        export.tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10), "The real system image share sheet must open")
        let save = app.descendants(matching: .any).matching(NSPredicate(format:
            "label IN %@", ["保存图像", "存储图像", "存储图片", "存储到照片", "Save Image", "Save to Photos"])).firstMatch
        let canSave = save.waitForExistence(timeout: 10)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-card-system-activity"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(canSave, "Image export must offer the system save-image action")
    }
}
