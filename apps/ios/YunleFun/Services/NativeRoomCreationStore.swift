import Combine
import CryptoKit
import Foundation

@MainActor
final class NativeRoomCreationStore: ObservableObject {
    @Published private(set) var operation: NativeRoomCreationOperation?
    @Published private(set) var isCreating = false
    @Published private(set) var error: String?
    @Published private(set) var needsConsent = false
    private let access: AccountRequestAccess<NativeRoomCreationError>
    private let boundary: AccountRequestBoundary
    private let service: NativeRoomCreating
    private let defaults: UserDefaults
    private let journalKey: String

    init(accounts: IdentityScopedAccountAuthorizing, service: NativeRoomCreating = NativeRoomCreationService(), defaults: UserDefaults = .standard) {
        access = AccountRequestAccess(accounts: accounts); boundary = access.boundary
        self.service = service; self.defaults = defaults
        let scope = SHA256.hash(data: Data((boundary.uid ?? "guest").utf8)).map { String(format: "%02x", $0) }.joined()
        journalKey = "games.roomCreation.v1." + scope
        if let data = defaults.data(forKey: journalKey), data.count <= 4096,
           let value = try? JSONDecoder().decode(NativeRoomCreationOperation.self, from: data),
           (try? value.draft.payload()) != nil,
           value.inviteCode.map({ (try? NativeGameRoomIntent(input: $0)) != nil }) ?? true { operation = value }
    }

    func create(_ draft: NativeRoomCreationDraft, consent: Bool = false) async -> NativeGameRoomIntent? {
        guard !isCreating, access.isCurrent(boundary), boundary.uid != nil else { return nil }
        if let code = operation?.inviteCode { return try? NativeGameRoomIntent(input: code) }
        if operation == nil {
            guard (try? draft.payload()) != nil else { error = NativeRoomCreationError.invalidInput.localizedDescription; return nil }
            operation = .init(key: UUID(), draft: draft)
            save()
        }
        guard let operation else { return nil }
        isCreating = true; error = nil; needsConsent = false
        defer { isCreating = false }
        do {
            let room = try await access.perform(boundary: boundary) { identity in
                try await service.create(operation.draft, key: operation.key, identity: identity, consent: consent,
                    isCurrent: { [access, boundary] in await MainActor.run { access.isCurrent(boundary) } })
            }
            self.operation?.inviteCode = room.inviteCode; save()
            return room
        } catch {
            guard access.isCurrent(boundary), !Task.isCancelled else { return nil }
            needsConsent = error as? NativeRoomCreationError == .consentRequired
            self.error = (error as? NativeRoomCreationError)?.localizedDescription ?? NativeRoomCreationError.unavailable.localizedDescription
            return nil
        }
    }

    func startAnother() {
        guard !isCreating, operation?.inviteCode != nil, access.isCurrent(boundary) else { return }
        operation = nil; error = nil; needsConsent = false; defaults.removeObject(forKey: journalKey)
    }
    private func save() { if let operation, let data = try? JSONEncoder().encode(operation) { defaults.set(data, forKey: journalKey) } }
}
