import Combine
import Foundation

@MainActor
final class DeveloperProfileStore: ObservableObject {
    @Published private(set) var profile: DeveloperProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let service: DeveloperProfileServing
    private var requestedLogin: String?
    private var operationID = UUID()

    init(service: DeveloperProfileServing = DeveloperProfileService()) { self.service = service }

    func refresh(login: String) async {
        let operation = UUID()
        operationID = operation
        guard let login = DeveloperProfile.normalizedLogin(login) else {
            requestedLogin = nil; profile = nil; isLoading = false; error = DeveloperProfileError.invalidLogin.message
            return
        }
        if requestedLogin?.lowercased() != login.lowercased() { profile = nil }
        requestedLogin = login; isLoading = true; error = nil
        defer { if operationID == operation { isLoading = false } }
        do {
            let result = try await service.profile(login: login)
            guard operationID == operation, !Task.isCancelled else { return }
            profile = result
        } catch is CancellationError {
            return
        } catch let issue as URLError where issue.code == .cancelled {
            return
        } catch {
            guard operationID == operation, !Task.isCancelled else { return }
            self.error = (error as? DeveloperProfileError)?.message ?? DeveloperProfileError.unavailable.message
        }
    }

    func cancel() { operationID = UUID(); isLoading = false }
}
