import AppKit
import SwiftUI

/// AppKit owns the sheet lifecycle; all authentication and policy decisions
/// remain in AccountStore and NativeAuthorizationBroker respectively.
@MainActor
final class MacAuthorizationUI: NSObject, MacAuthorizationPresenting, NSWindowDelegate {
    private final class Presentation {
        let sheet: NSWindow
        weak var parent: NSWindow?
        let complete: (AuthorizationSheetChoice) -> Void
        var choice: AuthorizationSheetChoice?
        var cancelLogin: (() -> Void)?
        var parentClosingObserver: NSObjectProtocol?

        init(sheet: NSWindow, parent: NSWindow, complete: @escaping (AuthorizationSheetChoice) -> Void) {
            self.sheet = sheet
            self.parent = parent
            self.complete = complete
        }

        deinit {
            if let parentClosingObserver { NotificationCenter.default.removeObserver(parentClosingObserver) }
        }
    }

    private let accounts: AccountStore
    private let window: @MainActor () -> NSWindow?
    private var presentation: Presentation?

    init(accounts: AccountStore, window: @escaping @MainActor () -> NSWindow?) {
        self.accounts = accounts
        self.window = window
        super.init()
    }

    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard let current = prepare(title: "登录云乐坊", complete: { completion($0 == .current) }) else { return false }
        let content = MacLoginView(
            accounts: accounts,
            authorizationApplication: application,
            onAuthenticated: { [weak self, weak current] in
                guard let self, let current else { return }
                self.finish(current, choice: .current)
            },
            onDismiss: { [weak self, weak current] in
                guard let self, let current else { return }
                self.finish(current, choice: .cancel)
            },
            registerCancellation: { [weak current] cancel in
                current?.cancelLogin = cancel
            }
        )
        present(current, content: content)
        return true
    }

    func showConsent(policy: HostSsoPolicy, user: AccountUser,
                     completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        guard let current = prepare(title: "云乐坊账号授权", complete: completion) else { return false }
        present(current, content: MacAuthorizationConsentView(policy: policy, user: user) { [weak self, weak current] choice in
            guard let self, let current else { return }
            self.finish(current, choice: choice)
        })
        return true
    }

    func dismiss() {
        guard let presentation else { return }
        finish(presentation, choice: .cancel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let presentation, presentation.sheet === sender else { return true }
        finish(presentation, choice: .cancel)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let current = presentation, notification.object as? NSWindow === current.sheet else { return }
        finish(current, choice: .cancel)
    }

    private func prepare(title: String, complete: @escaping (AuthorizationSheetChoice) -> Void) -> Presentation? {
        guard presentation == nil, let parent = window(), parent.isVisible,
              parent.attachedSheet == nil, !parent.isMiniaturized else { return nil }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = title
        sheet.isReleasedWhenClosed = false
        sheet.delegate = self
        let current = Presentation(sheet: sheet, parent: parent, complete: complete)
        presentation = current
        current.parentClosingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main
        ) { [weak self, weak current] _ in
            MainActor.assumeIsolated {
                guard let self, let current else { return }
                self.finish(current, choice: .cancel)
            }
        }
        return current
    }

    private func present<Content: View>(_ current: Presentation, content: Content) {
        let controller = NSHostingController(rootView: content)
        current.sheet.contentViewController = controller
        current.sheet.setContentSize(controller.view.fittingSize)
        current.parent?.beginSheet(current.sheet) { [weak self, weak current] _ in
            guard let self, let current else { return }
            self.didEnd(current)
        }
    }

    private func finish(_ current: Presentation, choice: AuthorizationSheetChoice) {
        guard presentation === current, current.choice == nil else { return }
        current.choice = choice
        // Expiry or parent-window closure must cancel the login before AppKit's
        // dismissal animation; waiting for onDisappear leaves a response race.
        if choice == .cancel { current.cancelLogin?() }
        current.cancelLogin = nil
        if let parent = current.sheet.sheetParent {
            parent.endSheet(current.sheet, returnCode: choice == .cancel ? .cancel : .OK)
        } else {
            didEnd(current)
        }
    }

    private func didEnd(_ current: Presentation) {
        guard presentation === current else { return }
        // Also cover a caller ending the sheet directly through AppKit.
        if current.choice == nil { current.cancelLogin?() }
        current.cancelLogin = nil
        presentation = nil
        if let observer = current.parentClosingObserver {
            NotificationCenter.default.removeObserver(observer)
            current.parentClosingObserver = nil
        }
        current.sheet.delegate = nil
        current.sheet.orderOut(nil)
        current.sheet.contentViewController = nil
        // Completion runs after AppKit has removed the sheet, so the broker can
        // present the next consent sheet without competing with a closing login.
        current.complete(current.choice ?? .cancel)
    }
}

private struct MacAuthorizationConsentView: View {
    let policy: HostSsoPolicy
    let user: AccountUser
    let choose: (AuthorizationSheetChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("登录\(policy.applicationName)", systemImage: "person.crop.circle.badge.checkmark")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("authorization.title")
            Text(policy.applicationOrigin)
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .accessibilityIdentifier("authorization.origin")
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36)).foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName).font(.headline)
                        Text(user.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(6)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("将向\(policy.applicationName)提供")
                Text(policy.permissionDescription).font(.headline)
                Text("不会共享你的密码或云乐坊长期登录凭证。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("使用其他账号") { choose(.other) }
                    .accessibilityIdentifier("authorization.other-account")
                Spacer()
                Button("取消") { choose(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("authorization.cancel")
                Button("使用此账号继续") { choose(.current) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("authorization.confirm")
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
