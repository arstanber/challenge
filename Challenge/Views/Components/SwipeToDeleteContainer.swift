import SwiftUI

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
                .simultaneousGesture(dragGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let translation = value.translation.width
                guard translation < 0 || isSwiped else { return }
                let base: CGFloat = isSwiped ? -actionWidth : 0
                offset = max(-actionWidth, min(0, base + translation))
            }
            .onEnded { _ in
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
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            isSwiped = false
        }
    }
}

extension View {
    /// Reveals a red "Удалить" action on left swipe and calls `onDelete` when tapped.
    func swipeToDelete(onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(onDelete: onDelete))
    }
}
