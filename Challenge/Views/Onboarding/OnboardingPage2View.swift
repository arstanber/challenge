import SwiftUI

// MARK: - Page 2: The Challenge motivation screen

struct TheChallengeView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Fullscreen background photo
                Image("cat_lazy")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Dark blob — top-left
                P2BlobTopLeft()

                // Dark gradient — bottom
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0), location: 0.35),
                        .init(color: Color.black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    P2TitleView()
                        .padding(.top, 60)
                        .padding(.horizontal, 20)

                    P2QuestionsView()
                        .padding(.top, 8)
                        .padding(.horizontal, 20)

                    Spacer()

                    P2FixItView()
                        .frame(maxWidth: .infinity, alignment: .center)

                    LiquidGlassButton(title: "Continue", action: onContinue)
                        .padding(.top, 16)
                        .padding(.bottom, OBStyle.ctaBottomPad)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Subviews

private struct P2BlobTopLeft: View {
    var body: some View {
        GeometryReader { geo in
            Ellipse()
                .fill(Color.black.opacity(0.45))
                .frame(width: 560, height: 500)
                .blur(radius: 50)
                .position(x: 80, y: 100)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct P2TitleView: View {
    var body: some View {
        Text("The\nChallenge.")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .appearEffect(delay: 0.05)
    }
}

private struct P2QuestionsView: View {
    private let questions = [
        "Always distracted?",
        "Can't focus and ",
        "always feel lazyy?",
        "Forgive to do tasks?",
        "0 discipline in work and studying?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(questions.enumerated()), id: \.element) { index, q in
                Text(q)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)
                    .appearEffect(delay: 0.15 + Double(index) * 0.1)
            }
        }
    }
}

private struct P2FixItView: View {
    var body: some View {
        Text("We will fix it .")
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "FFFFFF"), location: 0.0),
                        .init(color: Color(hex: "0048E2"), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .multilineTextAlignment(.center)
            .appearEffect(delay: 0.7)
            .shimmer(delay: 1.0)
    }
}

#Preview {
    TheChallengeView(onContinue: {})
}
