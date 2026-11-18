import XCTest
@testable import YunleFun

@MainActor
final class WeChatAuthorizationTests: XCTestCase {
    func testOnlyTheCurrentSDKResponseCompletesTheAttempt() async throws {
        let sent = expectation(description: "authorization requested")
        var state = ""
        var driver = WeChatAuthorization.Driver()
        driver.isInstalled = { true }
        driver.register = { _, _ in true }
        driver.send = { value, sentOK in state = value; sentOK(true); sent.fulfill() }
        driver.handleURL = { _, reply in reply(0, "stale-state", "other-code"); return true }
        driver.handleActivity = { _, reply in reply(0, state, "current-code"); return true }
        let authorization = WeChatAuthorization(driver: driver)
        let scheme = URL(string: "\(WeChatAuthorization.appID)://oauth")!
        let universal = URL(string: WeChatAuthorization.universalLink)!
        XCTAssertFalse(authorization.handle(scheme), "Do not accept unsolicited callbacks")
        let task = Task { try await authorization.authorize() }
        defer { task.cancel() }
        await fulfillment(of: [sent], timeout: 1)
        XCTAssertFalse(authorization.handle(URL(string: "https://apps.yunle.fun.evil.invalid/auth/wechat/return")!))
        XCTAssertTrue(authorization.handle(scheme))
        XCTAssertTrue(authorization.handle(universal))
        let code = try await task.value
        XCTAssertEqual(code, "current-code")
        XCTAssertFalse(authorization.handle(universal), "A completed attempt cannot be replayed")
    }

    func testCancelledOrMalformedSDKResponseCannotProduceACode() {
        XCTAssertThrowsError(try WeChatAuthorization.validatedCode(status: -2, code: "unused")) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertThrowsError(try WeChatAuthorization.validatedCode(status: 0, code: "contains a space"))
    }
}
