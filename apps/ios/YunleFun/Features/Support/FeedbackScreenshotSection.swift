import PhotosUI
import SwiftUI

struct FeedbackScreenshotSection: View {
    @Binding var screenshots: [FeedbackScreenshot]
    let onPreview: (FeedbackScreenshot) -> Void
    var onImportingChanged: (Bool) -> Void = { _ in }
    @State private var selection: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var error: String?
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool

    var body: some View {
        Section {
            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, screenshot in
                HStack(spacing: 12) {
                    Button { onPreview(screenshot) } label: {
                        HStack {
                            if let image = UIImage(data: screenshot.data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 72)
                                    .accessibilityHidden(true)
                            }
                            Text("截图 \(index + 1)")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("预览截图 \(index + 1)")
                    .accessibilityIdentifier("feedback.screenshot.preview.\(index)")
                    Spacer()
                    Button(role: .destructive) { screenshots.removeAll { $0.id == screenshot.id } } label: {
                        Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("移除截图 \(index + 1)")
                    .accessibilityIdentifier("feedback.screenshot.remove.\(index)")
                }
            }
            if screenshots.count < FeedbackScreenshot.maximumCount {
                PhotosPicker(selection: $selection, maxSelectionCount: FeedbackScreenshot.maximumCount - screenshots.count,
                             matching: .images, preferredItemEncoding: .current) {
                    Label("添加截图（\(screenshots.count)/\(FeedbackScreenshot.maximumCount)）", systemImage: "photo.badge.plus")
                        .frame(minHeight: 44)
                }
                .disabled(isImporting)
                .accessibilityIdentifier("feedback.screenshot.add")
            }
            if isImporting { ProgressView("正在读取图片") }
            if let error {
                Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused)
                    .accessibilityIdentifier("feedback.screenshot.error")
            }
        } header: { Text("截图（选填）") }
        footer: { Text("最多 3 张，压缩后每张不超过 1 MB，并移除照片附加信息。截图仅随在线反馈发送；提交前请检查图片中的私密内容。") }
        .task(id: selection) { await importSelection() }
        .onChange(of: error) { if $0 != nil { errorFocused = true } }
        .onChange(of: isImporting) { onImportingChanged($0) }
        .onDisappear { onImportingChanged(false) }
    }

    @MainActor private func importSelection() async {
        guard !selection.isEmpty else { return }
        isImporting = true; error = nil
        defer { isImporting = false }
        for item in selection {
            do {
                guard let screenshot = try await item.loadTransferable(type: FeedbackScreenshot.self) else {
                    throw FeedbackScreenshotError.unreadable
                }
                try Task.checkCancellation()
                if screenshots.count < FeedbackScreenshot.maximumCount,
                   !screenshots.contains(where: { $0.data == screenshot.data }) {
                    screenshots.append(screenshot)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? FeedbackScreenshotError)?.message ?? FeedbackScreenshotError.unreadable.message
            }
        }
        selection = []
    }
}
