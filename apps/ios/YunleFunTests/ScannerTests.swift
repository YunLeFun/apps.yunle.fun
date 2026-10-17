import AVFoundation
import Combine
import CoreImage.CIFilterBuiltins
import ImageIO
import XCTest
@testable import YunleFun

final class ScanRoutingTests: XCTestCase {
    func testRecognizesCanonicalWorkshopAndApplicationLinksWithoutLegacySlugGuessing() {
        XCTAssertEqual(ScanParser.parse("https://apps.yunle.fun/w/abc234", purpose: .general), .destination(.workshop("ABC234")))
        XCTAssertEqual(ScanParser.parse("ABC234", purpose: .workshop), .destination(.workshop("ABC234")))
        XCTAssertEqual(ScanParser.parse("https://apps.yunle.fun/app/ai-sfc", purpose: .general), .destination(.application("ai-sfc")))
        XCTAssertEqual(NativeLink.destination(URL(string: "yunlefun://workshop/abc234")!), .workshop("ABC234"))
        XCTAssertEqual(NativeLink.destination(URL(string: "yunlefun://w/abc234")!), .workshop("ABC234"))
        XCTAssertEqual(NativeLink.destination(URL(string: "yunlefun://app/record-one")!), .application("record-one"))
        let market = CloudApplication(id: "record-one", name: "公开作品", slug: "collision", marketShortName: "ai-sfc")
        let collision = CloudApplication(id: "record-two", name: "另一作者的同名作品", slug: "ai-sfc")
        XCTAssertEqual(NativeLink.publicApplication(key: "AI-SFC", in: [market, collision])?.id, "record-one")
        XCTAssertEqual(NativeLink.publicApplication(key: "record-two", in: [market, collision])?.id, "record-two")
        XCTAssertNil(NativeLink.publicApplication(key: "collision", in: [market, collision]))
        XCTAssertNil(NativeLink.publicApplication(key: "ai-sfc", in: [market, market]))
    }
    func testExternalURLAndPlainTextAreResultsRatherThanImplicitNavigation() {
        let external = URL(string: "https://example.invalid/app/123?q=hello")!
        XCTAssertEqual(ScanParser.parse(external.absoluteString, purpose: .general), .website(external))
        XCTAssertEqual(ScanParser.parse("http://example.invalid/", purpose: .general), .website(URL(string: "http://example.invalid/")!))
        XCTAssertEqual(ScanParser.parse("普通文本\n第二行", purpose: .general), .text("普通文本\n第二行"))
        XCTAssertEqual(ScanParser.parse(external.absoluteString, purpose: .workshop), .unsupportedWorkshop)
    }
    func testCodeCredentialsActiveSchemesAndForeignOriginsCannotBecomeNativeRoutes() {
        for value in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hello", "https://name:secret@example.invalid/",
                      "yunlefun://auth/callback?code=secret&state=private", "https://apps.yunle.fun/app/%2E%2E", "https://apps.yunle.fun/app/a%2Fb",
                      "https://apps.yunle.fun:444/w/ABC234", "https://apps.yunle.fun/w/ABC234?access_token=secret", "https://apps.yunle.fun/unknown"] {
            XCTAssertEqual(ScanParser.parse(value, purpose: .general), .unsupportedLink, value)
            XCTAssertNil(NativeLink.destination(URL(string: value)!), value)
        }
        let foreign = "https://apps.yunle.fun.evil.invalid/w/ABC234"
        XCTAssertEqual(ScanParser.parse(foreign, purpose: .general), .website(URL(string: foreign)!))
        XCTAssertEqual(ScanParser.parse(foreign, purpose: .workshop), .unsupportedWorkshop)
        XCTAssertEqual(ScanParser.parse(String(repeating: "x", count: 10_001), purpose: .general), .unsupportedLink)
    }
    func testPublicCatalogRefreshNeverStripsTheWorkshopEditionFromAHomeEntry() {
        var saved = CloudApplication(id: "app-one", name: "工坊当前版本", websiteUrl: "https://example.invalid/current", accessMode: "public", audience: "workshop", accessWorkshopID: "ABC234")
        saved.homeReference = "legacy-reference"
        let publicEdition = CloudApplication(id: "app-one", name: "公开获批版本", websiteUrl: "https://example.invalid/old")
        let resolved = saved.refreshingPublicMetadata(with: publicEdition)
        XCTAssertEqual(resolved, saved)
        XCTAssertFalse(resolved.canOpenAsGuest)
        let publicHome = CloudApplication(id: "app-one", name: "旧资料", homeReference: "legacy-reference")
        XCTAssertEqual(publicHome.refreshingPublicMetadata(with: publicEdition).name, publicEdition.name)
        XCTAssertEqual(publicHome.refreshingPublicMetadata(with: publicEdition).homeKey, "legacy-reference")
    }
}

final class PhotoQRCodeTests: XCTestCase {
    func testNativeDecoderDecodesAnActualGeneratedShareQRCode() async throws {
        let payload = "https://apps.yunle.fun/w/ABC234"
        let data = try qrImageData([(payload, CGRect(x: 80, y: 80, width: 440, height: 440))], canvas: CGSize(width: 600, height: 600))
        let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
        XCTAssertEqual(decoded, [payload])
    }
    func testDownsampledJPEGWithOrientationAndUnicodeCanBeDecoded() async throws {
        let payload = "云乐坊：你好，世界 🌏"
        let data = try qrImageData([(payload, CGRect(x: 800, y: 800, width: 700, height: 700))], canvas: CGSize(width: 3200, height: 2400), jpeg: true, orientation: 6)
        let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
        XCTAssertEqual(decoded, [payload])
    }
    func testMultipleActualCodesAreOfferedInsteadOfSilentlySelectingTheFirst() async throws {
        let data = try qrImageData([("https://apps.yunle.fun/w/ABC234", CGRect(x: 80, y: 100, width: 440, height: 440)),
                                   ("https://example.invalid/", CGRect(x: 680, y: 100, width: 440, height: 440))], canvas: CGSize(width: 1200, height: 660))
        let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
        XCTAssertEqual(Set(decoded), Set(["https://apps.yunle.fun/w/ABC234", "https://example.invalid/"]))
    }
    func testExportableAppQRCodeUsesTheSameNativeDecoder() async throws {
        let payload = "https://apps.yunle.fun/app/ai-sfc"
        let data = try qrImageData([(payload, CGRect(x: 80, y: 80, width: 440, height: 440))], canvas: CGSize(width: 600, height: 600))
        let decoded = try await PhotoQRCodeDecoder().payloads(in: data)
        XCTAssertEqual(decoded, [payload])
    }
    func testUnreadableImagesAndImagesWithoutACodeHaveDifferentFailures() async throws {
        do { _ = try await PhotoQRCodeDecoder().payloads(in: Data("not an image".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? ScanImageError, .invalidImage) }
        let empty = try qrImageData([], canvas: CGSize(width: 240, height: 240))
        do { _ = try await PhotoQRCodeDecoder().payloads(in: empty); XCTFail() }
        catch { XCTAssertEqual(error as? ScanImageError, .noCode) }
    }
    func testCancelledImageWorkDoesNotPublishAnEmptySuccess() async throws {
        let data = try qrImageData([("https://apps.yunle.fun/w/ABC234", CGRect(x: 40, y: 40, width: 240, height: 240))], canvas: CGSize(width: 320, height: 320))
        let task = Task { try Task.checkCancellation(); return try await PhotoQRCodeDecoder().payloads(in: data) }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
final class QRScannerModelTests: XCTestCase {
    func testEnteringScannerDoesNotRequestCameraPermissionForPhotoOnlyUse() async {
        let permission = ScannerPermission(.notDetermined), camera = ScannerCamera()
        let model = QRScannerModel(purpose: .general, permission: permission, camera: camera)
        model.appear()
        XCTAssertEqual(model.cameraState, .permissionRequired); XCTAssertEqual(permission.requests, 0); XCTAssertTrue(camera.starts.isEmpty)
        permission.allow = false
        await model.enableCamera()
        XCTAssertEqual(permission.requests, 1); XCTAssertEqual(model.cameraState, .denied); XCTAssertTrue(camera.starts.isEmpty)
    }
    func testDeniedRestrictedAndMissingCamerasKeepThePhotoFallbackWithoutRequestingAccessAgain() {
        for (permission, expected) in [(ScannerPermission(.denied), QRScannerCameraState.denied), (ScannerPermission(.restricted), .restricted), (ScannerPermission(.authorized, available: false), .unavailable)] {
            let camera = ScannerCamera(), model = QRScannerModel(purpose: .workshop, permission: permission, camera: camera)
            model.appear()
            XCTAssertEqual(model.cameraState, expected); XCTAssertEqual(permission.requests, 0); XCTAssertTrue(camera.starts.isEmpty)
        }
    }
    func testPermissionGrantedAfterDismissalDoesNotStartTheCamera() async {
        let gate = ScannerGate(), permission = ScannerPermission(.notDetermined, gate: gate), camera = ScannerCamera()
        let model = QRScannerModel(purpose: .general, permission: permission, camera: camera)
        model.appear()
        let request = Task { await model.enableCamera() }
        await fulfillment(of: [gate.entered], timeout: 3)
        model.disappear(); await gate.open(); await request.value
        XCTAssertTrue(camera.starts.isEmpty); XCTAssertNotEqual(model.cameraState, .running)
    }
    func testInactivePhotoPickerAndDismissalStopCameraAndTorch() async {
        let camera = ScannerCamera(), model = QRScannerModel(purpose: .general, permission: ScannerPermission(.authorized), camera: camera)
        model.appear(); await running(camera, model)
        let torch = expectation(description: "torch on")
        let observer = model.$torchOn.filter { $0 }.sink { _ in torch.fulfill() }
        model.toggleTorch(); camera.emit(.torch(true)); await fulfillment(of: [torch], timeout: 3)
        withExtendedLifetime(observer) {}
        XCTAssertEqual(camera.torches, [true])
        let stops = camera.stops
        model.sceneIsActive(false)
        XCTAssertGreaterThan(camera.stops, stops); XCTAssertFalse(model.torchOn); XCTAssertFalse(model.torchAvailable)
        model.sceneIsActive(true); await running(camera, model)
        model.pickerIsPresented(true)
        XCTAssertEqual(model.cameraState, .paused)
        let starts = camera.starts.count
        model.sceneIsActive(true)
        XCTAssertEqual(camera.starts.count, starts, "Returning active while Photos is open must not restart capture")
        model.pickerCancelled(); await running(camera, model)
        model.disappear(); XCTAssertEqual(model.cameraState, .paused); XCTAssertFalse(model.torchOn)
    }
    func testOldCameraCallbackCannotReplaceAResultOrAnotherCaptureSession() async {
        let camera = ScannerCamera(), model = QRScannerModel(purpose: .workshop, permission: ScannerPermission(.authorized), camera: camera)
        model.appear(); await running(camera, model)
        let old = camera.starts[0]
        let decoded = expectation(description: "workshop result")
        let observer = model.$candidates.filter { !$0.isEmpty }.prefix(1).sink { _ in decoded.fulfill() }
        camera.emit(.codes(["https://apps.yunle.fun/w/ABC234", "https://apps.yunle.fun/w/ABC234"]))
        await fulfillment(of: [decoded], timeout: 3); withExtendedLifetime(observer) {}
        XCTAssertEqual(model.candidates.count, 1); XCTAssertEqual(model.cameraState, .paused)
        model.continueScanning(); await running(camera, model)
        let leaked = expectation(description: "old capture ignored"); leaked.isInverted = true
        let noOld = model.$candidates.filter { !$0.isEmpty }.sink { _ in leaked.fulfill() }
        camera.emit(.codes(["https://apps.yunle.fun/w/XYZ234"]), id: old)
        await fulfillment(of: [leaked], timeout: 0.1); withExtendedLifetime(noOld) {}
        XCTAssertTrue(model.candidates.isEmpty)
    }
    func testInterruptedCaptureCanBeRestartedInsteadOfKeepingAnUnusableSessionID() async {
        let camera = ScannerCamera(), model = QRScannerModel(purpose: .general, permission: ScannerPermission(.authorized), camera: camera)
        model.appear(); await running(camera, model)
        let interrupted = expectation(description: "interrupted")
        let observer = model.$cameraState.filter { $0 == .interrupted }.sink { _ in interrupted.fulfill() }
        camera.emit(.interrupted); await fulfillment(of: [interrupted], timeout: 3); withExtendedLifetime(observer) {}
        let count = camera.starts.count
        model.continueScanning(); XCTAssertEqual(camera.starts.count, count + 1)
        await running(camera, model)
    }
    func testPhotoFailureIsNotAResultAndCanBeRetriedWithoutCameraPermission() async {
        let camera = ScannerCamera(), model = QRScannerModel(purpose: .general, permission: ScannerPermission(.denied), camera: camera,
                                                           decoder: ScannerDecoder(error: .noCode))
        model.appear()
        let failed = expectation(description: "image error")
        let observer = model.$issue.compactMap { $0 }.sink { _ in failed.fulfill() }
        model.readPhoto { Data([1]) }
        await fulfillment(of: [failed], timeout: 3); withExtendedLifetime(observer) {}
        XCTAssertEqual(model.issue, ScanImageError.noCode.message); XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(model.isReadingPhoto); XCTAssertTrue(camera.starts.isEmpty)
    }
    func testDismissedScannerDiscardsAnUncooperativeLatePhotoDecode() async {
        let gate = ScannerGate(), camera = ScannerCamera(), model = QRScannerModel(purpose: .general, permission: ScannerPermission(.denied), camera: camera,
                                                                                 decoder: ScannerDecoder(gate: gate))
        model.appear(); model.readPhoto { Data([1]) }
        await fulfillment(of: [gate.entered], timeout: 3)
        let leaked = expectation(description: "late image ignored"); leaked.isInverted = true
        let observer = model.$candidates.filter { !$0.isEmpty }.sink { _ in leaked.fulfill() }
        model.disappear(); await gate.open()
        await fulfillment(of: [leaked], timeout: 0.1); withExtendedLifetime(observer) {}
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertNil(model.issue); XCTAssertFalse(model.isReadingPhoto)
    }
    private func running(_ camera: ScannerCamera, _ model: QRScannerModel) async {
        let ready = expectation(description: "camera running")
        let observer = model.$cameraState.filter { $0 == .running }.prefix(1).sink { _ in ready.fulfill() }
        camera.emit(.running(torchAvailable: true))
        await fulfillment(of: [ready], timeout: 3); withExtendedLifetime(observer) {}
        XCTAssertEqual(model.cameraState, .running)
    }
}
private final class ScannerPermission: CameraPermissionChecking {
    var isAvailable: Bool
    var status: CameraPermission
    var requests = 0
    var allow = true
    let gate: ScannerGate?
    init(_ status: CameraPermission, available: Bool = true, gate: ScannerGate? = nil) { self.status = status; isAvailable = available; self.gate = gate }
    func request() async -> Bool { requests += 1; await gate?.wait(); status = allow ? .authorized : .denied; return allow }
}
private final class ScannerCamera: CameraQRReading {
    let session = AVCaptureSession()
    var starts: [UUID] = []
    var stops = 0
    var torches: [Bool] = []
    var callbacks: [UUID: (UUID, CameraReaderEvent) -> Void] = [:]
    func start(id: UUID, receive: @escaping (UUID, CameraReaderEvent) -> Void) { starts.append(id); callbacks[id] = receive }
    func stop() { stops += 1 }
    func torch(_ enabled: Bool) { torches.append(enabled) }
    func emit(_ event: CameraReaderEvent, id: UUID? = nil) { if let id = id ?? starts.last { callbacks[id]?(id, event) } }
}
private actor ScannerGate {
    let entered = XCTestExpectation(description: "scanner operation entered")
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async { entered.fulfill(); if !opened { await withCheckedContinuation { continuation = $0 } } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
private struct ScannerDecoder: PhotoQRCodeDecoding {
    var gate: ScannerGate?
    var error: ScanImageError?
    func payloads(in data: Data) async throws -> [String] {
        await gate?.wait()
        if let error { throw error }
        return ["https://apps.yunle.fun/w/ABC234"]
    }
}
private func qrImageData(_ items: [(String, CGRect)], canvas: CGSize, jpeg: Bool = false, orientation: Int = 1) throws -> Data {
    var image = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(origin: .zero, size: canvas))
    for (payload, rect) in items {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(payload.utf8); filter.correctionLevel = "M"
        let code = try XCTUnwrap(filter.outputImage)
        let scaled = code.transformed(by: CGAffineTransform(scaleX: rect.width / code.extent.width, y: rect.height / code.extent.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        image = scaled.composited(over: image)
    }
    let cgImage = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, (jpeg ? "public.jpeg" : "public.png") as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    if ProcessInfo.processInfo.environment["YLF_EXPORT_SCAN_FIXTURES"] == "1", let payload = items.first?.0 {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qr-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = items.count > 1 ? "multiple" : jpeg ? "rotated" : payload.contains("/w/") ? "workshop" : payload.contains("/app/") ? "application" : "external"
        let file = folder.appendingPathComponent(name).appendingPathExtension(jpeg ? "jpg" : "png")
        try (data as Data).write(to: file)
        print("Scanner test fixture: \(file.path)")
    }
    return data as Data
}
