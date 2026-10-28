import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Only re-encoded pixels leave the device; original filenames and photo metadata are discarded.
struct FeedbackScreenshot: Identifiable, Equatable, Sendable, Transferable {
    static let maximumCount = 3
    static let maximumBytes = 1024 * 1024
    static let maximumInputBytes = 20 * 1024 * 1024
    let id: UUID
    let data: Data
    let width: Int
    let height: Int

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in
            let size = try file.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= maximumInputBytes else { throw FeedbackScreenshotError.tooLarge }
            let data = try Data(contentsOf: file.file, options: .mappedIfSafe)
            let work = Task.detached(priority: .userInitiated) { try prepare(data) }
            return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
        }
    }

    static func prepare(_ data: Data, maximumPixels: Double = 60_000_000) throws -> Self {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= maximumInputBytes else { throw FeedbackScreenshotError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { throw FeedbackScreenshotError.unreadable }
        guard width.doubleValue * height.doubleValue <= maximumPixels else { throw FeedbackScreenshotError.tooLarge }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FeedbackScreenshotError.unreadable
        }
        for quality in [0.85, 0.7, 0.5] {
            try Task.checkCancellation()
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw FeedbackScreenshotError.unreadable
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw FeedbackScreenshotError.unreadable }
            if output.length <= maximumBytes {
                return Self(id: UUID(), data: output as Data, width: image.width, height: image.height)
            }
        }
        throw FeedbackScreenshotError.tooLarge
    }
}

enum FeedbackScreenshotError: Error {
    case tooLarge, unreadable
    var message: String {
        switch self {
        case .tooLarge: return "图片文件或尺寸过大，请选择 20 MB 以内的截图，或裁剪后重试。"
        case .unreadable: return "无法读取这张图片，请重新选择，或等待 iCloud 下载后再试。"
        }
    }
}
