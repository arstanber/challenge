import ActivityKit
import Foundation

// MARK: - Live Activity attributes (#20)
// NOTE: This definition is duplicated in w1/w1LiveActivity.swift (widget target).
// Both copies MUST stay in sync — they encode/decode the same data.

public struct ChallengeActivityAttributes: ActivityAttributes {
    public var dailyGoal: Int

    public struct ContentState: Codable, Hashable {
        public var todayDone: Int
        public var streakCurrent: Int
        public var nextTaskTitle: String
        public var goalReached: Bool
    }
}
