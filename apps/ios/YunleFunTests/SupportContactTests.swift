import XCTest
@testable import YunleFun

final class SupportContactTests: XCTestCase {
    private let context = SupportMailContext(appVersion: "1.2.3", buildNumber: "45", systemVersion: "iOS 27.0")

    func testFeedbackTemplatePreservesIssueAndIncludesSupportReceiptAndBasicVersions() {
        let draft = SupportMailDraft.feedback(issueDescription: "  点击获取后提示失败\n再次尝试仍失败  ",
                                             supportCode: " abcdef123456 ", context: context)
        XCTAssertEqual(draft.recipient, "kf@yunle.fun")
        XCTAssertEqual(draft.subject, "【问题反馈】来自云乐坊用户")
        XCTAssertTrue(draft.body.contains("问题描述：点击获取后提示失败\n再次尝试仍失败"))
        for field in ["操作步骤：", "期望结果：", "实际结果：", "支持编号：ABCDEF123456",
                      "App 版本：1.2.3（45）", "系统版本：iOS 27.0"] {
            XCTAssertTrue(draft.body.contains(field), "Missing feedback field: \(field)")
        }
    }

    func testUntrustedSupportCodeCannotAddUnexpectedMetadataToTemplate() {
        let draft = SupportMailDraft.feedback(issueDescription: "", supportCode: "ABCDEF123456\nuid=private", context: context)
        XCTAssertTrue(draft.body.contains("支持编号：未提供"))
        XCTAssertFalse(draft.body.contains("uid=private"))
        XCTAssertFalse(draft.body.contains("Authorization"))
        XCTAssertFalse(draft.body.contains("accessToken"))
    }

    func testCopyAndSharePayloadContainsDestinationAndEditableFeedbackWithoutMailService() {
        let draft = SupportMailDraft.feedback(issueDescription: "无法打开应用", supportCode: nil, context: context)
        XCTAssertTrue(draft.shareText.contains("收件人：kf@yunle.fun"))
        XCTAssertTrue(draft.shareText.contains("主题：【问题反馈】来自云乐坊用户"))
        XCTAssertTrue(draft.shareText.contains("问题描述：无法打开应用"))
        XCTAssertTrue(draft.shareText.contains("操作步骤："))
        XCTAssertTrue(draft.shareText.contains("支持编号：未提供"))
    }

    func testBusinessTemplateUsesSeparateContactAndCooperationFields() {
        let draft = SupportMailDraft.business(context: context)
        XCTAssertEqual(draft.recipient, "i@yunle.fun")
        XCTAssertEqual(draft.subject, "【业务合作】来自云乐坊用户")
        for field in ["公司/个人名称：", "联系方式：", "合作意向："] { XCTAssertTrue(draft.body.contains(field)) }
        XCTAssertFalse(draft.body.contains("支持编号："))
        XCTAssertFalse(draft.body.contains("问题描述："))
    }
}
