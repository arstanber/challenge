import Foundation

struct ReviewPromptPolicy {
    static let minimumInstallAge: TimeInterval = 24 * 60 * 60
    static let negativeExperienceCooldown: TimeInterval = 48 * 60 * 60
    static let requestCooldown: TimeInterval = 120 * 24 * 60 * 60

    struct Context {
        let trigger: Trigger
        let now: Date
        let installedAt: Date
        let lastAskedAt: Date?
        let lastNegativeExperienceAt: Date?
    }

    enum Trigger: Equatable {
        case thirdConsecutiveVerifiedDay
        case duelVictory
    }

    static func shouldAsk(_ context: Context) -> Bool {
        guard context.now.timeIntervalSince(context.installedAt) >= minimumInstallAge else {
            return false
        }
        if let lastNegativeExperienceAt = context.lastNegativeExperienceAt,
           context.now.timeIntervalSince(lastNegativeExperienceAt) < negativeExperienceCooldown {
            return false
        }
        if let lastAskedAt = context.lastAskedAt,
           context.now.timeIntervalSince(lastAskedAt) < requestCooldown {
            return false
        }
        return true
    }

    static func isThirdConsecutiveDay(
        adding day: Date,
        to recordedDays: [Date],
        calendar: Calendar
    ) -> Bool {
        let days = Set((recordedDays + [day]).map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: day)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
            return false
        }
        return days.contains(today) && days.contains(yesterday) && days.contains(twoDaysAgo)
    }
}
