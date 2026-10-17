import SwiftUI

struct LoginView: View {
    var authorizationApplication: String? = nil
    var onSignedIn: (() -> Void)? = nil
    var continuationMessage: String? = nil
    var continuation: AccountSignInContinuation? = nil
    var onCommitted: ((AccountSignInSuccess) -> Void)? = nil
    var onCancelled: (() -> Void)? = nil
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var method = Method.phone
    @State private var identifier = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: VerificationChallenge?
    @State private var resendAt = Date.distantPast
    @State private var error: String?
    @State private var isBusy = false
    @State private var authenticationCommitted = false
    @State private var continuationCancelled = false
    @State private var signInAttemptID: UUID?
    @State private var operation: Task<Void, Never>?
    @State private var captchaAction: Action?
    @FocusState private var focus: Field?
    @AccessibilityFocusState private var errorFocused: Bool

    private enum Method: String, CaseIterable, Identifiable {
        case phone = "手机号", email = "邮箱", password = "密码"
        var id: Self { self }
    }
    private enum Field { case identifier, password, code }
    private enum Action: String, Identifiable {
        case sendCode, signIn
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("登录云乐坊").font(.title2.bold())
                        Text("让有趣的应用，成为日常。").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if let application = authorizationApplication {
                        Text("登录后返回\(application)，仍需在原生面板确认。登录本身不会自动授权。")
                            .font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("login.authorization-context")
                    } else if let continuationMessage {
                        Text(continuationMessage).font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("login.continuation-context")
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        methodPicker.pickerStyle(.menu)
                    } else {
                        methodPicker.pickerStyle(.segmented)
                    }
                }
                .disabled(isBusy)
                Section {
                    identifierField
                    if method == .password {
                        SecureField("密码", text: $password)
                            .accessibilityLabel("密码")
                            .accessibilityIdentifier("login.password")
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { perform(.signIn) }
                    } else {
                        TextField("6 位验证码", text: $code)
                            .accessibilityLabel("验证码")
                            .accessibilityIdentifier("login.code")
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                            .onChange(of: code) { value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(ceil(resendAt.timeIntervalSince(context.date))))
                            Button(seconds > 0 ? "\(seconds) 秒后重新获取" : "获取验证码") { perform(.sendCode) }
                                .disabled(seconds > 0)
                        }
                    }
                } footer: {
                    if method != .password { Text("未注册的手机号或邮箱将在验证后创建账号。") }
                }
                .disabled(isBusy)
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                            .accessibilityIdentifier("login.error")
                            .accessibilityFocused($errorFocused)
                    }
                }
                Section {
                    Button { perform(.signIn) } label: {
                        HStack {
                            Text(method == .password ? "登录" : "登录或注册")
                            Spacer()
                            if isBusy { ProgressView().accessibilityLabel("正在处理") }
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityIdentifier("login.submit")
                } footer: {
                    Text("继续即表示你已阅读并同意[服务条款](https://www.yunle.fun/docs/terms-of-service)和[隐私政策](https://www.yunle.fun/docs/privacy-policy)。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(authorizationApplication == nil && continuationMessage == nil ? "账号" : "登录并继续")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { continuationCancelled = true; onCancelled?(); cancel(); dismiss() }
                }
                if focus != nil {
                    ToolbarItem(placement: keyboardDismissPlacement) {
                        Button { focus = nil } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                        }
                        .accessibilityIdentifier("login.dismiss-keyboard")
                    }
                }
            }
            .interactiveDismissDisabled(isBusy)
            .sheet(item: $captchaAction) { action in
                CaptchaView { token in perform(action, captcha: token) }
            }
            .onChange(of: method) { _ in resetChallenge(); password = ""; identifier = ""; error = nil }
            .onChange(of: identifier) { _ in resetChallenge(); error = nil }
            .onDisappear { cancel(); password = ""; code = "" }
        }
    }

    private var methodPicker: some View {
        Picker("登录方式", selection: $method) {
            ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("login.method")
    }

    private var keyboardDismissPlacement: ToolbarItemPlacement {
        if #available(iOS 17, *) { return .topBarTrailing }
        return .navigationBarTrailing
    }

    @ViewBuilder private var identifierField: some View {
        switch method {
        case .phone:
            HStack {
                Text("+86").foregroundStyle(.secondary).accessibilityLabel("中国大陆，区号 86")
                TextField("手机号", text: $identifier)
                    .accessibilityLabel("手机号")
                    .accessibilityIdentifier("login.phone")
                    .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    .focused($focus, equals: .identifier)
            }
        case .email:
            TextField("邮箱地址", text: $identifier)
                .accessibilityLabel("邮箱地址")
                .accessibilityIdentifier("login.email")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focus, equals: .identifier)
        case .password:
            TextField("用户名、邮箱或手机号", text: $identifier)
                .accessibilityLabel("用户名、邮箱或手机号")
                .accessibilityIdentifier("login.username")
                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focus, equals: .identifier).submitLabel(.next)
                .onSubmit { focus = .password }
        }
    }

    private func resetChallenge() { challenge = nil; code = "" }

    private func cancel() {
        // A successful identity publication can rebuild the presenting view
        // before its await resumes. Keep that already committed task alive.
        guard !authenticationCommitted else { operation = nil; return }
        let attempt = signInAttemptID
        signInAttemptID = nil
        operation?.cancel()
        operation = nil
        if let attempt { Task { await accounts.cancelSignIn(attemptID: attempt) } }
    }

    private func perform(_ action: Action, captcha: String? = nil) {
        guard !isBusy else { return }
        error = nil
        isBusy = true
        focus = nil
        operation = Task { @MainActor in
            defer { isBusy = false }
            do {
                switch action {
                case .sendCode:
                    let address = try method == .phone
                        ? VerificationAddress.phoneInput(identifier) : VerificationAddress.emailInput(identifier)
                    challenge = try await accounts.sendVerification(address: address, captcha: captcha)
                    resendAt = Date().addingTimeInterval(60)
                    focus = .code
                case .signIn:
                    let attempt = UUID()
                    signInAttemptID = attempt
                    let committed: (AccountSignInSuccess) -> Void = { success in
                        authenticationCommitted = true
                        onCommitted?(success)
                    }
                    let authenticated = { authenticationCommitted = true }
                    if method == .password {
                        try await accounts.passwordSignIn(identifier: identifier, password: password, captcha: captcha,
                                                          continuation: continuation, onCommitted: committed,
                                                          attemptID: attempt, onAuthenticated: authenticated)
                    } else {
                        guard let challenge else { throw AccountError.invalidVerification }
                        try await accounts.verify(challenge, code: code, captcha: captcha,
                                                  continuation: continuation, onCommitted: committed,
                                                  attemptID: attempt, onAuthenticated: authenticated)
                    }
                    password = ""
                    try Task.checkCancellation()
                    authenticationCommitted = true
                    guard !continuationCancelled else { return }
                    onSignedIn?()
                    dismiss()
                }
            } catch is CancellationError { }
            catch AccountError.captchaRequired { captchaAction = action }
            catch {
                guard !Task.isCancelled else { return }
                self.error = AccountError.message(for: error)
                errorFocused = true
            }
        }
    }
}
