import Foundation
import Supabase
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "ActivitiesViewModel")

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

@MainActor
@Observable
final class ActivitiesViewModel {
    var myActivities: [Activity] = []
    var parentActivities: [Activity] = []
    var isLoading = false
    var errorMessage: String?

    /// Per-day goal-met flags for the current month (index i = day i+1), used by
    /// the "Прогресс за месяц" card and the month-progress home-screen widget.
    /// This is a display heatmap -- the server engine remains the streak source
    /// of truth; here a day is "met" when its check-ins reach the daily goal.
    private(set) var monthDays: [Bool] = []

    /// Weekly completion rates (last 6 weeks, index 0 = oldest) and 30-day
    /// check-in counts feeding the performance card / widget. Display metrics --
    /// the server stays authoritative for streaks.
    private(set) var weekRates: [Double] = []
    private(set) var last30Checkins = 0
    private(set) var prev30Checkins = 0

    // Done-today state and streaks live in TaskEngine (reports table is the
    // source of truth); these are thin pass-throughs so view code stays small.
    private let engine = TaskEngine.shared

    func isDoneToday(_ id: UUID) -> Bool { engine.isDoneToday(id) }
    func isHandledToday(_ id: UUID) -> Bool { engine.isHandledToday(id) }
    var globalStreakCurrent: Int { engine.globalStreakCurrent }
    var globalStreakBest: Int { engine.globalStreakBest }
    var todayCount: Int { engine.todayCount }
    var freezesAvailable: Int { engine.freezesAvailable }
    var yesterdayFreezable: Bool { engine.yesterdayFreezable }

    /// Spend a freeze on yesterday, then reload so the banner and streak update.
    func freezeYesterday() async {
        if await engine.useStreakFreeze() {
            await loadActivities()
        }
    }

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

    // MARK: - Disk cache (instant cold-start)

    /// On-disk snapshot of the lists so a cold launch paints the last-known
    /// tasks immediately, before the network round-trip. The server stays the
    /// source of truth -- this is only an optimistic head-start.
    private struct CachedLists: Codable {
        var mine: [Activity]
        var parents: [Activity]
    }

    private var cacheKey: String? {
        authService.currentUser.map { "activities_\($0.id.uuidString)" }
    }

    /// Populate the lists from disk when we have nothing yet, so the loading
    /// skeleton is skipped on a warm cache. Returns true on a cache hit.
    @discardableResult
    private func hydrateFromCache() -> Bool {
        guard myActivities.isEmpty, parentActivities.isEmpty,
              let key = cacheKey,
              let cached = DiskCache.load(CachedLists.self, key: key)
        else { return false }
        myActivities = cached.mine
        parentActivities = cached.parents
        return true
    }

    private func persistCache() {
        guard let key = cacheKey else { return }
        DiskCache.save(CachedLists(mine: myActivities, parents: parentActivities), key: key)
    }

    // MARK: - Load

    func loadActivities() async {
        guard let user = authService.currentUser else { return }
        // Paint cached tasks instantly; the network refresh below replaces them.
        hydrateFromCache()
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
            await engine.refresh(activityIds: all.map(\.id))
            await replayWidgetCheckins()
            await engine.refreshStreaks()
            applyEngineStreaks()
            await recomputeMonthDays()
            await recomputePerformance()
            publishWidgetSnapshot()
            persistCache()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Turn completions tapped on the home-screen widget into real check-in
    /// reports (the widget extension has no Supabase session, so it only
    /// queues ids in the App Group).
    private func replayWidgetCheckins() async {
        let ids = WidgetDataStore.drainPendingCheckins()
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let activity = (myActivities + parentActivities).first(where: { $0.id == id }),
                  activity.status == .active,
                  !activity.type.hasAIVerification,
                  !engine.isDoneToday(id)
            else { continue }
            await engine.markDone(activity)
        }
    }

    /// Patch server-maintained streaks into the in-memory activities.
    private func applyEngineStreaks() {
        for (idx, activity) in myActivities.enumerated() {
            if let s = engine.activityStreaks[activity.id] {
                myActivities[idx].streakCurrent = s.current
                myActivities[idx].streakBest = s.best
            }
        }
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
            await engine.refresh(activityIds: all.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Complete recurring habit

    /// Mark a recurring habit done: instant local tick + check-in report in the DB.
    func markHabitDone(_ activity: Activity) async {
        await engine.markDone(activity)
        applyEngineStreaks()
        publishWidgetSnapshot()
    }

    /// Mark a task done for today locally (after a photo report was already saved elsewhere),
    /// without inserting a second report. Hides it from today's list / counts the ring.
    func markDoneLocally(_ activity: Activity) {
        engine.markDoneLocally(activity.id)
        publishWidgetSnapshot()
    }

    /// Re-sync done-today state and streaks from the server (e.g. after a photo report).
    func recalculateGlobalStreak() async {
        await engine.resync()
        applyEngineStreaks()
        publishWidgetSnapshot()
    }

    // MARK: - Month progress (heatmap dots)

    /// Recompute per-day goal-met flags for the current month from the reports
    /// table. A day counts as met when its check-ins reach the daily goal --
    /// the same denominator the rest of the app shows. Network-backed, so it is
    /// refreshed on load (not on every optimistic tick); `publishWidgetSnapshot`
    /// patches today's dot locally in between.
    func recomputeMonthDays() async {
        let now = Date()
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let todayDay = calendar.component(.day, from: now)
        let ids = (myActivities + parentActivities).map(\.id)
        guard !ids.isEmpty else {
            monthDays = Array(repeating: false, count: daysInMonth)
            return
        }
        let goal = max(1, dailyStreakGoal)
        do {
            struct Row: Decodable {
                let createdAt: Date
                enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
            }
            let rows: [Row] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: ids.map(\.uuidString))
                .gte("created_at", value: ISO8601DateFormatter().string(from: interval.start))
                .execute()
                .value
            var counts: [Int: Int] = [:]
            for r in rows {
                counts[calendar.component(.day, from: r.createdAt), default: 0] += 1
            }
            monthDays = (1...daysInMonth).map { day in
                day <= todayDay && (counts[day] ?? 0) >= goal
            }
        } catch {
            logger.error("recomputeMonthDays failed: \(error)")
            if monthDays.count != daysInMonth {
                monthDays = Array(repeating: false, count: daysInMonth)
            }
        }
    }

    // MARK: - Performance (weekly bars + 30-day growth)

    /// Recompute weekly completion rates for the last 6 weeks plus the trailing
    /// 30-day vs prior-30-day check-in counts, from the reports table.
    func recomputePerformance() async {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let ids = (myActivities + parentActivities).map(\.id)
        guard !ids.isEmpty, let windowStart = cal.date(byAdding: .day, value: -59, to: today) else {
            weekRates = []; last30Checkins = 0; prev30Checkins = 0
            return
        }
        let goal = max(1, dailyStreakGoal)
        do {
            struct Row: Decodable {
                let createdAt: Date
                enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
            }
            let rows: [Row] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: ids.map(\.uuidString))
                .gte("created_at", value: ISO8601DateFormatter().string(from: windowStart))
                .execute()
                .value

            var weekCounts = Array(repeating: 0, count: 6)
            var last30 = 0, prev30 = 0
            for r in rows {
                let day = cal.startOfDay(for: r.createdAt)
                let offset = cal.dateComponents([.day], from: day, to: today).day ?? 0
                guard offset >= 0 else { continue }
                if offset < 30 { last30 += 1 } else if offset < 60 { prev30 += 1 }
                if offset < 42 { weekCounts[5 - offset / 7] += 1 }
            }
            weekRates = weekCounts.map { Double($0) / Double(goal * 7) }
            last30Checkins = last30
            prev30Checkins = prev30
        } catch {
            logger.error("recomputePerformance failed: \(error)")
        }
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
                    isDone: engine.isDoneToday(activity.id),
                    requiresPhoto: activity.type.hasAIVerification
                )
            }

        // Patch today's dot from the live count so the widget reflects a
        // just-completed task without waiting for the next month recompute.
        var days = monthDays
        let todayIdx = calendar.component(.day, from: Date()) - 1
        if days.indices.contains(todayIdx) {
            days[todayIdx] = todayDoneTopLevelCount >= dailyStreakGoal
        }

        let snapshot = WidgetSnapshot(
            streakCurrent: globalStreakCurrent,
            streakBest: globalStreakBest,
            todayDone: todayDoneTopLevelCount,
            dailyGoal: dailyStreakGoal,
            activeCount: activeCount,
            tasks: tasks,
            updatedAt: Date(),
            monthDays: days.isEmpty ? nil : days,
            weekRates: weekRates.isEmpty ? nil : weekRates,
            last30Checkins: last30Checkins,
            prev30Checkins: prev30Checkins,
            isPremium: authService.currentUser?.isPremium ?? false
        )
        WidgetDataStore.save(snapshot)

        // Live Activity (#20)
        let nextTask = myActivities
            .filter { $0.parentId == nil && $0.status == .active && !engine.isHandledToday($0.id) }
            .first?.title ?? ""
        let goalReached = todayDoneTopLevelCount >= dailyStreakGoal
        LiveActivityService.shared.update(
            dailyGoal: dailyStreakGoal,
            todayDone: todayDoneTopLevelCount,
            streakCurrent: globalStreakCurrent,
            nextTaskTitle: nextTask,
            goalReached: goalReached
        )

        // Keep the cold-start cache in step with optimistic mutations so a
        // relaunch shows the just-changed list, not the last network snapshot.
        persistCache()
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

    // MARK: - Mutations

    /// Deletes an activity. `reason` is mandatory and logged to
    /// `activity_deletions` before the activity (and its reports) are removed.
    func deleteActivity(_ activity: Activity, reason: String) async {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { return }

        do {
            if let userId = authService.currentUser?.id {
                try await supabase
                    .from("activity_deletions")
                    .insert([
                        "user_id": userId.uuidString,
                        "activity_id": activity.id.uuidString,
                        "title": activity.title,
                        "type": activity.type.rawValue,
                        "reason": trimmedReason,
                    ])
                    .execute()
            }
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

    /// Reorder the top-level active tasks (ReorderSheet) and remap the new
    /// order into myActivities, leaving every other row in place.
    func moveTopLevel(fromOffsets: IndexSet, toOffset: Int) {
        var top = myActivities.filter { $0.parentId == nil && $0.status == .active }
        // Same semantics as SwiftUI's move(fromOffsets:toOffset:) without
        // importing SwiftUI into the view model.
        let indices = fromOffsets.sorted()
        let moving = indices.map { top[$0] }
        for index in indices.reversed() { top.remove(at: index) }
        let adjusted = toOffset - indices.filter { $0 < toOffset }.count
        top.insert(contentsOf: moving, at: min(adjusted, top.count))
        var iterator = top.makeIterator()
        myActivities = myActivities.map { item in
            guard item.parentId == nil, item.status == .active,
                  let next = iterator.next() else { return item }
            return next
        }
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
        engine.markDoneLocally(activity.id)
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

    /// Create a brand-new activity (used by the habit template picker / editor
    /// and the first-win card, which needs the created value back to open the
    /// photo flow immediately).
    @discardableResult
    func createActivity(
        title: String,
        type: ActivityType,
        frequency: ActivityFrequency,
        goalTarget: Double? = nil,
        reminderTime: Date? = nil,
        condition: String? = nil,
        scheduleDays: [Int]? = nil
    ) async -> Activity? {
        guard let user = authService.currentUser else { return nil }
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
            parentId: nil,
            scheduleDays: scheduleDays
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
            ConnectorSuggestionEngine.shared.taskCreated(title: created.title, description: created.description)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Creates a single one-off subtask under a parent goal. Mirrors
    /// ActivityDetailViewModel.createSubtasks for the manual "add subtask" flow.
    func createSubtask(parent: Activity, title: String, deadline: Date?) async {
        guard let user = authService.currentUser else { return }
        let req = CreateActivityRequest(
            userId: user.id,
            assignedBy: nil,
            title: title,
            description: "",
            type: .task,
            condition: nil,
            frequency: .once,
            deadline: deadline,
            reminderTime: nil,
            goalTarget: nil,
            planId: nil,
            planTitle: nil,
            workspaceId: parent.workspaceId,
            parentId: parent.id
        )
        do {
            let created: Activity = try await supabase
                .from("activities")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            myActivities.append(created)
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
        reminderTime: Date?,
        scheduleDays: [Int]? = nil
    ) async {
        struct UpdateRequest: Encodable {
            let title: String
            let frequency: String
            let deadline: Date?
            let reminderTime: Date?
            let scheduleDays: [Int]?
            enum CodingKeys: String, CodingKey {
                case title, frequency, deadline
                case reminderTime = "reminder_time"
                case scheduleDays = "schedule_days"
            }
            // Custom encode so schedule_days is sent as explicit null when nil --
            // switching weekly -> daily must clear stale days in the DB
            // (synthesized Codable would omit the key entirely).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(title, forKey: .title)
                try c.encode(frequency, forKey: .frequency)
                try c.encode(deadline, forKey: .deadline)
                try c.encode(reminderTime, forKey: .reminderTime)
                try c.encode(scheduleDays, forKey: .scheduleDays)
            }
        }
        // Only weekly tasks carry specific days; daily/once clear them.
        let days = frequency == .weekly ? scheduleDays : nil
        let req = UpdateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            frequency: frequency.rawValue,
            deadline: deadline,
            reminderTime: reminderTime,
            scheduleDays: days
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
                myActivities[idx].scheduleDays = days
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
        myActivities.filter { $0.parentId == nil && engine.isDoneToday($0.id) }.count
    }

    /// Today's streak goal under the 75% rule: share of the recurring tasks
    /// scheduled today (mirrors the server's compute_user_streak denominator).
    var dailyStreakGoal: Int {
        let scheduledToday = myActivities.filter {
            $0.parentId == nil && $0.status == .active
            && $0.frequency != .once && $0.isScheduled(on: Date())
        }.count
        return Constants.App.dailyStreakGoal(scheduledToday: scheduledToday)
    }

    private func checkAndCompleteParent(parentId: UUID) async {
        // A goal finishes when all its one-time subtasks are completed.
        // Recurring children never "finish" -- they neither block nor complete
        // the parent (a single done-today tick must not close a goal forever).
        let siblings = myActivities.filter { $0.parentId == parentId }
        let onceSiblings = siblings.filter { $0.frequency == .once }
        guard !onceSiblings.isEmpty else { return }
        let allDone = onceSiblings.allSatisfy { $0.status == .completed }
        guard allDone else { return }

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
