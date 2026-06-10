import Foundation

enum Constants {
    enum Supabase {
        static let url = URL(string: "https://tvuvfuguxjvzyzsjnepr.supabase.co")!
        static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR2dXZmdWd1eGp2enl6c2puZXByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk5NTUxODQsImV4cCI6MjA5NTUzMTE4NH0.OE05dFHZwTm0HKb7FD20qp-Pphg3efMQYj6NXZ-JoC4"
    }

    enum App {
        static let maxFreeActivities = 3
        static let maxFreeReportsPerMonth = 10
        static let freezeIntervalDays = 7
        static let streakMilestones = [7, 14, 30, 100]
        static let minDailyActivitiesForStreak = 3
    }

    enum Storage {
        static let reportsBucket = "reports"
    }

    enum Telegram {
        /// Username of the @BotFather bot that backs the in-app integration (no leading @).
        static let botUsername = "thechallengeapp_bot"
    }

    enum Store {
        /// Must match the product IDs you create in App Store Connect.
        static let monthlyProductID       = "com.challenge.premium.monthly"
        static let familyProductID        = "com.challenge.premium.family"   // #18
    }

    enum Aptabase {
        // Replace with your Aptabase App Key from app.aptabase.com → Settings → App Key.
        // Format: "A-US-XXXXXXXXXX", "A-EU-XXXXXXXXXX", or "A-DEV-XXXXXXXXXX".
        static let appKey = "A-EU-7608056201"
    }


}
