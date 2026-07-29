import Foundation

enum PhotoVerificationPolicy {
    static let settingKey = "requirePhotoVerification"

    static var requiresPhotoForEveryTask: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static func requiresPhoto(for activity: Activity) -> Bool {
        requiresPhotoForEveryTask
    }
}

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

enum ActivityCompletionMode: String, Codable, CaseIterable, Identifiable {
    case check
    case counter
    case timer
    case abstinence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .check: return String(localized: "Отметка")
        case .counter: return String(localized: "Счётчик")
        case .timer: return String(localized: "Таймер")
        case .abstinence: return String(localized: "Не делать")
        }
    }

    var icon: String {
        switch self {
        case .check: return "checkmark.circle.fill"
        case .counter: return "number.circle.fill"
        case .timer: return "timer"
        case .abstinence: return "hand.raised.fill"
        }
    }

    var needsTarget: Bool {
        self == .counter || self == .timer
    }

    var defaultUnit: String {
        switch self {
        case .counter: return String(localized: "раз")
        case .timer: return String(localized: "мин")
        case .check, .abstinence: return ""
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
    /// How the user records completion. Optional so cached rows created before
    /// the column existed continue to decode; `effectiveCompletionMode`
    /// provides the backwards-compatible value.
    var completionMode: ActivityCompletionMode? = nil
    var completionUnit: String? = nil
    var createdAt: Date
    var planId: UUID?
    var planTitle: String?
    var workspaceId: UUID?
    var parentId: UUID?
    var sortOrder: Int = 0
    var category: String?
    /// Shared across the per-child rows a parent creates in one "assign task"
    /// action, so the app can group an assignment and show who completed it.
    /// nil for self-created tasks and pre-grouping legacy assignments.
    var assignmentGroupId: UUID?
    /// ISO weekdays (1 = Monday ... 7 = Sunday) the activity is scheduled on.
    /// nil/empty = every day. Matches Postgres extract(isodow).
    var scheduleDays: [Int]?
    /// Data source bound to this task at creation, auto-counting its progress.
    var connector: DataConnector?
    /// Which metric the bound connector reads for this task (steps, games, ...).
    var connectorMetric: ConnectorMetric?

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
        case completionMode = "completion_mode"
        case completionUnit = "completion_unit"
        case createdAt = "created_at"
        case planId = "plan_id"
        case planTitle = "plan_title"
        case workspaceId = "workspace_id"
        case parentId = "parent_id"
        case sortOrder = "sort_order"
        case category
        case assignmentGroupId = "assignment_group_id"
        case scheduleDays = "schedule_days"
        case connector
        case connectorMetric = "connector_metric"
    }

    var progressFraction: Double {
        guard let target = goalTarget, target > 0 else { return 0 }
        return max(0, min(goalProgress / target, 1.0))
    }

    var effectiveCompletionMode: ActivityCompletionMode {
        completionMode ?? (goalTarget.map { $0 > 0 } == true ? .counter : .check)
    }

    var effectiveCompletionUnit: String {
        let unit = completionUnit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !unit.isEmpty { return unit }
        if connector != nil || connectorMetric != nil {
            switch connectorMetric ?? ConnectorMetric.infer(from: self) {
            case .steps: return String(localized: "шагов")
            case .activeEnergy: return String(localized: "ккал")
            case .exerciseMinutes: return String(localized: "мин")
            case .distance: return String(localized: "км")
            case .itemsToday: return String(localized: "раз")
            }
        }
        return effectiveCompletionMode.defaultUnit
    }

    var isFromParent: Bool { assignedBy != nil }
    var requiresPhotoProof: Bool { PhotoVerificationPolicy.requiresPhoto(for: self) }

    /// ISO weekday of a date: Monday = 1 ... Sunday = 7.
    /// Calendar.weekday is Sunday = 1 ... Saturday = 7, hence the shift
    /// (e.g. Calendar Mon=2 -> ISO 1, Calendar Sun=1 -> ISO 7).
    static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    /// Whether this activity is scheduled on the given date.
    /// Once-tasks are deadline-driven (the caller filters by deadline);
    /// recurring tasks with no scheduleDays run every day.
    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        guard frequency != .once else { return true }
        guard let days = scheduleDays, !days.isEmpty else { return true }
        return days.contains(Self.isoWeekday(of: date, calendar: calendar))
    }
}

struct CreateActivityRequest: Codable {
    /// Client-generated primary key. Sending it (instead of relying on the
    /// server default) lets a creation be applied optimistically and replayed
    /// from the offline queue without an id round-trip, and keeps later
    /// edits/deletes of an offline-created row referring to the same row.
    var id: UUID = UUID()
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
    var completionMode: ActivityCompletionMode? = nil
    var completionUnit: String? = nil
    var planId: UUID?
    var planTitle: String?
    var workspaceId: UUID?
    var parentId: UUID?
    var category: String? = nil
    var assignmentGroupId: UUID? = nil
    var scheduleDays: [Int]? = nil
    var connector: DataConnector? = nil
    var connectorMetric: ConnectorMetric? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assignedBy = "assigned_by"
        case title, description, type, condition, frequency, deadline
        case reminderTime = "reminder_time"
        case goalTarget = "goal_target"
        case completionMode = "completion_mode"
        case completionUnit = "completion_unit"
        case planId = "plan_id"
        case planTitle = "plan_title"
        case workspaceId = "workspace_id"
        case parentId = "parent_id"
        case category
        case assignmentGroupId = "assignment_group_id"
        case scheduleDays = "schedule_days"
        case connector
        case connectorMetric = "connector_metric"
    }
}

extension Activity {
    /// Build the in-memory row a create request produces, so a new activity can
    /// be shown (and cached) instantly without waiting for the insert to return.
    /// Server-maintained columns start at their zero values.
    init(from req: CreateActivityRequest, createdAt: Date = Date()) {
        self.init(
            id: req.id,
            userId: req.userId,
            assignedBy: req.assignedBy,
            title: req.title,
            description: req.description,
            type: req.type,
            condition: req.condition,
            frequency: req.frequency,
            deadline: req.deadline,
            reminderTime: req.reminderTime,
            status: .active,
            streakCurrent: 0,
            streakBest: 0,
            goalProgress: 0,
            goalTarget: req.goalTarget,
            completionMode: req.completionMode,
            completionUnit: req.completionUnit,
            createdAt: createdAt,
            planId: req.planId,
            planTitle: req.planTitle,
            workspaceId: req.workspaceId,
            parentId: req.parentId,
            sortOrder: 0,
            category: req.category,
            assignmentGroupId: req.assignmentGroupId,
            scheduleDays: req.scheduleDays,
            connector: req.connector,
            connectorMetric: req.connectorMetric
        )
    }
}
