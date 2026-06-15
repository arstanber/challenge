import ActivityKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "LiveActivityService")

// MARK: - LiveActivityService (#20)
// Note: We use ActivityKit.Activity<T> explicitly because the app already
// has its own `struct Activity` (domain model) that shadows the name.

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private init() {}

    typealias Attrs = ReInspireActivityAttributes
    typealias LAState = ReInspireActivityAttributes.ContentState
    typealias LA = ActivityKit.Activity<ReInspireActivityAttributes>

    private var current: LA?

    // MARK: - Public

    func update(dailyGoal: Int? = nil, todayDone: Int, streakCurrent: Int,
                nextTaskTitle: String, goalReached: Bool) {
        // User opt-out: tear down anything running and never launch.
        guard AppPrefs.liveActivityEnabled else {
            endCurrent()
            return
        }
        let state = LAState(todayDone: todayDone, streakCurrent: streakCurrent,
                            nextTaskTitle: nextTaskTitle, goalReached: goalReached)
        if let activity = current ?? running() {
            push(activity, state: state)
        } else if let goal = dailyGoal {
            launch(dailyGoal: goal, state: state)
        }
    }

    /// Dismisses the running activity immediately, keeping its last content
    /// (used on day rollover and when the user disables the feature). A fresh
    /// activity re-launches on the next `update` when the feature is enabled.
    func endCurrent() {
        guard let activity = current ?? running() else { return }
        Task {
            await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            self.current = nil
        }
    }

    func end(todayDone: Int, streakCurrent: Int, goalReached: Bool) {
        guard let activity = current ?? running() else { return }
        let finalState = LAState(todayDone: todayDone, streakCurrent: streakCurrent,
                                 nextTaskTitle: "", goalReached: goalReached)
        let content = ActivityContent(state: finalState, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: ActivityUIDismissalPolicy.default)
            self.current = nil
        }
    }

    // MARK: - Private

    private func launch(dailyGoal: Int, state: LAState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let stale = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        let content = ActivityContent(state: state, staleDate: stale)
        do {
            current = try ActivityKit.Activity.request(
                attributes: Attrs(dailyGoal: dailyGoal),
                content: content
            )
        } catch {
            logger.error("LiveActivityService start error: \(error)")
        }
    }

    private func push(_ activity: LA, state: LAState) {
        let stale = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        let content = ActivityContent(state: state, staleDate: stale)
        Task { await activity.update(content) }
    }

    private func running() -> LA? {
        ActivityKit.Activity<Attrs>.activities.first
    }
}
