import SwiftUI

// MARK: - "Perfect Day" celebration

struct PerfectDayView: View {
    var title: String = "Идеальный день!"
    var message: String = "100% выполнено. Сегодня ты сделал это для себя."
    var buttonTitle: String = "Это про меня!"
    var onDismiss: () -> Void

    @State private var starScale: CGFloat = 0.4
    @State private var starOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    private let blue = Color(hex: "4580FF")

    var body: some View {
        ZStack {
            // Dim + blur backdrop
            Color.black.opacity(0.55)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .hapticTap { onDismiss() }

            VStack(spacing: 18) {
                Text("⭐️")
                    .font(.system(size: 96))
                    .scaleEffect(starScale)
                    .opacity(starOpacity)
                    .shadow(color: .yellow.opacity(0.5), radius: 30)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.manrope(.extraBold, size: 30))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.manrope(.medium, size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(contentOpacity)

                Button(action: onDismiss) {
                    Text(buttonTitle)
                        .font(.manrope(.bold, size: 17))
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(blue))
                }
                .padding(.top, 12)
                .opacity(contentOpacity)
            }
            .padding(.bottom, 40)
            .frame(maxWidth: 480)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                starScale = 1.0
                starOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
            Haptics.success()
        }
    }
}

#Preview {
    ZStack {
        Color.white
        PerfectDayView { }
    }
}
