import Foundation

// MARK: - Max statistics

/// Rich, local analytics derived from reports already loaded by
/// `StatisticsView`. The server remains the source of truth for streaks.
struct ProStats {
    struct ReportEvent {
        let activityId: UUID
        let date: Date
        let result: AIVerificationResult
    }

    struct ActivityInfo {
        let id: UUID
        let title: String
        let category: String?
    }

    struct RankedItem: Identifiable {
        let id: String
        let title: String
        let value: Int
        let share: Double
    }

    struct BestDay {
        let date: Date
        let count: Int
    }

    enum TimeBucket: String, CaseIterable {
        case morning, day, evening, night

        var title: String {
            switch self {
            case .morning: return String(localized: "Утро")
            case .day: return String(localized: "День")
            case .evening: return String(localized: "Вечер")
            case .night: return String(localized: "Ночь")
            }
        }

        var emoji: String {
            switch self {
            case .morning: return "🌅"
            case .day: return "☀️"
            case .evening: return "🌆"
            case .night: return "🌙"
            }
        }
    }

    let totalAttempts: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let pendingCount: Int
    let excusedCount: Int
    let successRate: Double
    let activeDays: Int
    let consistencyRate: Double
    let averagePerActiveDay: Double
    let perfectDays: Int
    let bestDay: BestDay?
    let averageCompletionHour: Double?
    let weekdayAverages: [Double]
    let timeOfDay: [TimeBucket: Double]
    let hourlyCounts: [Int]
    let last30: [Int]
    let prior30: [Int]
    let trendDelta: Int
    let trendPercent: Int?
    let monthlyCounts: [Int]
    let topActivities: [RankedItem]
    let topCategories: [RankedItem]
    let nextMilestone: (days: Int, target: Int)?

    init(
        events: [ReportEvent],
        activities: [ActivityInfo],
        currentStreak: Int,
        dailyGoal: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        let accepted = events.filter {
            $0.result == .approved || $0.result == .notApplicable
        }
        let completed = events.filter {
            $0.result == .approved || $0.result == .notApplicable || $0.result == .pending
        }

        totalAttempts = events.count
        acceptedCount = accepted.count
        rejectedCount = events.filter { $0.result == .rejected }.count
        pendingCount = events.filter { $0.result == .pending }.count
        excusedCount = events.filter { $0.result == .excused }.count
        let decided = acceptedCount + rejectedCount
        successRate = decided > 0 ? Double(acceptedCount) / Double(decided) : 0

        let today = calendar.startOfDay(for: now)
        let dailyCounts = Dictionary(grouping: completed) {
            calendar.startOfDay(for: $0.date)
        }.mapValues(\.count)
        activeDays = dailyCounts.count
        averagePerActiveDay = activeDays > 0 ? Double(completed.count) / Double(activeDays) : 0
        perfectDays = dailyCounts.values.filter { $0 >= max(1, dailyGoal) }.count
        bestDay = dailyCounts.max(by: { $0.value < $1.value }).map {
            BestDay(date: $0.key, count: $0.value)
        }

        if let first = completed.map(\.date).min() {
            let elapsed = max(1, (calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: first),
                to: today
            ).day ?? 0) + 1)
            consistencyRate = Double(activeDays) / Double(elapsed)
        } else {
            consistencyRate = 0
        }

        if !completed.isEmpty {
            averageCompletionHour = completed.map {
                let hour = Double(calendar.component(.hour, from: $0.date))
                let minute = Double(calendar.component(.minute, from: $0.date)) / 60
                return hour + minute
            }.reduce(0, +) / Double(completed.count)
        } else {
            averageCompletionHour = nil
        }

        var byWeekday = [Int: Int]()
        var weeksSeen = [Int: Set<Date>]()
        var buckets = [TimeBucket: Int]()
        var hours = Array(repeating: 0, count: 24)
        for event in completed {
            let iso = (calendar.component(.weekday, from: event.date) + 5) % 7 + 1
            byWeekday[iso, default: 0] += 1
            let week = calendar.dateInterval(of: .weekOfYear, for: event.date)?.start ?? event.date
            weeksSeen[iso, default: []].insert(week)

            let hour = calendar.component(.hour, from: event.date)
            hours[hour] += 1
            let bucket: TimeBucket
            switch hour {
            case 5..<12: bucket = .morning
            case 12..<17: bucket = .day
            case 17..<22: bucket = .evening
            default: bucket = .night
            }
            buckets[bucket, default: 0] += 1
        }
        weekdayAverages = (1...7).map { iso in
            Double(byWeekday[iso] ?? 0) / Double(max(1, weeksSeen[iso]?.count ?? 1))
        }
        hourlyCounts = hours
        timeOfDay = Dictionary(uniqueKeysWithValues: TimeBucket.allCases.map {
            ($0, Double(buckets[$0] ?? 0) / Double(max(1, completed.count)))
        })

        func counts(startOffset: Int, length: Int) -> [Int] {
            (startOffset..<(startOffset + length)).reversed().map { offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                return dailyCounts[day] ?? 0
            }
        }
        last30 = counts(startOffset: 0, length: 30)
        prior30 = counts(startOffset: 30, length: 30)
        let currentTotal = last30.reduce(0, +)
        let priorTotal = prior30.reduce(0, +)
        trendDelta = currentTotal - priorTotal
        trendPercent = priorTotal > 0
            ? Int((Double(trendDelta) / Double(priorTotal) * 100).rounded())
            : nil

        monthlyCounts = (0..<12).reversed().map { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: now),
                  let interval = calendar.dateInterval(of: .month, for: month)
            else { return 0 }
            return completed.filter { interval.contains($0.date) }.count
        }

        let activityById = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        let byActivity = Dictionary(grouping: completed, by: \.activityId)
        topActivities = byActivity
            .map { id, values in
                RankedItem(
                    id: id.uuidString,
                    title: activityById[id]?.title ?? String(localized: "Удалённая задача"),
                    value: values.count,
                    share: Double(values.count) / Double(max(1, completed.count))
                )
            }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }

        let categoryGroups = Dictionary(grouping: completed) {
            let category = activityById[$0.activityId]?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let category, !category.isEmpty { return category }
            return String(localized: "Без категории")
        }
        topCategories = categoryGroups
            .map { category, values in
                RankedItem(
                    id: category,
                    title: category,
                    value: values.count,
                    share: Double(values.count) / Double(max(1, completed.count))
                )
            }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }

        if let target = Constants.App.streakMilestones.first(where: { $0 > currentStreak }) {
            nextMilestone = (days: target - currentStreak, target: target)
        } else {
            nextMilestone = nil
        }
    }
}
