import SwiftUI

// MARK: - Design Tokens
private enum WOUStyle {
    static let accentBlue = Color(red: 0.333, green: 0.541, blue: 0.941).opacity(0.30)
    static let bodyGray   = Color(red: 0.459, green: 0.459, blue: 0.459)

    static let headerSize:   CGFloat = 22
    static let titleSize:    CGFloat = 22
    static let bodySize:     CGFloat = 17
    static let boldLineSize: CGFloat = 20
    static let footerSize:   CGFloat = 15

    static let hPad:   CGFloat = 20
    static let topPad: CGFloat = 60
}

// MARK: - Week On Us (post-registration welcome trial)
/// Shown once right after account creation (AuthService.needsWelcomeIntro).
/// The trial itself is activated server-side: users.pro_until defaults to
/// now() + 7 days for new rows (migration 20260612d_welcome_trial.sql),
/// so this screen only informs -- there is nothing for the user to do.
struct WeekOnUsView: View {
    let onContinue: () -> Void

    private let bodyText = """
    We'd love for you to try out the app. Here's a week of PRO on us.
    Nothing you need to do, it's already activated.
    I wish I could offer a free plan or make this longer, but for transparency: \
    I'm using extremely expensive AI providers to power reInspire \
    and simply can't afford it.
    """

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // Background decorative gradient ellipse
            Ellipse()
                .fill(WOUStyle.accentBlue)
                .frame(width: 712, height: 850)
                .offset(x: 60, y: 200)
                .blur(radius: 40)
                .ignoresSafeArea()

            // Decorative star artwork
            Image("star2")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 610)
                .clipped()
                .offset(y: 160)
                .opacity(0.25)
                .allowsHitTesting(false)

            // Single scroll column: copy flows top-to-bottom with the footer
            // following the text directly. Avoids the previous layout where a
            // full-height ScrollView shoved the footer to the bottom and left a
            // large empty gap in the middle. Each Text is width-capped so long
            // lines wrap instead of overflowing the screen edges.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("reInspire.")
                        .font(.system(size: WOUStyle.headerSize, weight: .medium))
                        .foregroundColor(.black)
                        .lineSpacing(2)
                        .padding(.bottom, 12)
                        .appearEffect(delay: 0.05)

                    Text("Week on us.")
                        .font(.manrope(.semiBold, size: WOUStyle.titleSize))
                        .foregroundColor(.black)
                        .padding(.bottom, 10)
                        .appearEffect(delay: 0.15)
                        .shimmer(delay: 0.8)

                    Text(bodyText)
                        .font(.manrope(.semiBold, size: WOUStyle.bodySize))
                        .foregroundColor(WOUStyle.bodyGray)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                        .appearEffect(delay: 0.25)

                    Text("No credit card required. Just enjoy!")
                        .font(.manrope(.semiBold, size: WOUStyle.boldLineSize))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .appearEffect(delay: 0.35)

                    VStack(spacing: 16) {
                        Text("By Arslan (dev) and his team\nResearch and best moments")
                            .font(.manrope(.semiBold, size: WOUStyle.footerSize))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        LiquidGlassButton(title: "Sounds good!") {
                            Haptics.success()
                            onContinue()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .appearEffect(delay: 0.45)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, WOUStyle.topPad)
                .padding(.bottom, OBStyle.ctaBottomPad)
            }
            .padding(.horizontal, WOUStyle.hPad)
            .readableWidth(560)
        }
        .multilineTextAlignment(.leading)
        .onAppear {
            AnalyticsService.shared.track(.welcomeTrialShown)
        }
    }
}

#Preview {
    WeekOnUsView(onContinue: {})
}
