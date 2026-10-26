import SwiftUI

struct MyApplicationsView: View {
    @EnvironmentObject private var accounts: AccountStore
    var service: PublishingServing = PublishingService()
    var body: some View { MyApplicationsContent(accounts: accounts, service: service).id(accounts.identityGeneration) }
}
private struct MyApplicationsContent: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var store: PublishingStore
    @State private var showLogin = false
    @State private var showCreate = false
    @State private var query = ""
    init(accounts: AccountStore, service: PublishingServing) { self.accounts = accounts; _store = StateObject(wrappedValue: PublishingStore(accounts: accounts, service: service)) }
    var body: some View {
        List {
            if accounts.user == nil {
                ContentStateView(title: "发布你的云应用", systemImage: "square.and.pencil",
                                 message: "登录后管理作品、保存当前版本，并查看云乐坊投稿状态。")
                Button("登录云乐坊") { showLogin = true }
            } else {
                PublishingLoadStatus(store: store)
                if let notice = store.notice { Label(notice, systemImage: "checkmark.circle") }
                if store.hasLoaded {
                    if !store.canSubmit {
                        Section { Text("发布、编辑和下架需要已验证手机号且状态正常的账号。").foregroundStyle(.secondary) }
                    }
                    if store.applications.isEmpty && store.error == nil {
                        ContentStateView(title: "还没有作品", systemImage: "square.and.pencil", message: "创建作品并设置可见范围，准备好后再投稿云乐坊。")
                    }
                    ForEach(store.applications.filter { $0.application.matches(query) }) { app in
                        NavigationLink { ManagedApplicationView(id: app.id, store: store) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(application: app.application)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(app.application.name).font(.headline)
                                    Text(app.hasCurrentMetadata ? app.marketState.label : "当前版本资料待核对").font(.subheadline).foregroundStyle(.secondary)
                                    Text(app.publicationStatus?.label ?? "旧版作品").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    if store.canSubmit { Button("创建应用") { showCreate = true } }
                    if let message = store.publishingAccess?.thirdPartyMessage { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
                }
            }
        }
        .navigationTitle("我的应用").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索自己的作品")
        .task { await store.refresh() }.refreshable { await store.refresh() }
        .sheet(isPresented: $showLogin) {
            LoginView(continuationMessage: "登录后可管理作品。发布需要已验证手机号的正式账号。").environmentObject(accounts)
        }
        .sheet(isPresented: $showCreate) { ApplicationEditorView(application: nil, store: store, accounts: accounts) }
    }
}
struct PublishingLoadStatus: View {
    @ObservedObject var store: PublishingStore
    var body: some View {
        if store.isLoading { ProgressView("正在载入作品") }
        if let error = store.error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button("重试") { Task { await store.refresh() } }
        }
    }
}
private struct ManagedApplicationView: View {
    let id: String
    @ObservedObject var store: PublishingStore
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @State private var editing: ManagedApplication?
    @State private var market: MarketConfirmation?
    @State private var delisting: DelistConfirmation?
    @State private var actionError: String?
    var body: some View {
        List {
            PublishingLoadStatus(store: store)
            if let actionError { Label(actionError, systemImage: "exclamationmark.triangle") }
            if let notice = store.notice { Label(notice, systemImage: "checkmark.circle") }
            if let app = store.application(id: id), !app.hasCurrentMetadata {
                ContentStateView(title: "当前版本资料待核对", systemImage: "arrow.triangle.2.circlepath", message: "作品的当前版本和审核版本不同，暂时无法编辑或预览。请刷新后再试。")
                Button("刷新作品") { Task { await store.refresh() } }
            } else if let app = store.application(id: id) {
                Section {
                    HStack(spacing: 16) {
                        ApplicationIcon(application: app.application, size: 76)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(app.application.name).font(.title2.bold())
                            Text(app.draft.slug).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    Text(app.draft.description).textSelection(.enabled)
                    LabeledContent("可见范围", value: app.draft.audience.label)
                    LabeledContent("访问方式", value: app.draft.accessMode.label)
                    LabeledContent("发布阶段", value: app.draft.releaseStage.label)
                    LabeledContent("作品状态", value: app.publicationStatus?.label ?? "旧版作品")
                    if store.canSubmit { Button("编辑作品") { editing = app } }
                    if let restriction = app.application.ownerPreviewRestriction { Text(restriction).foregroundStyle(.secondary) }
                    else if app.application.launchURL != nil {
                        Button("预览作品") { runtime.open(app.application, catalog: catalog, library: library) }
                            .disabled(runtime.verifyingScopedApplicationID == id)
                        if runtime.verifyingScopedApplicationID == id { ProgressView("正在确认作品权限") }
                    }
                }
                Section("云乐坊投稿") {
                    Label(app.marketState.label, systemImage: "square.and.arrow.up")
                    Text(app.marketState.detail).foregroundStyle(.secondary)
                    if let action = app.marketState.action, store.canSubmit {
                        Button(action == .makePublic ? "设为公开并投稿云乐坊" : "投稿云乐坊") {
                            market = MarketConfirmation(application: app, generation: accounts.identityGeneration)
                        }.disabled(store.isWriting)
                    }
                }
                Section("版本信息") {
                    if let submission = app.latestSubmission { LabeledContent("提交版本", value: "\(submission.revision)") }
                    Text(app.draft.websiteUrl).textSelection(.enabled)
                    Text(Date(timeIntervalSince1970: app.updatedAt / 1000), format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                if store.canSubmit && app.publicationStatus != .delisted {
                    Section {
                        Button("下架作品", role: .destructive) { delisting = DelistConfirmation(base: ApplicationEditBase(app), name: app.application.name, generation: accounts.identityGeneration) }
                            .disabled(store.isWriting)
                    } footer: { Text("下架后作品从目录移除，提交和审核记录仍保留。") }
                }
            } else if let pending = store.pending(id: id) {
                ContentStateView(title: "投稿已提交", systemImage: "checkmark.circle", message: pending.madePublic ? "作品已设为公开并投稿，请刷新查看最新版本与审核状态。" : "请刷新查看最新版本与审核状态。")
                Button("刷新作品") { Task { await store.refresh() } }
            } else if !store.isLoading {
                ContentStateView(title: "作品资料暂不可用", systemImage: "square.and.pencil", message: "请返回列表刷新。下架操作不会删除提交与审核记录。")
            }
            if store.isWriting { ProgressView("正在处理") }
        }
        .navigationTitle(store.application(id: id)?.application.name ?? "管理作品").navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .onChange(of: accounts.identityGeneration) { _ in editing = nil; market = nil; delisting = nil; actionError = nil }
        .sheet(item: $editing) { app in ApplicationEditorView(application: app, store: store, accounts: accounts) }
        .sheet(item: $market) { MarketSubmissionView(selection: $0, store: store, accounts: accounts) }
        .confirmationDialog("下架“\(delisting?.name ?? "作品")”？", isPresented: Binding(get: { delisting != nil }, set: { if !$0 { delisting = nil } }), titleVisibility: .visible) {
            if let selection = delisting {
                Button("确认下架", role: .destructive) {
                    delisting = nil
                    Task { do { try await store.delist(base: selection.base, generation: selection.generation); actionError = nil }
                        catch { actionError = PublishingError.message(for: error) + " 如未确认结果，请先刷新检查。" } }
                }
            }
            Button("取消", role: .cancel) { delisting = nil }
        } message: { Text("作品会从目录移除；提交和审核记录仍保留。") }
    }
    private struct DelistConfirmation { let base: ApplicationEditBase; let name: String; let generation: UUID }
}
struct MarketConfirmation: Identifiable {
    let id = UUID()
    let application: ManagedApplication
    let generation: UUID
}
private struct MarketSubmissionView: View {
    let selection: MarketConfirmation
    @ObservedObject var store: PublishingStore
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var shortName: String
    @State private var confirm = false
    @State private var error: String?
    init(selection: MarketConfirmation, store: PublishingStore, accounts: AccountStore) {
        self.selection = selection; self.store = store; self.accounts = accounts
        _shortName = State(initialValue: selection.application.listing?.shortName ?? selection.application.draft.slug)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(selection.application.application.name).font(.headline)
                    TextField("市场短名", text: $shortName).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(selection.application.listing?.shortName != nil)
                } footer: { Text("市场短名面向全站，取得后不能更改。所属空间的应用标识与它独立。") }
                Section {
                    Text(selection.application.draft.audience == .public ? "当前版本会进入审核队列。旧版已上架时，审核期间继续展示旧版。" : "此次操作会创建公开版本并投稿。作品的名称、简介和应用网址将可公开；网站自身的登录或邀请保护继续保留。")
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle") }
                if store.isWriting { ProgressView("正在投稿") }
            }
            .navigationTitle("投稿云乐坊").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isWriting) }
                ToolbarItem(placement: .confirmationAction) { Button("投稿") { confirm = true }.disabled(!PublishingValue.slug(shortName) || store.isWriting) }
            }
            .interactiveDismissDisabled(store.isWriting)
            .confirmationDialog("确认投稿这个版本？", isPresented: $confirm, titleVisibility: .visible) {
                Button("确认投稿") {
                    Task { do { try await store.submit(base: ApplicationEditBase(selection.application), makePublic: selection.application.draft.audience != .public, shortName: shortName, generation: selection.generation); dismiss() }
                        catch { self.error = PublishingError.message(for: error) + " 如未确认结果，请返回刷新检查。" } }
                }
            }
            .onChange(of: accounts.identityGeneration) { _ in dismiss() }
        }
    }
}
