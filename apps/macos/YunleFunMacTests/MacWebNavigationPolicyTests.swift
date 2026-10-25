import XCTest
@testable import YunleFunMac

final class MacWebNavigationPolicyTests: XCTestCase {
    private var application: CloudApplication {
        CloudApplication(id: "public-test", name: "Test", websiteUrl: "https://app.example/path", audience: "public", isPublic: true)
    }

    func testOnlyFreePublicCatalogueApplicationsCanLaunch() {
        XCTAssertEqual(MacWebNavigationPolicy.launchURL(for: application)?.host, "app.example")
        var rejected = [CloudApplication]()
        var app = application; app.coinCost = 1; rejected.append(app)
        app = application; app.requiresMembership = true; rejected.append(app)
        app = application; app.accessMode = "login_required"; rejected.append(app)
        app = application; app.isUnavailable = true; rejected.append(app)
        app = application; app.isPublic = false; rejected.append(app)
        app = application; app.audience = "owner"; rejected.append(app)
        app = application; app.audience = "workshop"; rejected.append(app)
        app = application; app.audience = "future-private-scope"; rejected.append(app)
        app = application; app.accessWorkshopID = "workshop"; rejected.append(app)
        app = application; app.accessOwnerID = "owner"; rejected.append(app)
        app = application; app.personalMarketOwnerLogin = "author"; rejected.append(app)
        app = application; app.websiteUrl = "http://app.example"; rejected.append(app)
        app = application; app.websiteUrl = "https://user:secret@app.example"; rejected.append(app)
        for restricted in rejected {
            XCTAssertNil(MacWebNavigationPolicy.launchURL(for: restricted), "Unexpectedly accepted \(restricted)")
        }
    }

    func testOAuthHTTPSNavigationRemainsInTheIsolatedWebProfile() {
        for raw in ["https://app.example/", "https://identity.example/authorize?state=opaque", "https://app.example/callback?code=opaque"] {
            XCTAssertEqual(MacWebNavigationPolicy.decision(for: URL(string: raw), isMainFrame: true, userInitiated: false), .allow)
        }
    }

    func testUnsafeSchemesAndCredentialURLsNeverNavigateOrLaunchAnotherApp() {
        for raw in ["http://app.example", "file:///etc/hosts", "javascript:alert(1)", "data:text/html,hello", "yunlefun://login", "https://user:secret@app.example"] {
            XCTAssertEqual(MacWebNavigationPolicy.decision(for: URL(string: raw), isMainFrame: true, userInitiated: true), .cancel)
        }
    }

    func testExternalLinksRequireAnExplicitUserActionInTheMainFrame() {
        let url = URL(string: "mailto:hello@example.com")!
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: url, isMainFrame: true, userInitiated: true), .openExternally)
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: url, isMainFrame: true, userInitiated: false), .cancel)
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: url, isMainFrame: false, userInitiated: true), .cancel)
    }

    func testBlankPopupBootstrapDoesNotPermitArbitraryLocalPages() {
        let url = URL(string: "about:blank")!
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: url, isMainFrame: true, userInitiated: false), .cancel)
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: url, isMainFrame: true, userInitiated: false, allowsBlank: true), .allow)
        XCTAssertEqual(MacWebNavigationPolicy.decision(for: URL(string: "about:config"), isMainFrame: true, userInitiated: false, allowsBlank: true), .cancel)
    }
}
