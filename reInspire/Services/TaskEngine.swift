import Foundation
import Supabase
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "TaskEngine")

/// Single owner of "done today" state and streaks.
///
/// Source of truth is the `reports` table: an activity is done today when a
/// report with a counting `ai_result` exists for the user's current day.
/// A local optimistic overlay (persisted to UserDefaults) keeps completion
/// instant offline; it is reconciled against the server on every `refresh`.
///
/// Streaks are computed server-side by the `refresh_my_streaks` RPC (the same
/// algorithm the leaderboard and the reports trigger use); the client only
/// reads. A local recomputation is kept as an offline fallback so the home
/// header never blanks out.
@MainActor
@Observable
final class TaskEngine {
    static let shared = TaskEngine()

    // MARK: - State

    /// Activities with any non-rejected report today, including excused --
    /// used to hide tasks from today's list ("already handled").
    private(set) var handledTodayIds: Set<UUID> = []
    /// Activities that count toward the day ring and streak (excludes excused).
    private(set) var doneTodayIds: Set<UUID> = []
    /// Local overlay for instant feedback and offline completions.
    private(set) var optimisticDoneIds: Set<UUID> = []

    private(set) var globalStreakCurrent = 0
    private(set) var globalStreakBest = 0
    /// Distinct activities completed today (server-computed when online).
    private(set) var serverTodayCount = 0
    /// Spendable streak freezes (server is the single source of truth).
    private(set) var freezesAvailable = 0
    /// True when yesterday is missed, unfrozen, and the user has balance.
    private(set) var yesterdayFreezable = false
    /// Per-activity streaks from the last `refresh_my_streaks` call.
    private(set) var activityStreaks: [UUID: (current: Int, best: Int)] = [:]

    /// Activity ids known from the last refresh -- used by the offline fallback.
    private var knownActivityIds: [UUID] = []

    private let calendar = Calendar.current

    private init() {
        optimisticDoneIds = Self.readIdSet(key: Self.doneKey)
    }

    /// Today's count for UI: server count plus optimistic completions the
    /// server hasn't confirmed yet.
    var todayCount: Int {
        serverTodayCount + optimisticDoneIds.subtracting(doneTodayIds).count
    }

    /// Number of known activities not yet handled today -- used for the
    /// morning reminder ("today's task list") notification copy.
    var pendingTodayCount: Int {
        max(0, knownActivityIds.count - handledTodayIds.subtracting(optimisticDoneIds).count - optimisticDoneIds.count)
    }

    /// The one rule for "is this task completed today".
    func isDoneToday(_ id: UUID) -> Bool {
        doneTodayIds.contains(id) || optimisticDoneIds.contains(id)
    }

    /// True when the task needs no further attention today (done or excused).
    func isHandledToday(_ id: UUID) -> Bool {
        handledTodayIds.contains(id) || optimisticDoneIds.contains(id)
    }

    // MARK: - UserDefaults (day-keyed cache + offline queue)

    private static var dayStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    // Same key the app used before the redesign so existing caches carry over.
    private static var doneKey: String { "habitDone_\(dayStamp)" }
    private static var pendingKey: String { "pendingReports_\(dayStamp)" }

    private static func readIdSet(key: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init))
    }

    private static func persist(_ id: UUID, key: String) {
        var arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !arr.contains(id.uuidString) {
            arr.append(id.uuidString)
            UserDefaults.standard.set(arr, forKey: key)
        }
    }

    private static func remove(_ id: UUID, key: String) {
        var arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        arr.removeAll { $0 == id.uuidString }
        UserDefaults.standard.set(arr, forKey: key)
    }

    // MARK: - Refresh (server -> client)

    private struct TodayReportRow: Decodable {
        let activityId: UUID
        let aiResult: AIVerificationResult
        enum CodingKeys: String, CodingKey {
            case activityId = "activity_id"
            case aiResult = "ai_result"
        }
    }

    /// Reload today's completion state from the reports table and replay any
    /// completions queued while offline.
    func refresh(activityIds: [UUID]) async {
        knownActivityIds = activityIds
        await replayPendingReports()
        guard !activityIds.isEmpty else {
            handledTodayIds = []
            doneTodayIds = []
            return
        }
        let startOfDay = calendar.startOfDay(for: Date())
        do {
            let rows: [TodayReportRow] = try await supabase
                .from("reports")
                .select("activity_id, ai_result")
                .in("activity_id", values: activityIds.map(\.uuidString))
                .gte("created_at", value: ISO8601DateFormatter().string(from: startOfDay))
                .execute()
                .value
            var handled: Set<UUID> = []
            var done: Set<UUID> = []
            for row in rows where row.aiResult != .rejected {
                handled.insert(row.activityId)
                if row.aiResult != .excused { done.insert(row.activityId) }
            }
            handledTodayIds = handled
            doneTodayIds = done
            // Server confirmed these -- the overlay no longer needs them.
            for id in optimisticDoneIds.intersection(done) {
                optimisticDoneIds.remove(id)
                Self.remove(id, key: Self.doneKey)
            }
        } catch {
            logger.error("refresh today state failed (keeping local overlay): \(error)")
        }
    }

    // MARK: - Completion

    /// Mark a recurring activity done: instant local tick, then a plain
    /// check-in report (ai_result defaults to 'not_applicable' server-side).
    /// Offline failures stay in the overlay and are replayed on next refresh.
    func markDone(_ activity: Activity) async {
        markDoneLocally(activity.id)
        await insertCheckinReport(activityId: activity.id, queueOnFailure: true)
        await refreshStreaks()
    }

    /// Local-only optimistic tick (used while a photo report is being handled
    /// elsewhere, or before the network round trip finishes).
    func markDoneLocally(_ id: UUID) {
        optimisticDoneIds.insert(id)
        Self.persist(id, key: Self.doneKey)
    }

    /// Tell the engine a report for this activity was inserted/updated/deleted
    /// outside `markDone` (photo flow, undo, goal progress).
    func noteReportChanged(activityId: UUID) async {
        if !knownActivityIds.contains(activityId) {
            knownActivityIds.append(activityId)
        }
        await resync()
    }

    /// Re-pull done-today state and streaks for the known activity set.
    func resync() async {
        await refresh(activityIds: knownActivityIds)
        await refreshStreaks()
    }

    /// Midnight rollover: yesterday's done/handled state must not leak into
    /// the new day. Re-reads the overlay from the new day-keyed cache (empty
    /// for a fresh day) and re-pulls today's reports and streaks.
    func handleDayChange() async {
        // Drop yesterday's Live Activity so it never carries stale day counts
        // into the new day; a fresh one re-launches on the next snapshot.
        LiveActivityService.shared.endCurrent()
        optimisticDoneIds = Self.readIdSet(key: Self.doneKey)
        handledTodayIds = []
        doneTodayIds = []
        serverTodayCount = 0
        await resync()
    }

    /// Today's reports for this activity were deleted (undo) -- drop every
    /// local trace, then re-sync with the server.
    func undoToday(activityId: UUID) async {
        optimisticDoneIds.remove(activityId)
        doneTodayIds.remove(activityId)
        handledTodayIds.remove(activityId)
        Self.remove(activityId, key: Self.doneKey)
        Self.remove(activityId, key: Self.pendingKey)
        await resync()
    }

    private func insertCheckinReport(activityId: UUID, queueOnFailure: Bool) async {
        do {
            let req = CreateReportRequest(activityId: activityId)
            try await supabase.from("reports").insert(req).execute()
            optimisticDoneIds.remove(activityId)
            Self.remove(activityId, key: Self.doneKey)
            doneTodayIds.insert(activityId)
            handledTodayIds.insert(activityId)
        } catch {
            logger.error("check-in report insert failed: \(error)")
            if queueOnFailure {
                Self.persist(activityId, key: Self.pendingKey)
            }
        }
    }

    /// Re-send check-ins that failed while offline (same local day only --
    /// the queue key is day-stamped, so stale entries expire naturally).
    private func replayPendingReports() async {
        let pending = Self.readIdSet(key: Self.pendingKey)
        guard !pending.isEmpty else { return }
        for id in pending {
            do {
                let req = CreateReportRequest(activityId: id)
                try await supabase.from("reports").insert(req).execute()
                Self.remove(id, key: Self.pendingKey)
                logger.debug("replayed pending check-in for \(id)")
            } catch {
                logger.error("pending check-in replay failed for \(id): \(error)")
            }
        }
    }

    // MARK: - Typical completion time

    private struct ReportTimeRow: Decodable {
        let createdAt: Date
        enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
    }

    /// Median minute-of-day (device timezone) of the user's recent reports --
    /// drives the "your usual time" nudge. Needs at least 5 reports over the
    /// last 30 days to be meaningful; returns nil otherwise.
    func typicalCompletionMinute() async -> Int? {
        guard !knownActivityIds.isEmpty else { return nil }
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        do {
            let rows: [ReportTimeRow] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: knownActivityIds.map(\.uuidString))
                .gte("created_at", value: ISO8601DateFormatter().string(from: monthAgo))
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            guard rows.count >= 5 else { return nil }
            let minutes = rows
                .map { calendar.component(.hour, from: $0.createdAt) * 60
                     + calendar.component(.minute, from: $0.createdAt) }
                .sorted()
            return minutes[minutes.count / 2]
        } catch {
            logger.error("typicalCompletionMinute failed: \(error)")
            return nil
        }
    }

    // MARK: - Streaks

    private struct StreakPayload: Decodable {
        struct ActivityStreak: Decodable {
            let id: UUID
            let streakCurrent: Int
            let streakBest: Int
            enum CodingKeys: String, CodingKey {
                case id
                case streakCurrent = "streak_current"
                case streakBest = "streak_best"
            }
        }
        let globalCurrent: Int
        let globalBest: Int
        let todayCount: Int
        let activities: [ActivityStreak]
        let freezesAvailable: Int?
        let yesterdayFreezable: Bool?
        enum CodingKeys: String, CodingKey {
            case globalCurrent = "global_current"
            case globalBest = "global_best"
            case todayCount = "today_count"
            case activities
            case freezesAvailable = "freezes_available"
            case yesterdayFreezable = "yesterday_freezable"
        }
    }

    /// Pull canonical streaks from the server (also self-heals the
    /// streak_current/streak_best columns on activities).
    func refreshStreaks() async {
        do {
            let payload: StreakPayload = try await supabase
                .rpc("refresh_my_streaks")
                .execute()
                .value
            globalStreakCurrent = payload.globalCurrent
            globalStreakBest = payload.globalBest
            serverTodayCount = payload.todayCount
            freezesAvailable = payload.freezesAvailable ?? 0
            yesterdayFreezable = payload.yesterdayFreezable ?? false
            activityStreaks = Dictionary(
                uniqueKeysWithValues: payload.activities.map { ($0.id, (current: $0.streakCurrent, best: $0.streakBest)) }
            )
            // Anyone with streak history is past their first report -- they
            // must never see the first-win activation card.
            if payload.globalBest > 0 || payload.todayCount > 0 {
                UserDefaults.standard.set(true, forKey: "hasSubmittedFirstReport")
            }
        } catch {
            logger.error("refresh_my_streaks failed, using offline fallback: \(error)")
            await computeStreaksFallback()
        }
    }

    /// Spends a freeze on yesterday (default) and refreshes streaks. Returns
    /// true on success. The server validates balance and day eligibility.
    @discardableResult
    func useStreakFreeze() async -> Bool {
        do {
            _ = try await supabase.rpc("use_streak_freeze").execute()
            await refreshStreaks()
            return true
        } catch {
            logger.error("use_streak_freeze failed: \(error)")
            return false
        }
    }

    // MARK: - Offline fallback (server is canonical)

    private struct ReportDateRow: Decodable {
        let activityId: UUID
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case activityId = "activity_id"
            case createdAt = "created_at"
        }
    }

    /// Offline fallback, server is canonical. Approximates the server rule
    /// (>= 75% of the day's scheduled tasks done) with device-local day
    /// bucketing and today's roster as the denominator for every day.
    /// Used only when the RPC is unreachable.
    private func computeStreaksFallback() async {
        guard !knownActivityIds.isEmpty else { return }
        do {
            let rows: [ReportDateRow] = try await supabase
                .from("reports")
                .select("activity_id, created_at")
                .in("activity_id", values: knownActivityIds.map(\.uuidString))
                .order("created_at", ascending: true)
                .execute()
                .value

            let minPerDay = max(1, Int((Constants.App.streakDailyCompletionRatio
                                        * Double(knownActivityIds.count)).rounded(.up)))
            var dayActivities: [Date: Set<UUID>] = [:]
            for row in rows {
                let day = calendar.startOfDay(for: row.createdAt)
                dayActivities[day, default: []].insert(row.activityId)
            }
            let today = calendar.startOfDay(for: Date())
            serverTodayCount = dayActivities[today]?.count ?? 0

            let qualifyingDays = dayActivities
                .filter { $0.value.count >= minPerDay }
                .map(\.key)
                .sorted()
            guard !qualifyingDays.isEmpty else {
                globalStreakCurrent = 0
                return
            }

            var best = 1
            var temp = 1
            for i in 1..<qualifyingDays.count {
                let diff = calendar.dateComponents([.day], from: qualifyingDays[i - 1], to: qualifyingDays[i]).day ?? 0
                if diff == 1 { temp += 1; best = max(best, temp) } else { temp = 1 }
            }

            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            var current = 0
            if let last = qualifyingDays.last, last == today || last == yesterday {
                var expected = last
                for day in qualifyingDays.reversed() {
                    guard day == expected else { break }
                    current += 1
                    expected = calendar.date(byAdding: .day, value: -1, to: expected)!
                }
            }
            globalStreakCurrent = current
            globalStreakBest = max(globalStreakBest, best)
        } catch {
            logger.error("offline streak fallback failed too (keeping last values): \(error)")
        }
    }
}
