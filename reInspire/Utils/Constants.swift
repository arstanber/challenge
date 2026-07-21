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
        /// rounded UP (minimum 1) -- i.e. "at least half". MUST match the server
        /// engine (`compute_user_streak` / `day_qualifies`, migration
        /// `20260616l_streak_half.sql`); change them together.
        static let streakDailyCompletionRatio = 0.5

        /// Tasks the user must complete today for the day to count toward the
        /// streak, given how many recurring tasks are scheduled today. Half,
        /// rounded up (6 tasks -> 3, 5 -> 3, 4 -> 2, 3 -> 2, 2 -> 1).
        static func dailyStreakGoal(scheduledToday: Int) -> Int {
            max(1, Int((streakDailyCompletionRatio * Double(scheduledToday)).rounded(.up)))
        }

        /// Instagram handle (without @) stamped on share cards and used in the
        /// auto-caption for the system share sheet.
        static let instagramHandle = "reinspireqzly"
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
        /// Must match the product IDs created in App Store Connect exactly.
        static let premiumMonthlyID = "reProMonthly"
        static let premiumAnnualID  = "reProAnnually"
        static let premiumForeverID = "reProLifetime"     // non-renewing lifetime
        static let familyMonthlyID  = "reFamilyMonthly"
        static let familyAnnualID   = "reFamilyAnnually"
        static let maxMonthlyID     = "reMaxMonthly"
        static let maxAnnualID      = "reMaxAnnually"

        static let allProductIDs: Set<String> = [
            premiumMonthlyID, premiumAnnualID, premiumForeverID,
            familyMonthlyID, familyAnnualID, maxMonthlyID, maxAnnualID
        ]

        // Backward-compatible aliases (older call sites)
        static let monthlyProductID = premiumMonthlyID
        static let familyProductID  = familyMonthlyID
    }

    enum RevenueCat {
        /// Public SDK key from RevenueCat -> Project settings -> API keys -> Apple.
        /// Safe to ship in the binary (it is a publishable key), unlike the secret key.
        static let apiKey = "appl_xkthlFFvYtbcgxbkXMgLwvLWqed"

        /// Entitlement identifiers configured in the RevenueCat dashboard.
        /// Each maps 1:1 onto a `UserPlan` tier.
        static let premiumEntitlement = "premium"
        static let familyEntitlement  = "family"
        static let maxEntitlement     = "max"

        /// Offering identifier the paywall pulls packages from.
        /// "default" is whatever offering is marked current in the dashboard.
        static let defaultOffering = "default"

        /// Which plan an entitlement unlocks. nil = unknown entitlement.
        static func plan(forEntitlement id: String) -> UserPlan? {
            switch id {
            case premiumEntitlement: return .premium
            case familyEntitlement:  return .family
            case maxEntitlement:     return .max
            default:                 return nil
            }
        }
    }

    enum Aptabase {
        // Replace with your Aptabase App Key from app.aptabase.com → Settings → App Key.
        // Format: "A-US-XXXXXXXXXX", "A-EU-XXXXXXXXXX", or "A-DEV-XXXXXXXXXX".
        static let appKey = "A-EU-7608056201"
    }


}
