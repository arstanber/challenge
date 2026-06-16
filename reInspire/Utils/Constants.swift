import Foundation

enum Constants {
    enum Supabase {
        static let url = URL(string: "https://tvuvfuguxjvzyzsjnepr.supabase.co")!
        static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR2dXZmdWd1eGp2enl6c2puZXByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk5NTUxODQsImV4cCI6MjA5NTUzMTE4NH0.OE05dFHZwTm0HKb7FD20qp-Pphg3efMQYj6NXZ-JoC4"
    }

    enum App {
        static let maxFreeActivities = 3
        static let freezeIntervalDays = 7
        static let streakMilestones = [7, 14, 30, 100]
        /// A day counts toward the global streak when the user completed at
        /// least this share of the recurring tasks scheduled for that day,
        /// rounded DOWN (minimum 1). MUST match the server engine
        /// (`compute_user_streak` / `day_qualifies`, migration
        /// `20260616g_streak_75_floor.sql`); change them together.
        static let streakDailyCompletionRatio = 0.75

        /// Tasks the user must complete today for the day to count toward the
        /// streak, given how many recurring tasks are scheduled today. Rounded
        /// down so "most of your tasks" counts (2 tasks -> 1, 3 -> 2, 4 -> 3).
        static func dailyStreakGoal(scheduledToday: Int) -> Int {
            max(1, Int((streakDailyCompletionRatio * Double(scheduledToday)).rounded(.down)))
        }
    }

    enum Storage {
        static let reportsBucket = "reports"
        static let avatarsBucket = "avatars"
    }

    enum Telegram {
        /// Username of the @BotFather bot that backs the in-app integration (no leading @).
        static let botUsername = "thechallengeapp_bot"
    }

    enum Store {
        /// Must match the product IDs you create in App Store Connect.
        static let premiumMonthlyID = "com.reinspire.premium.monthly"
        static let premiumAnnualID  = "com.reinspire.premium.annual"
        static let premiumForeverID = "com.reinspire.premium.forever"        // non-consumable (lifetime)
        static let familyMonthlyID  = "com.reinspire.premium.family"         // #18
        static let familyAnnualID   = "com.reinspire.premium.family.annual"
        static let maxMonthlyID     = "com.reinspire.max.monthly"

        static let allProductIDs: Set<String> = [
            premiumMonthlyID, premiumAnnualID, premiumForeverID,
            familyMonthlyID, familyAnnualID, maxMonthlyID
        ]

        // Backward-compatible aliases (older call sites)
        static let monthlyProductID = premiumMonthlyID
        static let familyProductID  = familyMonthlyID
    }

    enum Aptabase {
        // Replace with your Aptabase App Key from app.aptabase.com → Settings → App Key.
        // Format: "A-US-XXXXXXXXXX", "A-EU-XXXXXXXXXX", or "A-DEV-XXXXXXXXXX".
        static let appKey = "A-EU-7608056201"
    }


}
