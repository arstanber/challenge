import Foundation
import Observation

/// Matches freshly created tasks (manual or AI-generated) to data connectors
/// by topic and queues a one-tap "connect" suggestion that HomeView presents
/// as a sheet. All creation flows funnel through `taskCreated`/`tasksCreated`.
@MainActor
@Observable
final class ConnectorSuggestionEngine {
    static let shared = ConnectorSuggestionEngine()

    struct Suggestion: Identifiable, Equatable {
        let id: UUID
        let taskTitles: [String]
        let connectors: [DataConnector]
    }

    /// Next suggestion to present; HomeView observes this and shows the sheet.
    private(set) var pending: Suggestion?

    /// Connectors connected from the currently presented sheet -- they must
    /// not get a decline snooze on dismiss.
    private var connectedFromSheet: Set<DataConnector> = []

    /// rawValue -> date until which a declined connector is not re-suggested.
    private var snoozedUntil: [String: Date]
    private let snoozeKey = "connector_suggestion_snooze_v1"
    private let snoozeDays = 7
    private let maxSuggested = 4

    private init() {
        snoozedUntil = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Date] ?? [:]
    }

    // MARK: - Entry points

    /// Call right after a task is created. `category` is the AI classifier
    /// label (SPORT/HEALTH/STUDY/...) when the task came from the voice flow.
    func taskCreated(title: String, description: String = "", category: String? = nil) {
        tasksCreated([(title, description, category)])
    }

    /// Batch variant for the AI planner: one suggestion covering the whole plan.
    func tasksCreated(_ tasks: [(title: String, description: String, category: String?)]) {
        var matched: [DataConnector] = []
        for task in tasks {
            matched.append(contentsOf: Self.match(title: task.title, description: task.description, category: task.category))
        }
        queue(connectors: matched, titles: tasks.map { $0.title })
    }

    // MARK: - Sheet lifecycle

    /// A connector was connected from the suggestion sheet.
    func markConnected(_ connector: DataConnector) {
        connectedFromSheet.insert(connector)
    }

    /// The sheet went away: snooze whatever was suggested but not connected,
    /// so the user isn't nagged about the same connector on every new task.
    func dismissPending() {
        guard let pending else { return }
        let until = Calendar.current.date(byAdding: .day, value: snoozeDays, to: Date()) ?? Date()
        for connector in pending.connectors where !connectedFromSheet.contains(connector) {
            snoozedUntil[connector.rawValue] = until
        }
        UserDefaults.standard.set(snoozedUntil, forKey: snoozeKey)
        connectedFromSheet = []
        self.pending = nil
    }

    // MARK: - Queueing

    private func queue(connectors: [DataConnector], titles: [String]) {
        let now = Date()
        var seen = Set<DataConnector>(pending?.connectors ?? [])
        let fresh = connectors.filter { connector in
            guard !ConnectorService.shared.isConnected(connector) else { return false }
            if let until = snoozedUntil[connector.rawValue], until > now { return false }
            return seen.insert(connector).inserted
        }
        guard !fresh.isEmpty else { return }

        if let current = pending {
            // Merge while the sheet hasn't been shown yet (e.g. AI plan creates
            // several tasks back to back).
            let mergedTitles = current.taskTitles + titles.filter { !current.taskTitles.contains($0) }
            pending = Suggestion(
                id: current.id,
                taskTitles: mergedTitles,
                connectors: Array((current.connectors + fresh).prefix(maxSuggested))
            )
        } else {
            pending = Suggestion(id: UUID(), taskTitles: titles, connectors: Array(fresh.prefix(maxSuggested)))
        }
    }

    // MARK: - Topic matching

    /// Keyword/topic -> connectors, ordered by relevance. Health and fitness
    /// themes map to HealthKit-backed sources, planning to calendars, etc.
    static func match(title: String, description: String = "", category: String? = nil) -> [DataConnector] {
        let text = (title + " " + description).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        var result: [DataConnector] = []
        func add(_ connectors: DataConnector...) {
            // Never suggest sources whose OAuth app isn't registered yet.
            for c in connectors where !result.contains(c) && c.isConfigured { result.append(c) }
        }

        // Running / cycling / swimming
        if has(["бег", "пробеж", "марафон", "run", "jog", "велосипед", "велик", "вело", "cycl", "bike", "плава", "swim", "лыж", "ski"]) {
            add(.appleHealth, .strava, .appleFitness)
        }
        // Steps & walking
        if has(["шаг", "step", "ходьб", "пешком", "прогулк", "walk", "гулять"]) {
            add(.appleHealth, .appleFitness)
        }
        // Gym / workouts
        if has(["трениров", "зал", "качал", "workout", "gym", "отжим", "подтяг", "присед", "планк", "йог", "yoga", "растяж", "stretch", "спорт", "фитнес", "fitness", "кардио", "табата", "кроссфит", "crossfit"]) {
            add(.appleFitness, .appleHealth, .strava)
        }
        // Body metrics / nutrition / water
        if has(["калори", "calor", "похуд", "взвес", "вес тела", "weight", "питани", "диет", "diet", "вода", "воды", "стакан", "water", "пульс", "давлени"]) {
            add(.appleHealth)
        }
        // Sleep & recovery
        if has(["сон", "спать", "выспат", "sleep", "восстановлен", "recovery", "медитац", "meditat", "дыхатель", "breath"]) {
            add(.appleHealth)
        }
        // Early wake-up / morning routine
        if has(["проснуться", "подъём", "подъем", "встать в", "вставать", "будильник", "wake", "режим дня", "утренн"]) {
            add(.appleClock, .appleHealth)
        }
        // Meetings & planning
        if has(["встреч", "созвон", "митинг", "meeting", "звонок", "call", "расписани", "календар", "calendar", "планир", "дедлайн", "deadline", "собеседован"]) {
            add(.appleCalendar)
        }
        // Telegram bot reports
        if has(["telegram", "телеграм", "фото-отч", "фото отч", "боту"]) {
            add(.telegram)
        }

        // AI category as a fallback when keywords didn't hit.
        if result.isEmpty, let category = category?.uppercased() {
            switch category {
            case "SPORT":         add(.appleFitness, .appleHealth, .strava)
            case "HEALTH":        add(.appleHealth)
            case "FOOD":          add(.appleHealth)
            case "WORK":          add(.appleCalendar)
            case "MENTAL HEALTH": add(.appleHealth)
            default: break
            }
        }
        return result
    }
}
