import CryptoKit
import Foundation

/// Durable ownership of named WebKit stores. This file contains identifiers,
/// never website contents or authentication credentials. Missing/corrupt state
/// must not cause the legacy default store to be assigned to a new account.
@MainActor
final class WebProfileRepository {
    enum Principal: Equatable {
        case guest
        case account(String)
    }

    struct Selection: Equatable {
        let identifier: UUID
        fileprivate let owner: String
        fileprivate let application: String
        fileprivate var key: String { owner + "/" + application }
    }

    enum ContinuationDisposition: Equatable {
        /// The account had no store for this application; it owns the former guest store.
        case adopted(Selection)
        /// Keep the account's previous store and retain the continuation separately.
        /// Neither existing drafts nor the live continuation may be overwritten.
        case retained(continuation: Selection, existing: Selection)
    }

    enum Failure: Error, Equatable {
        case invalidIdentity, invalidState, unsupportedVersion, staleSelection
    }

    private struct State: Codable {
        var version = 1
        var active: [String: UUID] = [:]
        var retained: [String: [UUID]] = [:]
    }

    private let fileURL: URL
    private let namespace: String
    private let write: (Data, URL) throws -> Void

    init(fileURL: URL, namespace: String,
         write: @escaping (Data, URL) throws -> Void = { data, url in
             try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
         }) {
        self.fileURL = fileURL
        self.namespace = namespace
        self.write = write
    }

    /// Keys include the identity provider and application trust scope. The
    /// on-disk metadata never contains the raw UID or an authenticated URL.
    func select(_ principal: Principal, application: CloudApplication) throws -> Selection {
        let owner = try ownerKey(principal)
        let app = try applicationKey(application)
        let key = owner + "/" + app
        return try update { state in
            if let identifier = state.active[key] {
                return Selection(identifier: identifier, owner: owner, application: app)
            }
            let identifier = UUID()
            state.active[key] = identifier
            return Selection(identifier: identifier, owner: owner, application: app)
        }
    }

    /// Call only for the broker's accepted guest-login continuation, before
    /// releasing the one-time code. Once bound, a future guest gets a new store.
    /// A stale page cannot take ownership of a newer guest's store.
    func bindGuestContinuation(_ selected: Selection, to accountID: String) throws -> ContinuationDisposition {
        let guest = try ownerKey(.guest)
        let owner = try ownerKey(.account(accountID))
        guard selected.owner == guest else { throw Failure.staleSelection }
        let destination = owner + "/" + selected.application
        return try update { state in
            guard state.active[selected.key] == selected.identifier else { throw Failure.staleSelection }
            state.active.removeValue(forKey: selected.key)
            let continuation = Selection(identifier: selected.identifier, owner: owner, application: selected.application)
            if let existingID = state.active[destination] {
                state.retained[destination, default: []].append(selected.identifier)
                return .retained(continuation: continuation,
                                 existing: Selection(identifier: existingID, owner: owner, application: selected.application))
            }
            state.active[destination] = selected.identifier
            return .adopted(continuation)
        }
    }

    /// Removing a host account can detach its stores without deleting them or
    /// exposing them to the next identity. Reauthentication starts a new store;
    /// retained data requires a separate, explicit recovery flow for its owner.
    func retire(_ accountID: String) throws {
        let prefix = try ownerKey(.account(accountID)) + "/"
        try update { state in
            for key in state.active.keys.filter({ $0.hasPrefix(prefix) }) {
                if let identifier = state.active.removeValue(forKey: key) {
                    state.retained[key, default: []].append(identifier)
                }
            }
        }
    }

    func retained(for principal: Principal, application: CloudApplication) throws -> [Selection] {
        let owner = try ownerKey(principal), app = try applicationKey(application)
        let state = try read()
        return (state.retained[owner + "/" + app] ?? []).map {
            Selection(identifier: $0, owner: owner, application: app)
        }
    }

    private func ownerKey(_ principal: Principal) throws -> String {
        guard !namespace.isEmpty else { throw Failure.invalidIdentity }
        switch principal {
        case .guest: return try digest([namespace, "guest"])
        case .account(let id):
            guard !id.isEmpty, id.trimmingCharacters(in: .whitespacesAndNewlines) == id else {
                throw Failure.invalidIdentity
            }
            return try digest([namespace, "account", id])
        }
    }

    private func applicationKey(_ application: CloudApplication) throws -> String {
        guard !application.id.isEmpty, let url = application.launchURL,
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { throw Failure.invalidIdentity }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return try digest([application.id, application.runtimeScope, scheme, host, String(port)])
    }

    private func digest(_ parts: [String]) throws -> String {
        SHA256.hash(data: try JSONEncoder().encode(parts)).map { String(format: "%02x", $0) }.joined()
    }

    private func read() throws -> State {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return State() }
        let state: State
        do { state = try JSONDecoder().decode(State.self, from: data) }
        catch { throw Failure.invalidState }
        guard state.version == 1 else { throw Failure.unsupportedVersion }
        try validate(state)
        return state
    }

    // Synchronous MainActor transactions reload each time so two repositories
    // in this app process cannot overwrite each other's completed assignments.
    // No in-memory mutation is published before the atomic write succeeds.
    private func update<T>(_ operation: (inout State) throws -> T) throws -> T {
        var state = try read()
        let before = state
        let result = try operation(&state)
        try validate(state)
        if state.active != before.active || state.retained != before.retained {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try write(encoder.encode(state), fileURL)
        }
        return result
    }

    private func validate(_ state: State) throws {
        let keys = Array(state.active.keys) + Array(state.retained.keys)
        guard keys.allSatisfy({ key in
            let parts = key.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { part in
                part.count == 64 && part.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            }
        }) else { throw Failure.invalidState }
        let ids = Array(state.active.values) + state.retained.values.flatMap { $0 }
        guard ids.count == Set(ids).count,
              !ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) else { throw Failure.invalidState }
    }
}
