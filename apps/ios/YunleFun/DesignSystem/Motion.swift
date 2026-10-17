import SwiftUI
import UIKit

/// Shared motion vocabulary. Curves stay short and critically damped so state
/// changes read as confirmation rather than decoration. With Reduce Motion on,
/// every curve becomes a plain cross-fade: the change stays visible, nothing
/// slides, scales or zooms.
enum Motion {
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.72)
    static let fade = Animation.easeInOut(duration: 0.2)

    static func standard(reduceMotion: Bool) -> Animation { reduceMotion ? fade : spring }

    /// Grid items grow in from their own position; Reduce Motion keeps opacity only.
    static func appear(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }
}

/// Feedback that pairs with a visible state change. iOS 17+ uses the system
/// sensory feedback API (it already honours the user's haptics setting); iOS 16
/// falls back to the matching UIKit generator.
enum Haptic {
    case success, warning, selection, impact

    @available(iOS 17, *)
    fileprivate var sensory: SensoryFeedback {
        switch self {
        case .success: return .success
        case .warning: return .warning
        case .selection: return .selection
        case .impact: return .impact(weight: .light)
        }
    }

    fileprivate func play() {
        switch self {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .impact: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

extension View {
    /// Plays `haptic` whenever `trigger` changes and `condition(old, new)` holds.
    @ViewBuilder
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T,
                              condition: @escaping (T, T) -> Bool = { _, _ in true }) -> some View {
        if #available(iOS 17, *) {
            sensoryFeedback(trigger: trigger) { old, new in condition(old, new) ? haptic.sensory : nil }
        } else {
            modifier(LegacyHaptic(haptic: haptic, trigger: trigger, condition: condition))
        }
    }

    /// Numeric labels roll between values on iOS 17+.
    @ViewBuilder
    func numericTransition(_ value: Double) -> some View {
        if #available(iOS 17, *) { contentTransition(.numericText(value: value)) } else { self }
    }

    /// Hero zoom from a source view into a pushed destination (iOS 18+).
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { matchedTransitionSource(id: id, in: namespace) } else { self }
    }

    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        if #available(iOS 18, *), !reduceMotion { navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }

    @ViewBuilder
    func bounceSymbol(value: some Equatable) -> some View {
        if #available(iOS 17, *) { symbolEffect(.bounce, value: value) } else { self }
    }
}

private struct LegacyHaptic<T: Equatable>: ViewModifier {
    let haptic: Haptic
    let trigger: T
    let condition: (T, T) -> Bool
    @State private var previous: T?

    func body(content: Content) -> some View {
        content
            .onAppear { previous = trigger }
            .onChange(of: trigger) { new in
                if let old = previous, condition(old, new) { haptic.play() }
                previous = new
            }
    }
}

/// Springboard-style press: icons sink slightly under the finger. With Reduce
/// Motion the press dims instead of scaling.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
