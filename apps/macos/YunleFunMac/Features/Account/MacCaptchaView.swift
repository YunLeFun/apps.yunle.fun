import AppKit
import ImageIO
import SwiftUI

struct MacCaptchaView: View {
    @ObservedObject var accounts: AccountStore
    let verified: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: CaptchaImage?
    @State private var image: NSImage?
    @State private var text = ""
    @State private var error: String?
    @State private var isBusy = false
    @State private var expiresAt = Date.distantPast
    @State private var operationID: UUID?
    @State private var operation: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("安全验证").font(.title2.bold())
            Text("请输入图片中的字符以继续。").foregroundStyle(.secondary)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 100)
                    .accessibilityLabel("图片验证码")
            } else if isBusy {
                ProgressView().frame(maxWidth: .infinity).frame(height: 100)
                    .accessibilityLabel("正在载入验证码")
            }
            HStack {
                TextField("图片中的字符", text: $text)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .focused($inputFocused).onSubmit { submit() }
                    .accessibilityIdentifier("captcha.input")
                Button("更换图片") { load() }
            }
            .disabled(isBusy)
            if let error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") { cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("验证") { submit() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(isBusy || challenge == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { load() }
        .onDisappear { cancel() }
    }

    private func cancel() {
        operationID = nil
        operation?.cancel()
        operation = nil
    }

    private func load() {
        cancel()
        isBusy = true
        error = nil
        challenge = nil
        image = nil
        text = ""
        let currentID = UUID()
        operationID = currentID
        operation = Task { @MainActor in
            defer { if operationID == currentID { isBusy = false; operation = nil } }
            do {
                let result = try await accounts.captcha()
                try Task.checkCancellation()
                guard operationID == currentID else { return }
                guard let decoded = Self.decode(result) else { throw AccountError.invalidResponse }
                image = decoded
                challenge = result
                expiresAt = Date().addingTimeInterval(TimeInterval(result.expiresIn))
                inputFocused = true
            } catch {
                if !Task.isCancelled, operationID == currentID { self.error = AccountError.message(for: error) }
            }
        }
    }

    private func submit() {
        guard !isBusy, let challenge else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        guard expiresAt > Date() else { load(); return }
        isBusy = true
        error = nil
        let currentID = UUID()
        operationID = currentID
        operation = Task { @MainActor in
            defer { if operationID == currentID { isBusy = false; operation = nil } }
            do {
                let token = try await accounts.verifyCaptcha(token: challenge.token, text: answer)
                try Task.checkCancellation()
                guard operationID == currentID else { return }
                dismiss()
                verified(token)
            } catch {
                if !Task.isCancelled, operationID == currentID { self.error = AccountError.message(for: error) }
            }
        }
    }

    private static func decode(_ challenge: CaptchaImage) -> NSImage? {
        guard challenge.type == "image", challenge.expiresIn > 0, !challenge.token.isEmpty,
              challenge.data.utf8.count <= 2_000_000,
              let comma = challenge.data.firstIndex(of: ","),
              ["data:image/gif;base64", "data:image/png;base64", "data:image/jpeg;base64"].contains(String(challenge.data[..<comma])),
              let data = Data(base64Encoded: String(challenge.data[challenge.data.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4_096, height <= 4_096, width * height <= 4_000_000,
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: decoded, size: NSSize(width: CGFloat(width), height: CGFloat(height)))
    }
}
