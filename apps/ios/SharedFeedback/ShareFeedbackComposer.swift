import Combine
import Foundation

@MainActor
final class ShareFeedbackComposer: ObservableObject {
    enum Phase { case idle, loading, editing, submitting, received }
    @Published private(set) var phase = Phase.idle
    @Published var description = ""
    @Published var product = "www"
    @Published var category = "problem"
    @Published private(set) var screenshots: [FeedbackScreenshot] = []
    @Published private(set) var error: String?
    @Published private(set) var record: SharedFeedbackRecord?
    @Published private(set) var recordWasSaved = false
    @Published private(set) var usesGeneralFeedback: Bool
    let channel: FeedbackChannel
    private let context: SharedFeedbackContext
    private let history: SharedFeedbackHistory
    private let importer: SharedScreenshotImporting
    private let service: SupportFeedbackSubmitting
    private let version: String
    private var access: SupportFeedbackAccess?
    private var lastSubmission: SupportFeedbackSubmission?
    private var submissionKey = UUID().uuidString
    private var operation = UUID()
    private var uploadTask: Task<SupportFeedbackReceipt, Error>?
    private var requestWasDispatched = false

    init(context: SharedFeedbackContext, history: SharedFeedbackHistory,
         service: SupportFeedbackSubmitting = SupportFeedbackClient(), importer: SharedScreenshotImporting = SharedScreenshotImporter(),
         version: String) {
        self.context = context; self.history = history; self.service = service; self.importer = importer
        self.version = version; channel = context.channel
        usesGeneralFeedback = context.channel != .testFlight
    }

    var canSubmit: Bool {
        phase == .editing && (5...4000).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)
    }

    func chooseGeneralFeedback() { usesGeneralFeedback = true }

    func load(_ providers: [NSItemProvider]) async {
        guard usesGeneralFeedback, phase == .idle else { return }
        let current = UUID(); operation = current; phase = .loading; error = nil
        do {
            try check(current)
            let images = try await importer.load(providers)
            try check(current)
            screenshots = images; phase = .editing
        } catch {
            guard operation == current, !Task.isCancelled else { return }
            phase = .idle
            self.error = (error as? SharedScreenshotImportError)?.message
                ?? (error as? FeedbackScreenshotError)?.message
                ?? (error as? SharedFeedbackHistoryError)?.message
                ?? "无法读取分享的图片，请重新选择或稍后重试。"
        }
    }

    func remove(_ id: UUID) {
        guard phase == .editing else { return }
        screenshots.removeAll { $0.id == id }
    }

    func reviewedSubmission() -> SupportFeedbackSubmission? {
        guard canSubmit else { return nil }
        return SupportFeedbackSubmission(product: product, category: category, description: description, screenshots: screenshots,
            context: .init(source: "apps-ios-share", version: version))
    }

    /// Called only after the system confirmation, with the exact frozen payload.
    func submit(_ submission: SupportFeedbackSubmission) async {
        guard phase == .editing else { return }
        let current = UUID(); operation = current
        do { try submission.validate(); try check(current) }
        catch { self.error = message(error); return }
        if lastSubmission != submission { lastSubmission = submission; submissionKey = UUID().uuidString }
        phase = .submitting; error = nil; requestWasDispatched = false
        let key = submissionKey
        let task = Task<SupportFeedbackReceipt, Error> {
            if self.access == nil {
                let access = try await service.connectGuest()
                try check(current); self.access = access
            }
            try check(current)
            guard let access else { throw SupportFeedbackError.invalidResponse }
            requestWasDispatched = true
            let receipt = try await service.submit(submission, key: key, access: access)
            try check(current)
            guard SupportFeedbackClient.ticketURL(receipt, requiringGuestAccess: true) != nil else { throw SupportFeedbackError.invalidResponse }
            return receipt
        }
        uploadTask = task
        defer { if operation == current { uploadTask = nil } }
        do {
            let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try check(current)
            let record = SharedFeedbackRecord(receipt: receipt, createdAt: Date())
            do { try history.save(record, expected: context); recordWasSaved = true }
            catch SharedFeedbackHistoryError.scopeChanged { throw SharedFeedbackHistoryError.scopeChanged }
            catch { recordWasSaved = false }
            self.record = record; screenshots = []; description = ""; lastSubmission = nil; access = nil; phase = .received
        } catch {
            guard operation == current, !Task.isCancelled else { return }
            phase = .editing; self.error = message(error)
        }
    }

    func cancelWork() {
        operation = UUID(); uploadTask?.cancel(); uploadTask = nil
        if phase == .loading { phase = .idle }
        if phase == .submitting {
            phase = .editing
            error = requestWasDispatched ? "提交结果尚未确认，内容已保留；重试会使用同一提交编号。" : nil
        }
    }

    func discardDraft() {
        cancelWork()
        screenshots = []; description = ""; lastSubmission = nil; access = nil
    }

    private func check(_ current: UUID) throws {
        try Task.checkCancellation()
        guard current == operation, try history.isCurrent(context) else { throw SharedFeedbackHistoryError.scopeChanged }
    }

    private func message(_ error: Error) -> String {
        (error as? SupportFeedbackError)?.message ?? (error as? SharedFeedbackHistoryError)?.message
            ?? "提交结果尚未确认。内容已保留，重试会使用同一提交编号，避免重复反馈。"
    }
}
