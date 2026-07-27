import ActivityKit
import Foundation

// MARK: - Live Activity attributes (#20)
// NOTE: This definition is duplicated in w1/w1LiveActivity.swift (widget target).
// Both copies MUST stay in sync — they encode/decode the same data.

/// One row in the expanded island's today list. Kept tiny: ActivityKit caps
/// the encoded content state, so we ship at most a few of these.
public struct LiveTask: Codable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var verifying: Bool

    public init(id: UUID, title: String, done: Bool, verifying: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
        self.verifying = verifying
    }
}

public struct ReInspireActivityAttributes: ActivityAttributes {
    public var dailyGoal: Int

    public struct ContentState: Codable, Hashable {
        public var todayDone: Int
        public var streakCurrent: Int
        public var nextTaskTitle: String
        public var goalReached: Bool
        /// Today's top-level tasks (capped) shown in the expanded presentation.
        public var tasks: [LiveTask]
        /// Transient: drives the green checkmark pop in compact/minimal right
        /// after a verification is approved.
        public var flashApproved: Bool
        /// Optional persisted task timer. Optional fields keep remote pushes
        /// from older server code backwards-compatible with the new widget.
        public var timerTaskId: UUID?
        public var timerTitle: String?
        public var timerStartedAt: Date?
        public var timerAccumulatedSeconds: Double?
        public var timerTargetMinutes: Double?

        public init(todayDone: Int, streakCurrent: Int, nextTaskTitle: String,
                    goalReached: Bool, tasks: [LiveTask] = [], flashApproved: Bool = false,
                    timerTaskId: UUID? = nil, timerTitle: String? = nil,
                    timerStartedAt: Date? = nil, timerAccumulatedSeconds: Double? = nil,
                    timerTargetMinutes: Double? = nil) {
            self.todayDone = todayDone
            self.streakCurrent = streakCurrent
            self.nextTaskTitle = nextTaskTitle
            self.goalReached = goalReached
            self.tasks = tasks
            self.flashApproved = flashApproved
            self.timerTaskId = timerTaskId
            self.timerTitle = timerTitle
            self.timerStartedAt = timerStartedAt
            self.timerAccumulatedSeconds = timerAccumulatedSeconds
            self.timerTargetMinutes = timerTargetMinutes
        }
    }
}
