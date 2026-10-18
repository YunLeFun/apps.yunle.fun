import SwiftUI

struct PublicWorkshopView: View {
    let id: String
    @EnvironmentObject private var accounts: AccountStore
    var body: some View { PublicWorkshopContent(id: id, accounts: accounts).id(accounts.identityGeneration) }
}
private struct PublicWorkshopContent: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: WorkshopPageStore
    @State private var showLogin = false
    @State private var showShare = false
    @State private var leavingGeneration: UUID?
    @State private var actionError: String?
    init(id: String, accounts: AccountStore) {
        self.accounts = accounts; _model = StateObject(wrappedValue: WorkshopPageStore(id: id, accounts: accounts))
    }
    var body: some View {
        List {
            WorkshopLoadStatus(isLoading: model.isLoading, error: model.error) { await model.refresh() }
            if let page = model.page {
                Section {
                    WorkshopRow(workshop: page.workshop)
                    if let description = page.workshop.description, !description.isEmpty { Text(description).textSelection(.enabled) }
                    LabeledContent("工坊编号", value: page.workshop.id).textSelection(.enabled)
                    Button("分享工坊") { showShare = true }
                }
                Section {
                    if page.workshop.status == .disabled { Label("工坊已暂停，暂时无法访问应用。", systemImage: "pause.circle") }
                    membership(page)
                }
                if let actionError { Label(actionError, systemImage: "exclamationmark.triangle") }
                if let notice = model.notice { Label(notice, systemImage: "checkmark.circle") }
                if model.isWriting { ProgressView("正在处理") }
                if page.permitsApps {
                    Section("工坊应用 · \(page.apps.count)") {
                        if page.apps.isEmpty { Text("还没有可用的工坊应用").foregroundStyle(.secondary) }
                        ForEach(page.apps) { app in
                            NavigationLink { ApplicationDetailView(application: app) } label: { ApplicationRow(application: app) }
                        }
                    }
                }
            }
        }
        .navigationTitle(model.page?.workshop.name ?? "个人工坊").navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showLogin) {
            LoginView(continuationMessage: "登录后可申请加入这个工坊。登录不会自动提交申请。").environmentObject(accounts)
        }
        .sheet(isPresented: $showShare) { if let workshop = model.page?.workshop { WorkshopShareView(workshop: workshop) } }
        .confirmationDialog("离开这个工坊？", isPresented: Binding(get: { leavingGeneration != nil }, set: { if !$0 { leavingGeneration = nil } }), titleVisibility: .visible) {
            if let generation = leavingGeneration {
                Button("离开工坊", role: .destructive) { leavingGeneration = nil; perform { try await model.leave(generation: generation) } }
            }
            Button("取消", role: .cancel) { leavingGeneration = nil }
        } message: { Text("离开后将无法继续访问仅限坊客的应用。再次加入需遵循工坊的加入方式。") }
    }
    @ViewBuilder private func membership(_ page: WorkshopPage) -> some View {
        switch page.access {
        case .owner:
            Label("你是这个工坊的坊主", systemImage: "person.crop.circle.badge.checkmark")
            NavigationLink("管理个人工坊") { MyWorkshopsView() }
        case .active:
            Label("已加入工坊", systemImage: "checkmark.circle")
            Button("离开工坊", role: .destructive) { leavingGeneration = accounts.identityGeneration }.disabled(model.isWriting)
        case .pending: Label("申请已提交，等待坊主审批", systemImage: "clock")
        case .blocked: Label("当前账号已被禁止加入这个工坊", systemImage: "hand.raised")
        case .anonymous, .none:
            if page.workshop.status == .active {
                if page.workshop.joinPolicy == .closed { Label("工坊已停止接受新坊客", systemImage: "lock") }
                else if accounts.user == nil { Button("登录后加入") { showLogin = true } }
                else {
                    Button(page.workshop.joinPolicy == .open ? "加入工坊" : "申请加入") {
                        let generation = accounts.identityGeneration
                        perform { try await model.join(generation: generation) }
                    }.disabled(model.isWriting)
                    Text(page.workshop.joinPolicy == .open ? "加入后可查看工坊应用。" : "坊主通过申请后，可查看工坊应用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); actionError = nil }
            catch { actionError = WorkshopError.message(for: error) + " 如未确认结果，请刷新检查。" }
        }
    }
}

struct WorkshopLookupView: View {
    @State private var input = ""
    @State private var destination: String?
    @State private var showWorkshop = false
    @State private var invalid = false
    @State private var showScanner = false
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        Form {
            Section {
                TextField("工坊编号或链接", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).submitLabel(.go)
                    .accessibilityIdentifier("workshop.lookup.input").onSubmit(open)
                Button("打开工坊", action: open).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("workshop.lookup.open")
            } footer: { Text("输入 6 位工坊编号，或 apps.yunle.fun 的工坊分享链接。") }
            if invalid { Label("无法识别这个工坊编号或链接，请检查后重试。", systemImage: "exclamationmark.triangle").accessibilityFocused($errorFocused) }
        }
        .navigationTitle("打开个人工坊").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showScanner = true } label: { Label("扫描工坊二维码", systemImage: "qrcode.viewfinder") }
            }
        }
        .sheet(isPresented: $showScanner) { QRScannerView(purpose: .workshop) }
        .navigationDestination(isPresented: $showWorkshop) { if let destination { PublicWorkshopView(id: destination) } }
    }
    private func open() {
        guard let id = WorkshopLink.parse(input) else { invalid = true; errorFocused = true; return }
        invalid = false; destination = id; showWorkshop = true
    }
}
