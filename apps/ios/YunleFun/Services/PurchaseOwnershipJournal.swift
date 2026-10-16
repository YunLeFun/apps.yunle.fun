import CryptoKit
import Foundation

enum PurchaseAccountToken {
    // An opaque, deterministic UUID v8; no raw uid is sent to the App Store.
    static func forUser(_ uid: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("fun.yunle.apps.iap-owner.v1\0" + uid).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let positions = [0, 8, 12, 16, 20, 32]
        let parts = zip(positions, positions.dropFirst()).map { start, end in
            String(hex[hex.index(hex.startIndex, offsetBy: start)..<hex.index(hex.startIndex, offsetBy: end)])
        }
        return UUID(uuidString: parts.joined(separator: "-"))!
    }
}

actor PurchaseOwnershipJournal {
    struct Binding: Codable, Sendable {
        let uid: String
        let confirmed: Bool
    }
    private struct Envelope: Codable {
        var version = 2
        var owners: [String: Binding] = [:]
    }
    private struct LegacyEnvelope: Codable { let version: Int; let owners: [String: String] }
    let vault: AccountVault
    init(vault: AccountVault = KeychainAccountVault(service: (Bundle.main.bundleIdentifier ?? "fun.yunle.apps") + ".iap-owners")) { self.vault = vault }
    private func read() throws -> Envelope {
        do {
            guard let data = try vault.read() else { return Envelope() }
            let result: Envelope
            if let current = try? JSONDecoder().decode(Envelope.self, from: data), current.version == 2 { result = current }
            else if let legacy = try? JSONDecoder().decode(LegacyEnvelope.self, from: data), legacy.version == 1 {
                // The prototype v1 recorded attempts before verification, so it cannot prove confirmed ownership.
                result = Envelope(owners: legacy.owners.mapValues { Binding(uid: $0, confirmed: false) })
            } else { throw WalletError.storage }
            guard result.owners.count <= 20_000,
                  result.owners.allSatisfy({ !$0.key.isEmpty && !$0.value.uid.isEmpty }) else { throw WalletError.storage }
            return result
        } catch { throw WalletError.storage }
    }
    func prepare() throws {
        do {
            let value = try read()
            guard value.owners.count < 20_000 else { throw WalletError.storage }
            try vault.write(JSONEncoder().encode(value))
        } catch { throw WalletError.storage }
    }
    func owner(of id: String) throws -> String? { try read().owners[id]?.uid }
    func binding(for id: String) throws -> Binding? { try read().owners[id] }
    func bind(_ id: String, to uid: String) throws {
        try writeBinding(id, uid: uid, confirmed: true, allowUnconfirmedReassignment: false)
    }
    func reserve(_ id: String, to uid: String, allowUnconfirmedReassignment: Bool) throws {
        try writeBinding(id, uid: uid, confirmed: false, allowUnconfirmedReassignment: allowUnconfirmedReassignment)
    }
    private func writeBinding(_ id: String, uid: String, confirmed: Bool, allowUnconfirmedReassignment: Bool) throws {
        var envelope = try read()
        guard !uid.isEmpty, id.range(of: #"^[0-9]{1,32}$"#, options: .regularExpression) != nil,
              envelope.owners[id] != nil || envelope.owners.count < 20_000 else { throw WalletError.storage }
        let previous = envelope.owners[id]
        guard previous == nil || previous?.uid == uid || (previous?.confirmed == false && allowUnconfirmedReassignment) else { throw WalletError.forbidden }
        envelope.owners[id] = Binding(uid: uid, confirmed: confirmed || (previous?.uid == uid && previous?.confirmed == true))
        do { try vault.write(JSONEncoder().encode(envelope)) } catch { throw WalletError.storage }
    }
}
