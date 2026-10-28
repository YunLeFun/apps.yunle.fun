import SwiftUI

struct MyWorkshopsView: View {
    @EnvironmentObject private var accounts: AccountStore
    var body: some View { MyWorkshopsContent(accounts: accounts).id(accounts.identityGeneration) }
}
private struct MyWorkshopsContent: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: MyWorkshopsStore
    @State private var showLogin = false
    @State private var showCreate = false
    @State private var isRefreshing = false
    init(accounts: AccountStore) {
        self.accounts = accounts; _model = StateObject(wrappedValue: MyWorkshopsStore(accounts: accounts))
    }
    var body: some View {
        List {
            if accounts.user == nil {
                ContentStateView(title: "和同好一起使用应用", systemImage: "person.2",
                                 message: "登录后创建个人工坊，或查看你加入的工坊。")
                Button("登录云乐坊") { showLogin = true }
            } else {
                WorkshopLoadStatus(isLoading: false, error: model.error) { await model.refresh() }
                if let notice = model.notice { Label(notice, systemImage: "checkmark.circle") }
                if model.hasLoaded {
                    Section("我的工坊") {
                        if let management = model.management {
                            NavigationLink { OwnedWorkshopView(model: model) } label: { WorkshopRow(workshop: management.workshop) }
                            NavigationLink("查看工坊内容") { PublicWorkshopView(id: management.workshop.id) }
                        } else {
                            Text("创建一个工坊，邀请同好一起使用你发布的应用。").foregroundStyle(.secondary)
                            Button("创建个人工坊") { showCreate = true }
                        }
                    }
                    Section("我加入的工坊") {
                        if model.joined.isEmpty { Text("还没有加入工坊").foregroundStyle(.secondary) }
                        ForEach(model.joined) { workshop in
                            NavigationLink { PublicWorkshopView(id: workshop.id) } label: { WorkshopRow(workshop: workshop) }
                        }
                    }
                } else if model.error == nil {
                    Section("我的工坊") { workshopPlaceholder }
                    Section("我加入的工坊") {
                        ForEach(0..<3) { _ in workshopPlaceholder }
                    }
                }
            }
            Section {
                NavigationLink { WorkshopLookupView() } label: { Label("输入工坊编号或链接", systemImage: "number") }
            }
        }
        .transaction { $0.animation = nil }
        .navigationTitle("个人工坊").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            WorkshopLoadingToolbarItem(placement: .navigationBarTrailing,
                isLoading: model.isLoading && !isRefreshing)
        }
        .task { await model.loadIfNeeded() }
        .refreshable {
            isRefreshing = true
            defer { isRefreshing = false }
            await model.refresh()
        }
        .sheet(isPresented: $showLogin) {
            LoginView(continuationMessage: "登录后可创建和管理个人工坊，或加入其他工坊。").environmentObject(accounts)
        }
        .sheet(isPresented: $showCreate) {
            WorkshopEditor(model: model, workshop: nil, generation: accounts.identityGeneration).environmentObject(accounts)
        }
    }

    private var workshopPlaceholder: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("工坊名称").font(.headline)
            Text("工坊创建者 · 申请加入").font(.subheadline)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

struct WorkshopLoadingToolbarItem: ToolbarContent {
    let placement: ToolbarItemPlacement
    let isLoading: Bool

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: placement) { indicator }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { indicator }
        }
    }
    private var indicator: some View {
        LoadingIndicator(isLoading: isLoading, label: "正在载入工坊")
            .controlSize(.small)
            .frame(width: 24, height: 24)
    }
}

struct WorkshopRow: View {
    let workshop: PersonalWorkshop
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(workshop.name).font(.headline)
            Text("\(workshop.ownerName) · \(workshop.status == .disabled ? workshop.status.label : workshop.joinPolicy.label)")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
struct WorkshopLoadStatus: View {
    let isLoading: Bool
    let error: String?
    let retry: () async -> Void
    var body: some View {
        if isLoading { ProgressView("正在载入工坊") }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button("重试") { Task { await retry() } }
        }
    }
}

private struct OwnedWorkshopView: View {
    @ObservedObject var model: MyWorkshopsStore
    @EnvironmentObject private var accounts: AccountStore
    @State private var showEdit = false
    @State private var showShare = false
    @State private var decision: MemberDecision?
    @State private var actionError: String?
    var body: some View {
        List {
            WorkshopLoadStatus(isLoading: model.isLoading, error: model.error) { await model.refresh() }
            if let actionError { Label(actionError, systemImage: "exclamationmark.triangle") }
            if let notice = model.notice { Label(notice, systemImage: "checkmark.circle") }
            if let management = model.management {
                Section {
                    WorkshopRow(workshop: management.workshop)
                    if let description = management.workshop.description, !description.isEmpty { Text(description) }
                    LabeledContent("工坊编号", value: management.workshop.id).textSelection(.enabled)
                    Button("编辑工坊") { showEdit = true }
                    Button("分享工坊") { showShare = true }
                    NavigationLink("查看工坊内容") { PublicWorkshopView(id: management.workshop.id) }
                }
                members("加入申请", rows: management.pending)
                members("坊客", rows: management.guests)
                members("禁止加入", rows: management.blocked)
            }
            if model.isWriting { ProgressView("正在处理") }
        }
        .navigationTitle("管理工坊").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .onChange(of: accounts.identityGeneration) { _ in showEdit = false; showShare = false; decision = nil; actionError = nil }
        .sheet(isPresented: $showEdit) {
            if let workshop = model.management?.workshop {
                WorkshopEditor(model: model, workshop: workshop, generation: accounts.identityGeneration).environmentObject(accounts)
            }
        }
        .sheet(isPresented: $showShare) {
            if let workshop = model.management?.workshop { WorkshopShareView(workshop: workshop) }
        }
        .confirmationDialog(decision?.action.label ?? "坊客管理", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), titleVisibility: .visible) {
            if let selected = decision {
                Button(selected.action.label, role: selected.action == .approve || selected.action == .unblock ? nil : .destructive) {
                    decision = nil
                    Task {
                        do { try await model.decide(member: selected.member, action: selected.action, generation: selected.generation); actionError = nil }
                        catch { actionError = WorkshopError.message(for: error) + " 如未确认结果，请刷新检查。" }
                    }
                }
            }
            Button("取消", role: .cancel) { decision = nil }
        } message: {
            if let selected = decision { Text("将对“\(selected.member.displayName)”执行\(selected.action.label)。") }
        }
    }
    private func members(_ title: String, rows: [WorkshopMembership]) -> some View {
        Section("\(title) · \(rows.count)") {
            if rows.isEmpty { Text("暂无\(title)").foregroundStyle(.secondary) }
            ForEach(rows) { member in
                Menu {
                    ForEach(WorkshopDecision.allCases.filter { $0.allows(member.status) }) { action in
                        Button(action.label, role: action == .approve || action == .unblock ? nil : .destructive) {
                            decision = MemberDecision(member: member, action: action, generation: accounts.identityGeneration)
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.displayName).foregroundStyle(.primary)
                            if let date = member.requestedAt ?? member.joinedAt {
                                Text(Date(timeIntervalSince1970: date / 1000), format: .dateTime.year().month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(); Image(systemName: "ellipsis.circle").accessibilityHidden(true)
                    }.padding(.vertical, 4)
                }
                .accessibilityLabel("管理坊客：\(member.displayName)")
                .disabled(model.isWriting)
            }
        }
    }
    private struct MemberDecision { let member: WorkshopMembership; let action: WorkshopDecision; let generation: UUID }
}

private struct WorkshopEditor: View {
    @ObservedObject var model: MyWorkshopsStore
    let workshop: PersonalWorkshop?
    let generation: UUID
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkshopDraft
    @State private var error: String?
    @State private var confirmChange = false
    init(model: MyWorkshopsStore, workshop: PersonalWorkshop?, generation: UUID) {
        self.model = model; self.workshop = workshop; self.generation = generation
        _draft = State(initialValue: workshop.map(WorkshopDraft.init) ?? WorkshopDraft())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("工坊名称", text: $draft.name).textContentType(.organizationName)
                    TextField("工坊简介", text: $draft.description, axis: .vertical).lineLimit(3...6)
                } footer: { Text("名称最多 40 字，简介最多 200 字。") }
                if workshop != nil {
                    Section {
                        Picker("加入方式", selection: $draft.joinPolicy) { ForEach(WorkshopJoinPolicy.allCases) { Text($0.label).tag($0) } }
                        Picker("工坊状态", selection: $draft.status) { ForEach(WorkshopStatus.allCases) { Text($0.label).tag($0) } }
                    } footer: { Text("暂停后工坊内的应用暂不可访问，已有坊客身份会保留。停止加入仅关闭新申请。") }
                } else {
                    Section { Text("每个账号可以创建一个工坊。新工坊默认需要坊主审批后加入。").foregroundStyle(.secondary) }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) } }
                if model.isWriting { ProgressView("正在保存") }
            }
            .navigationTitle(workshop == nil ? "创建工坊" : "编辑工坊").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(model.isWriting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if (draft.joinPolicy == .open && workshop?.joinPolicy != .open) || (draft.status == .disabled && workshop?.status != .disabled) { confirmChange = true }
                        else { save() }
                    }.disabled(!draft.isValid || model.isWriting)
                }
            }
            .interactiveDismissDisabled(model.isWriting)
            .confirmationDialog("确认更改工坊访问方式？", isPresented: $confirmChange, titleVisibility: .visible) {
                Button("保存更改", role: draft.status == .disabled ? .destructive : nil) { save() }
                Button("取消", role: .cancel) {}
            } message: { Text(draft.status == .disabled ? "工坊暂停后，坊客将暂时无法访问工坊应用。" : "改为自由加入后，持有工坊链接的用户可以直接加入。") }
            .onChange(of: accounts.identityGeneration) { _ in dismiss() }
        }
    }
    private func save() {
        Task {
            do { try await model.save(draft, expectedID: workshop?.id, generation: generation); dismiss() }
            catch { self.error = WorkshopError.message(for: error) + " 如未确认结果，请返回刷新检查后再提交。" }
        }
    }
}
