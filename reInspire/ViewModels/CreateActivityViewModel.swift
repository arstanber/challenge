import Foundation
import Supabase
import PostgREST
import Observation

@Observable
@MainActor
final class CreateActivityViewModel {
    var title = ""
    var description = ""
    var type: ActivityType = .challenge {
        // Auto-verification lives on goal tasks; leaving .goal drops the binding.
        didSet { if type != .goal { selectedCapability = nil } }
    }
    var condition = ""
    var frequency: ActivityFrequency = .daily
    /// ISO weekdays (1=Mon..7=Sun) for weekly activities; empty = every day.
    var scheduleDays: Set<Int> = []
    var deadline: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    var hasDeadline = true
    var reminderEnabled = false
    var reminderTime: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()
    var goalTarget: String = ""
    /// Live text in the connector picker, e.g. "chess.com".
    var connectorQuery: String = ""
    /// Capability the user picked from the connector picker (binds the task).
    private(set) var selectedCapability: ConnectorCapability?
    var assignToChildId: UUID?
    /// When non-empty, the activity is created once for each of these children
    /// (parent "assign to all kids" flow). Takes precedence over assignToChildId.
    var assignToChildIds: [UUID] = []
    var workspaceId: UUID?
    var parentId: UUID?
    var category: String?

    var isLoading = false
    var errorMessage: String?
    var didCreate = false

    private let authService = AuthService.shared
    private let notifications = NotificationService.shared

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if type.hasAIVerification && condition.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        // A connector-bound task needs a positive target to count against.
        if selectedCapability != nil, !((Double(goalTarget) ?? 0) > 0) { return false }
        return true
    }

    var showConditionField: Bool { type.hasAIVerification && selectedCapability == nil }
    var showGoalTarget: Bool { type == .goal }

    // MARK: - Connector capability picker

    /// Capabilities matching the current query (full list when query is empty).
    var capabilityResults: [ConnectorCapability] {
        ConnectorCapability.search(connectorQuery)
    }

    /// Unit for the goal-target field once a capability is bound (e.g. "партий").
    var goalTargetUnit: String? { selectedCapability?.unit }

    /// Bind a capability: the task becomes an auto-tracked goal with a prefilled
    /// target and title (title only when the user hasn't typed their own).
    func selectCapability(_ capability: ConnectorCapability) {
        selectedCapability = capability
        type = .goal
        if (Double(goalTarget) ?? 0) <= 0 {
            goalTarget = String(Int(capability.defaultTarget))
        }
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = capability.taskTitle(target: Double(goalTarget) ?? capability.defaultTarget)
        }
        connectorQuery = ""
    }

    func clearCapability() {
        selectedCapability = nil
    }

    func create() async {
        guard isValid, let user = authService.currentUser else { return }
        isLoading = true
        errorMessage = nil

        // Resolve who this task is for. A child-assignment list wins over a
        // single child id; with neither, the task is the user's own.
        let childTargets: [UUID] = assignToChildIds.isEmpty
            ? (assignToChildId.map { [$0] } ?? [])
            : assignToChildIds
        let isAssignment = !childTargets.isEmpty
        let targets: [UUID] = isAssignment ? childTargets : [user.id]

        let resolvedScheduleDays = frequency == .weekly && !scheduleDays.isEmpty && scheduleDays.count < 7
            ? scheduleDays.sorted()
            : nil

        do {
            for target in targets {
                let request = CreateActivityRequest(
                    userId: target,
                    assignedBy: isAssignment ? user.id : nil,
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    type: type,
                    condition: showConditionField ? condition.trimmingCharacters(in: .whitespaces) : nil,
                    frequency: frequency,
                    deadline: hasDeadline ? deadline : nil,
                    reminderTime: reminderEnabled ? reminderTime : nil,
                    goalTarget: showGoalTarget ? Double(goalTarget) : nil,
                    workspaceId: workspaceId,
                    parentId: parentId,
                    category: category,
                    scheduleDays: resolvedScheduleDays,
                    connector: isAssignment ? nil : selectedCapability?.connector,
                    connectorMetric: isAssignment ? nil : selectedCapability?.metric
                )
                let created: Activity = try await supabase
                    .from("activities")
                    .insert(request)
                    .select()
                    .single()
                    .execute()
                    .value
                // Only schedule a local reminder for the user's own tasks --
                // a child's reminders live on the child's device.
                if reminderEnabled && !isAssignment {
                    notifications.scheduleLocalReminder(for: created)
                }
                // Parent assigned this to a child -- push them so it lands instantly.
                if isAssignment {
                    await notifications.sendPush(
                        toUserId: target,
                        title: "Новое задание 🎯",
                        body: "Родитель добавил: «\(created.title)»",
                        data: ["activity_id": created.id.uuidString]
                    )
                    AnalyticsService.shared.track(.activityCreated, ["type": "assigned_to_child"])
                } else if let capability = selectedCapability {
                    // Offer to connect the source the user explicitly bound.
                    ConnectorSuggestionEngine.shared.suggestExplicit(
                        capability.connector,
                        taskTitle: created.title
                    )
                } else {
                    ConnectorSuggestionEngine.shared.taskCreated(
                        title: created.title,
                        description: created.description,
                        category: category
                    )
                }
            }
            AnalyticsService.shared.track(.activityCreated, [
                "type": type.rawValue,
                "frequency": frequency.rawValue
            ])
            didCreate = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
