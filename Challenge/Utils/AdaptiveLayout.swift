import SwiftUI

// MARK: - iPad-friendly layout helpers
//
// The app's screens are designed around a narrow iPhone column. On iPad
// (regular horizontal size class) that content would otherwise stretch edge to
// edge. These helpers cap the content to a comfortable reading width and centre
// it, while staying a no-op on iPhone (compact width).

private struct ReadableWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            content
        }
    }
}

extension View {
    /// Constrains content to a centred, readable column on iPad (regular width).
    /// On iPhone (compact width) this does nothing.
    func readableWidth(_ maxWidth: CGFloat = 640, alignment: Alignment = .center) -> some View {
        modifier(ReadableWidthModifier(maxWidth: maxWidth, alignment: alignment))
    }
}
