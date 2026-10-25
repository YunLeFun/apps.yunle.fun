import SwiftUI

struct MacLoginView: View {
    @ObservedObject var accounts: AccountStore
    var authorizationApplication: String? = nil
    var onAuthenticated: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var registerCancellation: ((@escaping () -> Void) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var method = Method.phone
    @State private var identifier = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: VerificationChallenge?
    @State private var resendAt = Date.distantPast
    @State private var error: String?
    @State private var isBusy = false
    @State private var authenticationCommitted = false
    @State private var signInAttemptID: UUID?
    @State private var operationID: UUID?
    @State private var operation: Task<Void, Never>?
    @State private var captchaAction: Action?
    @FocusState private var focus: Field?

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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("登录云乐坊").font(.title2.bold())
                Text("让有趣的应用，成为日常。").foregroundStyle(.secondary)
                if let authorizationApplication {
                    Text("登录后返回\(authorizationApplication)，仍需确认是否提供账号标识、昵称和头像。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("login.authorization-context")
                }
            }
            Picker("登录方式", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("login.method")
            .disabled(isBusy)

            VStack(alignment: .leading, spacing: 12) {
                identifierField
                if method == .password {
                    SecureField("密码", text: $password)
                        .accessibilityIdentifier("login.password")
                        .focused($focus, equals: .password)
                        .onSubmit { perform(.signIn) }
                } else {
                    HStack(spacing: 12) {
                        TextField("6 位验证码", text: $code)
                            .accessibilityIdentifier("login.code")
                            .focused($focus, equals: .code)
                            .onChange(of: code) { _, value in
                                code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                            }
                            .onSubmit { perform(.signIn) }
                        TimelineView(MacVerificationResendTimeline(deadline: resendAt)) { context in
                            let seconds = max(0, Int(ceil(resendAt.timeIntervalSince(context.date))))
                            Button(seconds > 0 ? "\(seconds) 秒后重试" : "获取验证码") { perform(.sendCode) }
                                .disabled(seconds > 0)
                                .accessibilityIdentifier("login.send-code")
                        }
                    }
                    Text("未注册的手机号或邮箱将在验证后创建账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .disabled(isBusy)

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("login.error")
            }

            Text("继续即表示你已阅读并同意[服务条款](https://www.yunle.fun/docs/terms-of-service)和[隐私政策](https://www.yunle.fun/docs/privacy-policy)。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text("正在处理…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { cancel(); dismissLogin() }
                    .keyboardShortcut(.cancelAction)
                Button(method == .password ? "登录" : "登录或注册") { perform(.signIn) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                    .accessibilityIdentifier("login.submit")
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $captchaAction) { action in
            MacCaptchaView(accounts: accounts) { token in perform(action, captcha: token) }
        }
        .onChange(of: method) { _, _ in
            resetChallenge()
            password = ""
            identifier = ""
            error = nil
        }
        .onChange(of: identifier) { _, _ in resetChallenge(); error = nil }
        .onAppear { registerCancellation?(cancel); focus = .identifier }
        .onDisappear { cancel(); password = ""; code = "" }
    }

    @ViewBuilder private var identifierField: some View {
        switch method {
        case .phone:
            HStack {
                Text("+86").foregroundStyle(.secondary).accessibilityLabel("中国大陆，区号 86")
                TextField("手机号", text: $identifier)
                    .accessibilityIdentifier("login.phone")
                    .focused($focus, equals: .identifier)
                    .onSubmit { perform(.sendCode) }
            }
        case .email:
            TextField("邮箱地址", text: $identifier)
                .autocorrectionDisabled()
                .accessibilityIdentifier("login.email")
                .focused($focus, equals: .identifier)
                .onSubmit { perform(.sendCode) }
        case .password:
            TextField("用户名、邮箱或手机号", text: $identifier)
                .autocorrectionDisabled()
                .accessibilityIdentifier("login.username")
                .focused($focus, equals: .identifier)
                .onSubmit { focus = .password }
        }
    }

    private func resetChallenge() { challenge = nil; code = "" }

    private func dismissLogin() {
        if let onDismiss { onDismiss() }
        else { dismiss() }
    }

    private func cancel() {
        // AccountStore publishes identity before the awaiting UI resumes. Do not
        // cancel a login that the session has already accepted and published.
        guard !authenticationCommitted else { operation = nil; return }
        let attempt = signInAttemptID
        signInAttemptID = nil
        operationID = nil
        operation?.cancel()
        operation = nil
        isBusy = false
        if let attempt { Task { await accounts.cancelSignIn(attemptID: attempt) } }
    }

    private func perform(_ action: Action, captcha: String? = nil) {
        guard !isBusy else { return }
        error = nil
        isBusy = true
        focus = nil
        let currentID = UUID()
        operationID = currentID
        operation = Task { @MainActor in
            defer {
                if operationID == currentID { isBusy = false; operation = nil; operationID = nil }
            }
            do {
                try Task.checkCancellation()
                guard operationID == currentID else { return }
                switch action {
                case .sendCode:
                    guard Date() >= resendAt || captcha != nil else { return }
                    let address = try method == .phone
                        ? VerificationAddress.phoneInput(identifier) : VerificationAddress.emailInput(identifier)
                    let sent = try await accounts.sendVerification(address: address, captcha: captcha)
                    try Task.checkCancellation()
                    guard operationID == currentID else { return }
                    challenge = sent
                    resendAt = Date().addingTimeInterval(60)
                    focus = .code
                case .signIn:
                    let attempt = UUID()
                    signInAttemptID = attempt
                    let authenticated = { authenticationCommitted = true }
                    if method == .password {
                        try await accounts.passwordSignIn(identifier: identifier, password: password, captcha: captcha,
                                                          attemptID: attempt, onAuthenticated: authenticated)
                    } else {
                        guard let challenge else { throw AccountError.invalidVerification }
                        try await accounts.verify(challenge, code: code, captcha: captcha,
                                                  attemptID: attempt, onAuthenticated: authenticated)
                    }
                    try Task.checkCancellation()
                    guard operationID == currentID else { return }
                    authenticationCommitted = true
                    password = ""
                    code = ""
                    // This callback belongs to this accepted attempt, after
                    // AccountStore has published its identity. External account
                    // changes are never treated as this sheet's login success.
                    onAuthenticated?()
                    dismissLogin()
                }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, operationID == currentID else { return }
                if error as? AccountError == .captchaRequired { captchaAction = action }
                else { self.error = AccountError.message(for: error) }
            }
        }
    }
}

/// Stop ticking after the resend deadline so an idle login sheet stays idle.
private struct MacVerificationResendTimeline: TimelineSchedule, Sendable {
    let deadline: Date

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(nextDate: startDate, deadline: deadline)
    }

    struct Entries: Sequence, IteratorProtocol, Sendable {
        var nextDate: Date?
        let deadline: Date

        mutating func next() -> Date? {
            guard let date = nextDate else { return nil }
            nextDate = date < deadline ? Swift.min(date.addingTimeInterval(1), deadline) : nil
            return date
        }
    }
}
