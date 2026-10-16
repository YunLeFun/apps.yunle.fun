import SwiftUI
import UIKit

@MainActor
final class NativeAuthorizationPage: HostAuthorizationPage {
    weak var browser: WebViewController?
    private weak var accounts: AccountStore?
    private weak var modal: UIViewController?

    init(browser: WebViewController, accounts: AccountStore) {
        self.browser = browser; self.accounts = accounts
    }
    func isPending(_ requestID: String) -> Bool { browser?.authorizationEvent(requestId: requestID) != nil }
    func pause(_ requestID: String) -> Bool { browser?.pauseAuthorizationTimeout(requestId: requestID) == true }
    func resume(_ requestID: String) -> Bool { browser?.resumeAuthorizationTimeout(requestId: requestID) == true }
    func resolve(_ requestID: String, result: [String: Any]?, error: String?) {
        browser?.resolveAuthorization(requestId: requestID, result: result, error: error)
    }
    func useOtherAccount(_ requestID: String) -> Bool { browser?.beginOtherAccountAuthorization(requestId: requestID) == true }

    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard let browser = presenter, let accounts else { return false }
        let controller = HostLoginController(accounts: accounts, application: application) { [weak self] result in
            self?.modal = nil
            completion(result)
        }
        modal = controller
        browser.present(controller, animated: true)
        return true
    }

    func showConsent(policy: HostSsoPolicy, user: AccountUser,
                     completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        guard let browser = presenter else { return false }
        let controller = AuthorizationConsentViewController(content: AuthorizationSheetContent(
            applicationName: policy.applicationName, applicationOrigin: policy.applicationOrigin,
            applicationIconURL: policy.applicationIconURL, accountName: user.displayName,
            accountAvatarURL: user.picture, permissionDescription: policy.permissionDescription,
            authorizationNotice: nil
        )) { [weak self] choice in
            self?.modal = nil
            completion(choice)
        }
        if let presentation = controller.sheetPresentationController {
            configureAuthorizationConsentPresentation(presentation,
                                                       contentSizeCategory: browser.traitCollection.preferredContentSizeCategory)
        }
        modal = controller
        browser.present(controller, animated: true)
        return true
    }
    func dismissAuthorizationUI() {
        if let consent = modal as? AuthorizationConsentViewController { consent.expire() }
        else { modal?.dismiss(animated: false) }
        modal = nil
    }
    private var presenter: WebViewController? {
        guard let browser, browser.viewIfLoaded?.window != nil, browser.presentedViewController == nil,
              !browser.isBeingDismissed, !browser.isBeingPresented else { return nil }
        return browser
    }
}

private struct HostLoginContent: View {
    @ObservedObject var accounts: AccountStore
    let application: String
    let signedIn: () -> Void
    var body: some View {
        LoginView(authorizationApplication: application, onSignedIn: signedIn)
            .environmentObject(accounts)
    }
}

@MainActor
private final class HostLoginController: UIHostingController<HostLoginContent>, UIAdaptivePresentationControllerDelegate {
    private final class Decision { var signedIn = false }
    private let decision: Decision
    private let completion: (Bool) -> Void
    private var completed = false
    init(accounts: AccountStore, application: String, completion: @escaping (Bool) -> Void) {
        let decision = Decision()
        self.decision = decision; self.completion = completion
        super.init(rootView: HostLoginContent(accounts: accounts, application: application,
                                             signedIn: { decision.signedIn = true }))
        modalPresentationStyle = .pageSheet
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { finish() }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
    private func finish() {
        guard !completed else { return }
        completed = true
        completion(decision.signedIn)
    }
}
