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

    var todayProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(todayDone) / Double(dailyGoal), 1.0)
    }

    var goalReached: Bool { dailyGoal > 0 && todayDone >= dailyGoal }

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

    static let empty = WidgetSnapshot(
        streakCurrent: 0,
        streakBest: 0,
        todayDone: 0,
        dailyGoal: 3,
        activeCount: 0,
        tasks: [],
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

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
