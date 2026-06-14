import SwiftUI

extension UserPlan: Identifiable {
    public var id: String { rawValue }
}

/// One-time congratulation popup shown when the user's plan becomes
/// (or upgrades to) a paid tier -- after an in-app purchase or a
/// server-side grant picked up on launch.
struct PlanCelebrationView: View {
    let plan: UserPlan
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(hex: "7C4DF0")
    private let accentDeep = Color(hex: "5B2FD6")

    private var perks: [String] {
        switch plan {
        case .premium:
            return [
                "Безлимит задач и привычек",
                "30 AI-проверок фото в месяц",
                "AI-коуч и планировщик целей"
            ]
        case .family:
            return [
                "Всё из Premium для 5 человек",
                "Семейный рейтинг",
                "Код приглашения для семьи"
            ]
        case .max:
            return [
                "100 AI-проверок фото в месяц",
                "Расширенные лимиты AI-коуча",
                "Коннекторы Max и приоритетная обработка"
            ]
        case .free:
            return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent, accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "crown.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: accent.opacity(0.4), radius: 24, y: 8)
            .padding(.bottom, 24)

            Text("Поздравляем!")
                .font(.largeTitle.bold())
                .padding(.bottom, 6)

            Text("Тебе доступен план \(plan.displayName)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                            .font(.system(size: 20))
                        Text(perk)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer()

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Отлично")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .readableWidth(480)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { Haptics.success() }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PlanCelebrationView(plan: .max)
    }
}
