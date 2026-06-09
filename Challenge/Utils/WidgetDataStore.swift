import Foundation
import WidgetKit
import os.log

private let widgetLogger = Logger(subsystem: "com.challenge", category: "WidgetDataStore")

// MARK: - Shared snapshot model
// NOTE: This struct is intentionally duplicated in the widget extension
// (ChallengeWidget/WidgetSnapshot.swift). Keep both copies in sync.
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

    static let placeholder = WidgetSnapshot(
        streakCurrent: 7,
        streakBest: 21,
        todayDone: 2,
        dailyGoal: 3,
        activeCount: 5,
        tasks: [
            WidgetTask(id: UUID(), title: "Morning workout", typeIcon: "camera.fill", typeColorName: "blue", deadline: nil, isDone: true),
            WidgetTask(id: UUID(), title: "Read 20 pages", typeIcon: "checkmark.circle.fill", typeColorName: "orange", deadline: nil, isDone: false),
            WidgetTask(id: UUID(), title: "Drink water", typeIcon: "repeat.circle.fill", typeColorName: "purple", deadline: nil, isDone: false)
        ],
        updatedAt: Date()
    )
}

struct WidgetTask: Codable, Identifiable {
    var id: UUID
    var title: String
    var typeIcon: String
    var typeColorName: String
    var deadline: Date?
    var isDone: Bool
}

// MARK: - App Group store

enum WidgetDataStore {
    static let appGroup = "group.qazaqpyn.Challenge"
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
