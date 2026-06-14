import Foundation

// MARK: - Advanced (PRO/Max) statistics
// Derived from the raw report timestamps already loaded by StatisticsView.
// Pure value type, no I/O -- safe to compute on the main actor.

struct ProStats {
    /// Average check-ins per ISO weekday (Mon..Sun), index 0 = Monday.
    let weekdayAverages: [Double]
    /// Share of check-ins by part of day: morning / day / evening / night.
    let timeOfDay: [TimeBucket: Double]
    /// Daily counts for the last 30 days, oldest first (sparkline).
    let last30: [Int]
    /// Check-ins in the last 30 days vs. the prior 30 days.
    let trendDelta: Int
    /// Days until the next streak milestone, and that milestone.
    let nextMilestone: (days: Int, target: Int)?

    enum TimeBucket: String, CaseIterable {
        case morning, day, evening, night
        var title: String {
            switch self {
            case .morning: return "Утро"
            case .day:     return "День"
            case .evening: return "Вечер"
            case .night:   return "Ночь"
            }
        }
        var emoji: String {
            switch self {
            case .morning: return "🌅"
            case .day:     return "☀️"
            case .evening: return "🌆"
            case .night:   return "🌙"
            }
        }
    }

    init(reportDates: [Date], currentStreak: Int, calendar: Calendar = .current, now: Date = .now) {
        // Weekday averages -------------------------------------------------
        var byWeekday = [Int: Int]()          // ISO weekday -> total check-ins
        var weeksSeen = [Int: Set<Date>]()    // ISO weekday -> distinct week anchors
        for date in reportDates {
            let iso = (calendar.component(.weekday, from: date) + 5) % 7 + 1  // 1=Mon..7=Sun
            byWeekday[iso, default: 0] += 1
            let weekAnchor = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            weeksSeen[iso, default: []].insert(weekAnchor)
        }
        weekdayAverages = (1...7).map { iso in
            let total = byWeekday[iso] ?? 0
            let weeks = max(1, weeksSeen[iso]?.count ?? 1)
            return Double(total) / Double(weeks)
        }

        // Time of day ------------------------------------------------------
        var buckets = [TimeBucket: Int]()
        for date in reportDates {
            let hour = calendar.component(.hour, from: date)
            let bucket: TimeBucket
            switch hour {
            case 5..<12:  bucket = .morning
            case 12..<17: bucket = .day
            case 17..<22: bucket = .evening
            default:      bucket = .night
            }
            buckets[bucket, default: 0] += 1
        }
        let totalBuckets = max(1, reportDates.count)
        timeOfDay = Dictionary(uniqueKeysWithValues: TimeBucket.allCases.map {
            ($0, Double(buckets[$0] ?? 0) / Double(totalBuckets))
        })

        // 30-day trend -----------------------------------------------------
        let today = calendar.startOfDay(for: now)
        var dailyCounts = [Date: Int]()
        for date in reportDates {
            dailyCounts[calendar.startOfDay(for: date), default: 0] += 1
        }
        last30 = (0..<30).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return dailyCounts[day] ?? 0
        }
        let thisWindow = last30.reduce(0, +)
        let priorWindow = (30..<60).map { offset -> Int in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return dailyCounts[day] ?? 0
        }.reduce(0, +)
        trendDelta = thisWindow - priorWindow

        // Next streak milestone -------------------------------------------
        if let target = Constants.App.streakMilestones.first(where: { $0 > currentStreak }) {
            nextMilestone = (days: target - currentStreak, target: target)
        } else {
            nextMilestone = nil
        }
    }
}
