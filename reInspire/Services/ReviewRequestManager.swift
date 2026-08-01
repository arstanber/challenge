import Foundation
import Observation

/// Decides when the app has earned a native App Store review request.
/// StoreKit still controls whether the system sheet is actually displayed.
@MainActor
@Observable
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    private(set) var requestSequence = 0

    private let defaults = UserDefaults.standard
    private let completionThreshold = 3

    private enum Key {
        static let successfulCompletions = "reviewSuccessfulCompletions"
        static let requestedVersion = "reviewRequestedVersion"
    }

    private init() {}

    func registerSuccessfulCompletion() {
        let completions = defaults.integer(forKey: Key.successfulCompletions) + 1
        defaults.set(completions, forKey: Key.successfulCompletions)

        guard completions >= completionThreshold,
              defaults.string(forKey: Key.requestedVersion) != currentVersion else { return }

        // Record the attempt before asking StoreKit so repeated task completions
        // cannot queue several sheets while the completion UI is dismissing.
        defaults.set(currentVersion, forKey: Key.requestedVersion)
        requestSequence += 1
        AnalyticsService.shared.track(.reviewRequested, ["successful_completions": completions])
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
