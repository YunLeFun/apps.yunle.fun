import ImageIO
import SwiftUI
import UIKit

struct ShareFeedbackView: View {
    @ObservedObject var model: ShareFeedbackComposer
    let providers: [NSItemProvider]
    let onCancel: () -> Void
    let onFinish: () -> Void
    @State private var pending: ReviewedFeedback?
    @State private var retry = UUID()
    @State private var copied = false
    @FocusState private var descriptionFocused: Bool
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool

    private struct ReviewedFeedback: Identifiable { let id = UUID(); let submission: SupportFeedbackSubmission }

    var body: some View {
        NavigationStack {
            Form {
                if !model.usesGeneralFeedback { testFlightGuidance }
                else if let record = model.record { receipt(record) }
                else { editor }
            }
            .navigationTitle("反馈给云乐坊").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.record != nil {
                        Button("完成", action: onFinish).accessibilityIdentifier("share.feedback.done")
                    } else {
                        Button("取消", action: onCancel).disabled(model.phase == .submitting)
                            .accessibilityIdentifier("share.feedback.cancel")
                    }
                }
                if descriptionFocused {
                    ToolbarItem(placement: .keyboard) { Button("完成输入") { descriptionFocused = false } }
                }
            }
            .task(id: "\(model.usesGeneralFeedback)|\(retry)") { if model.usesGeneralFeedback { await model.load(providers) } }
            .confirmationDialog("提交这条私密反馈？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { reviewed in
                Button("确认提交") { Task { await model.submit(reviewed.submission) } }
                Button("取消", role: .cancel) { }
            } message: { reviewed in
                Text("将以访客身份向\(SupportProduct.title(reviewed.submission.productId))提交问题描述和 \(reviewed.submission.images.count) 张截图，不附带诊断日志。")
            }
            .onChange(of: model.error) { if $0 != nil { errorFocused = true } }
            .onDisappear { model.cancelWork() }
        }
        .interactiveDismissDisabled(model.phase == .submitting)
    }

    private var testFlightGuidance: some View {
        Group {
            Section {
                Label("优先使用 TestFlight 反馈", systemImage: "airplane")
                Text("这是 TestFlight 测试版。请在系统截屏预览中选择“共享 Beta 版反馈”，也可以在 TestFlight 中选择云乐坊，再点“发送 Beta 版反馈”。")
                Button("关闭此页，使用 TestFlight 反馈", action: onFinish)
                    .accessibilityIdentifier("share.feedback.testflight-done")
            } header: { Text("TestFlight 测试反馈（推荐）") }
            Section {
                Button("仍使用云乐坊通用反馈") { model.chooseGeneralFeedback() }
                    .accessibilityIdentifier("share.feedback.use-general")
            } footer: { Text("通用反馈会进入云乐坊支持中心，可以继续查看工单处理进度。") }
        }
    }

    private var editor: some View {
        Group {
            Section {
                if model.phase == .loading { ProgressView("正在读取分享的图片") }
                ForEach(Array(model.screenshots.enumerated()), id: \.element.id) { index, image in
                    HStack {
                        NavigationLink { ScreenshotPreview(data: image.data, imageLabel: "待提交的截图预览") } label: {
                            HStack {
                                ShareScreenshotThumbnail(screenshot: image).frame(width: 56, height: 64)
                                Text("预览截图 \(index + 1)")
                            }
                        }.buttonStyle(.borderless).accessibilityIdentifier("share.feedback.preview.\(index)")
                        Spacer()
                        Button(role: .destructive) { model.remove(image.id) } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("移除截图 \(index + 1)")
                    }
                }
            } header: { Text("分享的截图") }
            footer: { Text("最多 3 张，压缩后每张不超过 1 MB。请核对图片中的私密内容；照片附加信息会在上传前移除。") }
            Section {
                Picker("相关产品", selection: $model.product) {
                    ForEach(SupportProduct.submissionIDs, id: \.self) { Text(SupportProduct.title($0)).tag($0) }
                }
                Picker("反馈类型", selection: $model.category) {
                    Text("遇到问题").tag("problem"); Text("功能建议").tag("suggestion"); Text("其他").tag("other")
                }
                TextEditor(text: $model.description).frame(minHeight: 120).focused($descriptionFocused)
                    .accessibilityLabel("问题描述").accessibilityIdentifier("share.feedback.description")
                Text("\(model.description.utf16.count) / 4000").font(.caption).foregroundStyle(.secondary)
                Button {
                    descriptionFocused = false
                    if let submission = model.reviewedSubmission() { pending = ReviewedFeedback(submission: submission) }
                } label: { Label(model.phase == .submitting ? "正在提交反馈" : "提交反馈", systemImage: "paperplane") }
                    .disabled(!model.canSubmit).accessibilityIdentifier("share.feedback.submit")
                if model.phase == .submitting { ProgressView("正在提交，请稍候") }
            } header: { Text("问题描述") }
            footer: { Text("以访客身份提交，无需登录。提交成功后，可回到云乐坊“我 → 反馈与建议”查看工单。") }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused).accessibilityIdentifier("share.feedback.error")
                    if model.phase == .idle { Button("重新读取图片") { retry = UUID() } }
                }
            }
        }
        .disabled(model.phase == .submitting)
    }

    private func receipt(_ record: SharedFeedbackRecord) -> some View {
        Section {
            Label("反馈已收到", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text(record.id).font(.footnote.monospaced()).textSelection(.enabled)
                .accessibilityIdentifier("share.feedback.receipt")
            Text(model.recordWasSaved ? "工单已保存在云乐坊。回到 App 的“我 → 反馈与建议”即可查看处理进度。"
                 : "反馈已提交，但工单链接暂时无法保存到 App。请先复制链接，妥善保存到自己的备忘录。")
            Button(copied ? "工单链接已复制" : "复制工单访问链接") {
                if let url = record.ticketURL { UIPasteboard.general.string = url.absoluteString; copied = true }
            }.accessibilityIdentifier("share.feedback.copy-ticket")
            Button("完成", action: onFinish).accessibilityIdentifier("share.feedback.done")
        } footer: { Text("工单链接包含访客访问凭证，请勿转发给他人。") }
    }
}

private struct ShareScreenshotThumbnail: View {
    let screenshot: FeedbackScreenshot
    var body: some View {
        if let source = CGImageSourceCreateWithData(screenshot.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) {
            Image(decorative: image, scale: 1).resizable().scaledToFit().accessibilityHidden(true)
        }
    }
}

struct ShareFeedbackUnavailableView: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            Form { Section { Text(message); Button("关闭", action: onClose) } }
                .navigationTitle("反馈给云乐坊").navigationBarTitleDisplayMode(.inline)
        }
    }
}
