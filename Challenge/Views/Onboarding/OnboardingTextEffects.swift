import SwiftUI

// MARK: - Onboarding text effects

/// Staggered entrance: fade + slide-up + slight de-blur when the view appears.
struct AppearEffect: ViewModifier {
    var delay: Double = 0
    var yOffset: CGFloat = 18
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : yOffset)
            .blur(radius: shown ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(delay)) { shown = true }
            }
    }
}

/// A soft highlight that sweeps across the content (great on gradient text).
struct ShimmerEffect: ViewModifier {
    var duration: Double = 2.6
    var delay: Double = 0.6
    @State private var move = false

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.45)
                    .offset(x: move ? w * 1.1 : -w * 0.55)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: duration).delay(delay).repeatForever(autoreverses: false)) {
                    move = true
                }
            }
    }
}

/// A loading "shine" that dims the content and sweeps a bright band across it.
/// Designed for light text on a dark background (e.g. white on blue).
struct LoadingShineEffect: ViewModifier {
    var duration: Double = 1.6
    var dim: Double = 0.5
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .opacity(dim)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.55)
                    .offset(x: animate ? w * 1.05 : -w * 0.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

extension View {
    /// Fade + slide-up entrance. Use increasing `delay` to stagger lines.
    func appearEffect(delay: Double = 0, yOffset: CGFloat = 18) -> some View {
        modifier(AppearEffect(delay: delay, yOffset: yOffset))
    }

    /// Repeating shimmer sweep — best on gradient-filled text.
    func shimmer(duration: Double = 2.6, delay: Double = 0.6) -> some View {
        modifier(ShimmerEffect(duration: duration, delay: delay))
    }

    /// Repeating loading shine — best on light text over a dark background.
    func loadingShine(duration: Double = 1.6, dim: Double = 0.5) -> some View {
        modifier(LoadingShineEffect(duration: duration, dim: dim))
    }
}
