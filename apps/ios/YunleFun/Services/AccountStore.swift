import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var overview = AccountOverview()
    @Published private(set) var isRestoring = false
    @Published private(set) var notice: String?
    @Published private(set) var identityGeneration = UUID()
    private let session: AccountSession
    private let identityDidChange: (String?) -> Void

    init(session: AccountSession = AccountSession(), identityDidChange: @escaping (String?) -> Void = { _ in }) {
        self.session = session
        self.identityDidChange = identityDidChange
    }

    var user: AccountUser? { overview.activeUser }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        await publish()
        do {
            try await session.restore()
            notice = nil
        } catch is CancellationError { return }
        catch AccountError.sessionChanged { return }
        catch { notice = AccountError.message(for: error) }
        await publish()
    }

    func passwordSignIn(identifier: String, password: String, captcha: String?) async throws {
        try await session.passwordSignIn(identifier: identifier, password: password, captcha: captcha)
        notice = nil
        await publish()
    }

    func sendVerification(address: VerificationAddress, captcha: String?) async throws -> VerificationChallenge {
        try await session.sendVerification(address: address, captcha: captcha)
    }

    func verify(_ challenge: VerificationChallenge, code: String, captcha: String?) async throws {
        try await session.verify(challenge, code: code, captcha: captcha)
        notice = nil
        await publish()
    }

    func cancelSignIn() async { await session.cancelSignIn() }

    func authorization(forceRefresh: Bool = false) async throws -> AuthorizedAccount {
        do {
            let identity = try await session.authorization(forceRefresh: forceRefresh)
            await publish()
            guard user?.id == identity.userID else { throw AccountError.sessionChanged }
            return identity
        } catch {
            await publish()
            throw error
        }
    }

    func select(_ id: String) async throws {
        try await session.select(id)
        await publish()
        await restore()
    }

    func remove(_ id: String) async throws {
        let revocation = try await session.remove(id)
        // Clear private data and close identity-bound WebViews immediately;
        // a slow/offline remote sign-out must not delay the local transition.
        await publish()
        let revoked = await revocation.value
        notice = revoked ? nil : "已在此设备退出，暂时未能同步退出状态。"
    }

    func updateProfile(name: String, description: String) async throws {
        do {
            try await session.updateProfile(name: name, description: description)
            await publish()
        } catch {
            await publish()
            throw error
        }
    }

    func captcha() async throws -> CaptchaImage { try await session.captcha() }
    func verifyCaptcha(token: String, text: String) async throws -> String {
        try await session.verifyCaptcha(token: token, text: text)
    }

    private func publish() async {
        do {
            let next = try await session.overview()
            guard next.revision >= overview.revision else { return }
            if next.activeID != overview.activeID {
                identityGeneration = UUID()
                identityDidChange(next.activeID)
            }
            overview = next
        } catch { notice = AccountError.message(for: error) }
    }
}
