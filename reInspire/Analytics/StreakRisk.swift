import SwiftUI

// MARK: - Streak risk prediction (#16)

/// Lightweight heuristic that estimates whether today's streak is in danger,
/// based on how much of the daily goal is left and how late in the day it is.
enum StreakRisk {
    enum Level {
        case done       // goal already met today
        case safe       // plenty of day left
        case atRisk     // evening, still tasks left
        case critical   // late night, still tasks left
        case idle       // no streak to protect yet

        var tint: Color {
            switch self {
            case .done:     return Color(hex: "2FB873")
            case .safe:     return Color(hex: "4580FF")
            case .atRisk:   return Color(hex: "FF7A00")
            case .critical: return Color(hex: "FF3B30")
            case .idle:     return Color(hex: "8E8E93")
            }
        }

        var emoji: String {
            switch self {
            case .done:     return "✅"
            case .safe:     return "🛡️"
            case .atRisk:   return "⏳"
            case .critical: return "🚨"
            case .idle:     return "🌱"
            }
        }
    }

    struct Result {
        let level: Level
        let title: String
        let message: String
    }

    static func evaluate(
        todayDone: Int,
        dailyGoal: Int,
        currentStreak: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result {
        let remaining = max(0, dailyGoal - todayDone)
        let hour = calendar.component(.hour, from: now)

        if remaining == 0 {
            return Result(
                level: .done,
                title: "Streak secured",
                message: currentStreak > 0
                    ? "You've hit today's goal. \(currentStreak)-day streak is safe 🔥"
                    : "You've hit today's goal. Keep it going!"
            )
        }

        if currentStreak == 0 {
            return Result(
                level: .idle,
                title: "Start a streak",
                message: "Complete \(remaining) more today to begin a streak."
            )
        }

        let taskWord = remaining == 1 ? "activity" : "activities"
        switch hour {
        case 21...23:
            return Result(
                level: .critical,
                title: "Streak at risk!",
                message: "Only a few hours left — \(remaining) \(taskWord) to save your \(currentStreak)-day streak."
            )
        case 18...20:
            return Result(
                level: .atRisk,
                title: "Don't lose your streak",
                message: "\(remaining) \(taskWord) left today to keep your \(currentStreak)-day streak alive."
            )
        default:
            return Result(
                level: .safe,
                title: "On track",
                message: "\(remaining) \(taskWord) left to keep your \(currentStreak)-day streak going."
            )
        }
    }
}

// MARK: - Risk card

struct StreakRiskCard: View {
    let result: StreakRisk.Result

    var body: some View {
        HStack(spacing: 14) {
            Text(result.level.emoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.manrope(.bold, size: 16))
                    .foregroundColor(.black)
                Text(result.message)
                    .font(.manrope(.medium, size: 12))
                    .foregroundColor(.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(result.level.tint.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(result.level.tint.opacity(0.35), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        StreakRiskCard(result: StreakRisk.evaluate(todayDone: 3, dailyGoal: 3, currentStreak: 12))
        StreakRiskCard(result: StreakRisk.evaluate(todayDone: 1, dailyGoal: 3, currentStreak: 12, now: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!))
        StreakRiskCard(result: StreakRisk.evaluate(todayDone: 1, dailyGoal: 3, currentStreak: 12, now: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!))
        StreakRiskCard(result: StreakRisk.evaluate(todayDone: 0, dailyGoal: 3, currentStreak: 0))
    }
    .padding()
}
