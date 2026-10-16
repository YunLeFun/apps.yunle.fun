import Foundation
import Security
import XCTest
@testable import YunleFun

/// Explicit, opt-in integration suite. Passwords are read once from an owner-only
/// simulator cache file and never appear in launch arguments or test attachments.
@MainActor
final class ManagedAccountLiveTests: XCTestCase {
    func testManagedLoginRefreshSwitchWalletAndSignOut() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_FIXED_ACCOUNTS"] == "1" else {
            throw XCTSkip("Requires an explicitly provisioned managed synthetic account pool")
        }
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iOSNativeValidation/test-accounts.json")
        let data = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let expected = ["production-standard": "ylf_prod_standard",
                        "production-member-active": "ylf_prod_member",
                        "production-zero-balance": "ylf_prod_zero"]
        let credentials = pool.accounts.filter { expected[$0.id] != nil }
        guard credentials.count == 3, Set(credentials.map(\.id)).count == 3,
              credentials.allSatisfy({ $0.environment == "production" && $0.username == expected[$0.id] && !$0.password.isEmpty })
        else { return XCTFail("The managed account pool does not match the allowed synthetic identities") }

        let service = "fun.yunle.apps.live-validation." + UUID().uuidString
        let vault = KeychainAccountVault(service: service)
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let session = AccountSession(vault: vault)
        let accounts = AccountStore(session: session)
        var identities: [String: String] = [:]
        var evidence: [[String: Any]] = []
        do {
            for credential in credentials.sorted(by: { $0.id < $1.id }) {
                try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
                let user = try XCTUnwrap(accounts.user)
                guard user.username == credential.username, user.isUsable else { throw LiveFailure.identity }
                identities[credential.id] = user.id
                let identity = try await accounts.authorization(forceRefresh: true)
                guard identity.userID == user.id else { throw LiveFailure.identity }
                let wallet = try await WalletService().account(identity: identity)
                if credential.id == "production-member-active" {
                    guard wallet.membership.isActive, (wallet.membership.expiration ?? .distantPast) > Date() else { throw LiveFailure.wallet }
                } else if wallet.membership.isActive { throw LiveFailure.wallet }
                if credential.id == "production-zero-balance", wallet.coin != 0 { throw LiveFailure.wallet }
                let ledger = try await WalletService().transactions(skip: 0, limit: 10, identity: identity)
                if credential.id == "production-member-active" {
                    let assistant = AssistantStore(accounts: accounts)
                    assistant.draft = "推荐几个开发工具"
                    await assistant.send()?.value
                    guard assistant.error == nil, !assistant.running,
                          assistant.messages.last?.status == .done,
                          !(assistant.messages.last?.content.isEmpty ?? true) else {
                        if let message = assistant.error { XCTFail("Native assistant returned: \(message)") }
                        throw LiveFailure.assistant
                    }
                    let catalog = try await CatalogService().applications()
                    guard assistant.messages.flatMap(\.cards).allSatisfy({ $0.resolve(in: catalog) != nil }) else { throw LiveFailure.assistant }
                    evidence.append(["account": credential.id, "nativeAssistantStream": true,
                                     "resolvedCards": assistant.messages.flatMap(\.cards).count])
                }
                evidence.append(["account": credential.id, "passwordLogin": true, "refresh": true,
                                 "coin": wallet.coin, "memberActive": wallet.membership.isActive,
                                 "ledgerRead": true, "ledgerItems": ledger.items.count])
            }
            guard Set(identities.values).count == 3 else { throw LiveFailure.identity }
            for id in expected.keys.sorted() {
                guard let uid = identities[id] else { throw LiveFailure.identity }
                try await accounts.select(uid)
                guard accounts.user?.id == uid, accounts.notice == nil else { throw LiveFailure.restore }
            }
            let restored = AccountStore(session: AccountSession(vault: vault))
            await restored.restore()
            guard restored.notice == nil, restored.overview.users.count == 3,
                  restored.user?.id == accounts.user?.id else { throw LiveFailure.restore }
            for uid in identities.values {
                try await restored.remove(uid)
                guard restored.notice == nil else { throw LiveFailure.signOut }
            }
            let empty = AccountStore(session: AccountSession(vault: vault))
            await empty.restore()
            guard empty.user == nil, empty.overview.users.isEmpty else { throw LiveFailure.signOut }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
                "accounts": evidence, "keychainRestore": true, "accountSwitch": true, "remoteSignOut": true,
                "signedOutRestart": true, "realPayments": false,
            ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "managed-accounts-live-validation"; attachment.lifetime = .keepAlways; add(attachment)
        } catch {
            // Revoke only sessions created by this test. No auth responses or
            // credentials are interpolated into diagnostics.
            for user in accounts.overview.users { try? await accounts.remove(user.id) }
            if let failure = error as? LiveFailure { XCTFail("Managed integration stage failed: \(failure)") }
            else if let failure = error as? AccountError { XCTFail("Native auth failed: \(failure)") }
            else if let failure = error as? WalletError { XCTFail("Native wallet failed: \(failure)") }
            else { XCTFail("Managed integration failed; response contents intentionally omitted") }
        }
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private enum LiveFailure: Error { case identity, wallet, restore, signOut, assistant }
}
