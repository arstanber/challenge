import Foundation
import SwiftUI

// MARK: - Shared snapshot model
// NOTE: Mirror of Challenge/Utils/WidgetDataStore.swift. Keep both in sync.

struct WidgetSnapshot: Codable {
    var streakCurrent: Int
    var streakBest: Int
    var todayDone: Int
    var dailyGoal: Int
    var activeCount: Int
    var tasks: [WidgetTask]
    var updatedAt: Date
    /// Per-day goal-met flags for the CURRENT month: index i = day (i+1).
    /// Days after today are `false`. Optional for back-compat with old writers.
    var monthDays: [Bool]?
    /// Weekly completion rates for the last 6 weeks (index 0 = oldest), each =
    /// week's check-ins / (dailyGoal * 7); can exceed 1.0 on big weeks.
    var weekRates: [Double]?
    /// Check-in counts for the trailing 30 days and the 30 before that.
    var last30Checkins: Int?
    var prev30Checkins: Int?

    /// 1-based index of today within the month, clamped to the array bounds.
    var todayDayIndex: Int { Calendar.current.component(.day, from: Date()) }

    /// Days in the month that met the goal so far.
    var monthDaysMet: Int { (monthDays ?? []).filter { $0 }.count }

    /// Honest 30-day growth vs the prior 30 days, as a signed percent. Returns
    /// nil when there's no prior baseline to compare against.
    var performanceGrowthPercent: Int? {
        guard let prev = prev30Checkins, prev > 0, let last = last30Checkins else { return nil }
        return Int(((Double(last) - Double(prev)) / Double(prev) * 100).rounded())
    }

    var todayProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(todayDone) / Double(dailyGoal), 1.0)
    }

    var goalReached: Bool { dailyGoal > 0 && todayDone >= dailyGoal }

    /// Evening risk state: there is a streak to lose and the day goal is not
    /// met. The provider refreshes hourly, so the styling flips on its own.
    var risk: WidgetRisk {
        guard streakCurrent > 0, !goalReached else { return .none }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 21 { return .critical }
        if hour >= 18 { return .atRisk }
        return .none
    }

    static let placeholder = WidgetSnapshot(
        streakCurrent: 7,
        streakBest: 21,
        todayDone: 2,
        dailyGoal: 3,
        activeCount: 5,
        tasks: [
            WidgetTask(id: UUID(), title: "Morning workout", typeIcon: "camera.fill", typeColorName: "blue", deadline: nil, isDone: true, requiresPhoto: true),
            WidgetTask(id: UUID(), title: "Read 20 pages", typeIcon: "checkmark.circle.fill", typeColorName: "orange", deadline: nil, isDone: false, requiresPhoto: false),
            WidgetTask(id: UUID(), title: "Drink water", typeIcon: "repeat.circle.fill", typeColorName: "purple", deadline: nil, isDone: false, requiresPhoto: false)
        ],
        updatedAt: Date(),
        monthDays: [true, true, false, true, true, true, true, false, true, true,
                    true, false, true, true, true, true, true, false, true, true,
                    true, true, false, true, false, false, false, false, false, false],
        weekRates: [0.12, 0.78, 0.62, 0.70, 0.75, 1.05],
        last30Checkins: 76,
        prev30Checkins: 20
    )

    static let empty = WidgetSnapshot(
        streakCurrent: 0,
        streakBest: 0,
        todayDone: 0,
        dailyGoal: 3,
        activeCount: 0,
        tasks: [],
        updatedAt: Date(),
        monthDays: nil,
        weekRates: nil,
        last30Checkins: nil,
        prev30Checkins: nil
    )
}

enum WidgetRisk {
    case none, atRisk, critical
}

struct WidgetTask: Codable, Identifiable {
    var id: UUID
    var title: String
    var typeIcon: String
    var typeColorName: String
    var deadline: Date?
    var isDone: Bool
    /// Photo tasks can't complete from the widget (the camera needs the app).
    /// Optional so snapshots written by older app builds still decode.
    var requiresPhoto: Bool?

    var color: Color {
        switch typeColorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        default: return .accentColor
        }
    }
}

// MARK: - App Group read

enum WidgetDataStore {
    static let appGroup = "group.qazaqpyn.Challenge"
    static let snapshotKey = "widget_snapshot"
    static let checkinQueueKey = "widget_checkin_queue"

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Queue a completion tapped on the widget. The extension has no Supabase
    /// session, so it only records the intent; the app replays the queue into
    /// real check-in reports on next open. The snapshot is patched
    /// optimistically so the row flips to done immediately.
    static func queueCheckin(_ id: UUID) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        var queue = defaults.stringArray(forKey: checkinQueueKey) ?? []
        guard !queue.contains(id.uuidString) else { return }
        queue.append(id.uuidString)
        defaults.set(queue, forKey: checkinQueueKey)

        if var snapshot = load(),
           let idx = snapshot.tasks.firstIndex(where: { $0.id == id }),
           !snapshot.tasks[idx].isDone {
            snapshot.tasks[idx].isDone = true
            snapshot.todayDone += 1
            snapshot.updatedAt = Date()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                defaults.set(data, forKey: snapshotKey)
            }
        }
    }
}
