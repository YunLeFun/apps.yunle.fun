import SwiftUI

struct ApplicationReviewsView: View {
    let application: CloudApplication
    @EnvironmentObject private var accounts: AccountStore
    var body: some View { ReviewsContent(application: application, accounts: accounts) }
}

private struct ReviewsContent: View {
    let application: CloudApplication
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: ReviewsStore
    @State private var presentation: Presentation?
    @State private var confirmDelete = false
    @State private var deleteID: String?
    @State private var deleteGeneration: UUID?
    @State private var actionError: String?
    private enum Presentation: Identifiable {
        case login, write, report(ReportTarget)
        var id: String {
            switch self { case .login: return "login"; case .write: return "write"; case .report(let target): return "report-\(target.type)-\(target.id)" }
        }
    }
    init(application: CloudApplication, accounts: AccountStore) {
        self.application = application; self.accounts = accounts
        _model = StateObject(wrappedValue: ReviewsStore(appKey: application.publicKey, accounts: accounts))
    }
    var body: some View {
        List {
            if let summary = model.summary {
                Section {
                    LabeledContent("平均评分", value: summary.count == 0 ? "暂无评分" : String(format: "%.1f / 5", summary.average))
                    LabeledContent("已发布评价", value: "\(summary.count)")
                    if summary.count > 0 {
                        ForEach((1...5).reversed(), id: \.self) { rating in
                            LabeledContent("\(rating) 星", value: "\(summary.distribution[String(rating)] ?? 0)")
                        }
                    }
                }
            } else if model.error == nil {
                ProgressView("正在载入评价")
            }
            if let error = model.error {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark")
                    Button("重试") { Task { await model.refresh() } }
                }
            }
            if let notice = model.notice { Section { Text(notice).foregroundStyle(.secondary) } }
            if let own = model.myReview {
                Section("我的评价 · \(own.status?.label ?? "")") {
                    ReviewRow(review: own)
                    if let reason = own.rejectedReason, !reason.isEmpty, own.status == .rejected {
                        Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    }
                    Button("修改评价") { presentation = .write }
                    Button("删除评价", role: .destructive) {
                        deleteID = own.id; deleteGeneration = accounts.identityGeneration; confirmDelete = true
                    }
                }
            } else {
                Section {
                    Button(accounts.user == nil ? "登录后写评价" : "写评价") {
                        presentation = accounts.user == nil ? .login : .write
                    }
                }
            }
            if model.summary != nil {
                Section {
                    if model.reviews.isEmpty {
                        ContentStateView(title: "暂无可展示的评价", systemImage: "text.bubble",
                                         message: "分享你的使用感受，帮助更多人发现好应用。")
                    } else {
                        ForEach(model.reviews) { review in
                            VStack(alignment: .leading, spacing: 10) {
                                ReviewRow(review: review)
                                Button("举报这条评价", systemImage: "flag") {
                                    presentReport(ReportTarget(type: .review, id: review.id,
                                                              appKey: application.publicKey, label: "\(review.authorName)的评价"))
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: { Text("用户评价") } footer: { Text("展示最近 50 条已发布评价，评分统计包含全部已发布评价。") }
            }
            Section {
                Button("举报应用", systemImage: "flag") {
                    presentReport(ReportTarget(type: .app, id: application.publicKey,
                                              appKey: application.publicKey, label: application.name))
                }
                NavigationLink("我的举报") { MyReportsView() }
            }
        }
        .disabled(model.isSubmitting)
        .navigationTitle("评分与评价")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task(id: accounts.identityGeneration) { await model.refresh() }
        .onChange(of: accounts.identityGeneration) { _ in
            model.identityChanged(); presentation = nil; confirmDelete = false; actionError = nil
        }
        .sheet(item: $presentation, onDismiss: { Task { await model.refresh() } }) { item in
            switch item {
            case .login:
                LoginView(continuationMessage: "登录后返回\(application.name)的评价页面。提交评价或举报仍需你确认。")
                    .environmentObject(accounts)
            case .write:
                ReviewEditor(model: model, application: application, accounts: accounts)
            case .report(let target):
                ReportEditor(model: model, target: target, accounts: accounts)
            }
        }
        .confirmationDialog("删除自己的评价？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除评价", role: .destructive) {
                guard let id = deleteID, let generation = deleteGeneration else { return }
                Task { do { try await model.deleteMine(expectedID: id, generation: generation) }
                    catch { actionError = communityWriteMessage(error) } }
            }
        } message: { Text("删除后将重新计算应用评分。") }
        .alert("暂时未能完成", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("好") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }
    private func presentReport(_ target: ReportTarget) {
        presentation = accounts.user == nil ? .login : .report(target)
    }
}

private struct ReviewRow: View {
    let review: AppReview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.authorName).font(.headline)
                Spacer()
                Text(review.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
            }
            Label("\(review.rating) 星", systemImage: "star.fill").font(.subheadline).foregroundStyle(.secondary)
            if let title = review.title, !title.isEmpty { Text(title).font(.headline) }
            Text(review.content).textSelection(.enabled)
        }
    }
}

private struct ReviewEditor: View {
    @ObservedObject var model: ReviewsStore
    let application: CloudApplication
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReviewDraft
    @State private var initial: ReviewDraft
    @State private var generation: UUID
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var operation: Task<Void, Never>?
    @AccessibilityFocusState private var errorFocused: Bool
    @FocusState private var focus: Field?
    private enum Field { case title, content }
    init(model: ReviewsStore, application: CloudApplication, accounts: AccountStore) {
        self.model = model; self.application = application; self.accounts = accounts
        let draft = ReviewDraft(review: model.myReview)
        _draft = State(initialValue: draft); _initial = State(initialValue: draft)
        _generation = State(initialValue: accounts.identityGeneration)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("评分", selection: $draft.rating) {
                        ForEach(1...5, id: \.self) { Text("\($0) 星").tag($0) }
                    }
                    TextField("标题（选填）", text: $draft.title)
                        .focused($focus, equals: .title)
                        .accessibilityIdentifier("review.title")
                    TextEditor(text: $draft.content).frame(minHeight: 160)
                        .focused($focus, equals: .content)
                        .accessibilityLabel("评价内容").accessibilityIdentifier("review.content")
                } header: { Text(application.name) }
                footer: { Text("标题 \(draft.title.utf16.count)/100，内容 \(draft.content.utf16.count)/1000 字符。评价提交后可能需要审核。") }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                            .accessibilityFocused($errorFocused)
                    }
                }
                Section {
                    Button { submit() } label: {
                        HStack { Text("提交评价"); Spacer(); if model.isSubmitting { ProgressView() } }
                    }
                    .disabled(!draft.isValid || model.isSubmitting)
                    .accessibilityIdentifier("review.submit")
                }
            }
            .disabled(model.isSubmitting)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(initial.content.isEmpty ? "写评价" : "修改评价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { if draft != initial { confirmDiscard = true } else { dismiss() } }
                    .disabled(model.isSubmitting)
            } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focus = nil } } }
            .interactiveDismissDisabled(model.isSubmitting || draft != initial)
            .confirmationDialog("放弃本次编辑？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃编辑", role: .destructive) { dismiss() }
            }
            .onChange(of: accounts.identityGeneration) { _ in operation?.cancel(); draft = ReviewDraft(); dismiss() }
            .onDisappear { operation?.cancel() }
        }
    }
    private func submit() {
        guard generation == accounts.identityGeneration, !model.isSubmitting else { return }
        error = nil
        focus = nil
        operation = Task { @MainActor in
            do {
                let status = try await model.submit(draft, generation: generation)
                guard generation == accounts.identityGeneration, !Task.isCancelled else { return }
                if status == .rejected { initial = draft; error = status.message; errorFocused = true }
                else { dismiss() }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = communityWriteMessage(error); errorFocused = true
            }
        }
    }
}

private struct ReportEditor: View {
    @ObservedObject var model: ReviewsStore
    let target: ReportTarget
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var generation: UUID
    @State private var reason = ReportReason.illegal
    @State private var detail = ""
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var operation: Task<Void, Never>?
    @FocusState private var editing: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    init(model: ReviewsStore, target: ReportTarget, accounts: AccountStore) {
        self.model = model; self.target = target; self.accounts = accounts
        _generation = State(initialValue: accounts.identityGeneration)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("举报对象") { Text(target.label) }
                Section {
                    Picker("原因", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.label).tag($0) }
                    }
                    TextEditor(text: $detail).frame(minHeight: 140).focused($editing).accessibilityLabel("补充说明（选填）")
                } footer: { Text("补充说明 \(detail.utf16.count)/500 字符。举报提交后可在“我的举报”查看处理状态。") }
                if let error { Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityFocused($errorFocused)
                } }
                Section {
                    Button { submit() } label: {
                        HStack { Text("提交举报"); Spacer(); if model.isSubmitting { ProgressView() } }
                    }
                    .disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 || model.isSubmitting)
                }
            }
            .disabled(model.isSubmitting)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("举报").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { if !detail.isEmpty || reason != .illegal { confirmDiscard = true } else { dismiss() } }
                    .disabled(model.isSubmitting)
            } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } } }
            .interactiveDismissDisabled(model.isSubmitting || !detail.isEmpty || reason != .illegal)
            .confirmationDialog("放弃本次举报？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃举报", role: .destructive) { dismiss() }
            }
            .onChange(of: accounts.identityGeneration) { _ in operation?.cancel(); detail = ""; dismiss() }
            .onDisappear { operation?.cancel() }
        }
    }
    private func submit() {
        guard generation == accounts.identityGeneration, !model.isSubmitting else { return }
        error = nil
        editing = false
        operation = Task { @MainActor in
            do { try await model.report(target: target, reason: reason, detail: detail, generation: generation)
                if !Task.isCancelled { dismiss() } }
            catch { if !Task.isCancelled { self.error = communityWriteMessage(error); errorFocused = true } }
        }
    }
}

private func communityWriteMessage(_ error: Error) -> String {
    if let error = error as? CommunityError, error != .unavailable, error != .invalidResponse { return error.message }
    return "提交结果暂未确认。内容仍保留，请刷新检查后再决定是否重试。"
}
