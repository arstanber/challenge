import SwiftUI

// MARK: - Page 4: Push notifications permission screen
//
// Full-bleed brand illustration with a white fade at the top so the headline
// and a stack of "live" notification cards read clearly. Continue triggers the
// system push-permission prompt, then advances regardless of the choice.

struct PushNotificationsOnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let notifications: [P4NotificationItem] = [
        .init(title: "WE ARE SO BACK 🔥", time: "34 мин",
              body: "67 дней подряд. Серия не останавливается."),
        .init(title: "История пишется сейчас", time: "34 мин",
              body: "Через год ты вспомнишь этот день. Что ты сделал?"),
        .init(title: "Это не цитата. Это режим.", time: "34 мин",
              body: "Дисциплина > мотивация. Всегда.")
    ]

    var body: some View {
        let s = OBStyle.scale(sizeClass)
        ZStack(alignment: .topLeading) {
            // Brand illustration, full-bleed.
            GeometryReader { geo in
                Image("pushes")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // The illustration is grayscale ink art; desaturating drops
                    // the baked-in blue background wash without touching the art.
                    .saturation(0)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            // White fade at the top for headline + card legibility. Scales with
            // the content so the (taller) iPad stack stays fully covered.
            LinearGradient(
                colors: [Color.white, Color.white, Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 520 * s)
            .ignoresSafeArea()

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text("reInspire.")
                    .font(.system(size: 17 * s, weight: .medium))
                    .foregroundColor(.black)
                    .lineSpacing(2)
                    .padding(.top, 16)
                    .appearEffect(delay: 0.05)

                Text("You can't \nforget about it. Turn on \nthe Push-notifications.")
                    .font(.system(size: 34 * s, weight: .medium))
                    .foregroundColor(.black)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .appearEffect(delay: 0.2)

                VStack(spacing: 8 * s) {
                    ForEach(notifications.indices, id: \.self) { i in
                        P4NotificationCard(item: notifications[i], scale: s)
                            .appearEffect(delay: 0.35 + Double(i) * 0.12, yOffset: 24)
                    }
                }
                .padding(.top, 22 * s)

                Spacer()

                LiquidGlassButton(title: "Continue") {
                    Task {
                        await NotificationService.shared.requestPermission()
                        onContinue()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, OBStyle.ctaBottomPad)
            }
            .padding(.horizontal, 20)
            .readableWidth(560 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        // Extend to the physical bottom edge so the CTA aligns with the
        // full-bleed pages (which ignore the safe area) at OBStyle.ctaBottomPad.
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

// MARK: - Notification card

private struct P4NotificationItem {
    let title: String
    let time: String
    let body: String
}

private struct P4NotificationCard: View {
    let item: P4NotificationItem
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                Text(item.time)
                    .font(.system(size: 13 * scale, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
                    .lineLimit(1)
            }

            Text(item.body)
                .font(.system(size: 13 * scale, weight: .regular))
                .foregroundColor(.black.opacity(0.8))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Native iOS Liquid Glass (matches the onboarding CTA button).
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    PushNotificationsOnboardingView(onContinue: {})
}
