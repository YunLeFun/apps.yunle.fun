import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if canImport(YunleFun)
@testable import YunleFun
#else
@testable import ShareFeedbackCore
#endif

final class SharedScreenshotImporterTests: XCTestCase {
    func testFileProviderProducesOwnedSanitizedJPEGData() async throws {
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic.jpg")
        try sharedFeedbackTestImage().write(to: file)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))
        let result = try await SharedScreenshotImporter().load([provider])
        try FileManager.default.removeItem(at: file)
        let image = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(image.width, 48); XCTAssertEqual(image.height, 80)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testMissingAndTooManyImagesFailWithoutSilentlyDroppingAttachments() async throws {
        do { _ = try await SharedScreenshotImporter().load([]); XCTFail() }
        catch { XCTAssertTrue(error is SharedScreenshotImportError) }
        let directory = try sharedFeedbackTestDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic.jpg")
        try sharedFeedbackTestImage().write(to: file)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))
        do { _ = try await SharedScreenshotImporter().load(Array(repeating: provider, count: 4)); XCTFail() }
        catch { XCTAssertTrue(error is SharedScreenshotImportError) }
    }

    func testCancellationBeforeRegistrationAndLateDuplicateCompletionResumeExactlyOnce() async {
        let operation = SharedImageReadOperation()
        operation.cancel()
        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(operation.begin(continuation))
                operation.finish(.success(Data([1])))
            }
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
        let active = SharedImageReadOperation()
        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                XCTAssertTrue(active.begin(continuation)); active.cancel()
                active.finish(.success(Data([1]))); active.cancel()
            }
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
