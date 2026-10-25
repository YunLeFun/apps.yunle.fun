import SwiftUI

/// The account surface belongs to the app's Settings scene. Its store is shared
/// with the application runtime, so restoring or changing identity is atomic.
struct MacAccountView: View {
    @ObservedObject var accounts: AccountStore
    @State private var showsLogin = false
    @State private var accountToRemove: AccountUser?
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if let user = accounts.user {
                    identity(user)
                    if let description = user.description, !description.isEmpty {
                        Text(description).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    Label("尚未登录云乐坊", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("登录后会在此 Mac 保存账号，下次启动自动恢复登录。")
                        .foregroundStyle(.secondary)
                }

                if accounts.isRestoring {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在恢复登录会话…").foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("account.restoring")
                }
            }

            if !accounts.overview.users.isEmpty {
                Section("此 Mac 上的账号") {
                    ForEach(accounts.overview.users) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                Text(user.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if user.id == accounts.user?.id {
                                Label("当前账号", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("切换") { run { try await accounts.select(user.id) } }
                                    .accessibilityLabel("切换到 \(user.displayName)")
                            }
                            Button(role: .destructive) { accountToRemove = user } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("从此 Mac 移除 \(user.displayName)")
                        }
                    }
                }
                .disabled(isBusy || accounts.isRestoring)
            }

            Section {
                HStack {
                    Button(accounts.user == nil ? "登录云乐坊" : "添加账号") { showsLogin = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("account.login")
                    Button("刷新会话") { run { await accounts.restore() } }
                        .accessibilityIdentifier("account.refresh")
                    if let user = accounts.user {
                        Button("退出登录", role: .destructive) { accountToRemove = user }
                            .accessibilityIdentifier("account.sign-out")
                    }
                    if isBusy { ProgressView().controlSize(.small).accessibilityLabel("正在更新账号") }
                }
                .disabled(isBusy || accounts.isRestoring)
            } footer: {
                Text("登录凭据保存在 macOS 钥匙串中，下次启动会自动恢复。切换或退出账号会关闭正在运行的云应用。")
            }

            if let error {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            if let notice = accounts.notice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsLogin) { MacLoginView(accounts: accounts) }
        .confirmationDialog("从此 Mac 移除账号？", isPresented: Binding(
            get: { accountToRemove != nil },
            set: { if !$0 { accountToRemove = nil } }
        ), titleVisibility: .visible, presenting: accountToRemove) { user in
            Button("退出并移除", role: .destructive) { run { try await accounts.remove(user.id) } }
            Button("取消", role: .cancel) { accountToRemove = nil }
        } message: { user in
            Text(user.id == accounts.user?.id
                 ? "将退出 \(user.displayName)，并关闭正在运行的云应用。"
                 : "将从此 Mac 移除 \(user.displayName) 的登录凭据。")
        }
    }

    private func identity(_ user: AccountUser) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.title3.bold())
                Text(user.detail).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("account.identity")
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !accounts.isRestoring else { return }
        isBusy = true
        error = nil
        Task { @MainActor in
            defer { isBusy = false }
            do { try await action() }
            catch is CancellationError { }
            catch { self.error = AccountError.message(for: error) }
        }
    }
}
