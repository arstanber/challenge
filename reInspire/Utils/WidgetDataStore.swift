import Foundation
import WidgetKit
import os.log

private let widgetLogger = Logger(subsystem: "com.reinspire", category: "WidgetDataStore")

// MARK: - Shared snapshot model
// NOTE: This struct is intentionally duplicated in the widget extension
// (w1/WidgetSnapshot.swift). Keep both copies in sync.
// They are kept separate so the app and the extension don't need to share
// target membership of a single file.

struct WidgetSnapshot: Codable {
    var streakCurrent: Int
    var streakBest: Int
    var todayDone: Int
    var dailyGoal: Int
    var activeCount: Int
    var tasks: [WidgetTask]
    var updatedAt: Date
    /// Per-day goal-met flags for the CURRENT month: index i = day (i+1).
    /// Days after today are `false` (the future hasn't happened yet).
    /// Optional so snapshots written by older app builds still decode.
    var monthDays: [Bool]?
    /// Weekly completion rates for the last 6 weeks (index 0 = oldest), each =
    /// week's check-ins / (dailyGoal * 7); can exceed 1.0 on big weeks.
    var weekRates: [Double]?
    /// Check-in counts for the trailing 30 days and the 30 days before that --
    /// the performance card derives an honest growth %.
    var last30Checkins: Int?
    var prev30Checkins: Int?
    /// Gates the premium-only Performance widget. Optional for back-compat.
    var isPremium: Bool?

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
        prev30Checkins: 20,
        isPremium: true
    )
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
}

// MARK: - App Group store

enum WidgetDataStore {
    static let appGroup = "group.qazaqpyn.reInspire"
    static let snapshotKey = "widget_snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder.widget.encode(snapshot)
            defaults.set(data, forKey: snapshotKey)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            widgetLogger.error("Save error: \(error)")
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder.widget.decode(WidgetSnapshot.self, from: data)
    }

    // MARK: Widget check-in queue

    static let checkinQueueKey = "widget_checkin_queue"

    /// Completions tapped on the widget while the app was closed (the
    /// extension has no Supabase session, so it only queues). Read & clear;
    /// the caller turns them into real check-in reports.
    static func drainPendingCheckins() -> [UUID] {
        guard let defaults else { return [] }
        let ids = (defaults.stringArray(forKey: checkinQueueKey) ?? []).compactMap(UUID.init)
        if !ids.isEmpty { defaults.removeObject(forKey: checkinQueueKey) }
        return ids
    }
}

extension JSONEncoder {
    static let widget: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let widget: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
