import SwiftUI

// MARK: - First win activation card

/// Shown on Home until the user sends their first photo report. The first
/// AI verdict is the app's aha moment -- this card makes it happen in the
/// first session instead of "someday": a 2-minute starter challenge with
/// the camera one tap away.
struct FirstWinCard: View {
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("💧")
                    .font(.system(size: 34))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(8)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Первая победа за 2 минуты")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text("Выпей стакан воды и сфотографируй. AI проверит и засчитает -- так начинается твоя серия.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAccept) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("Принять вызов")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "0048E2"))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.haptic)
            .padding(.top, 2)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: "0048E2"), Color(hex: "3D6EFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

#Preview {
    FirstWinCard(onAccept: {}, onDismiss: {})
        .padding()
}
