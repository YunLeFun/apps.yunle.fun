import Foundation
import CoreImage
import ImageIO
import Vision

protocol PhotoQRCodeDecoding: Sendable { func payloads(in data: Data) async throws -> [String] }
struct PhotoQRCodeDecoder: PhotoQRCodeDecoding {
    func payloads(in data: Data) async throws -> [String] {
        let work = Task.detached(priority: .userInitiated) { try Self.decode(data) }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }
    private static func decode(_ data: Data) throws -> [String] {
        try Task.checkCancellation()
        guard data.count <= 60 * 1024 * 1024 else { throw ScanImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { throw ScanImageError.invalidImage }
        guard width.doubleValue * height.doubleValue <= 100_000_000 else { throw ScanImageError.tooLarge }
        let longest = max(width.intValue, height.intValue)
        let sizes = [min(1536, longest), min(4096, longest), min(8192, longest)].reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        for size in sizes {
            try Task.checkCancellation()
            let payloads: [String] = try autoreleasepool {
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceShouldCacheImmediately: true]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ScanImageError.invalidImage }
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                #if targetEnvironment(simulator)
                // Simulator runtimes may not provide the default inference
                // context. Select only CPUs that Vision reports as supported.
                if #available(iOS 17, *) {
                    for (stage, devices) in (try? request.supportedComputeStageDevices) ?? [:] {
                        if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                            request.setComputeDevice(cpu, for: stage)
                        }
                    }
                } else { request.usesCPUOnly = true }
                #endif
                // Some runtimes cannot load their barcode inference model or
                // return no observations. Core Image remains an independent
                // on-device QR decoder; no image leaves the process.
                try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                try Task.checkCancellation()
                var seen = Set<String>()
                var values = (request.results ?? []).sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
                    .compactMap(\.payloadStringValue)
                let context = CIContext(options: [.useSoftwareRenderer: true])
                let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
                values += (detector?.features(in: CIImage(cgImage: image)) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                try Task.checkCancellation()
                return values.filter { !$0.isEmpty && $0.utf8.count <= 10_000 && seen.insert($0).inserted }
            }
            if !payloads.isEmpty { return Array(payloads.prefix(20)) }
        }
        throw ScanImageError.noCode
    }
}
