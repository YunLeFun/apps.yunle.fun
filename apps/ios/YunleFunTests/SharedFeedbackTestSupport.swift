import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

func sharedFeedbackTestImage() throws -> Data {
    let color = CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(CGContext(data: nil, width: 48, height: 80, bitsPerComponent: 8, bytesPerRow: 48 * 4,
        space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 48, height: 80))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2, kCGImagePropertyGPSLongitude: 121.5],
    ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
}

func sharedFeedbackTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-feedback-test-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func sharedFeedbackTestRecord(_ id: String = "fb_fixture") -> SharedFeedbackRecord {
    .init(receipt: .init(id: id, productId: "www", ticketId: id,
        ticketUrl: "https://support.yunle.fun/tickets/" + id + "#access=synthetic-fixture-capability"), createdAt: Date())
}
