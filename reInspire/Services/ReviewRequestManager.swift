import Foundation
import Observation

/// Decides when the app has earned a native App Store review request.
/// StoreKit still controls whether the system sheet is actually displayed.
@MainActor
@Observable
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    private(set) var requestSequence = 0

    private let defaults: UserDefaults
    private let calendar: Calendar

    private enum Key {
        static let installedAt = "review.installedAt"
        static let lastAskedAt = "review.lastAskedAt"
        static let lastNegativeExperienceAt = "review.lastNegativeExperienceAt"
        static let verifiedDays = "review.verifiedDays"
    }

    private init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if defaults.object(forKey: Key.installedAt) == nil {
            defaults.set(Date(), forKey: Key.installedAt)
        }
    }

    /// Only an AI-approved photo counts. Plain check-ins, pending verdicts,
    /// excuses and offline fallbacks deliberately do not earn a review prompt.
    func registerVerifiedSuccess(at date: Date = Date()) {
        var days = verifiedDays
        let day = calendar.startOfDay(for: date)
        if !days.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            days.append(day)
            let cutoff = calendar.date(byAdding: .day, value: -4, to: day) ?? day
            days.removeAll { $0 < cutoff }
            defaults.set(days, forKey: Key.verifiedDays)
        }

        guard ReviewPromptPolicy.isThirdConsecutiveDay(
            adding: day,
            to: days,
            calendar: calendar
        ) else { return }
        attempt(trigger: .thirdConsecutiveVerifiedDay, now: date)
    }

    func registerDuelVictory(at date: Date = Date()) {
        attempt(trigger: .duelVictory, now: date)
    }

    func registerVerificationFailure(at date: Date = Date()) {
        defaults.set(date, forKey: Key.lastNegativeExperienceAt)
    }

    func registerStreakBreak(at date: Date = Date()) {
        defaults.set(date, forKey: Key.lastNegativeExperienceAt)
    }

    private func attempt(trigger: ReviewPromptPolicy.Trigger, now: Date) {
        let installedAt = defaults.object(forKey: Key.installedAt) as? Date ?? now
        let context = ReviewPromptPolicy.Context(
            trigger: trigger,
            now: now,
            installedAt: installedAt,
            lastAskedAt: defaults.object(forKey: Key.lastAskedAt) as? Date,
            lastNegativeExperienceAt: defaults.object(forKey: Key.lastNegativeExperienceAt) as? Date
        )
        guard ReviewPromptPolicy.shouldAsk(context) else { return }

        // Record the attempt before asking StoreKit so repeated events cannot
        // queue several sheets while the success UI is dismissing.
        defaults.set(now, forKey: Key.lastAskedAt)
        requestSequence += 1
        AnalyticsService.shared.track(.reviewRequested, [
            "trigger": trigger == .duelVictory ? "duel_victory" : "third_verified_day"
        ])
    }

    private var verifiedDays: [Date] {
        defaults.array(forKey: Key.verifiedDays) as? [Date] ?? []
    }
}
