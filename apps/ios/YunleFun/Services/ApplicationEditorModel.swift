import Combine
import Foundation

struct ApplicationIconSlot: Identifiable, Equatable {
    enum Kind: String { case appIcon, appIconDark, mark, markDark }
    let kind: Kind
    var id: String { kind.rawValue }
    var role: ApplicationIconRole { kind == .appIcon || kind == .appIconDark ? .appIcon : .mark }
    var dark: Bool { kind == .appIconDark || kind == .markDark }
    var label: String {
        switch kind { case .appIcon: return "完整图标"; case .appIconDark: return "完整图标 · 深色"; case .mark: return "主体图标"; case .markDark: return "主体图标 · 深色" }
    }
    static let all = [Kind.appIcon, .appIconDark, .mark, .markDark].map { ApplicationIconSlot(kind: $0) }
}
@MainActor
final class ApplicationEditorModel: ObservableObject {
    @Published var draft: ApplicationDraft
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var isUploading = false
    @Published private(set) var recovered: SavedApplicationDraft?
    @Published private(set) var hasOlderDraft = false
    @Published private(set) var localIconPreviews: [String: Data] = [:]
    private(set) var base: ApplicationEditBase?
    let generation: UUID
    let owner: String
    private let accounts: IdentityScopedAccountAuthorizing
    private let store: PublishingStore
    private let vault: ApplicationDraftVault
    private let initialBase: ApplicationEditBase?
    private var draftBaseRevision: String?
    private var draftBaseUpdatedAt: Double?
    private var draftBaseWriteVersion: String?
    private var initial: ApplicationDraft
    private var uploadID = UUID()
    private let appID: String?
    init(application: ManagedApplication?, accounts: IdentityScopedAccountAuthorizing, store: PublishingStore, vault: ApplicationDraftVault = ApplicationDraftVault()) {
        self.accounts = accounts; self.store = store; self.vault = vault
        generation = accounts.identityGeneration; owner = accounts.user?.id ?? ""; appID = application?.id
        initial = application?.draft ?? ApplicationDraft(); draft = initial
        base = application.map(ApplicationEditBase.init); initialBase = base
        draftBaseRevision = base?.revision; draftBaseUpdatedAt = base?.updatedAt; draftBaseWriteVersion = base?.writeVersion
        do { recovered = try vault.load(owner: owner, appID: appID) }
        catch { self.error = PublishingError.storage.message }
    }
    var isDirty: Bool { draft != initial }
    var isBusy: Bool { isUploading || store.isWriting }
    func restoreDraft() {
        guard let recovered else { return }
        draft = recovered.draft
        draftBaseRevision = recovered.baseRevision; draftBaseUpdatedAt = recovered.baseUpdatedAt; draftBaseWriteVersion = recovered.baseWriteVersion
        hasOlderDraft = appID != nil && (recovered.baseRevision != initialBase?.revision || recovered.baseUpdatedAt != initialBase?.updatedAt || recovered.baseWriteVersion != initialBase?.writeVersion)
        self.recovered = nil
        notice = hasOlderDraft ? "草稿基于旧版。请核对字段，再确认是否以它覆盖当前版本。" : "已恢复此账号的本机草稿。"
    }
    func useDraftOnCurrentVersion() {
        hasOlderDraft = false; base = initialBase; draftBaseRevision = base?.revision; draftBaseUpdatedAt = base?.updatedAt; draftBaseWriteVersion = base?.writeVersion
    }
    func ignoreRecoveredDraft() { recovered = nil }
    func saveLocalDraft() throws {
        guard !owner.isEmpty else { throw PublishingError.identityChanged }
        try vault.save(SavedApplicationDraft(draft: draft, baseRevision: draftBaseRevision, baseUpdatedAt: draftBaseUpdatedAt, baseWriteVersion: draftBaseWriteVersion), owner: owner, appID: appID)
        notice = "本机草稿已保存"
    }
    func saveVersion() async -> ManagedApplication? {
        do {
            try checkIdentity()
            guard !hasOlderDraft, draft.isValid else { throw PublishingError.invalidInput }
            let result = try await store.save(draft, base: base, generation: generation)
            try checkIdentity()
            initial = draft; error = nil
            do { try vault.remove(owner: owner, appID: appID) }
            catch { notice = "版本已保存，本机旧草稿暂时无法清理。" }
            return result
        } catch { self.error = PublishingError.message(for: error); return nil }
    }
    func upload(data: Data, slot: ApplicationIconSlot) async {
        let id = UUID(); uploadID = id; isUploading = true; error = nil
        defer { if uploadID == id { isUploading = false } }
        do {
            try checkIdentity()
            let png = try await ApplicationIconNormalizer().normalize(data, role: slot.role)
            try checkIdentity(); guard uploadID == id else { return }
            let fileID = try await store.upload(png: png, role: slot.role, generation: generation)
            try checkIdentity(); guard uploadID == id else { return }
            setIcon(fileID, slot: slot); localIconPreviews[slot.id] = png
            notice = "\(slot.label)已上传，保存版本后应用到作品。"
        } catch is CancellationError { }
        catch {
            guard uploadID == id, accounts.identityGeneration == generation else { return }
            self.error = (error as? IconNormalizationError)?.message ?? PublishingError.message(for: error)
        }
    }
    func icon(_ slot: ApplicationIconSlot) -> String {
        let value = slot.role == .appIcon ? draft.iconAssets?.appIcon : draft.iconAssets?.mark
        return (slot.dark ? value?.darkSrc : value?.src) ?? ""
    }
    func setIcon(_ source: String, slot: ApplicationIconSlot) {
        var icons = draft.iconAssets ?? CloudApplication.IconAssets()
        var variants = (slot.role == .appIcon ? icons.appIcon : icons.mark) ?? CloudApplication.IconAssets.Variants()
        if slot.dark { variants.darkSrc = source } else { variants.src = source }
        if slot.role == .appIcon { icons.appIcon = variants } else { icons.mark = variants }
        draft.iconAssets = icons
    }
    func showError(_ error: Error) {
        guard accounts.identityGeneration == generation, !(error is CancellationError) else { return }
        self.error = (error as? IconNormalizationError)?.message ?? PublishingError.message(for: error)
    }
    func cancelWork() { uploadID = UUID(); isUploading = false }
    private func checkIdentity() throws {
        guard accounts.user?.id == owner, accounts.identityGeneration == generation, !Task.isCancelled else { throw PublishingError.identityChanged }
    }
}
