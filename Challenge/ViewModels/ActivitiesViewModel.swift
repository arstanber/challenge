import Foundation
import Supabase
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "ActivitiesViewModel")

// Lightweight model for streak calculation (only dates needed)
private struct ReportDate: Decodable {
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
}

private struct ReportActivityId: Decodable {
    let activityId: UUID
    enum CodingKeys: String, CodingKey { case activityId = "activity_id" }
}

private struct HabitReport: Encodable {
    let activityId: UUID
    let aiResult: String
    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case aiResult = "ai_result"
    }
}

// MARK: - Plan Group model

struct ActivityPlanGroup: Identifiable {
    let id: UUID
    let title: String
    var activities: [Activity]

    var completedCount: Int { activities.filter { $0.status == .completed }.count }
    var totalCount: Int { activities.count }
    var progressFraction: Double { totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0 }
    var isFullyCompleted: Bool { completedCount == totalCount && totalCount > 0 }
}

@Observable
final class ActivitiesViewModel {
    var myActivities: [Activity] = []
    var parentActivities: [Activity] = []
    var isLoading = false
    var errorMessage: String?

    // IDs of recurring activities already completed today — UserDefaults is source of truth
    var todayDoneIds: Set<UUID> = []

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "habitDone_\(f.string(from: Date()))"
    }

    private func readLocalDoneIds() -> Set<UUID> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.todayKey) ?? []
        return Set(arr.compactMap { UUID(uuidString: $0) })
    }

    private func persistLocalDoneId(_ id: UUID) {
        var arr = UserDefaults.standard.stringArray(forKey: Self.todayKey) ?? []
        let str = id.uuidString
        if !arr.contains(str) {
            arr.append(str)
            UserDefaults.standard.set(arr, forKey: Self.todayKey)
        }
    }

    var globalStreakCurrent: Int = 0
    var globalStreakBest: Int = 0
    var todayCount: Int = 0

    private let authService = AuthService.shared
    private let calendar = Calendar.current

    var activeCount: Int { myActivities.filter { $0.status == .active }.count }
    var canCreateMore: Bool {
        guard let user = authService.currentUser else { return false }
        return user.isPremium || activeCount < Constants.App.maxFreeActivities
    }

    // Map from parent_id → active child activities
    var childActivitiesMap: [UUID: [Activity]] {
        var map: [UUID: [Activity]] = [:]
        for a in myActivities where a.parentId != nil && a.status == .active {
            map[a.parentId!, default: []].append(a)
        }
        return map
    }

    var planGroups: [ActivityPlanGroup] {
        var groups: [UUID: ActivityPlanGroup] = [:]
        for activity in myActivities {
            guard let planId = activity.planId else { continue }
            if groups[planId] == nil {
                groups[planId] = ActivityPlanGroup(
                    id: planId,
                    title: activity.planTitle ?? "AI Plan",
                    activities: []
                )
            }
            groups[planId]!.activities.append(activity)
        }
        return groups.values
            .map { group in
                var g = group
                g.activities.sort { $0.createdAt < $1.createdAt }
                return g
            }
            .sorted { $0.title < $1.title }
    }

    var standaloneActivities: [Activity] {
        myActivities.filter { $0.planId == nil }
    }

    // MARK: - Load

    func loadActivities() async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        errorMessage = nil
        do {
            let all: [Activity] = try await supabase
                .from("activities")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .order("sort_order", ascending: true)
                .order("created_at", ascending: false)
                .execute()
                .value
            myActivities = all.filter { $0.assignedBy == nil }
            parentActivities = all.filter { $0.assignedBy != nil }
            // Load from local cache instantly, then merge with DB
            todayDoneIds = readLocalDoneIds()
            await recalculateGlobalStreak()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadWorkspaceActivities(workspaceId: UUID) async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        errorMessage = nil
        do {
            let all: [Activity] = try await supabase
                .from("activities")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .eq("workspace_id", value: workspaceId.uuidString)
                .order("sort_order", ascending: true)
                .order("created_at", ascending: false)
                .execute()
                .value
            myActivities = all.filter { $0.assignedBy == nil }
            parentActivities = all.filter { $0.assignedBy != nil }
            todayDoneIds = readLocalDoneIds()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Complete recurring habit

    func markHabitDone(_ activity: Activity) async {
        // Persist locally first — this is the source of truth
        persistLocalDoneId(activity.id)
        todayDoneIds.insert(activity.id)

        // Best-effort DB insert for streak tracking; never rollback on failure
        do {
            let report = HabitReport(activityId: activity.id, aiResult: "habit_done")
            try await supabase
                .from("reports")
                .insert(report)
                .execute()
            await recalculateGlobalStreak()
        } catch {
            logger.error("Habit report insert error (streak may be off): \(error)")
        }
    }

    /// Mark a task done for today locally (after a photo report was already saved elsewhere),
    /// without inserting a second report. Hides it from today's list / counts the ring.
    func markDoneLocally(_ activity: Activity) {
        persistLocalDoneId(activity.id)
        todayDoneIds.insert(activity.id)
        publishWidgetSnapshot()
        Task { await recalculateGlobalStreak() }
    }

    // MARK: - Global Streak

    func recalculateGlobalStreak() async {
        let allIds = (myActivities + parentActivities).map { $0.id.uuidString }
        guard !allIds.isEmpty else {
            globalStreakCurrent = 0
            globalStreakBest = 0
            todayCount = 0
            return
        }

        do {
            let reports: [ReportDate] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: allIds)
                .order("created_at", ascending: true)
                .execute()
                .value

            let (current, best, todayN) = computeStreak(from: reports.map { $0.createdAt })
            globalStreakCurrent = current
            globalStreakBest = best
            todayCount = todayN
        } catch {
            logger.error("Global streak calc error: \(error)")
        }
        publishWidgetSnapshot()
    }

    // MARK: - Widget snapshot

    /// Builds a lightweight snapshot of the current state and writes it to the
    /// shared App Group so the Home/Lock Screen widgets can render it.
    func publishWidgetSnapshot() {
        let topLevelActive = myActivities.filter { $0.parentId == nil && $0.status == .active }
        let tasks: [WidgetTask] = topLevelActive
            .prefix(6)
            .map { activity in
                WidgetTask(
                    id: activity.id,
                    title: activity.title,
                    typeIcon: activity.type.icon,
                    typeColorName: widgetColorName(for: activity.type),
                    deadline: activity.deadline,
                    isDone: todayDoneIds.contains(activity.id)
                )
            }

        let snapshot = WidgetSnapshot(
            streakCurrent: globalStreakCurrent,
            streakBest: globalStreakBest,
            todayDone: todayDoneTopLevelCount,
            dailyGoal: Constants.App.minDailyActivitiesForStreak,
            activeCount: activeCount,
            tasks: tasks,
            updatedAt: Date()
        )
        WidgetDataStore.save(snapshot)

        // Live Activity (#20)
        let nextTask = myActivities
            .filter { $0.parentId == nil && $0.status == .active && !todayDoneIds.contains($0.id) }
            .first?.title ?? ""
        let goalReached = todayDoneTopLevelCount >= Constants.App.minDailyActivitiesForStreak
        LiveActivityService.shared.update(
            dailyGoal: Constants.App.minDailyActivitiesForStreak,
            todayDone: todayDoneTopLevelCount,
            streakCurrent: globalStreakCurrent,
            nextTaskTitle: nextTask,
            goalReached: goalReached
        )
    }

    private func widgetColorName(for type: ActivityType) -> String {
        switch type {
        case .challenge: return "blue"
        case .goal: return "green"
        case .task: return "orange"
        case .habit: return "purple"
        case .assignment: return "pink"
        }
    }

    // MARK: - Streak Algorithm

    private func computeStreak(from dates: [Date]) -> (current: Int, best: Int, today: Int) {
        let minPerDay = Constants.App.minDailyActivitiesForStreak

        var dayCount: [Date: Int] = [:]
        for date in dates {
            let day = calendar.startOfDay(for: date)
            dayCount[day, default: 0] += 1
        }

        let qualifyingDays = dayCount
            .filter { $0.value >= minPerDay }
            .map { $0.key }
            .sorted()

        let today = calendar.startOfDay(for: Date())
        let todayN = dayCount[today] ?? 0

        guard !qualifyingDays.isEmpty else { return (0, 0, todayN) }

        var bestStreak = 1
        var tempStreak = 1
        for i in 1..<qualifyingDays.count {
            let diff = calendar.dateComponents([.day], from: qualifyingDays[i - 1], to: qualifyingDays[i]).day ?? 0
            if diff == 1 {
                tempStreak += 1
                bestStreak = max(bestStreak, tempStreak)
            } else {
                tempStreak = 1
            }
        }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastQualified = qualifyingDays.last!

        var currentStreak = 0
        if lastQualified == today || lastQualified == yesterday {
            var expectedDay = lastQualified
            for day in qualifyingDays.reversed() {
                if day == expectedDay {
                    currentStreak += 1
                    expectedDay = calendar.date(byAdding: .day, value: -1, to: expectedDay)!
                } else {
                    break
                }
            }
        }

        return (currentStreak, bestStreak, todayN)
    }

    // MARK: - Mutations

    func deleteActivity(_ activity: Activity) async {
        do {
            try await supabase
                .from("activities")
                .delete()
                .eq("id", value: activity.id.uuidString)
                .execute()
            myActivities.removeAll { $0.id == activity.id }
            parentActivities.removeAll { $0.id == activity.id }
            NotificationService.shared.cancelReminder(for: activity.id)
            await recalculateGlobalStreak()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reorder (drag & drop)

    /// Live in-array move while dragging. Reorders within myActivities.
    func moveActivity(_ dragged: Activity, before target: Activity) {
        guard dragged.id != target.id,
              let from = myActivities.firstIndex(where: { $0.id == dragged.id }),
              let to = myActivities.firstIndex(where: { $0.id == target.id })
        else { return }
        let item = myActivities.remove(at: from)
        myActivities.insert(item, at: to)
    }

    /// Persist the current order to the DB by writing sequential sort_order values.
    func persistOrder() async {
        let ordered = myActivities
        for (idx, activity) in ordered.enumerated() where activity.sortOrder != idx {
            myActivities[idx].sortOrder = idx
            do {
                try await supabase
                    .from("activities")
                    .update(["sort_order": idx])
                    .eq("id", value: activity.id.uuidString)
                    .execute()
            } catch {
                logger.error("persistOrder failed for \(activity.title): \(error)")
            }
        }
    }

    func markCompleted(_ activity: Activity) async {
        // Track as "done today" locally so the day-progress ring counts it
        persistLocalDoneId(activity.id)
        todayDoneIds.insert(activity.id)
        do {
            try await supabase
                .from("activities")
                .update(["status": "completed"])
                .eq("id", value: activity.id.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                myActivities[idx].status = .completed
            }
            // If this was a subtask, check if all siblings are done → auto-complete parent
            if let parentId = activity.parentId {
                await checkAndCompleteParent(parentId: parentId)
            }
            publishWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Move to tomorrow

    func moveToTomorrow(_ activity: Activity) async {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let target = cal.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let formatter = ISO8601DateFormatter()
        do {
            try await supabase
                .from("activities")
                .update(["deadline": formatter.string(from: target)])
                .eq("id", value: activity.id.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                myActivities[idx].deadline = target
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Duplicate

    func duplicate(_ activity: Activity) async {
        guard let user = authService.currentUser else { return }
        let req = CreateActivityRequest(
            userId: user.id,
            assignedBy: nil,
            title: activity.title,
            description: activity.description,
            type: activity.type,
            condition: activity.condition,
            frequency: activity.frequency,
            deadline: activity.deadline,
            reminderTime: activity.reminderTime,
            goalTarget: activity.goalTarget,
            workspaceId: activity.workspaceId,
            parentId: activity.parentId
        )
        do {
            let created: Activity = try await supabase
                .from("activities")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            myActivities.insert(created, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a brand-new activity (used by the habit template picker / editor).
    func createActivity(
        title: String,
        type: ActivityType,
        frequency: ActivityFrequency,
        goalTarget: Double? = nil,
        reminderTime: Date? = nil,
        condition: String? = nil
    ) async {
        guard let user = authService.currentUser else { return }
        let req = CreateActivityRequest(
            userId: user.id,
            assignedBy: nil,
            title: title,
            description: "",
            type: type,
            condition: condition,
            frequency: frequency,
            deadline: nil,
            reminderTime: reminderTime,
            goalTarget: goalTarget,
            workspaceId: nil,
            parentId: nil
        )
        do {
            let created: Activity = try await supabase
                .from("activities")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            myActivities.insert(created, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit

    func updateActivity(
        _ activity: Activity,
        title: String,
        frequency: ActivityFrequency,
        deadline: Date?,
        reminderTime: Date?
    ) async {
        struct UpdateRequest: Encodable {
            let title: String
            let frequency: String
            let deadline: Date?
            let reminderTime: Date?
            enum CodingKeys: String, CodingKey {
                case title, frequency, deadline
                case reminderTime = "reminder_time"
            }
        }
        let req = UpdateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            frequency: frequency.rawValue,
            deadline: deadline,
            reminderTime: reminderTime
        )
        do {
            try await supabase
                .from("activities")
                .update(req)
                .eq("id", value: activity.id.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                myActivities[idx].title = req.title
                myActivities[idx].frequency = frequency
                myActivities[idx].deadline = deadline
                myActivities[idx].reminderTime = reminderTime
            }
            // Refresh reminder
            NotificationService.shared.cancelReminder(for: activity.id)
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                NotificationService.shared.scheduleLocalReminder(for: myActivities[idx])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Day progress (for the header ring)

    /// Top-level activities completed today (recurring habits + one-time tasks).
    var todayDoneTopLevelCount: Int {
        myActivities.filter { $0.parentId == nil && todayDoneIds.contains($0.id) }.count
    }

    private func checkAndCompleteParent(parentId: UUID) async {
        // All one-time subtasks of this parent must be .completed
        let siblings = myActivities.filter { $0.parentId == parentId }
        let allDone = siblings.allSatisfy { $0.status == .completed || todayDoneIds.contains($0.id) }
        guard allDone, !siblings.isEmpty else { return }

        do {
            try await supabase
                .from("activities")
                .update(["status": "completed"])
                .eq("id", value: parentId.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == parentId }) {
                myActivities[idx].status = .completed
            }
        } catch {
            logger.error("Auto-complete parent error: \(error)")
        }
    }
}
