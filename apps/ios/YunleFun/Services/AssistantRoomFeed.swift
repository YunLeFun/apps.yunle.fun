import Combine
import Foundation

/// All room cards on the conversation screen consume the same public snapshot.
@MainActor
final class AssistantRoomFeed: ObservableObject {
    enum State: Equatable {
        case loading
        case current([NativePublicRoom])
        case unavailable
    }

    @Published private(set) var state: State = .loading
    private let service: NativePublicRoomServing
    private var watcher: UUID?

    init(service: NativePublicRoomServing) { self.service = service }

    func rooms() async throws -> [NativePublicRoom] {
        do { return try await service.rooms() }
        catch let error as NativePublicRoomError { throw error }
        catch { throw NativePublicRoomError.unavailable }
    }

    func watch() async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        watcher = id
        publish(.loading)
        defer {
            if watcher == id {
                watcher = nil
                publish(.loading)
            }
        }
        var delay: UInt64 = 5
        while !Task.isCancelled && watcher == id {
            do {
                let rooms = try await rooms()
                guard !Task.isCancelled, watcher == id else { return }
                publish(.current(rooms))
                delay = 5
            } catch {
                guard !Task.isCancelled, watcher == id else { return }
                publish(.unavailable)
                delay = min(delay * 2, 30)
            }
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            catch { return }
        }
    }

    private func publish(_ value: State) {
        if state != value { state = value }
    }
}
