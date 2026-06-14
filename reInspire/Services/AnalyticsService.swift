import Foundation
import Aptabase

/// Thin wrapper around Aptabase so the rest of the app has a single, typed entry point
/// for analytics. Call `AnalyticsService.shared.start()` once at launch, then
/// `track(_:_)` anywhere you want to record an event.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    /// Initialize the Aptabase SDK. Safe to call once at app startup.
    func start() {
        Aptabase.shared.initialize(appKey: Constants.Aptabase.appKey)
    }

    /// Track an event with optional properties.
    func track(_ event: Event, _ props: [String: Any]? = nil) {
        if let props {
            Aptabase.shared.trackEvent(event.rawValue, with: props)
        } else {
            Aptabase.shared.trackEvent(event.rawValue)
        }
    }

    /// App-wide event names. Keep them stable so dashboards stay consistent.
    enum Event: String {
        case appLaunched = "app_launched"
        case signedIn = "signed_in"
        case signedUp = "signed_up"
        case signedOut = "signed_out"
        case onboardingCompleted = "onboarding_completed"
        case welcomeTrialShown = "welcome_trial_shown"
        case activityCreated = "activity_created"
        case reportSubmitted = "report_submitted"
        case verificationSucceeded = "verification_succeeded"
        case verificationFailed = "verification_failed"
        case excuseUsed = "excuse_used"
        case goalPlanGenerated = "goal_plan_generated"
        case streakMilestone = "streak_milestone"
        case premiumPurchased = "premium_purchased"
        case premiumRevoked = "premium_revoked"
        case premiumPaywallShown = "premium_paywall_shown"
        case bonusXPDropped = "bonus_xp_dropped"
        case duelCreated = "duel_created"
        case duelJoined = "duel_joined"
        case duelFinished = "duel_finished"
        case referralRedeemed = "referral_redeemed"
        case referralRewardClaimed = "referral_reward_claimed"
        // Activation funnel: time-to-first-report is the aha-moment metric.
        case firstReportSubmitted = "first_report_submitted"
        case firstWinShown = "first_win_shown"
        case firstWinAccepted = "first_win_accepted"
    }
}
