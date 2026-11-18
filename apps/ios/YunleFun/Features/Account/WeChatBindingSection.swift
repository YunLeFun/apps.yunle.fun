import SwiftUI

struct WeChatBindingSection: View {
    let accountID: String
    @EnvironmentObject private var accounts: AccountStore
    @State private var bound: Bool?
    @State private var canBind = false
    @State private var showsUnbind = false
    @State private var mutation: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        Group {
            if bound == true || (bound == false && canBind) {
                Section {
                    LabeledContent("微信", value: bound == true ? "已绑定" : "未绑定")
                    if bound == true {
                        Button("解除绑定", role: .destructive) { showsUnbind = true }
                            .disabled(mutation != nil)
                    } else {
                        Button("绑定微信") { change(binding: true) }
                            .disabled(mutation != nil)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("绑定后可以使用微信登录当前云乐坊账号。")
                }
                .confirmationDialog("解除微信绑定？", isPresented: $showsUnbind, titleVisibility: .visible) {
                    Button("解除绑定", role: .destructive) { change(binding: false) }
                } message: {
                    Text("解除绑定后，仍可用短信、邮箱或密码登录这个账号。")
                }
            }
        }
        .task {
            async let status = accounts.weChatBinding(for: accountID)
            let enabled = WeChatAuthorization.shared.isAvailable ? await accounts.weChatLoginAvailable() : false
            guard let status = try? await status, !Task.isCancelled else { return }
            bound = status
            canBind = enabled
        }
        .onDisappear { mutation?.cancel(); mutation = nil }
    }

    private func change(binding: Bool) {
        guard mutation == nil, accounts.user?.id == accountID else { return }
        let generation = accounts.identityGeneration
        error = nil
        mutation = Task { @MainActor in
            defer { mutation = nil }
            do {
                let code: String?
                if binding {
                    guard await accounts.weChatLoginAvailable() else { throw AccountError.unavailable }
                    code = try await WeChatAuthorization.shared.authorize()
                } else { code = nil }
                try Task.checkCancellation()
                guard accounts.identityGeneration == generation else { throw AccountError.sessionChanged }
                try await accounts.changeWeChatBinding(code: code, for: accountID)
                try Task.checkCancellation()
                bound = binding
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = AccountError.message(for: error) } }
        }
    }
}
