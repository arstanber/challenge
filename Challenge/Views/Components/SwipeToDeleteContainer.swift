import SwiftUI
import UIKit

/// Adds a left-swipe-to-reveal "Удалить" action to cards that live outside a
/// `List` (where the native `.swipeActions` modifier isn't available).
private struct SwipeToDeleteModifier: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let actionWidth: CGFloat = 84

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            Button {
                Haptics.warning()
                onDelete()
                close()
            } label: {
                Color.red
                    .overlay(alignment: .trailing) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Удалить")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(width: actionWidth)
                        .frame(maxHeight: .infinity)
                    }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            // The tap-to-close layer must be attached BEFORE .offset: offset is a
            // render/hit-test translation that does not move the layout frame, so
            // an overlay added after it would stay on the original frame and cover
            // (swallow taps on) the revealed delete button.
            content
                .overlay {
                    if isSwiped {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .offset(x: offset)
                .gesture(HorizontalPanGesture(onChanged: handleChanged, onEnded: handleEnded))
        }
    }

    private func handleChanged(_ dx: CGFloat) {
        let base: CGFloat = isSwiped ? -actionWidth : 0
        offset = max(-actionWidth, min(0, base + dx))
    }

    private func handleEnded(_ dx: CGFloat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if offset < -actionWidth / 2 {
                offset = -actionWidth
                isSwiped = true
            } else {
                offset = 0
                isSwiped = false
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            isSwiped = false
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
    }
}

extension View {
    /// Reveals a red "Удалить" action on left swipe and calls `onDelete` when tapped.
    func swipeToDelete(onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(onDelete: onDelete))
    }
}
