import Foundation
import Observation

// MARK: - Daily Quests (#12)

enum QuestMetric {
    case checkinsToday      // number of check-ins today
    case reachDailyGoal     // todayDone >= dailyGoal (value irrelevant, target = 1)
    case streakActive       // currentStreak >= target
    case earlyBird          // a check-in before noon (passed in separately)
}

struct DailyQuest: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let xp: Int
    let metric: QuestMetric
    let target: Int

    /// Master catalog. A deterministic subset is shown each day.
    static let catalog: [DailyQuest] = [
        DailyQuest(id: "q_one",        title: "Get started",      emoji: "✅", xp: 15, metric: .checkinsToday,  target: 1),
        DailyQuest(id: "q_two",        title: "Double up",        emoji: "✌️", xp: 25, metric: .checkinsToday,  target: 2),
        DailyQuest(id: "q_goal",       title: "Hit your goal",    emoji: "🎯", xp: 40, metric: .reachDailyGoal, target: 1),
        DailyQuest(id: "q_triple",     title: "Triple threat",    emoji: "🔥", xp: 50, metric: .checkinsToday,  target: 3),
        DailyQuest(id: "q_streak3",    title: "Keep the streak",  emoji: "⛓️", xp: 20, metric: .streakActive,   target: 1),
        DailyQuest(id: "q_streak7",    title: "Week-strong",      emoji: "🌟", xp: 35, metric: .streakActive,   target: 7),
        DailyQuest(id: "q_early",      title: "Early bird",       emoji: "🌅", xp: 30, metric: .earlyBird,      target: 1),
    ]
}

/// Snapshot of today's numbers used to evaluate quests.
struct QuestInput {
    var checkinsToday: Int
    var dailyGoal: Int
    var currentStreak: Int
    var didCheckInBeforeNoon: Bool
}

@Observable
final class QuestEngine {
    static let shared = QuestEngine()

    private(set) var todaysQuests: [DailyQuest] = []
    private(set) var newlyCompleted: [DailyQuest] = []
    private var claimedIds: Set<String> = []
    private var input = QuestInput(checkinsToday: 0, dailyGoal: 3, currentStreak: 0, didCheckInBeforeNoon: false)

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: WidgetDataStore.appGroup) ?? .standard
        claimedIds = Set(defaults.stringArray(forKey: claimedKey) ?? [])
        todaysQuests = Self.pickQuests(for: Date())
    }

    // Per-day persistence key so claims reset each day.
    private var claimedKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "quests_claimed_\(f.string(from: Date()))"
    }

    /// Deterministically pick 3 quests for the given day (stable rotation).
    private static func pickQuests(for date: Date) -> [DailyQuest] {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let catalog = DailyQuest.catalog
        var picked: [DailyQuest] = []
        var idx = dayOfYear % catalog.count
        while picked.count < 3 {
            let q = catalog[idx % catalog.count]
            if !picked.contains(where: { $0.id == q.id }) { picked.append(q) }
            idx += 1
        }
        return picked.sorted { $0.xp < $1.xp }
    }

    // MARK: - Evaluation

    func value(for quest: DailyQuest) -> Int {
        switch quest.metric {
        case .checkinsToday:  return input.checkinsToday
        case .reachDailyGoal: return input.checkinsToday >= input.dailyGoal ? 1 : 0
        case .streakActive:   return input.currentStreak
        case .earlyBird:      return input.didCheckInBeforeNoon ? 1 : 0
        }
    }

    func isComplete(_ quest: DailyQuest) -> Bool {
        value(for: quest) >= quest.target
    }

    func isClaimed(_ quest: DailyQuest) -> Bool {
        claimedIds.contains(quest.id)
    }

    func progress(_ quest: DailyQuest) -> Double {
        guard quest.target > 0 else { return 1 }
        return min(Double(value(for: quest)) / Double(quest.target), 1)
    }

    var completedCount: Int { todaysQuests.filter { isClaimed($0) }.count }

    // MARK: - Refresh & auto-claim

    /// Recomputes quests against fresh numbers and auto-claims any newly
    /// completed ones, awarding bonus XP to the gamification engine.
    func refresh(with input: QuestInput) {
        self.input = input
        todaysQuests = Self.pickQuests(for: Date())

        var freshly: [DailyQuest] = []
        for quest in todaysQuests where isComplete(quest) && !claimedIds.contains(quest.id) {
            claimedIds.insert(quest.id)
            GamificationEngine.shared.awardBonusXP(quest.xp)
            freshly.append(quest)
        }
        if !freshly.isEmpty {
            defaults.set(Array(claimedIds), forKey: claimedKey)
        }
        newlyCompleted = freshly
    }

    func acknowledge() { newlyCompleted = [] }
}
