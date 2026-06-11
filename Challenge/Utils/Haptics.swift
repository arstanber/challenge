import SwiftUI
import UIKit

/// Centralized haptic feedback.
///
/// Call from anywhere on the main actor: `Haptics.tap()`, `Haptics.success()`,
/// `Haptics.selection()`, etc. Each call prepares its generator first so the
/// feedback fires with minimal latency.
@MainActor
enum Haptics {

    /// UserDefaults key for the global haptics setting (toggled in SettingsView).
    static let enabledKey = "hapticsEnabled"

    /// Global switch — when off, every call below becomes a no-op.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: Impact

    /// Light tap — default for button presses and simple taps.
    static func tap()    { impact(.light) }
    static func light()  { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy()  { impact(.heavy) }
    static func soft()   { impact(.soft) }
    static func rigid()  { impact(.rigid) }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                       intensity: CGFloat = 1.0) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    // MARK: Selection

    /// Used when moving between discrete values — pickers, segmented controls, toggles.
    static func selection() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: Notification

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error()   { notify(.error) }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Button style

/// A button style that fires a haptic on press and applies a subtle press
/// animation. Visually behaves like `.plain` (no tint), so it can replace
/// `.buttonStyle(.plain)` without changing appearance.
struct HapticButtonStyle: ButtonStyle {
    var style: UIImpactFeedbackGenerator.FeedbackStyle = .light
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.impact(style) }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    /// Plain-looking button that adds a light haptic on press.
    static var haptic: HapticButtonStyle { HapticButtonStyle() }

    /// Haptic button with a configurable impact style.
    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> HapticButtonStyle {
        HapticButtonStyle(style: style)
    }
}

// MARK: - Tap gesture helper

extension View {
    /// Drop-in replacement for `onTapGesture` that also fires a haptic.
    func hapticTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light,
                   perform action: @escaping () -> Void) -> some View {
        onTapGesture {
            Haptics.impact(style)
            action()
        }
    }

    /// Drop-in replacement for `sensoryFeedback(_:trigger:)` that respects
    /// the global haptics setting.
    func hapticFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(feedback, trigger: trigger) { _, _ in Haptics.isEnabled }
    }
}
