import CoreGraphics
import Foundation
import ImageIO

enum IconNormalizationError: Error, Equatable {
    case unreadable, tooLarge, notSquare, empty
    var message: String {
        switch self {
        case .unreadable: return "图片无法读取。可选择 PNG、WebP、JPEG、HEIC 或独立 SVG 图标，或填写图片链接。"
        case .tooLarge: return "位图原图需在 5 MB 以内，SVG 需在 2 MB 以内，标准化后需在 4 MB 以内。"
        case .notSquare: return "完整图标请使用接近正方形的画布，长宽差不超过 5%。"
        case .empty: return "主体图标不能是全透明图片。"
        }
    }
}
struct ApplicationIconNormalizer {
    func normalize(_ data: Data, role: ApplicationIconRole) async throws -> Data {
        let task = Task.detached(priority: .userInitiated) { try Self.render(data, role: role) }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    private static func render(_ data: Data, role: ApplicationIconRole) throws -> Data {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 5 * 1024 * 1024 else { throw IconNormalizationError.tooLarge }
        let image: CGImage
        do { image = try ApplicationImageDecoder.decode(data, maximumPixelSize: 2048).image }
        catch ApplicationImageError.oversized { throw IconNormalizationError.tooLarge }
        catch is CancellationError { throw CancellationError() }
        catch { throw IconNormalizationError.unreadable }
        if role == .appIcon, Double(abs(image.width - image.height)) / Double(max(image.width, image.height)) > 0.05 { throw IconNormalizationError.notSquare }
        guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw IconNormalizationError.unreadable }
        let scale = min(1024 / CGFloat(image.width), 1024 / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(image, in: role == .appIcon ? CGRect(x: 0, y: 0, width: 1024, height: 1024) :
            CGRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height))
        if role == .mark {
            guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { throw IconNormalizationError.unreadable }
            var minX = 1024, minY = 1024, maxX = -1, maxY = -1
            for y in 0..<1024 {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<1024 where bytes[y * 4096 + x * 4 + 3] > 4 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, let intermediate = context.makeImage() else { throw IconNormalizationError.empty }
            let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            guard let trimmed = intermediate.cropping(to: crop) else { throw IconNormalizationError.unreadable }
            context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let scale = 819.2 / CGFloat(max(trimmed.width, trimmed.height))
            let width = CGFloat(trimmed.width) * scale, height = CGFloat(trimmed.height) * scale
            context.draw(trimmed, in: CGRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
        }
        try Task.checkCancellation()
        guard let output = context.makeImage() else { throw IconNormalizationError.unreadable }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else { throw IconNormalizationError.unreadable }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination), png.length <= 4 * 1024 * 1024 else { throw IconNormalizationError.tooLarge }
        return png as Data
    }
}
