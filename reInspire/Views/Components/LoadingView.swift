import SwiftUI

// MARK: - Branded loading screen
// Full-bleed blue splash with the star burst and an animated "reInspire." title.

private enum LoadingDesign {
    static let backgroundBlue = Color(red: 0/255, green: 71.5/255, blue: 226/255)
    static let titleFontSize: CGFloat = 36
    static let titleLeadingPadding: CGFloat = 24
    static let titleTopOffset: CGFloat = 440
    static let starImageHeight: CGFloat = 610
    static let canvasHeight: CGFloat = 932
}

struct LoadingView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LoadingDesign.backgroundBlue
                    .ignoresSafeArea()

                LoadingStarBurst(geometry: geometry)

                LoadingTitle()
                    .padding(.leading, LoadingDesign.titleLeadingPadding)
                    .offset(y: titleOffset(for: geometry))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private func titleOffset(for geo: GeometryProxy) -> CGFloat {
        let scale = geo.size.height / LoadingDesign.canvasHeight
        return LoadingDesign.titleTopOffset * scale
    }
}

// MARK: - Animated title

private struct LoadingTitle: View {
    var body: some View {
        Text("reInspire.")
            .font(.system(size: LoadingDesign.titleFontSize, weight: .medium))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
            .appearEffect(delay: 0.1)
            .loadingShine()          // sweeping shine while loading
    }
}

// MARK: - Star burst

private struct LoadingStarBurst: View {
    let geometry: GeometryProxy
    @State private var appeared = false

    private var scale: CGFloat { geometry.size.height / LoadingDesign.canvasHeight }
    private var imageHeight: CGFloat { LoadingDesign.starImageHeight * scale }
    private var topOffset: CGFloat {
        (LoadingDesign.canvasHeight - LoadingDesign.starImageHeight) * scale
    }

    var body: some View {
        Image("star2")
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: imageHeight)
            .clipped()
            .offset(y: topOffset)
            .scaleEffect(appeared ? 1.0 : 0.86, anchor: .bottom)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { appeared = true }
            }
    }
}

// MARK: - Reusable overlay
// Use anywhere: `.loadingScreen(isLoading)` to cover the view while loading.

private struct LoadingScreenModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isVisible {
                LoadingView()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

extension View {
    /// Covers the view with the branded loading screen while `isLoading` is true.
    func loadingScreen(_ isLoading: Bool) -> some View {
        modifier(LoadingScreenModifier(isVisible: isLoading))
    }
}

#Preview {
    LoadingView()
}
