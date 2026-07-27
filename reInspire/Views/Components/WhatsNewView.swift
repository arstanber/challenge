import SwiftUI

enum WhatsNewRelease {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Что нового")
                    .font(.sfProDisplay(17, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .accessibilityLabel("Закрыть")
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color(hex: "7C4DF0"))
                            .padding(.bottom, 4)
                        Text("Задачи стали умнее")
                            .font(.sfProDisplay(34, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Версия \(WhatsNewRelease.version)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 24) {
                        WhatsNewRow(
                            icon: "wand.and.stars",
                            color: Color(hex: "7C4DF0"),
                            title: "ИИ планировщик",
                            description: "Опиши цель, а reInspire превратит её в понятный план действий."
                        )
                        WhatsNewRow(
                            icon: "play.circle.fill",
                            color: Color(hex: "0A84FF"),
                            title: "Рутины",
                            description: "Объединяй привычки в последовательности и выполняй их без лишних пауз."
                        )
                        WhatsNewRow(
                            icon: "checkmark.shield.fill",
                            color: Color(hex: "30B96F"),
                            title: "Строгий режим",
                            description: "Подключённые данные помогают честно подтвердить достижение цели."
                        )
                    }

                    Button {
                        Haptics.success()
                        dismiss()
                    } label: {
                        Text("Отлично")
                            .font(.sfProDisplay(18, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 12)
        .background(Color(.systemBackground))
    }
}

private struct WhatsNewRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.sfProDisplay(19, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WhatsNewView()
}
