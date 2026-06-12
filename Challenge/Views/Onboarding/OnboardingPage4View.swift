import SwiftUI

// MARK: - Page 4: Push notifications permission screen

struct PushNotificationsOnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            P4Header()
                .padding(.top, 60)
                .padding(.horizontal, 19)

            P4NotificationsList()
                .padding(.top, 32)
                .padding(.horizontal, 19)

            Spacer()

            LiquidGlassButton(title: "Continue", action: onContinue)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, OBStyle.ctaBottomPad)
        }
        .readableWidth(560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Extend to the physical bottom edge so the CTA lines up with the
        // full-bleed pages (which ignore the safe area) at OBStyle.ctaBottomPad.
        .ignoresSafeArea(.container, edges: .bottom)
        .background {
            ZStack {
                Color.white
                Ellipse()
                    .fill(Color(red: 0.0, green: 0.282, blue: 0.886).opacity(0.30))
                    .frame(width: 534, height: 510)
                    .offset(x: -52, y: 440)
                    .blur(radius: 40)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Header

private struct P4Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The\nChallenge.")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black)
                .lineSpacing(2)
                .appearEffect(delay: 0.05)

            Text("You can't \nforget about it. Turn on \nthe Push‑notifications.")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(.black)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .appearEffect(delay: 0.2)
        }
    }
}

// MARK: - Notifications list

private struct P4NotificationsList: View {
    private let items: [P4NotificationItem] = [
        .init(title: "Task Task Task!!!", time: "34m ago",
              body: "Here's notification text. This is a spot for app notification text."),
        .init(title: "Task Task Task!!!", time: "34m ago",
              body: "Here's notification text. This is a spot for app notification text."),
        .init(title: "Task Task Task!!!", time: "34m ago",
              body: "Here's notification text. This is a spot for app notification text."),
        .init(title: "Task Task Task!!!", time: "34m ago",
              body: "Here's notification text. This is a spot for app notification text.")
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(items.indices, id: \.self) { i in
                P4NotificationCard(item: items[i])
                    .appearEffect(delay: 0.35 + Double(i) * 0.12, yOffset: 24)
            }
        }
    }
}

private struct P4NotificationItem {
    let title: String
    let time: String
    let body: String
}

private struct P4NotificationCard: View {
    let item: P4NotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.time)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black)
                    .frame(width: 54, alignment: .trailing)
            }
            .frame(height: 20)

            Text(item.body)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
        )
    }
}

#Preview {
    PushNotificationsOnboardingView(onContinue: {})
}
