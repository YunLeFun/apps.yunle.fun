import SwiftUI
import UIKit

struct CaptchaView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    let verified: (String) -> Void
    @State private var challenge: CaptchaImage?
    @State private var image: UIImage?
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false
    @State private var expiresAt = Date.distantPast
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("请输入图片中的字符以继续。").foregroundStyle(.secondary)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 100)
                            .accessibilityLabel("图片验证码")
                    }
                    TextField("图片中的字符", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit { submit() }
                    Button("更换图片") { load() }
                }
                .disabled(busy)
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button { submit() } label: {
                        HStack { Text("验证"); Spacer(); if busy { ProgressView() } }
                    }
                    .disabled(busy || challenge == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("安全验证").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { load() }
            .onDisappear { operation?.cancel() }
        }
    }

    private func load() {
        operation?.cancel()
        busy = true
        error = nil
        challenge = nil
        image = nil
        text = ""
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await accounts.captcha()
                try Task.checkCancellation()
                guard result.type == "image", result.expiresIn > 0, !result.token.isEmpty,
                      result.data.utf8.count <= 2_000_000,
                      let comma = result.data.firstIndex(of: ","),
                      ["data:image/gif;base64", "data:image/png;base64", "data:image/jpeg;base64"].contains(String(result.data[..<comma])),
                      let data = Data(base64Encoded: String(result.data[result.data.index(after: comma)...])),
                      let decoded = AuthorizationImageDecoder.decode(data) else { throw AccountError.invalidResponse }
                image = decoded
                challenge = result
                expiresAt = Date().addingTimeInterval(TimeInterval(result.expiresIn))
            } catch { if !Task.isCancelled { self.error = AccountError.message(for: error) } }
        }
    }

    private func submit() {
        guard !busy, let challenge else { return }
        guard expiresAt > Date() else { load(); return }
        busy = true
        error = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let token = try await accounts.verifyCaptcha(token: challenge.token, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                try Task.checkCancellation()
                dismiss()
                verified(token)
            } catch { if !Task.isCancelled { self.error = AccountError.message(for: error) } }
        }
    }
}
