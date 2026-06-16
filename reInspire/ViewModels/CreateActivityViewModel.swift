import Foundation
import Supabase
import PostgREST
import Observation

@Observable
@MainActor
final class CreateActivityViewModel {
    var title = ""
    var description = ""
    var type: ActivityType = .challenge
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
    var assignToChildId: UUID?
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
        return true
    }

    var showConditionField: Bool { type.hasAIVerification }
    var showGoalTarget: Bool { type == .goal }

    func create() async {
        guard isValid, let user = authService.currentUser else { return }
        isLoading = true
        errorMessage = nil

        let request = CreateActivityRequest(
            userId: assignToChildId ?? user.id,
            assignedBy: assignToChildId != nil ? user.id : nil,
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
            scheduleDays: frequency == .weekly && !scheduleDays.isEmpty && scheduleDays.count < 7
                ? scheduleDays.sorted()
                : nil
        )

        do {
            let created: Activity = try await supabase
                .from("activities")
                .insert(request)
                .select()
                .single()
                .execute()
                .value
            if reminderEnabled {
                notifications.scheduleLocalReminder(for: created)
            }
            // Parent assigned this to a child -- push them so it lands instantly.
            if let childId = assignToChildId {
                await notifications.sendPush(
                    toUserId: childId,
                    title: "Новое задание 🎯",
                    body: "Родитель добавил: «\(created.title)»",
                    data: ["activity_id": created.id.uuidString]
                )
                AnalyticsService.shared.track(.activityCreated, ["type": "assigned_to_child"])
            }
            AnalyticsService.shared.track(.activityCreated, [
                "type": type.rawValue,
                "frequency": frequency.rawValue
            ])
            ConnectorSuggestionEngine.shared.taskCreated(
                title: created.title,
                description: created.description,
                category: category
            )
            didCreate = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
