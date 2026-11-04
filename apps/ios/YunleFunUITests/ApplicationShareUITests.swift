import XCTest

@MainActor
final class ApplicationShareUITests: XCTestCase {
    func testSlugPreviewAndDirectoryGenerationReachTheSystemFilePicker() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("URL launch requires iOS 16.4") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.open(URL(string: "yunlefun://app/dayun-kicker")!)
        let share = app.buttons["detail.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 20)); share.tap()
        let directory = app.buttons["application.share.catalog"]
        XCTAssertTrue(directory.waitForExistence(timeout: 10)); directory.tap()
        let slug = app.textFields["share.catalog.slug"]
        XCTAssertTrue(slug.waitForExistence(timeout: 10))
        XCTAssertEqual(slug.value as? String, "dayun-kicker")
        app.buttons["share.catalog.preview"].tap()
        let image = app.images["share.catalog.application.preview"]
        XCTAssertTrue(image.waitForExistence(timeout: 30))
        XCTAssertTrue(image.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertTrue(image.label.contains("暴力电驴"))
        let done = try XCTUnwrap(app.navigationBars.matching(identifier: "分享应用").buttons.matching(identifier: "完成").allElementsBoundByIndex.first(where: \.isHittable))
        done.tap()
        let generate = app.buttons["share.catalog.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10)); generate.tap()
        let ready = app.staticTexts["share.catalog.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 40))
        XCTAssertEqual(ready.label, "已生成 1 张卡片")
        app.buttons["share.catalog.save"].tap()
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["我的iPhone"].exists, "Use the local Files provider for this export")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-directory-system-picker"; attachment.lifetime = .keepAlways; add(attachment)
        let filename = XCTAttachment(string: app.textFields["DOCPicker.filenameTextField"].value as? String ?? "")
        filename.name = "share-directory-exported-name"; filename.lifetime = .keepAlways; add(filename)
        save.tap()
        XCTAssertTrue(app.staticTexts["目录已存储"].waitForExistence(timeout: 20), "The Files copy must finish successfully")
    }

    func testPublicLinkOpensDetailAndExportsBothAppearances() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("URL launch requires iOS 16.4") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.open(URL(string: "yunlefun://app/air-conditioner")!)
        let share = app.buttons["detail.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 20)); share.tap()
        let export = app.buttons["application.share.image"]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        XCTAssertTrue(export.wait(for: \.isEnabled, toEqual: true, timeout: 30))
        let picker = app.segmentedControls["application.share.appearance"]
        for title in ["浅色", "深色"] {
            picker.buttons[title].tap()
            XCTAssertTrue(export.wait(for: \.isEnabled, toEqual: true, timeout: 30))
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
