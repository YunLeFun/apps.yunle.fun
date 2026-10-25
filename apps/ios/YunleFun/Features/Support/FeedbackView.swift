import SwiftUI
import UIKit

struct FeedbackView: View {
    @ObservedObject private var logs: DiagnosticLogStore
    @ObservedObject private var accounts: AccountStore
    @StateObject private var upload: DiagnosticUploadStore
    @State private var issueDescription = ""
    @State private var preset = FeedbackRangePreset.hour
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var sheet: FeedbackSheet?
    @State private var pendingClear: FeedbackClearRequest?
    @State private var preparationError: String?
    @State private var completedUpload: DiagnosticUploadReceipt?
    @State private var showUploadSuccess = false
    @Environment(\.requestFeedbackLogin) private var requestLogin
    @Environment(\.screenshotFeedbackCoordinator) private var screenshotFeedback
    @State private var screenshotFeedbackVisibilityID = UUID()
    @FocusState private var descriptionFocused: Bool
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool

    init(logs: DiagnosticLogStore, accounts: AccountStore,
         service: DiagnosticServing = DiagnosticService(), receiptDirectory: URL? = nil,
         initialIssueDescription: String = "") {
        self.logs = logs; self.accounts = accounts
        _issueDescription = State(initialValue: initialIssueDescription)
        _upload = StateObject(wrappedValue: DiagnosticUploadStore(accounts: accounts, logs: logs,
            service: service, receiptDirectory: receiptDirectory))
    }

    var body: some View {
        Form {
            descriptionSection
            SupportContactSection(issueDescription: issueDescription, supportCode: upload.receipt?.supportCode)
            rangeSection
            logSection
            uploadSection
            if let receipt = upload.receipt { receiptSection(receipt) }
            else if let notice = upload.storageNotice {
                Section("支持编号") {
                    Text(notice).accessibilityIdentifier("feedback.receipt.storage-notice")
                }
            }
        }
        .navigationTitle("反馈与建议")
        .onAppear { screenshotFeedback?.feedbackVisibilityChanged(screenshotFeedbackVisibilityID, visible: true) }
        .onDisappear { screenshotFeedback?.feedbackVisibilityChanged(screenshotFeedbackVisibilityID, visible: false) }
        .scrollDismissesKeyboard(.interactively)
        .toolbar { keyboardToolbar }
        .sheet(item: $sheet, onDismiss: {
            upload.invalidateConfirmation()
            if completedUpload != nil { showUploadSuccess = true }
        }) { destination in
            switch destination {
            case .login: LoginView()
            case .review(let confirmation):
                DiagnosticUploadReviewSheet(confirmation: confirmation, store: upload,
                                            accountName: accounts.user?.displayName ?? "云乐坊账号",
                                            onUploaded: { completedUpload = $0 })
            }
        }
        .alert("日志已上传", isPresented: $showUploadSuccess, presenting: completedUpload) { receipt in
            Button("复制支持编号") { UIPasteboard.general.string = receipt.supportCode }
            Button("完成", role: .cancel) { }
        } message: { receipt in
            Text("支持编号：\(receipt.supportCode)。联系支持时请提供此编号，也可在页面下方查看或分享。")
        }
        .onChange(of: showUploadSuccess) { if !$0 { completedUpload = nil } }
        .onChange(of: preparationError ?? upload.error) { if $0 != nil { errorFocused = true } }
        .confirmationDialog("清除当前本地日志？", isPresented: Binding(
            get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            titleVisibility: .visible, presenting: pendingClear) { request in
                Button("清除日志", role: .destructive) {
                    guard logs.scopeGeneration == request.scope,
                          accounts.identityGeneration == request.accountGeneration else { return }
                    upload.invalidateConfirmation(); logs.clear(); pendingClear = nil
                }
                Button("取消", role: .cancel) { pendingClear = nil }
            } message: { _ in
                Text("清除当前账号或访客在此设备上的诊断日志，不影响已上传的记录或支持编号。")
            }
        .onChange(of: issueDescription) { _ in invalidateReview() }
        .onChange(of: start) { _ in invalidateReview() }
        .onChange(of: end) { _ in invalidateReview() }
        .onChange(of: preset) { value in applyPreset(value) }
        .onChange(of: logs.scopeGeneration) { _ in
            sheet = nil; pendingClear = nil; upload.invalidateConfirmation()
        }
        .onChange(of: accounts.identityGeneration) { _ in
            sheet = nil; pendingClear = nil; issueDescription = ""
            completedUpload = nil; showUploadSuccess = false
            upload.identityChanged(); preparationError = nil
        }
    }

    private var descriptionSection: some View {
        Section {
            TextEditor(text: $issueDescription)
                .frame(minHeight: 130)
                .focused($descriptionFocused)
                .accessibilityLabel("问题描述")
                .accessibilityIdentifier("feedback.description")
            Text("已输入 \(issueDescription.utf16.count) / 500")
                .font(.caption).foregroundStyle(.secondary)
            if issueDescription.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 {
                Text("上传日志的问题描述最多 500 个字符，请缩短后再试，也可以通过邮件反馈。")
                    .accessibilityIdentifier("feedback.description-limit")
            }
        } header: { Text("问题描述（选填）") }
        footer: { Text("可以写下操作步骤、预期和实际结果。请勿填写密码、验证码或其他私密内容。") }
    }

    private var rangeSection: some View {
        Section {
            Picker("日志范围", selection: $preset) {
                ForEach(FeedbackRangePreset.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("feedback.range")
            if preset == .custom {
                DatePicker("开始时间", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("feedback.range.start")
                DatePicker("结束时间", selection: $end, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("feedback.range.end")
            } else {
                Button("将范围更新到现在") { applyPreset(preset) }
            }
            Text("\(start.formatted(date: .abbreviated, time: .standard)) 至 \(end.formatted(date: .abbreviated, time: .standard))")
                .font(.footnote).foregroundStyle(.secondary)
            if let rangeError { Text(rangeError).accessibilityIdentifier("feedback.range.error") }
        } header: { Text("诊断日志") }
        footer: { Text("可选最近 7 天内、最多 24 小时的范围。这里只记录云乐坊宿主的运行事件，不采集系统或其他应用的日志。") }
    }

    private var logSection: some View {
        Section {
            if let first = logs.entries.first, let last = logs.entries.last {
                Text("本地可用：\(first.date.formatted(date: .abbreviated, time: .standard)) 至 \(last.date.formatted(date: .abbreviated, time: .standard))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = logs.storageError { Text(error).accessibilityIdentifier("feedback.storage-error") }
            LabeledContent("所选日志", value: "\(selectedLogs.count) 条")
                .accessibilityIdentifier("feedback.log-count")
            if selectedLogs.isEmpty {
                Text("所选时间内没有本地日志。你仍可以通过邮件或微信客服反馈。")
                    .accessibilityIdentifier("feedback.logs.empty")
            } else {
                LabeledContent("日志大小（约）", value: formattedBytes(selectedLogBytes))
                DisclosureGroup("预览所选日志") {
                    ForEach(Array(selectedLogs.enumerated()), id: \.offset) { _, entry in DiagnosticLogRow(entry: entry) }
                }
                .accessibilityIdentifier("feedback.logs.preview")
            }
            Button("清除本地日志", role: .destructive) {
                pendingClear = FeedbackClearRequest(scope: logs.scopeGeneration, accountGeneration: accounts.identityGeneration)
            }
            .disabled((logs.entries.isEmpty && logs.storageError == nil) || upload.isUploading)
            .accessibilityIdentifier("feedback.logs.clear")
        }
    }

    private var uploadSection: some View {
        Section {
            if accounts.user == nil {
                Text("上传诊断日志需要登录；联系反馈无需登录。")
                Button("登录后上传日志") {
                    descriptionFocused = false
                    upload.invalidateConfirmation()
                    if let requestLogin { requestLogin(issueDescription) }
                    else { sheet = .login }
                }
                .disabled(accounts.isRestoring)
                .accessibilityIdentifier("feedback.login")
            } else {
                Button("预览并上传日志") { prepareUpload() }
                    .disabled(accounts.isRestoring || upload.isUploading || selectedLogs.isEmpty || rangeError != nil
                              || issueDescription.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500)
                    .accessibilityIdentifier("feedback.upload.preview")
            }
            if upload.isUploading { ProgressView("正在上传日志") }
            if let error = preparationError ?? upload.error {
                Text(error).accessibilityFocused($errorFocused).accessibilityIdentifier("feedback.upload.error")
            }
        } footer: {
            Text("确认前可查看完整预览。上传会关联当前账号和 App 基本信息，仅支持人员可见，服务端保留 7 天。")
        }
    }

    private func receiptSection(_ receipt: DiagnosticUploadReceipt) -> some View {
        Section {
            Text("日志已上传").font(.headline)
            Text(receipt.supportCode).font(.title2.monospaced()).textSelection(.enabled)
                .accessibilityLabel("支持编号 \(receipt.supportCode)")
                .accessibilityIdentifier("feedback.receipt.code")
            Text("联系支持时请提供此编号。日志 \(receipt.logCount) 条，保留至 \(Date(timeIntervalSince1970: receipt.expiresAt / 1000).formatted(date: .abbreviated, time: .shortened))。")
                .font(.footnote)
            Button("复制支持编号") { UIPasteboard.general.string = receipt.supportCode }
                .accessibilityIdentifier("feedback.receipt.copy")
            ShareLink("分享支持编号", item: "云乐坊诊断支持编号：\(receipt.supportCode)")
                .accessibilityIdentifier("feedback.receipt.share")
            if let notice = upload.storageNotice {
                Text(notice).accessibilityIdentifier("feedback.receipt.storage-notice")
            }
        } header: { Text("最近一次上传") }
    }

    @ToolbarContentBuilder private var keyboardToolbar: some ToolbarContent {
        if descriptionFocused {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { descriptionFocused = false } label: { Label("收起键盘", systemImage: "keyboard.chevron.compact.down").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("feedback.dismiss-keyboard")
            }
        }
    }

    private var selectedLogs: [DiagnosticLogEntry] {
        guard rangeError == nil else { return [] }
        return logs.select(startTime: start.timeIntervalSince1970 * 1000, endTime: end.timeIntervalSince1970 * 1000)
    }
    private var selectedLogBytes: Int { (try? JSONEncoder().encode(selectedLogs).count) ?? 0 }
    private var rangeError: String? {
        if start > end { return "开始时间不能晚于结束时间。" }
        if end.timeIntervalSince(start) > 86_400.999 { return "单次最多选择 24 小时，请缩短范围。" }
        if start < Date().addingTimeInterval(-7 * 24 * 3600) { return "请选择最近 7 天内的日志。" }
        if end > Date().addingTimeInterval(300) { return "结束时间不能晚于当前时间。" }
        return nil
    }
    private func applyPreset(_ value: FeedbackRangePreset) {
        guard let duration = value.duration else { invalidateReview(); return }
        let now = Date(); start = now.addingTimeInterval(-duration); end = now
    }
    private func invalidateReview() { preparationError = nil; upload.invalidateConfirmation() }
    private func prepareUpload() {
        descriptionFocused = false; pendingClear = nil
        do {
            let client = DiagnosticClientContext(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                platform: "ios", route: "/feedback", timezone: TimeZone.current.identifier,
                userAgent: "YunleFun iOS \(UIDevice.current.systemVersion)")
            let confirmation = try upload.prepare(start: start, end: end, issueDescription: issueDescription, client: client)
            sheet = .review(confirmation)
        } catch { preparationError = (error as? DiagnosticError)?.message ?? "暂时无法准备日志，请检查范围后再试。" }
    }
}

private enum FeedbackRangePreset: String, CaseIterable, Identifiable {
    case quarterHour, hour, day, custom
    var id: Self { self }
    var label: String {
        switch self { case .quarterHour: return "15 分钟"; case .hour: return "1 小时"; case .day: return "24 小时"; case .custom: return "自定义" }
    }
    var duration: TimeInterval? {
        switch self { case .quarterHour: return 900; case .hour: return 3600; case .day: return 86_400; case .custom: return nil }
    }
}
private enum FeedbackSheet: Identifiable {
    case login, review(DiagnosticUploadConfirmation)
    var id: String {
        switch self { case .login: return "login"; case .review(let snapshot): return snapshot.id.uuidString }
    }
}
private struct FeedbackClearRequest { let scope: UUID; let accountGeneration: UUID }

private struct DiagnosticUploadReviewSheet: View {
    let confirmation: DiagnosticUploadConfirmation
    @ObservedObject var store: DiagnosticUploadStore
    let accountName: String
    let onUploaded: (DiagnosticUploadReceipt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var requested = false
    @AccessibilityFocusState(for: .voiceOver) private var errorFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("提交账号", value: accountName)
                    LabeledContent("日志", value: "\(confirmation.payload.logs.count) 条")
                    LabeledContent("上传大小", value: formattedBytes(confirmation.sizeBytes))
                    Text("\(Date(timeIntervalSince1970: confirmation.payload.startTime / 1000).formatted(date: .abbreviated, time: .standard)) 至 \(Date(timeIntervalSince1970: confirmation.payload.endTime / 1000).formatted(date: .abbreviated, time: .standard))")
                    Text("这些内容将关联当前账号，仅支持人员可见，服务端保留 7 天。请检查下面的脱敏预览，确认没有私密内容后再上传。")
                }
                if !confirmation.payload.issueDescription.isEmpty {
                    Section("问题描述") { Text(confirmation.payload.issueDescription).textSelection(.enabled) }
                }
                Section("App 基本信息") {
                    Text("云乐坊 \(confirmation.payload.client.appVersion)（\(confirmation.payload.client.buildNumber)）")
                    Text(confirmation.payload.client.userAgent)
                    Text(confirmation.payload.client.timezone)
                }
                Section {
                    DisclosureGroup("查看将上传的全部日志") {
                        ForEach(Array(confirmation.payload.logs.enumerated()), id: \.offset) { _, entry in DiagnosticLogRow(entry: entry) }
                    }
                }
                Section {
                    if store.isUploading { ProgressView("正在上传日志") }
                    if let error = store.error {
                        Text(error).accessibilityFocused($errorFocused).accessibilityIdentifier("feedback.confirmation.error")
                    }
                    Button("同意并上传") { requested = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(requested || !store.isValid(confirmation))
                        .accessibilityIdentifier("feedback.confirmation.upload")
                    if requested && !store.isUploading {
                        Button("返回修改") { dismiss() }
                    }
                }
            }
            .navigationTitle("上传诊断日志？")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if store.isUploading { store.cancelUpload() }; dismiss() }
                        .accessibilityIdentifier("feedback.confirmation.cancel")
                }
            }
        }
        .interactiveDismissDisabled(store.isUploading)
        .task(id: requested) {
            guard requested else { return }
            if await store.upload(confirmation), let receipt = store.receipt {
                onUploaded(receipt); dismiss()
            }
        }
        .onChange(of: store.error) { if $0 != nil { errorFocused = true } }
        .onDisappear {
            if store.isUploading { store.cancelUpload() }
            store.invalidateConfirmation()
        }
    }
}

private struct DiagnosticLogRow: View {
    let entry: DiagnosticLogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date.formatted(date: .abbreviated, time: .standard)).font(.caption)
            Text(levelTitle).font(.caption.weight(.semibold))
            Text(entry.message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
    private var levelTitle: String {
        switch entry.level { case .log: return "记录"; case .info: return "信息"; case .warn: return "提醒"; case .error: return "错误"; case .debug: return "调试" }
    }
}
private extension DiagnosticLogEntry { var date: Date { Date(timeIntervalSince1970: timestamp / 1000) } }
private func formattedBytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
