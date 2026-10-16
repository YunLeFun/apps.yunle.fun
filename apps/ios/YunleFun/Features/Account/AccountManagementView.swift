import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var showLogin = false
    @State private var removal: AccountUser?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(accounts.overview.users) { user in
                    Button {
                        guard user.id != accounts.user?.id else { return }
                        run { try await accounts.select(user.id) }
                    } label: {
                        HStack {
                            AccountIdentityLabel(user: user)
                            Spacer()
                            if user.id == accounts.user?.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("当前账号")
                            }
                        }
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("移除", role: .destructive) { removal = user }
                    }
                    .contextMenu {
                        Button("从此设备移除", role: .destructive) { removal = user }
                    }
                }
                Button { showLogin = true } label: { Label("添加账号", systemImage: "person.badge.plus") }
            } footer: { Text("切换账号会结束正在运行的云应用。每个账号的云居分别保存。") }
            .disabled(busy)
            if let user = accounts.user {
                Section {
                    Button("退出当前账号", role: .destructive) { removal = user }
                        .disabled(busy)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let notice = accounts.notice { Section { Text(notice).foregroundStyle(.secondary) } }
            if busy { ProgressView().accessibilityLabel("正在更新账号") }
        }
        .navigationTitle("账号管理")
        .sheet(isPresented: $showLogin) { LoginView() }
        .confirmationDialog("从此设备移除账号？", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible, presenting: removal) { user in
            Button("退出并移除", role: .destructive) { run { try await accounts.remove(user.id) } }
        } message: { user in
            Text("将退出 \(user.displayName)，并结束正在运行的云应用。已保存的云居会保留。")
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch { self.error = AccountError.message(for: error) }
        }
    }
}

struct AccountIdentityLabel: View {
    let user: AccountUser

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline).foregroundStyle(.primary)
                Text(user.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AccountProfileView: View {
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        Form {
            if let user = accounts.user {
                Section { AccountIdentityLabel(user: user) }
                Section("个人资料") {
                    LabeledContent("昵称", value: user.displayName)
                    if let description = user.description, !description.isEmpty { Text(description) }
                    NavigationLink("编辑资料") { ProfileEditView(user: user) }
                }
                Section("账号") {
                    if let username = user.username, !username.isEmpty { LabeledContent("用户名", value: username) }
                    if let phone = user.phoneNumber, !phone.isEmpty { LabeledContent("手机号", value: phone) }
                    if let email = user.email, !email.isEmpty { LabeledContent("邮箱", value: email) }
                    NavigationLink("账号管理") { AccountManagementView() }
                }
            }
        }
        .navigationTitle("个人资料")
    }
}

private struct ProfileEditView: View {
    let user: AccountUser
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var busy = false
    @State private var error: String?

    init(user: AccountUser) {
        self.user = user
        _name = State(initialValue: user.name ?? "")
        _description = State(initialValue: user.description ?? "")
    }

    var body: some View {
        Form {
            Section("昵称") { TextField("昵称", text: $name).textContentType(.nickname) }
            Section("个人简介") { TextField("介绍一下自己", text: $description, axis: .vertical).lineLimit(3...8) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if busy { ProgressView().accessibilityLabel("正在保存资料") }
        }
        .disabled(busy)
        .navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    busy = true
                    error = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do {
                            guard accounts.user?.id == user.id else { throw AccountError.sessionChanged }
                            try await accounts.updateProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description)
                            dismiss()
                        } catch { self.error = AccountError.message(for: error) }
                    }
                }
                .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          (name == (user.name ?? "") && description == (user.description ?? "")))
            }
        }
    }
}
