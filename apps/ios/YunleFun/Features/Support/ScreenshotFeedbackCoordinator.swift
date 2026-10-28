import SwiftUI
import UIKit

/// Owns a small, non-modal accessory in this scene's existing window. A root
/// SwiftUI overlay alone would sit behind the full-screen cloud-app runtime.
@MainActor
final class ScreenshotFeedbackCoordinator: ObservableObject {
    private weak var window: UIWindow?
    private weak var feedbackController: UIViewController?
    private var prompt = ScreenshotFeedbackPromptState()
    private var capsule: ScreenshotFeedbackCapsule?
    private weak var capsulePresenter: UIViewController?
    private var refreshTask: Task<Void, Never>?
    private var restorationTask: Task<Void, Never>?
    private var earliestPresentation = Date.distantPast
    private var feedbackScreens: Set<UUID> = []
    private var sceneIsInactive = false
    private var accessibilityFocusInPrompt = false
    private var logs: DiagnosticLogStore?
    private var accounts: AccountStore?
    private var requestLogin: ((String) -> Bool)?
    private var loginDraft: (id: UUID, text: String, generation: UUID)?

    init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didTakeScreenshot), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneChanged), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneChanged), name: UIScene.willDeactivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneEnteredBackground), name: UIScene.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(accessibilityFocusChanged), name: UIAccessibility.elementFocusedNotification, object: nil)
    }

    deinit {
        refreshTask?.cancel()
        restorationTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(enabled: Bool, logs: DiagnosticLogStore, accounts: AccountStore,
                   requestLogin: @escaping (String) -> Bool) {
        self.logs = logs; self.accounts = accounts; self.requestLogin = requestLogin
        prompt.setEnabled(enabled && FeedbackChannel.current != .testFlight)
        refresh()
    }

    func attach(to window: UIWindow) {
        if self.window !== window {
            discard(); self.window = window
            sceneIsInactive = window.windowScene?.activationState != .foregroundActive
        }
    }

    func discard() {
        prompt.discard()
        refreshTask?.cancel(); refreshTask = nil
        removeCapsule()
    }

    func cancelPendingLogin() {
        loginDraft = nil
        restorationTask?.cancel(); restorationTask = nil
    }

    func feedbackVisibilityChanged(_ id: UUID, visible: Bool) {
        if visible { feedbackScreens.insert(id); discard() }
        else { feedbackScreens.remove(id) }
    }

    @objc private func didTakeScreenshot() {
        guard let scene = window?.windowScene, window?.isKeyWindow == true,
              scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive,
              feedbackScreens.isEmpty else { return }
        let now = Date()
        let alreadyPending = prompt.hasPending
        prompt.receive(at: now)
        if prompt.hasPending, !alreadyPending { earliestPresentation = now.addingTimeInterval(0.7) }
        refresh()
    }

    @objc private func sceneChanged(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
        if notification.name == UIScene.willDeactivateNotification {
            sceneIsInactive = true
            prompt.suspend(at: Date())
            removeCapsule()
            refreshTask?.cancel(); refreshTask = nil
        } else {
            sceneIsInactive = false
            earliestPresentation = Date().addingTimeInterval(0.7)
            refresh()
        }
    }

    @objc private func sceneEnteredBackground(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
        sceneIsInactive = true
        discard()
    }

    @objc private func accessibilityFocusChanged(_ notification: Notification) {
        let focused = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey] as? UIView
        accessibilityFocusInPrompt = capsule.map { focused?.isDescendant(of: $0) == true } ?? false
        if accessibilityFocusInPrompt { prompt.suspend(at: Date()) }
        refresh()
    }

    private func refresh() {
        refreshTask?.cancel(); refreshTask = nil
        // Let an assistive-technology user finish activating the focused
        // control. Do not move focus or announce a screenshot on their behalf.
        if accessibilityFocusInPrompt, prompt.hasPending, !sceneIsInactive,
           let window, window.windowScene?.activationState == .foregroundActive,
           window.isKeyWindow, Self.feedbackPresenter(in: window) != nil { return }
        let now = Date()
        prompt.advance(at: now)
        guard prompt.hasPending, let window else { removeCapsule(); return }
        // Do not consume the visible lifetime behind system screenshot UI,
        // another app, an authorization sheet, or a native alert.
        if !sceneIsInactive, window.windowScene?.activationState == .foregroundActive,
           window.isKeyWindow, now >= earliestPresentation,
           feedbackScreens.isEmpty, let presenter = Self.feedbackPresenter(in: window) {
            prompt.present(at: now)
            if capsulePresenter !== presenter { removeCapsule() }
            if prompt.isVisible, capsule == nil { showCapsule(in: window, presenter: presenter) }
            capsule?.overrideUserInterfaceStyle = presenter.traitCollection.userInterfaceStyle
        } else {
            prompt.suspend(at: now)
            removeCapsule()
        }
        guard prompt.hasPending else { return }
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Allow the host and its full-screen navigation runtime, but never place
    /// the accessory over a sheet, picker, alert, or an in-flight transition.
    static func feedbackPresenter(in window: UIWindow) -> UIViewController? {
        guard var controller = window.rootViewController else { return nil }
        while let next = controller.presentedViewController {
            guard next is UINavigationController, next.modalPresentationStyle == .fullScreen,
                  !next.isBeingPresented, !next.isBeingDismissed else { return nil }
            controller = next
        }
        guard !controller.isBeingPresented, !controller.isBeingDismissed,
              controller.transitionCoordinator == nil,
              controller.viewIfLoaded?.window === window else { return nil }
        return controller
    }

    private func showCapsule(in window: UIWindow, presenter: UIViewController) {
        let accessory = ScreenshotFeedbackCapsule(onOpen: { [weak self] in self?.openFeedback() },
                                                  onClose: { [weak self] in self?.dismissPrompt() })
        accessory.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(accessory)
        // The keyboard guide belongs to the current controller's content view;
        // a guide on UIWindow itself does not receive the content layout updates.
        let keyboardPosition = accessory.bottomAnchor.constraint(equalTo: presenter.view.keyboardLayoutGuide.topAnchor, constant: -80)
        keyboardPosition.priority = .defaultHigh
        NSLayoutConstraint.activate([
            accessory.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            accessory.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            // Above the tab bar / home indicator, and above an onscreen keyboard.
            keyboardPosition,
            accessory.bottomAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            accessory.topAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
        capsule = accessory
        capsulePresenter = presenter
    }

    private func removeCapsule() {
        capsule?.removeFromSuperview(); capsule = nil
        capsulePresenter = nil
        accessibilityFocusInPrompt = false
    }

    private func dismissPrompt() {
        prompt.dismiss(at: Date())
        refresh()
    }

    private func openFeedback() {
        presentFeedback(initialDescription: "")
    }

    @discardableResult
    private func presentFeedback(initialDescription: String) -> Bool {
        guard let window, window.isKeyWindow, !window.isHidden, !sceneIsInactive,
              window.windowScene?.activationState == .foregroundActive,
              let presenter = Self.feedbackPresenter(in: window), let logs, let accounts,
              feedbackScreens.isEmpty else { discard(); return false }
        prompt.consume(at: Date()); refresh()
        let content = ScreenshotFeedbackSheet(logs: logs, accounts: accounts, initialDescription: initialDescription,
                                              onClose: { [weak self] in self?.closeFeedback() })
            .environmentObject(accounts)
            .environment(\.screenshotFeedbackCoordinator, self)
            .environment(\.requestFeedbackLogin, { [weak self] text in self?.requestLoginFromFeedback(text: text) })
        let controller = UIHostingController(rootView: content)
        feedbackController = controller
        presenter.present(controller, animated: true)
        return true
    }

    func closeFeedback() { feedbackController?.dismiss(animated: true) }

    func requestLoginFromFeedback(text: String) {
        guard let root = window?.rootViewController, let accounts,
              accounts.user == nil, !accounts.isRestoring else { return }
        let generation = accounts.identityGeneration
        let requestID = UUID()
        loginDraft = (requestID, text, generation)
        // Logging in resets the web runtime before the login commit callback.
        // Move this explicit login request to the existing root-owned flow so
        // that reset cannot destroy the login page or its feedback draft.
        root.dismiss(animated: true) { [weak self, weak accounts] in
            guard let self, self.loginDraft?.id == requestID, let accounts, accounts.identityGeneration == generation,
                  accounts.user == nil else { return }
            if self.requestLogin?(text) != true { self.loginDidDismiss() }
        }
    }

    func loginDidDismiss() {
        guard let draft = loginDraft else { return }
        // Successful sign-in resumes through FeedbackLoginCoordinator. A
        // cancelled sign-in returns to the unchanged guest draft instead.
        guard let accounts, accounts.user == nil, accounts.identityGeneration == draft.generation else {
            cancelPendingLogin(); return
        }
        restorationTask?.cancel()
        // UIKit dismissal completion can precede SwiftUI's onDisappear and
        // release of its transition coordinator. Wait for that actual teardown
        // without presenting over a new route or another modal.
        restorationTask = Task { [weak self] in
            for _ in 0..<8 {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, !Task.isCancelled, self.loginDraft?.id == draft.id,
                      let accounts = self.accounts, accounts.user == nil,
                      accounts.identityGeneration == draft.generation else { return }
                if self.presentFeedback(initialDescription: draft.text) {
                    self.loginDraft = nil; self.restorationTask = nil
                    return
                }
            }
            if self?.loginDraft?.id == draft.id { self?.cancelPendingLogin() }
        }
    }
}

private struct ScreenshotFeedbackSheet: View {
    let logs: DiagnosticLogStore
    let accounts: AccountStore
    let initialDescription: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            FeedbackView(logs: logs, accounts: accounts, initialIssueDescription: initialDescription)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成", action: onClose).accessibilityIdentifier("screenshot-feedback.done")
                    }
                }
        }
    }
}

/// Only the capsule's bounds take touches; the rest of the window is untouched.
final class ScreenshotFeedbackCapsule: UIVisualEffectView {
    init(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        super.init(effect: UIBlurEffect(style: .systemMaterial))
        layer.cornerRadius = 24; clipsToBounds = true
        accessibilityIdentifier = "screenshot-feedback.prompt"
        let open = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "反馈问题"
        configuration.image = UIImage(systemName: "bubble.left.and.bubble.right")
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 8)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        open.configuration = configuration
        open.titleLabel?.adjustsFontForContentSizeCategory = true
        open.accessibilityIdentifier = "screenshot-feedback.open"
        open.addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.accessibilityLabel = "关闭截屏反馈提示"
        close.accessibilityHint = "本次使用期间不再提示"
        close.accessibilityIdentifier = "screenshot-feedback.close"
        close.addAction(UIAction { _ in onClose() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [open, close])
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            open.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct ScreenshotFeedbackAnchor: UIViewRepresentable {
    let coordinator: ScreenshotFeedbackCoordinator
    let enabled: Bool
    let logs: DiagnosticLogStore
    let accounts: AccountStore
    let requestLogin: (String) -> Bool

    func makeUIView(context: Context) -> ScreenshotFeedbackAnchorView {
        let view = ScreenshotFeedbackAnchorView()
        view.coordinator = coordinator
        return view
    }

    func updateUIView(_ view: ScreenshotFeedbackAnchorView, context: Context) {
        coordinator.configure(enabled: enabled, logs: logs, accounts: accounts, requestLogin: requestLogin)
        if let window = view.window { coordinator.attach(to: window) }
    }

    static func dismantleUIView(_ view: ScreenshotFeedbackAnchorView, coordinator: ()) {
        view.coordinator?.discard()
        view.coordinator?.cancelPendingLogin()
    }
}

final class ScreenshotFeedbackAnchorView: UIView {
    weak var coordinator: ScreenshotFeedbackCoordinator?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A full-screen UIKit presentation temporarily removes this anchor.
        // Keep the weak window reference until the actual scene is dismantled.
        if let window { coordinator?.attach(to: window) }
    }
}

private struct ScreenshotFeedbackCoordinatorKey: EnvironmentKey {
    static let defaultValue: ScreenshotFeedbackCoordinator? = nil
}

extension EnvironmentValues {
    var screenshotFeedbackCoordinator: ScreenshotFeedbackCoordinator? {
        get { self[ScreenshotFeedbackCoordinatorKey.self] }
        set { self[ScreenshotFeedbackCoordinatorKey.self] = newValue }
    }
}
