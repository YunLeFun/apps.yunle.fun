import Foundation

/// Tracks the invitation only; it never captures a screenshot or submits feedback.
struct ScreenshotFeedbackPromptState {
    static let preferenceKey = "feedback.screenshotPromptEnabled"

    private(set) var enabled: Bool
    private(set) var suppressedForSession = false

    private struct Pending {
        let receivedAt: Date
        var remaining: TimeInterval = 8
        var visibleSince: Date?
    }

    private var pending: Pending?
    private var cooldownUntil: Date?

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    var hasPending: Bool { pending != nil }
    var isVisible: Bool { pending?.visibleSince != nil }

    func visibleTimeRemaining(at date: Date) -> TimeInterval {
        guard let pending else { return 0 }
        let elapsed = pending.visibleSince.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, pending.remaining - elapsed)
    }

    mutating func receive(at date: Date) {
        advance(at: date)
        guard enabled, !suppressedForSession, pending == nil,
              cooldownUntil.map({ date >= $0 }) ?? true else { return }
        pending = Pending(receivedAt: date)
    }

    mutating func present(at date: Date) {
        advance(at: date)
        guard pending != nil, pending?.visibleSince == nil else { return }
        pending?.visibleSince = date
    }

    mutating func suspend(at date: Date) {
        advance(at: date)
        guard let current = pending, current.visibleSince != nil else { return }
        let remaining = visibleTimeRemaining(at: date)
        pending?.remaining = remaining
        pending?.visibleSince = nil
    }

    mutating func advance(at date: Date) {
        guard let pending else { return }
        if date.timeIntervalSince(pending.receivedAt) >= 120 || visibleTimeRemaining(at: date) <= 0 {
            consume(at: date)
        }
    }

    mutating func dismiss(at date: Date) {
        // An explicit close applies to this process, without changing the saved preference.
        advance(at: date)
        suppressedForSession = true
        pending = nil
    }

    mutating func consume(at date: Date) {
        pending = nil
        cooldownUntil = date.addingTimeInterval(30)
    }

    mutating func setEnabled(_ value: Bool) {
        if value && !enabled { suppressedForSession = false }
        enabled = value
        if !value { pending = nil }
    }

    mutating func discard() {
        pending = nil
    }
}
