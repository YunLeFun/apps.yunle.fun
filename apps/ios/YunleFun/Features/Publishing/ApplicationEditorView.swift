import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationEditorView: View {
    let application: ManagedApplication?
    @ObservedObject var store: PublishingStore
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: ApplicationEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmSave = false
    @State private var showRecoveryPrompt = false
    @State private var didOfferRecovery = false
    @State private var confirmClose = false
    @State private var confirmRebase = false
    @State private var pickingPhoto = false
    @State private var pickingFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var iconSlot: ApplicationIconSlot?
    @State private var fileTask: Task<Void, Never>?
    @FocusState private var focusedField: String?
    @AccessibilityFocusState private var errorFocused: Bool
    init(application: ManagedApplication?, store: PublishingStore, accounts: AccountStore, draftVault: ApplicationDraftVault = ApplicationDraftVault()) {
        self.application = application; self.store = store; self.accounts = accounts
        _model = StateObject(wrappedValue: ApplicationEditorModel(application: application, accounts: accounts, store: store, vault: draftVault))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        if let data = model.localIconPreviews[ApplicationIconSlot.Kind.appIcon.rawValue], let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else { ApplicationIcon(application: model.draft.preview, size: 64) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.draft.name.isEmpty ? "你的云应用" : model.draft.name).font(.headline)
                            Text(model.draft.audience.label).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    textField("应用名称", text: $model.draft.name, key: "name", placeholder: "给作品起个名字")
                        .accessibilityIdentifier("publisher.name")
                    if application?.currentRevisionId?.isEmpty == false {
                        LabeledContent("应用标识", value: model.draft.slug).textSelection(.enabled)
                    } else {
                        textField("应用标识", text: $model.draft.slug, key: "slug", placeholder: "my-app")
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("publisher.slug")
                    }
                    textField("简介", text: $model.draft.description, key: "description", placeholder: "介绍作品的用途", axis: .vertical)
                } footer: { Text("名称最多 50 字，简介最多 300 字。标识为所属空间内唯一的 2–50 位小写字母、数字和连字符，以字母开头；已有当前版本后不能更改。") }
                Section("网址") {
                    urlField("应用网址", text: $model.draft.websiteUrl)
                    urlField("隐私政策", text: $model.draft.privacyPolicyUrl)
                    urlField("支持链接", text: $model.draft.supportUrl)
                    urlField("备用网址（可选）", text: $model.draft.backupUrl)
                }
                Section {
                    Picker("可见范围", selection: $model.draft.audience) { ForEach(ApplicationAudience.allCases) { Text($0.label).tag($0) } }
                    Picker("访问方式", selection: $model.draft.accessMode) { ForEach(ApplicationAccessMode.allCases) { Text($0.label).tag($0) } }
                    Picker("发布阶段", selection: $model.draft.releaseStage) { ForEach(ApplicationReleaseStage.allCases) { Text($0.label).tag($0) } }
                    if model.draft.audience == .workshop { NavigationLink("创建或管理个人工坊") { MyWorkshopsView() } }
                } footer: { Text("公开作品的网址需属于 yunle.fun。工坊可见需先创建个人工坊；仅本人和工坊作品可以使用外部站点。访问方式用于说明网站的登录或邀请要求。") }
                Section("应用图标") {
                    ForEach(ApplicationIconSlot.all) { slot in iconField(slot) }
                    urlField("旧版 Logo 链接（可选）", text: $model.draft.logo)
                    textField("备用图标文字", text: $model.draft.emoji, key: "emoji")
                    Text("支持 PNG、WebP、JPEG、HEIC 和独立 SVG 图形。SVG 不应包含外链、脚本或嵌入图片。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("更多信息") {
                    textField("GitHub 仓库", text: $model.draft.githubRepo, key: "github", placeholder: "owner/repo")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    textField("分类", text: $model.draft.category, key: "category")
                    textField("标签（每行一个）", text: Binding(get: { model.draft.tags.joined(separator: "\n") }, set: { model.draft.tags = $0.components(separatedBy: "\n") }), key: "tags", axis: .vertical)
                    textField("主题色", text: $model.draft.themeColor, key: "color", placeholder: "#RRGGBB")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    textField("授信域名（每行一个）", text: Binding(get: { model.draft.trustedHosts.joined(separator: "\n") }, set: { model.draft.trustedHosts = $0.components(separatedBy: "\n") }), key: "hosts", axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if model.hasOlderDraft {
                    Section {
                        Text("草稿基于不同版本。请先核对表单，再决定是否用这些字段覆盖当前版本。").foregroundStyle(.secondary)
                        Button("采用本机草稿覆盖当前版本") { confirmRebase = true }
                    }
                }
                if let issue = model.draft.validationIssue {
                    Section { Label(issue, systemImage: "info.circle").foregroundStyle(.secondary) }
                }
                if let notice = model.notice { Section { Label(notice, systemImage: "checkmark.circle") } }
                if let error = model.error { Section { Label(error, systemImage: "exclamationmark.triangle").accessibilityFocused($errorFocused) } }
                if model.isBusy { ProgressView(model.isUploading ? "正在处理和上传图标" : "正在保存版本") }
                Section { Button("保存本机草稿") { saveLocal() }.disabled(model.isBusy) }
            }
            .disabled(model.isBusy)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(application == nil ? "创建应用" : "编辑作品").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") {
                    if model.isDirty { confirmClose = true } else { cancelAndDismiss() }
                }.disabled(store.isWriting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存版本") { focusedField = nil; confirmSave = true }
                        .disabled(!model.draft.isValid || model.hasOlderDraft || model.isBusy)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focusedField = nil } }
            }
            .interactiveDismissDisabled(model.isDirty || model.isBusy)
            .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .current)
            .task(id: photoItem) {
                guard let item = photoItem, let slot = iconSlot else { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw IconNormalizationError.unreadable }
                    try Task.checkCancellation(); await model.upload(data: data, slot: slot)
                } catch { model.showError(error) }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first, let slot = iconSlot else { return }
                fileTask?.cancel()
                fileTask = Task {
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                            if let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes > 5 * 1024 * 1024 { throw IconNormalizationError.tooLarge }
                            return try Data(contentsOf: url)
                        }.value
                        try Task.checkCancellation(); await model.upload(data: data, slot: slot)
                    } catch { model.showError(error) }
                }
            }
            .confirmationDialog("保存并发布当前版本？", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("保存版本") { Task { if await model.saveVersion() != nil { dismiss() } } }
                Button("取消", role: .cancel) {}
            } message: { Text(saveExplanation) }
            .confirmationDialog("保留你的更改？", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("保存本机草稿并关闭") { do { try model.saveLocalDraft(); cancelAndDismiss() } catch { model.showError(error) } }
                Button("放弃更改", role: .destructive) { cancelAndDismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .confirmationDialog("以本机草稿覆盖当前表单字段？", isPresented: $confirmRebase, titleVisibility: .visible) {
                Button("采用这些字段") { model.useDraftOnCurrentVersion() }
            } message: { Text("请先核对名称、网址和可见范围。稍后保存时会再检查线上版本是否变化。") }
            .alert("发现本机草稿", isPresented: $showRecoveryPrompt) {
                Button("恢复草稿") { model.restoreDraft() }
                Button("暂不恢复", role: .cancel) { model.ignoreRecoveredDraft() }
            } message: { Text("此账号曾保存过这份草稿。恢复后可以继续核对和编辑，不会立即更新线上作品。") }
            .onAppear { if !didOfferRecovery { didOfferRecovery = true; showRecoveryPrompt = model.recovered != nil } }
            .onChange(of: accounts.identityGeneration) { _ in
                if model.isDirty { try? model.saveLocalDraft() }
                cancelAndDismiss()
            }
            .onChange(of: scenePhase) { phase in if phase == .background && model.isDirty { saveLocal() } }
            .onChange(of: model.error) { if $0 != nil { errorFocused = true } }
            .onDisappear { fileTask?.cancel(); model.cancelWork() }
        }
    }
    private var saveExplanation: String {
        switch model.draft.audience {
        case .public: return "名称、简介和应用网址将作为公开作品保存。云乐坊市场不会因此自动上架，投稿需要另行确认。"
        case .workshop: return "当前版本将对你的工坊坊主和坊客可见。请确认你已创建个人工坊。"
        case .owner: return "当前版本仅当前账号可见，网站本身的访问规则继续保留。"
        }
    }
    private func urlField(_ label: String, text: Binding<String>) -> some View {
        textField(label, text: text, key: label, placeholder: "https://", axis: .vertical)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    private func textField(_ title: String, text: Binding<String>, key: String, placeholder: String = "", axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(placeholder, text: text, axis: axis).lineLimit(1...5)
                .accessibilityLabel(title).focused($focusedField, equals: key)
        }.padding(.vertical, 3)
    }
    private func iconField(_ slot: ApplicationIconSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.label).font(.headline)
                Spacer()
                if let data = model.localIconPreviews[slot.id], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                } else if !model.icon(slot).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ApplicationAssetThumbnail(source: model.icon(slot), role: slot.role == .mark ? .mark : .appIcon)
                }
                Menu {
                    Button("从照片选择") { iconSlot = slot; photoItem = nil; pickingPhoto = true }
                    Button("从文件选择") { iconSlot = slot; pickingFile = true }
                } label: { Label("上传", systemImage: "square.and.arrow.up") }.disabled(model.isBusy)
            }
            TextField("图片链接", text: Binding(get: { model.icon(slot) }, set: { model.setIcon($0, slot: slot) }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).focused($focusedField, equals: slot.id)
                .accessibilityLabel(slot.label + "图片链接")
            Text(slot.role == .mark ? "透明主体会居中到约 80% 安全区。" : "完整图标保留背景，不预先裁圆角或加阴影。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func saveLocal() { do { try model.saveLocalDraft() } catch { model.showError(error) } }
    private func cancelAndDismiss() { fileTask?.cancel(); model.cancelWork(); dismiss() }
}
