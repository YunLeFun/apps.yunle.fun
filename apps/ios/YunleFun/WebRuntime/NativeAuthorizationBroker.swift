import Foundation

@MainActor
protocol HostAuthorizationPage: AnyObject {
    func isPending(_ requestID: String) -> Bool
    func pause(_ requestID: String) -> Bool
    func resume(_ requestID: String) -> Bool
    func resolve(_ requestID: String, result: [String: Any]?, error: String?)
    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool
    func showConsent(policy: HostSsoPolicy, user: AccountUser, completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool
    func dismissAuthorizationUI()
    func useOtherAccount(_ requestID: String) -> Bool
}

/// Coordinates a single user decision. All async work is tied to both the
/// originating document's pending request and the selected host account.
@MainActor
final class NativeAuthorizationBroker {
    private enum Phase { case resolving, login, consent, issuing }
    private final class Flow {
        let id = UUID()
        let requestID: String
        let request: HostSsoRequest
        let page: HostAuthorizationPage
        var accountID: String?
        var phase = Phase.resolving
        var waitingForCookies = false
        var loginFinished = false
        var operation: Task<Void, Never>?
        var timeout: DispatchWorkItem?
        init(requestID: String, request: HostSsoRequest, page: HostAuthorizationPage, accountID: String?) {
            self.requestID = requestID; self.request = request; self.page = page; self.accountID = accountID
        }
    }
    private weak var accounts: AccountAuthorizing?
    private let service: HostAuthorizationServing
    private var activeAccountID: String?
    private var flow: Flow?
    private let decisionTimeout: TimeInterval

    init(accounts: AccountAuthorizing, service: HostAuthorizationServing = HostAuthorizationService(),
         decisionTimeout: TimeInterval = 300) {
        self.accounts = accounts; self.service = service
        activeAccountID = accounts.user?.id
        self.decisionTimeout = decisionTimeout
    }
    deinit { flow?.operation?.cancel(); flow?.timeout?.cancel() }

    func begin(requestID: String, sourceOrigin: String, parameters: [String: Any], page: HostAuthorizationPage) {
        guard flow == nil, page.isPending(requestID) else {
            page.resolve(requestID, result: nil, error: HostAuthorizationError.unavailable.code)
            return
        }
        do {
            let request = try HostSsoRequest(sourceOrigin: sourceOrigin, parameters: parameters)
            let next = Flow(requestID: requestID, request: request, page: page, accountID: accounts?.user?.id)
            flow = next
            run(next, requireConsent: false)
        } catch {
            page.resolve(requestID, result: nil, error: HostAuthorizationError.invalidRequest.code)
        }
    }

    /// Only the explicitly awaited guest-to-login continuation can survive.
    /// Switching or leaving any authenticated identity cancels every flow.
    func identityWillChange(to id: String?) -> HostAuthorizationPage? {
        let previous = activeAccountID
        activeAccountID = id
        guard let current = flow else { return nil }
        if previous == nil, let id, current.accountID == nil,
           current.phase == .login, current.page.isPending(current.requestID) {
            current.accountID = id
            current.waitingForCookies = true
            return current.page
        }
        finish(current, error: .denied)
        return nil
    }

    func identityCookiesCleared() {
        guard let current = flow, current.waitingForCookies else { return }
        current.waitingForCookies = false
        resumeAfterLoginIfReady(current)
    }

    func cancel(page: HostAuthorizationPage) {
        guard let current = flow, current.page === page else { return }
        finish(current, error: .denied)
    }

    private func run(_ current: Flow, requireConsent: Bool) {
        current.phase = .resolving
        arm(current, seconds: 30)
        current.operation = Task { [weak self] in
            guard let self else { return }
            do {
                let policy = try await self.service.resolve(current.request)
                try self.ensureCurrent(current)
                if policy.prompt == "select_account" {
                    self.otherAccount(current)
                    return
                }
                guard let user = self.accounts?.user else {
                    self.login(current, application: policy.applicationName)
                    return
                }
                guard user.isUsable, user.id == current.accountID else { throw HostAuthorizationError.expired }
                if requireConsent || policy.prompt == "consent" {
                    self.consent(current, policy: policy, user: user)
                } else {
                    await self.issue(current)
                }
            } catch {
                self.finishIfCurrent(current, error: error as? HostAuthorizationError ?? .unavailable)
            }
        }
    }

    private func login(_ current: Flow, application: String) {
        guard current.accountID == nil, current.page.pause(current.requestID) else {
            finish(current, error: .expired); return
        }
        current.phase = .login
        arm(current, seconds: decisionTimeout)
        let shown = current.page.showLogin(application: application) { [weak self] succeeded in
            guard let self, self.flow === current else { return }
            guard succeeded else { self.finish(current, error: .denied); return }
            current.loginFinished = true
            self.resumeAfterLoginIfReady(current)
        }
        if !shown { finish(current, error: .unavailable) }
    }

    private func resumeAfterLoginIfReady(_ current: Flow) {
        guard flow === current, current.phase == .login, current.loginFinished, !current.waitingForCookies else { return }
        guard let id = current.accountID, accounts?.user?.id == id,
              current.page.resume(current.requestID) else { finish(current, error: .expired); return }
        // Re-resolve the registry after a potentially long login, and require a
        // separate explicit decision even for a normally trusted client.
        run(current, requireConsent: true)
    }

    private func consent(_ current: Flow, policy: HostSsoPolicy, user: AccountUser) {
        guard current.page.pause(current.requestID) else { finish(current, error: .expired); return }
        current.phase = .consent
        arm(current, seconds: decisionTimeout)
        let shown = current.page.showConsent(policy: policy, user: user) { [weak self] choice in
            guard let self, self.flow === current else { return }
            guard current.page.resume(current.requestID) else { self.finish(current, error: .expired); return }
            switch choice {
            case .cancel: self.finish(current, error: .denied)
            case .other: self.otherAccount(current)
            case .current:
                arm(current, seconds: 30)
                current.operation = Task { [weak self] in await self?.issue(current) }
            }
        }
        if !shown { finish(current, error: .unavailable) }
    }

    private func issue(_ current: Flow) async {
        do {
            try ensureCurrent(current)
            guard let accounts, let uid = current.accountID, accounts.user?.id == uid else { throw HostAuthorizationError.expired }
            current.phase = .issuing
            var identity = try await accounts.authorization(forceRefresh: false)
            try ensureCurrent(current)
            guard identity.userID == uid, accounts.user?.id == uid else { throw HostAuthorizationError.expired }
            let code: HostSsoCode
            do { code = try await service.issue(current.request, identity: identity) }
            catch HostAuthorizationError.unauthorized {
                try ensureCurrent(current)
                identity = try await accounts.authorization(forceRefresh: true)
                try ensureCurrent(current)
                guard identity.userID == uid, accounts.user?.id == uid else { throw HostAuthorizationError.expired }
                code = try await service.issue(current.request, identity: identity)
            }
            try ensureCurrent(current)
            guard accounts.user?.id == uid else { throw HostAuthorizationError.expired }
            clear(current)
            current.page.resolve(current.requestID, result: code.pageResult, error: nil)
        } catch {
            finishIfCurrent(current, error: error as? HostAuthorizationError ?? .unavailable)
        }
    }

    private func otherAccount(_ current: Flow) {
        guard current.page.isPending(current.requestID), current.page.useOtherAccount(current.requestID) else {
            finish(current, error: .unavailable); return
        }
        // ASWebAuthenticationSession owns its own state, cancellation and
        // callback validation. The host's stored account is not switched.
        clear(current)
    }
    private func ensureCurrent(_ current: Flow) throws {
        guard flow === current, !Task.isCancelled, current.page.isPending(current.requestID),
              accounts?.user?.id == current.accountID else { throw HostAuthorizationError.expired }
    }
    private func arm(_ current: Flow, seconds: TimeInterval) {
        current.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak current] in
            guard let current else { return }
            self?.finishIfCurrent(current, error: .expired)
        }
        current.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }
    private func clear(_ current: Flow) {
        guard flow === current else { return }
        flow = nil
        current.timeout?.cancel()
        current.operation?.cancel()
        current.timeout = nil
        current.operation = nil
    }
    private func finishIfCurrent(_ current: Flow, error: HostAuthorizationError) {
        guard flow === current else { return }
        finish(current, error: error)
    }
    private func finish(_ current: Flow, error: HostAuthorizationError) {
        clear(current)
        current.page.dismissAuthorizationUI()
        current.page.resolve(current.requestID, result: nil, error: error.code)
    }
}
