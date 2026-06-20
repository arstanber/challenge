import SwiftUI
import UIKit

/// Adds swipe actions to cards that live outside a `List` (where the native
/// `.swipeActions` modifier isn't available): left swipe (when `onComplete`
/// is provided) reveals a green "Готово", right swipe reveals a red
/// "Удалить".
private struct SwipeActionsModifier: ViewModifier {
    let onComplete: (() -> Void)?
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    private let actionWidth: CGFloat = 84

    private var minTrailing: CGFloat { onComplete != nil ? -actionWidth : 0 }

    func body(content: Content) -> some View {
        ZStack {
            // Trailing (left swipe): complete
            if offset < 0 {
                Button {
                    Haptics.success()
                    onComplete?()
                    close()
                } label: {
                    Color(hex: "2FB873")
                        .overlay(alignment: .trailing) {
                            actionLabel(icon: "checkmark.circle.fill", text: "Готово")
                        }
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            // Leading (right swipe): delete
            if offset > 0 {
                Button {
                    Haptics.warning()
                    onDelete()
                    close()
                } label: {
                    Color.red
                        .overlay(alignment: .leading) {
                            actionLabel(icon: "trash.fill", text: "Удалить")
                        }
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            // The tap-to-close layer must be attached BEFORE .offset: offset is a
            // render/hit-test translation that does not move the layout frame, so
            // an overlay added after it would stay on the original frame and cover
            // (swallow taps on) the revealed action button.
            content
                .overlay {
                    if restingOffset != 0 {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .offset(x: offset)
                .gesture(HorizontalPanGesture(onChanged: handleChanged, onEnded: handleEnded))
        }
    }

    private func actionLabel(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .frame(width: actionWidth)
        .frame(maxHeight: .infinity)
    }

    private func handleChanged(_ dx: CGFloat) {
        offset = max(minTrailing, min(actionWidth, restingOffset + dx))
    }

    private func handleEnded(_ dx: CGFloat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if offset < -actionWidth / 2 {
                offset = -actionWidth
            } else if offset > actionWidth / 2 {
                offset = actionWidth
            } else {
                offset = 0
            }
            restingOffset = offset
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            restingOffset = 0
        }
    }
}

/// Horizontal-only pan recognizer. A SwiftUI `DragGesture` here would compete
/// with the enclosing ScrollView and freeze vertical scrolling; this recognizer
/// refuses to begin unless the drag is predominantly horizontal, so vertical
/// swipes fall through to the list.
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            onChanged(dx)
        case .ended, .cancelled, .failed:
            onEnded(dx)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let t = pan.translation(in: view)
            return abs(t.x) > abs(t.y)
        }

        // The card also carries SwiftUI gestures (tap-to-open, a min-distance-0
        // press DragGesture for the scale effect, and contextMenu's long press).
        // A UIKit recognizer added via UIGestureRecognizerRepresentable does NOT
        // recognize simultaneously with SwiftUI's gestures by default, so the
        // press drag would swallow the touch and the horizontal swipe never
        // begins. Allowing simultaneous recognition lets the pan run alongside
        // them; `shouldBegin` still gates on horizontal-dominant movement so
        // vertical scrolling is untouched.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    /// Reveals a red "Удалить" action on right swipe and calls `onDelete` when tapped.
    func swipeToDelete(onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeActionsModifier(onComplete: nil, onDelete: onDelete))
    }

    /// Right swipe reveals "Удалить"; left swipe reveals a green "Готово"
    /// when `onComplete` is not nil (pass nil for cards without a manual
    /// complete action, e.g. auto-tracked goals). Named to avoid colliding
    /// with SwiftUI's List-only `swipeActions`.
    func swipeCardActions(onComplete: (() -> Void)?, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeActionsModifier(onComplete: onComplete, onDelete: onDelete))
    }
}
