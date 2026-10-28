import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import YunleFun

final class FeedbackScreenshotTests: XCTestCase {
    func testTestFlightHasPriorityOnlyForASandboxReceiptOutsideDevelopmentAndSimulator() {
        let sandbox = URL(fileURLWithPath: "/StoreKit/sandboxReceipt")
        XCTAssertEqual(FeedbackChannel.forLaunch(receiptURL: sandbox, isDevelopment: false, isSimulator: false), .testFlight)
        XCTAssertEqual(FeedbackChannel.forLaunch(receiptURL: sandbox, isDevelopment: true, isSimulator: false), .standard)
        XCTAssertEqual(FeedbackChannel.forLaunch(receiptURL: sandbox, isDevelopment: false, isSimulator: true), .standard)
        XCTAssertEqual(FeedbackChannel.forLaunch(receiptURL: nil, isDevelopment: false, isSimulator: false), .standard)
        XCTAssertEqual(FeedbackChannel.forLaunch(receiptURL: URL(fileURLWithPath: "/StoreKit/receipt"), isDevelopment: false, isSimulator: false), .standard)
    }
    func testScreenshotDownsamplesPixelsAndDropsLocationAndOriginalMetadata() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 3200), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 3200))
        }
        let input = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(input, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2, kCGImagePropertyGPSLongitude: 121.5],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private test metadata"],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try FeedbackScreenshot.prepare(input as Data)
        XCTAssertEqual(result.height, 2048)
        XCTAssertEqual(result.width, 1536)
        XCTAssertLessThanOrEqual(result.data.count, FeedbackScreenshot.maximumBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
    }

    func testInvalidAndOversizedImagesAreRejected() {
        XCTAssertThrowsError(try FeedbackScreenshot.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(try FeedbackScreenshot.prepare(Data(repeating: 0, count: FeedbackScreenshot.maximumInputBytes + 1)))
    }

    func testOrientationIsAppliedBeforeMetadataIsRemoved() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 80), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        }
        let input = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(input, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try FeedbackScreenshot.prepare(input as Data)
        XCTAssertEqual(result.width, 80)
        XCTAssertEqual(result.height, 160)
    }
}
