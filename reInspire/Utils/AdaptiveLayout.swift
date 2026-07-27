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

    /// Conditionally apply a modifier chain. Toggling `condition` rebuilds the
    /// view, so use only for mode switches (e.g. entering drag-reorder), never
    /// for per-frame state.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    /// A shared Liquid Glass surface for cards and compact controls.
    ///
    /// The subtle tint keeps each surface tied to its semantic accent while
    /// the native glass effect provides depth, highlights, and refraction.
    func liquidGlassSurface<S: InsettableShape>(
        in shape: S,
        tint: Color = .primary,
        tintOpacity: Double = 0.035,
        borderOpacity: Double = 0.12
    ) -> some View {
        background(tint.opacity(tintOpacity), in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

extension Array where Element == GridItem {
    /// Flexible grid columns whose count depends on the horizontal size class:
    /// `regular` columns on iPad, `compact` on iPhone.
    static func adaptive(
        compact: Int,
        regular: Int,
        for sizeClass: UserInterfaceSizeClass?,
        spacing: CGFloat = 12
    ) -> [GridItem] {
        let count = sizeClass == .regular ? regular : compact
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
