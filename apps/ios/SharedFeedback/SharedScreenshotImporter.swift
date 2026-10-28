import Foundation
import UniformTypeIdentifiers

protocol SharedScreenshotImporting: Sendable {
    func load(_ providers: [NSItemProvider]) async throws -> [FeedbackScreenshot]
}

struct SharedScreenshotImporter: SharedScreenshotImporting {
    func load(_ providers: [NSItemProvider]) async throws -> [FeedbackScreenshot] {
        let images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !images.isEmpty else { throw SharedScreenshotImportError.noImage }
        guard images.count <= FeedbackScreenshot.maximumCount else { throw SharedScreenshotImportError.tooMany }
        var result: [FeedbackScreenshot] = []
        for provider in images {
            try Task.checkCancellation()
            let type = provider.registeredTypeIdentifiers.first {
                !$0.hasPrefix("com.apple.private.") && UTType($0)?.conforms(to: .image) == true
            }
                ?? UTType.image.identifier
            let data = try await readFile(provider, type: type)
            let work = Task.detached(priority: .userInitiated) {
                try autoreleasepool { try FeedbackScreenshot.prepare(data, maximumPixels: 12_000_000) }
            }
            let image = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            result.append(image)
        }
        return result
    }

    private func readFile(_ provider: NSItemProvider, type: String) async throws -> Data {
        let operation = SharedImageReadOperation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard operation.begin(continuation) else { return }
                let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    // The provider may delete this URL immediately after the callback.
                    // Read into owned memory before returning; never retain its URL.
                    guard operation.isPending else { return }
                    do {
                        guard let url else { throw FeedbackScreenshotError.unreadable }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size > 0, size <= FeedbackScreenshot.maximumInputBytes else { throw FeedbackScreenshotError.tooLarge }
                        let data = try Data(contentsOf: url)
                        guard data.count <= FeedbackScreenshot.maximumInputBytes else { throw FeedbackScreenshotError.tooLarge }
                        operation.finish(.success(data))
                    } catch { operation.finish(.failure(error)) }
                }
                operation.attach(progress)
            }
        }, onCancel: { operation.cancel() })
    }
}

/// Exactly one completion, including cancellation before the provider registers its Progress.
final class SharedImageReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var progress: Progress?
    private var finished = false

    var isPending: Bool { lock.lock(); defer { lock.unlock() }; return !finished }

    func begin(_ continuation: CheckedContinuation<Data, Error>) -> Bool {
        lock.lock()
        if finished { lock.unlock(); continuation.resume(throwing: CancellationError()); return false }
        self.continuation = continuation
        lock.unlock(); return true
    }

    func attach(_ progress: Progress) {
        lock.lock()
        if finished { lock.unlock(); progress.cancel(); return }
        self.progress = progress
        lock.unlock()
    }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil; progress = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, progress = self.progress
        self.continuation = nil; self.progress = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
        progress?.cancel()
    }
}

enum SharedScreenshotImportError: Error {
    case noImage, tooMany
    var message: String {
        switch self {
        case .noImage: return "请从截图预览或照片中选择图片，再分享到云乐坊。"
        case .tooMany: return "一次最多分享 3 张截图，请减少图片后重试。"
        }
    }
}
