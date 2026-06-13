import SwiftUI

// Color(hex:) and the adaptive Color(hex:dark:) now live in
// Utils/Color+Adaptive.swift.

// MARK: - Design Tokens
enum OBStyle {
    static let accentBlue      = Color(hex: "0048E2").opacity(0.30)
    static let titleBlack      = Color.black
    static let subtitleGray    = Color(hex: "9B9B9B")
    static let buttonBg        = Color(hex: "F7F7F7")
    static let buttonText      = Color(hex: "1A1A1A")

    static let titleSize:  CGFloat = 36
    static let taglineSize: CGFloat = 40
    static let buttonSize: CGFloat = 17

    static let imageSize:   CGFloat = 326
    static let buttonW:     CGFloat = 305
    static let buttonH:     CGFloat = 48
    static let hPad:        CGFloat = 52

    /// Shared distance from the screen's physical bottom for the primary
    /// CTA button ("Continue" / "Get Started") so every onboarding page
    /// lines its button up at the same level.
    static let ctaBottomPad: CGFloat = 50
}

// MARK: - Liquid Glass Button
struct LiquidGlassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: OBStyle.buttonSize, weight: .medium))
                .frame(width: OBStyle.buttonW, height: OBStyle.buttonH)
                .glassEffect(in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Pressable Button Style
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.tap() }
            }
    }
}

// MARK: - Shared: Background Blob
private struct OBBlob: View {
    var color: Color = OBStyle.accentBlue

    var body: some View {
        Ellipse()
            .fill(color)
            .frame(width: 534, height: 510)
            .blur(radius: 40)
    }
}

// MARK: - Shared: Text Section
private struct OBTextSection: View {
    let title: String
    let boldText: String
    let regularText: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.system(size: OBStyle.titleSize, weight: .medium))
                .foregroundColor(OBStyle.titleBlack)
                .lineLimit(1)
                .appearEffect(delay: 0.15)
            HStack(spacing: 0) {
                Text(boldText)
                    .font(.system(size: OBStyle.taglineSize, weight: .medium))
                    .foregroundColor(OBStyle.titleBlack)
                Text(regularText)
                    .font(.system(size: OBStyle.taglineSize, weight: .medium))
                    .foregroundColor(OBStyle.subtitleGray)
            }
            .appearEffect(delay: 0.3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(.horizontal, OBStyle.hPad)
    }
}

// MARK: - Onboarding Container
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(AuthService.self) private var authService
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingLandingPage {
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 1 }
                }
                .tag(0)

                TheChallengeView {
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 2 }
                }
                .tag(1)

                ChallengePhotoView {
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 3 }
                }
                .tag(2)

                PushNotificationsOnboardingView {
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 4 }
                }
                .tag(3)

                GetStartedScreen {
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 3 }
                }
                .environment(authService)
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
    }
}

// MARK: - Page 1: Landing
private struct OnboardingLandingPage: View {
    let onNext: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Fullscreen background photo
                Image("cat_hero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Bottom gradient overlay for legibility
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0), location: 0.4),
                        .init(color: Color.black.opacity(0.55), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Bottom content
                VStack(alignment: .center, spacing: 16) {

                    VStack(alignment: .center, spacing: 4) {
                        Text("The Challenge.")
                            .font(.system(size: OBStyle.titleSize, weight: .medium))
                            .foregroundColor(.white)
                            .appearEffect(delay: 0.15)

                        Text("New life starts here")
                            .font(.system(size: OBStyle.taglineSize, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(hex: "FFFFFF"), location: 0.0),
                                        .init(color: Color(hex: "B9B9B9"), location: 0.5),
                                        .init(color: Color(hex: "868585"), location: 0.84)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .shimmer(delay: 1.0)
                            .appearEffect(delay: 0.3)
                    }
                    .multilineTextAlignment(.center)

                    LiquidGlassButton(title: "Get Started", action: onNext)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, OBStyle.hPad)
                .padding(.bottom, OBStyle.ctaBottomPad)
                .readableWidth(480)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pages 2 & 3: Feature Highlights
private struct OnboardingFeaturePage: View {
    let blobColor: Color
    let blobOffset: CGSize
    let cardBackground: Color
    let symbolName: String
    let symbolColor: Color
    let cardLabel: String
    let title: String
    let boldText: String
    let regularText: String
    let buttonLabel: String
    let onNext: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            OBBlob(color: blobColor)
                .offset(x: blobOffset.width, y: blobOffset.height)

            VStack(spacing: 0) {
                Spacer().frame(height: 200)

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cardBackground)
                        .frame(width: OBStyle.imageSize, height: OBStyle.imageSize)
                    Image(systemName: symbolName)
                        .font(.system(size: 110))
                        .foregroundColor(symbolColor.opacity(0.55))
                    VStack {
                        Spacer()
                        HStack {
                            Text(cardLabel)
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .padding(20)
                            Spacer()
                        }
                    }
                }
                .frame(width: OBStyle.imageSize, height: OBStyle.imageSize)
                .clipped()
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 148)

                OBTextSection(
                    title: title,
                    boldText: boldText,
                    regularText: regularText
                )

                Spacer().frame(height: 28)

                LiquidGlassButton(title: buttonLabel, action: onNext)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView()
}
