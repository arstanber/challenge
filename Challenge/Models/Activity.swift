import Foundation

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case challenge, goal, task, habit, assignment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .challenge: return NSLocalizedString("Challenge", comment: "")
        case .goal: return NSLocalizedString("Goal", comment: "")
        case .task: return NSLocalizedString("Task", comment: "")
        case .habit: return NSLocalizedString("Habit", comment: "")
        case .assignment: return NSLocalizedString("Assignment", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .challenge: return "camera.fill"
        case .goal: return "target"
        case .task: return "checkmark.circle.fill"
        case .habit: return "repeat.circle.fill"
        case .assignment: return "person.2.fill"
        }
    }

    var requiresPhoto: Bool {
        switch self {
        case .challenge, .assignment: return true
        case .goal: return false
        case .task, .habit: return false
        }
    }

    var hasAIVerification: Bool {
        self == .challenge || self == .assignment
    }

    var hasStreak: Bool {
        self == .challenge || self == .habit
    }
}

enum ActivityStatus: String, Codable {
    case active, completed, failed

    var displayName: String {
        switch self {
        case .active: return NSLocalizedString("Active", comment: "")
        case .completed: return NSLocalizedString("Completed", comment: "")
        case .failed: return NSLocalizedString("Failed", comment: "")
        }
    }

    var color: String {
        switch self {
        case .active: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        }
    }
}

enum ActivityFrequency: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: return NSLocalizedString("One-time", comment: "")
        case .daily: return NSLocalizedString("Daily", comment: "")
        case .weekly: return NSLocalizedString("Weekly", comment: "")
        case .custom: return NSLocalizedString("Custom", comment: "")
        }
    }
}

struct Activity: Codable, Identifiable {
    let id: UUID
    var userId: UUID
    var assignedBy: UUID?
    var title: String
    var description: String
    var type: ActivityType
    var condition: String?
    var frequency: ActivityFrequency
    var deadline: Date?
    var reminderTime: Date?
    var status: ActivityStatus
    var streakCurrent: Int
    var streakBest: Int
    var goalProgress: Double
    var goalTarget: Double?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assignedBy = "assigned_by"
        case title, description, type, condition, frequency, deadline
        case reminderTime = "reminder_time"
        case status
        case streakCurrent = "streak_current"
        case streakBest = "streak_best"
        case goalProgress = "goal_progress"
        case goalTarget = "goal_target"
        case createdAt = "created_at"
    }

    var progressFraction: Double {
        guard let target = goalTarget, target > 0 else { return 0 }
        return min(goalProgress / target, 1.0)
    }

    var isFromParent: Bool { assignedBy != nil }
}

struct CreateActivityRequest: Codable {
    var userId: UUID
    var assignedBy: UUID?
    var title: String
    var description: String
    var type: ActivityType
    var condition: String?
    var frequency: ActivityFrequency
    var deadline: Date?
    var reminderTime: Date?
    var goalTarget: Double?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case assignedBy = "assigned_by"
        case title, description, type, condition, frequency, deadline
        case reminderTime = "reminder_time"
        case goalTarget = "goal_target"
    }
}
