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
    /// Last state + goal we pushed, so the verification helpers can mutate one
    /// field (e.g. a task's `verifying` flag) and re-push a coherent snapshot
    /// without the ActivitiesViewModel re-deriving everything.
    private var lastState: LAState?
    private var lastGoal: Int = 0
    /// Cancels a pending "clear the approved flash" task if another result
    /// arrives first.
    private var flashResetTask: Task<Void, Never>?

    // MARK: - Public

    func update(dailyGoal: Int? = nil, todayDone: Int, streakCurrent: Int,
                nextTaskTitle: String, goalReached: Bool, tasks: [LiveTask] = []) {
        // User opt-out: tear down anything running and never launch.
        guard AppPrefs.liveActivityEnabled else {
            endCurrent()
            return
        }
        // Preserve an in-flight verification spinner across routine refreshes:
        // carry over `verifying` flags the viewmodel doesn't know about.
        let merged = mergeVerifying(into: tasks)
        let state = LAState(todayDone: todayDone, streakCurrent: streakCurrent,
                            nextTaskTitle: nextTaskTitle, goalReached: goalReached,
                            tasks: merged, flashApproved: lastState?.flashApproved ?? false)
        if let goal = dailyGoal { lastGoal = goal }
        lastState = state
        if let activity = current ?? running() {
            push(activity, state: state)
        } else if let goal = dailyGoal {
            launch(dailyGoal: goal, state: state)
        }
    }

    // MARK: - Verification (#20b)

    /// A photo for `taskId` is being checked by the AI: show the spinner.
    func setVerifying(taskId: UUID, title: String) {
        guard AppPrefs.liveActivityEnabled else { return }
        flashResetTask?.cancel()
        var state = lastState ?? LAState(todayDone: 0, streakCurrent: 0,
                                         nextTaskTitle: title, goalReached: false)
        state.flashApproved = false
        setVerifyingFlag(&state, taskId: taskId, title: title, verifying: true)
        lastState = state
        pushOrLaunch(state)
    }

    /// The AI verdict landed. On approval, mark the row done and flash a green
    /// check in the island for a beat, then settle back to the ring.
    func resolveVerifying(taskId: UUID, approved: Bool) {
        guard AppPrefs.liveActivityEnabled else { return }
        guard var state = lastState else { return }
        setVerifyingFlag(&state, taskId: taskId, title: "", verifying: false)
        if approved, let idx = state.tasks.firstIndex(where: { $0.id == taskId }) {
            state.tasks[idx].done = true
        }
        state.flashApproved = approved
        lastState = state
        pushOrLaunch(state)

        guard approved else { return }
        flashResetTask?.cancel()
        flashResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, var s = self.lastState else { return }
                s.flashApproved = false
                self.lastState = s
                self.pushOrLaunch(s)
            }
        }
    }

    /// Dismisses the running activity immediately, keeping its last content
    /// (used on day rollover and when the user disables the feature). A fresh
    /// activity re-launches on the next `update` when the feature is enabled.
    func endCurrent() {
        flashResetTask?.cancel()
        lastState = nil
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

    private func setVerifyingFlag(_ state: inout LAState, taskId: UUID, title: String, verifying: Bool) {
        if let idx = state.tasks.firstIndex(where: { $0.id == taskId }) {
            state.tasks[idx].verifying = verifying
        } else if verifying {
            // Task not in the (capped) list yet -- inject it so the spinner shows.
            state.tasks.insert(LiveTask(id: taskId, title: title, done: false, verifying: true), at: 0)
        }
    }

    /// Re-apply any currently-spinning rows onto a freshly built task list.
    private func mergeVerifying(into tasks: [LiveTask]) -> [LiveTask] {
        guard let verifyingIds = lastState?.tasks.filter(\.verifying).map(\.id), !verifyingIds.isEmpty else {
            return tasks
        }
        return tasks.map { task in
            var t = task
            if verifyingIds.contains(task.id) { t.verifying = true }
            return t
        }
    }

    private func pushOrLaunch(_ state: LAState) {
        if let activity = current ?? running() {
            push(activity, state: state)
        } else if lastGoal > 0 {
            launch(dailyGoal: lastGoal, state: state)
        }
    }

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
