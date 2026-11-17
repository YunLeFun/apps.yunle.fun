import SwiftUI
import XCTest
@testable import YunleFun

@MainActor
final class ApplicationShareCardTests: XCTestCase {
    // Public API projection for /api/apps/public/air-conditioner, checked 2026-11-04.
    private let application = CloudApplication(id: "3b49fbed6a2707b9000a533e02729196", name: "云空调", slug: "air-conditioner",
        marketShortName: "air-conditioner", description: "云空调，便携小空调！其实是个冷笑话，随身携带的毫无制冷效果的仿真小空调",
        websiteUrl: "https://ac.yunyoujun.cn", emoji: "❄️", themeColor: "#4ea5f5")

    func testExportedLightAndDarkCardsDecodeToTheExactWebsite() async throws {
        for appearance in ApplicationShareAppearance.allCases {
            let image = try ApplicationShareCardRenderer.image(application: application, appearance: appearance, icon: nil)
            XCTAssertEqual(image.size.width * image.scale, 1080)
            XCTAssertEqual(image.size.height * image.scale, 1620)
            let png = try XCTUnwrap(image.pngData())
            let decoded = try await PhotoQRCodeDecoder().payloads(in: png)
            XCTAssertEqual(decoded, [application.websiteUrl!])
            attach(image, name: "share-card-\(appearance.rawValue)")
            // Messaging apps resize and recompress the whole card, not just its QR.
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let reduced = UIGraphicsImageRenderer(size: CGSize(width: 540, height: 810), format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 540, height: 810))
            }
            let jpeg = try XCTUnwrap(reduced.jpegData(compressionQuality: 0.7))
            let compressedPayloads = try await PhotoQRCodeDecoder().payloads(in: jpeg)
            XCTAssertEqual(compressedPayloads, [application.websiteUrl!])
        }
    }

    func testInvalidThemeColorFallsBackToTheDefaultAccent() {
        for raw in [nil, "", "orange", "#GG4422", "##112233", "112233", "#12", "url(example.com)"] as [String?] {
            XCTAssertEqual(ApplicationShareTheme(hex: raw).hex, ApplicationShareTheme.defaultHex)
        }
        XCTAssertEqual(ApplicationShareTheme(hex: "#ffd447").hex, "#FFD447")
        XCTAssertEqual(ApplicationShareTheme(hex: "#abc").hex, "#AABBCC")
        XCTAssertLessThanOrEqual(ApplicationShareCard.qrSide / ApplicationShareCard.size.width, 0.45)
        XCTAssertGreaterThanOrEqual(ApplicationShareCard.qrSide / ApplicationShareCard.size.width, 0.38)
    }

    func testWebsitePayloadNeverUsesCanonicalLaunchOrMarketURL() async throws {
        var app = application
        app.marketShortName = "web-resume"
        app.websiteUrl = "https://example.com/app?name=%E4%BA%91&ref=share#hello"
        XCTAssertNotEqual(app.websiteUrl, app.launchURL?.absoluteString)
        for appearance in ApplicationShareAppearance.allCases {
            let data = try XCTUnwrap(ApplicationShareCardRenderer.image(application: app, appearance: appearance, icon: nil).pngData())
            let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
            XCTAssertEqual(decoded, [app.websiteUrl!])
        }
    }

    func testMissingAndInvalidWebsitesFailInsteadOfExportingAWrongCode() {
        for raw in [nil, "", "javascript:alert(1)", "https://user:secret@example.com", "https://example.com/\n", "/app/hello"] as [String?] {
            var app = application; app.websiteUrl = raw
            XCTAssertThrowsError(try ApplicationShareQRCode.payload(for: app))
            XCTAssertThrowsError(try ApplicationShareCardRenderer.image(application: app, appearance: .light, icon: nil))
        }
    }

    func testWebsiteMatchingRequiresOneExactPublicRecord() throws {
        let url = try XCTUnwrap(URL(string: application.websiteUrl!))
        XCTAssertEqual(NativeLink.publicApplication(websiteURL: url, in: [application])?.id, application.id)
        XCTAssertNil(NativeLink.publicApplication(websiteURL: url.appendingPathComponent("other"), in: [application]))
        XCTAssertNil(NativeLink.publicApplication(websiteURL: url, in: [application, application]))
        var scoped = application; scoped.accessWorkshopID = "ABC234"
        XCTAssertNil(NativeLink.publicApplication(websiteURL: url, in: [scoped]))
        scoped = application; scoped.isPublic = false
        XCTAssertNil(NativeLink.publicApplication(websiteURL: url, in: [scoped]))
        XCTAssertEqual(NativeLink.destination(application.shareURL), .application(application.publicKey))
    }

    func testLongNamesAndDescriptionsStillExportAScannableCard() async throws {
        var app = application
        app.name = "一个名字很长很长的云端应用 With A Long Name"
        app.description = String(repeating: "长简介也应该让二维码完整可见。", count: 30)
        let image = try ApplicationShareCardRenderer.image(application: app, appearance: .dark, icon: nil)
        let decoded = try await PhotoQRCodeDecoder().payloads(in: XCTUnwrap(image.pngData()))
        XCTAssertEqual(decoded, [app.websiteUrl!])
        attach(image, name: "share-card-long-content")
    }

    func testShareSheetRendersAtAccessibilitySizeInBothAppearances() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for appearance in ApplicationShareAppearance.allCases {
            let controller = UIHostingController(rootView: ApplicationShareView(application: application)
                .environment(\.dynamicTypeSize, .accessibility3).preferredColorScheme(appearance.colorScheme))
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 500_000_000)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            attach(image, name: "share-sheet-\(appearance.rawValue)-accessibility")
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
