import Foundation

actor AccountSession {
    private let api: AccountAuthenticating
    private let vault: AccountVault
    private let now: @Sendable () -> Date
    private var state: AccountVaultState?
    private var dirty = false
    private var revision = 0
    private var selectionGeneration = 0
    private var signInAttempt: UUID?
    private var refreshes: [String: RefreshFlight] = [:]

    private struct RefreshFlight {
        let id: UUID
        let original: AccountCredential
        let task: Task<AuthTokenResponse, Error>
    }

    init(api: AccountAuthenticating = CloudbaseAuthService(), vault: AccountVault = KeychainAccountVault(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.vault = vault
        self.now = now
    }

    func overview() throws -> AccountOverview {
        let current = try load()
        return AccountOverview(revision: revision, users: current.accounts.map(\.user), activeID: current.activeID)
    }

    func overview(matching commit: AccountSignInCommit) throws -> AccountOverview {
        let current = try load()
        guard current.activeID == commit.userID, selectionGeneration == commit.selectionGeneration else {
            throw AccountError.sessionChanged
        }
        return AccountOverview(revision: revision, users: current.accounts.map(\.user), activeID: current.activeID)
    }

    func restore() async throws {
        guard try load().activeID != nil else { return }
        try await refreshProfile()
    }

    @discardableResult
    func passwordSignIn(identifier: String, password: String, captcha: String?,
                        attemptID: UUID = UUID()) async throws -> AccountSignInCommit {
        try Task.checkCancellation()
        signInAttempt = attemptID
        let deviceID = try requestDeviceID()
        let response = try await api.passwordSignIn(identifier: identifier, password: password, deviceID: deviceID, captcha: captcha)
        return try await accept(response, attempt: attemptID, deviceID: deviceID)
    }

    func sendVerification(address: VerificationAddress, captcha: String?) async throws -> VerificationChallenge {
        try await api.sendVerification(address: address, deviceID: requestDeviceID(), captcha: captcha)
    }

    @discardableResult
    func verify(_ challenge: VerificationChallenge, code: String, captcha: String?,
                attemptID: UUID = UUID()) async throws -> AccountSignInCommit {
        try Task.checkCancellation()
        signInAttempt = attemptID
        let deviceID = try requestDeviceID()
        let response = try await api.verify(challenge, code: code, deviceID: deviceID, captcha: captcha)
        return try await accept(response, attempt: attemptID, deviceID: deviceID)
    }

    func cancelSignIn(attemptID: UUID? = nil) {
        if let attemptID, signInAttempt != attemptID { return }
        signInAttempt = nil
    }

    func authorization(forceRefresh: Bool = false) async throws -> AuthorizedAccount {
        let current = try load()
        try flush()
        guard let id = current.activeID, let account = current.accounts.first(where: { $0.user.id == id }) else {
            throw AccountError.signedOut
        }
        let generation = selectionGeneration
        let credential = forceRefresh || account.credential.expiresAt <= now().addingTimeInterval(60)
            ? try await refresh(account) : account.credential
        try Task.checkCancellation()
        guard try load().activeID == id, generation == selectionGeneration else { throw AccountError.sessionChanged }
        try flush()
        return AuthorizedAccount(userID: id, accessToken: credential.accessToken)
    }

    func select(_ id: String) throws {
        var proposed = try load()
        guard proposed.accounts.contains(where: { $0.user.id == id }) else { throw AccountError.signedOut }
        guard proposed.activeID != id else { return }
        proposed.activeID = id
        try commit(proposed)
        signInAttempt = nil
        selectionGeneration += 1
    }

    /// Local removal is authoritative and completes before remote revocation.
    /// The returned task contains no credentials in its public result.
    func remove(_ id: String) throws -> Task<Bool, Never> {
        var proposed = try load()
        guard let account = proposed.accounts.first(where: { $0.user.id == id }) else {
            throw AccountError.signedOut
        }
        proposed.accounts.removeAll { $0.user.id == id }
        if proposed.activeID == id { proposed.activeID = nil }
        try commit(proposed)
        signInAttempt = nil
        selectionGeneration += 1
        let api = api
        let deviceID = proposed.deviceID
        return Task {
            do {
                try await api.signOut(accessToken: account.credential.accessToken, deviceID: deviceID)
                return true
            } catch { return false }
        }
    }

    func refreshProfile() async throws {
        let generation = selectionGeneration
        var identity = try await authorization()
        let deviceID = try requestDeviceID()
        let user: AccountUser
        do {
            user = try await api.user(accessToken: identity.accessToken, deviceID: deviceID)
        } catch AccountError.expiredSession {
            try requireCurrent(identity, generation: generation)
            identity = try await authorization(forceRefresh: true)
            do { user = try await api.user(accessToken: identity.accessToken, deviceID: deviceID) }
            catch AccountError.expiredSession {
                try requireCurrent(identity, generation: generation)
                try invalidate(identity.userID)
                throw AccountError.expiredSession
            }
        }
        try requireCurrent(identity, generation: generation)
        guard user.id == identity.userID else { throw AccountError.invalidResponse }
        guard user.isUsable else {
            try invalidate(identity.userID)
            throw AccountError.blockedAccount
        }
        var proposed = try load()
        guard proposed.activeID == identity.userID,
              let index = proposed.accounts.firstIndex(where: { $0.user.id == identity.userID }) else { throw AccountError.sessionChanged }
        proposed.accounts[index].user = user
        try commit(proposed)
    }

    func updateProfile(name: String, description: String) async throws {
        let generation = selectionGeneration
        let identity = try await authorization()
        try requireCurrent(identity, generation: generation)
        try await api.updateProfile(userID: identity.userID, name: name, description: description,
                                    accessToken: identity.accessToken, deviceID: requestDeviceID())
        try requireCurrent(identity, generation: generation)
        try await refreshProfile()
    }

    func captcha() async throws -> CaptchaImage { try await api.captcha(deviceID: requestDeviceID()) }
    func verifyCaptcha(token: String, text: String) async throws -> String {
        try await api.verifyCaptcha(token: token, text: text, deviceID: requestDeviceID())
    }

    private func accept(_ response: AuthTokenResponse, attempt: UUID, deviceID: String) async throws -> AccountSignInCommit {
        guard signInAttempt == attempt else { throw AccountError.sessionChanged }
        let credential = try response.credential(at: now())
        let user = try await api.user(accessToken: credential.accessToken, deviceID: deviceID)
        try Task.checkCancellation()
        guard signInAttempt == attempt else { throw AccountError.sessionChanged }
        guard user.id == response.subject else { throw AccountError.invalidResponse }
        guard user.isUsable else { throw AccountError.blockedAccount }
        var proposed = try load()
        proposed.accounts.removeAll { $0.user.id == user.id }
        proposed.accounts.insert(SavedAccount(user: user, credential: credential), at: 0)
        proposed.activeID = user.id
        try commit(proposed)
        signInAttempt = nil
        selectionGeneration += 1
        return AccountSignInCommit(attemptID: attempt, userID: user.id, selectionGeneration: selectionGeneration)
    }

    private func refresh(_ account: SavedAccount) async throws -> AccountCredential {
        let id = account.user.id
        let flight: RefreshFlight
        if let existing = refreshes[id] { flight = existing }
        else {
            let api = api
            let deviceID = try requestDeviceID()
            let token = account.credential.refreshToken
            flight = RefreshFlight(id: UUID(), original: account.credential,
                                   task: Task { try await api.refresh(token, deviceID: deviceID) })
            refreshes[id] = flight
        }
        do {
            let response = try await flight.task.value
            var proposed = try load()
            guard let index = proposed.accounts.firstIndex(where: { $0.user.id == id }) else { throw AccountError.signedOut }
            // Another waiter may already have saved this rotation, or a new
            // login may have replaced the account while the request was running.
            if proposed.accounts[index].credential != flight.original { return proposed.accounts[index].credential }
            guard refreshes[id]?.id == flight.id else { throw AccountError.sessionChanged }
            guard response.subject == id else { throw AccountError.invalidResponse }
            let credential = try response.credential(at: now())
            proposed.accounts[index].credential = credential
            refreshes[id] = nil
            // The server has consumed the previous refresh token. Keep the new
            // value in memory even if Keychain is temporarily unavailable, and
            // require a successful retry of persistence before returning it.
            try commit(proposed, retainingOnFailure: true)
            return credential
        } catch {
            if refreshes[id]?.id == flight.id { refreshes[id] = nil }
            if error as? AccountError == .expiredSession || error as? AccountError == .blockedAccount,
               try load().accounts.first(where: { $0.user.id == id })?.credential == flight.original {
                try invalidate(id)
            }
            throw error
        }
    }

    private func invalidate(_ id: String) throws {
        var proposed = try load()
        proposed.accounts.removeAll { $0.user.id == id }
        if proposed.activeID == id { proposed.activeID = nil; selectionGeneration += 1 }
        try commit(proposed, retainingOnFailure: true)
    }

    private func requireCurrent(_ identity: AuthorizedAccount, generation: Int) throws {
        let current = try load()
        guard selectionGeneration == generation, current.activeID == identity.userID,
              current.accounts.first(where: { $0.user.id == identity.userID })?.credential.accessToken == identity.accessToken
        else { throw AccountError.sessionChanged }
    }

    private func load() throws -> AccountVaultState {
        if let state { return state }
        let data = try vault.read()
        let loaded: AccountVaultState
        if let data {
            do { loaded = try JSONDecoder().decode(AccountVaultState.self, from: data) }
            catch { throw AccountError.unsupportedVault }
            let ids = loaded.accounts.map(\.user.id)
            guard loaded.version == 1, UUID(uuidString: loaded.deviceID) != nil,
                  Set(ids).count == ids.count,
                  loaded.accounts.allSatisfy({ $0.user.isUsable && !$0.credential.accessToken.isEmpty && !$0.credential.refreshToken.isEmpty }),
                  loaded.activeID == nil || ids.contains(loaded.activeID!) else { throw AccountError.unsupportedVault }
        } else { loaded = AccountVaultState(); dirty = true }
        state = loaded
        revision += 1
        return loaded
    }

    private func requestDeviceID() throws -> String {
        let loaded = try load()
        try flush()
        return loaded.deviceID
    }

    private func commit(_ proposed: AccountVaultState, retainingOnFailure: Bool = false) throws {
        if retainingOnFailure {
            state = proposed
            dirty = true
            revision += 1
            try flush()
        } else {
            try vault.write(JSONEncoder().encode(proposed))
            state = proposed
            dirty = false
            revision += 1
        }
    }

    private func flush() throws {
        guard dirty, let state else { return }
        try vault.write(JSONEncoder().encode(state))
        dirty = false
    }
}
