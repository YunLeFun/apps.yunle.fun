import SafariServices
import UIKit
import WebKit
import XCTest
@testable import YunleFun

/// Opt-in live observation. A native UI driver taps the existing production
/// controls when progress.json says await-tap; DOM .click() is not a user gesture.
@MainActor
final class CookExternalLinkLiveTests: XCTestCase {
    private enum Failure: Error { case observation, timeout }
    private var phase = "setup"
    private var checks: [String: Bool] = [:]

    func testBilibiliAnchorAndWindowOpenUseSystemSafari() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["YLF_COOK_EXTERNAL_LINKS"] == "1" else { throw XCTSkip("Explicit live UI-driver validation only") }
        guard let run = environment["YLF_COOK_EXTERNAL_RUN_ID"], UUID(uuidString: run) != nil,
              environment["SIMULATOR_UDID"] == environment["YLF_COOK_EXTERNAL_SIMULATOR"] else { return XCTFail("Missing isolated simulator binding") }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CookExternalAcceptance")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        let browser = WebViewController()
        browser.url = URL(string: "https://cook.yunle.fun/home")!
        browser.customTitle = "今天来做菜"
        browser.usesSystemNavigationBar = true
        browser.websiteDataStore = .nonPersistent()
        browser.externalLinkBehavior = .safariView
        browser.appInfo = WebAppInfo(id: "cook", slug: "cook", name: "今天来做菜", emoji: "🥘", logo: "", themeColor: "#16a34a", description: "", category: "应用", developer: "YunYouJun", developerName: "云游君")
        let navigation = UINavigationController(rootViewController: browser)
        navigation.modalPresentationStyle = .fullScreen
        root.present(navigation, animated: false)
        let web = try XCTUnwrap(findWeb(browser.view))
        var failure = ""
        do {
            phase = "initial-cook"
            try await wait(45) { (try? await web.evaluateJavaScript("document.title==='食用手册' && !!document.querySelector('ion-tab-button')")) as? Bool == true }
            checks["productionCookLoaded"] = true
            phase = "anchor"
            web.load(URLRequest(url: URL(string: "https://cook.yunle.fun/about/me")!))
            let anchor = "[...document.querySelectorAll('ion-item,a')].find(e=>String(e.href||'').includes('bilibili.com'))"
            try await wait(30) { (try? await web.evaluateJavaScript("!!(" + anchor + ")")) as? Bool == true }
            try await prepareTap(web, selector: anchor, phase: phase, run: run, directory: directory, window: window)
            let anchorDocument = web.url
            try await wait(90) { self.safari(from: browser).map { !$0.isBeingPresented && $0.viewIfLoaded?.window != nil } == true }
            checks["anchorPresentedRealSystemSafari"] = true
            checks["anchorKeepsCookDocument"] = web.url == anchorDocument && web.url?.host == "cook.yunle.fun"
            attach(window, name: "ios-bilibili-anchor-system-safari")
            try await progress(["phase": "opened-anchor", "runID": run], directory: directory)
            try await Task.sleep(nanoseconds: 15_000_000_000)
            attach(window, name: "ios-bilibili-anchor-after-remote-ui-startup")
            self.safari(from: browser)?.dismiss(animated: false)
            try await wait(10) { self.safari(from: browser) == nil }
            checks["anchorReturnsToCook"] = web.url == anchorDocument
            phase = "window-open"
            web.load(URLRequest(url: URL(string: "https://cook.yunle.fun/library")!))
            let row = "document.querySelector('ion-item-sliding ion-item ion-label')"
            try await wait(35) { (try? await web.evaluateJavaScript("!!(" + row + ")")) as? Bool == true }
            try await prepareTap(web, selector: row, phase: phase, run: run, directory: directory, window: window)
            let recipeDocument = web.url
            try await wait(90) { self.safari(from: browser).map { !$0.isBeingPresented && $0.viewIfLoaded?.window != nil } == true }
            checks["recipeWindowOpenPresentedRealSystemSafari"] = true
            checks["windowOpenKeepsCookDocument"] = web.url == recipeDocument && web.url?.host == "cook.yunle.fun"
            attach(window, name: "ios-bilibili-recipe-system-safari")
            try await progress(["phase": "opened-window-open", "runID": run], directory: directory)
            try await Task.sleep(nanoseconds: 15_000_000_000)
            attach(window, name: "ios-bilibili-recipe-after-remote-ui-startup")
            self.safari(from: browser)?.dismiss(animated: false)
            try await wait(10) { self.safari(from: browser) == nil }
            checks["windowOpenReturnsToCook"] = web.url == recipeDocument
        } catch {
            failure = phase + ": " + String(reflecting: type(of: error))
            attach(window, name: "ios-external-failure-" + phase)
        }
        browser.cancelPendingAuthorizations()
        root.dismiss(animated: false)
        window.rootViewController = previous; window.makeKeyAndVisible()
        try? await wait(5) { browser.viewIfLoaded?.window == nil }
        checks["temporaryBrowserDismissed"] = browser.viewIfLoaded?.window == nil
        let report: [String: Any] = ["runID": run, "checks": checks, "failure": failure,
            "scope": "iOS simulator without Bilibili app; native user taps in production Cook; default safari-view behavior",
            "videoPlaybackTested": false, "universalLinkAppHandoffTested": false]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        attachment.name = "ios-cook-external-report"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(failure.isEmpty, "Safe phase: " + failure)
        XCTAssertEqual(checks.count, 8)
        XCTAssertTrue(checks.values.allSatisfy { $0 })
    }

    private func prepareTap(_ web: WKWebView, selector: String, phase: String, run: String, directory: URL, window: UIWindow) async throws {
        _ = try await web.evaluateJavaScript("(" + selector + ").scrollIntoView({block:'center'});true")
        try await Task.sleep(nanoseconds: 300_000_000)
        let rawObservation = try await web.evaluateJavaScript("(() => {const e=" + selector + ";const r=e.getBoundingClientRect();return {label:e.textContent.trim(),href:e.href||e.getAttribute('href')||'',x:r.x+r.width/2,y:r.y+r.height/2};})()") as? [String: Any]
        let observed = try XCTUnwrap(rawObservation)
        let x = try XCTUnwrap(observed["x"] as? Double), y = try XCTUnwrap(observed["y"] as? Double)
        let point = web.convert(CGPoint(x: x, y: y), to: window)
        var fields = observed
        fields["nativeX"] = point.x; fields["nativeY"] = point.y
        fields["phase"] = "await-tap-" + phase; fields["runID"] = run
        try await progress(fields, directory: directory)
        attach(window, name: "ios-before-" + phase)
        print("COOK_EXTERNAL_AWAIT " + phase)
    }
    private func progress(_ value: [String: Any], directory: URL) async throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("progress.json"), options: .atomic)
    }
    private func safari(from controller: UIViewController) -> SFSafariViewController? {
        if let safari = controller as? SFSafariViewController { return safari }
        if let presented = controller.presentedViewController, let safari = safari(from: presented) { return safari }
        return controller.children.compactMap { safari(from: $0) }.first
    }
    private func findWeb(_ view: UIView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.compactMap { findWeb($0) }.first }
    private func wait(_ seconds: TimeInterval, condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure.timeout
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
