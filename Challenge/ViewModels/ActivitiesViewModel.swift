import Foundation
import Supabase
import PostgREST
import Observation

// Lightweight model for streak calculation (only dates needed)
private struct ReportDate: Decodable {
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
}

@Observable
final class ActivitiesViewModel {
    var myActivities: [Activity] = []
    var parentActivities: [Activity] = []
    var isLoading = false
    var errorMessage: String?

    // Global streak — days with ≥ minDailyActivitiesForStreak completions in a row
    var globalStreakCurrent: Int = 0
    var globalStreakBest: Int = 0
    /// How many activities are done today
    var todayCount: Int = 0

    private let authService = AuthService.shared
    private let calendar = Calendar.current

    var activeCount: Int { myActivities.filter { $0.status == .active }.count }
    var canCreateMore: Bool {
        guard let user = authService.currentUser else { return false }
        return user.isPremium || activeCount < Constants.App.maxFreeActivities
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
                .order("created_at", ascending: false)
                .execute()
                .value
            myActivities = all.filter { $0.assignedBy == nil }
            parentActivities = all.filter { $0.assignedBy != nil }
            await recalculateGlobalStreak()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Global Streak

    /// Call this after any activity completion to refresh the global streak.
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
            print("Global streak calc error: \(error)")
        }
    }

    // MARK: - Streak Algorithm

    private func computeStreak(from dates: [Date]) -> (current: Int, best: Int, today: Int) {
        let minPerDay = Constants.App.minDailyActivitiesForStreak

        // Group report dates by calendar day
        var dayCount: [Date: Int] = [:]
        for date in dates {
            let day = calendar.startOfDay(for: date)
            dayCount[day, default: 0] += 1
        }

        // Days that qualify (≥ minPerDay completions), sorted ascending
        let qualifyingDays = dayCount
            .filter { $0.value >= minPerDay }
            .map { $0.key }
            .sorted()

        let today = calendar.startOfDay(for: Date())
        let todayN = dayCount[today] ?? 0

        guard !qualifyingDays.isEmpty else { return (0, 0, todayN) }

        // Best streak across all time
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

        // Current streak (count backwards from today or yesterday)
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
            await recalculateGlobalStreak()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markCompleted(_ activity: Activity) async {
        do {
            try await supabase
                .from("activities")
                .update(["status": "completed"])
                .eq("id", value: activity.id.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                myActivities[idx].status = .completed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
