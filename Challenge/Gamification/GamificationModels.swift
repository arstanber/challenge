import Foundation
import SwiftUI

// MARK: - Stats input

/// Snapshot of the player's raw numbers, fed into the engine to derive
/// XP, level, achievements and freeze rewards.
struct GameStats: Equatable {
    var totalCompleted: Int
    var totalCheckins: Int
    var currentStreak: Int
    var bestStreak: Int

    static let zero = GameStats(totalCompleted: 0, totalCheckins: 0, currentStreak: 0, bestStreak: 0)
}

// MARK: - Level curve

enum LevelCurve {
    /// XP required to advance *from* the given level to the next one.
    /// Grows linearly so early levels feel fast, later ones meaningful.
    static func xpToAdvance(from level: Int) -> Int {
        100 + (level - 1) * 75
    }

    /// Resolves total XP into level + in-level progress.
    static func resolve(xp: Int) -> LevelInfo {
        var level = 1
        var remaining = max(0, xp)
        var need = xpToAdvance(from: level)
        while remaining >= need {
            remaining -= need
            level += 1
            need = xpToAdvance(from: level)
        }
        return LevelInfo(
            level: level,
            xpIntoLevel: remaining,
            xpForNextLevel: need,
            totalXP: xp
        )
    }
}

struct LevelInfo: Equatable {
    let level: Int
    let xpIntoLevel: Int
    let xpForNextLevel: Int
    let totalXP: Int

    var progress: Double {
        xpForNextLevel > 0 ? Double(xpIntoLevel) / Double(xpForNextLevel) : 0
    }
}

// MARK: - Achievements

enum AchievementMetric {
    case completed, checkins, currentStreak, bestStreak, level
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    let metric: AchievementMetric
    let threshold: Int

    func isUnlocked(stats: GameStats, level: Int) -> Bool {
        value(stats: stats, level: level) >= threshold
    }

    func value(stats: GameStats, level: Int) -> Int {
        switch metric {
        case .completed:     return stats.totalCompleted
        case .checkins:      return stats.totalCheckins
        case .currentStreak: return stats.currentStreak
        case .bestStreak:    return stats.bestStreak
        case .level:         return level
        }
    }

    /// 0...1 progress toward unlocking.
    func progress(stats: GameStats, level: Int) -> Double {
        guard threshold > 0 else { return 1 }
        return min(Double(value(stats: stats, level: level)) / Double(threshold), 1)
    }

    // The full catalog. Ordered by rough difficulty.
    static let catalog: [Achievement] = [
        Achievement(id: "first_step",   title: "First Step",     subtitle: "Complete your first activity", emoji: "👟", metric: .completed,     threshold: 1),
        Achievement(id: "getting_going",title: "Getting Going",  subtitle: "Complete 10 activities",       emoji: "⚡️", metric: .completed,     threshold: 10),
        Achievement(id: "half_century", title: "Half Century",   subtitle: "Complete 50 activities",       emoji: "🏅", metric: .completed,     threshold: 50),
        Achievement(id: "centurion",    title: "Centurion",      subtitle: "Complete 100 activities",      emoji: "💯", metric: .completed,     threshold: 100),
        Achievement(id: "week_warrior", title: "Week Warrior",   subtitle: "Reach a 7-day streak",         emoji: "🔥", metric: .bestStreak,    threshold: 7),
        Achievement(id: "fortnight",    title: "Fortnight",      subtitle: "Reach a 14-day streak",        emoji: "🌟", metric: .bestStreak,    threshold: 14),
        Achievement(id: "unstoppable",  title: "Unstoppable",    subtitle: "Reach a 30-day streak",        emoji: "🚀", metric: .bestStreak,    threshold: 30),
        Achievement(id: "legend",       title: "Legend",         subtitle: "Reach a 100-day streak",       emoji: "👑", metric: .bestStreak,    threshold: 100),
        Achievement(id: "consistent",   title: "Consistent",     subtitle: "50 total check-ins",           emoji: "📈", metric: .checkins,      threshold: 50),
        Achievement(id: "dedicated",    title: "Dedicated",      subtitle: "200 total check-ins",          emoji: "🧱", metric: .checkins,      threshold: 200),
        Achievement(id: "rising_star",  title: "Rising Star",    subtitle: "Reach level 5",                emoji: "✨", metric: .level,         threshold: 5),
        Achievement(id: "veteran",      title: "Veteran",        subtitle: "Reach level 10",               emoji: "🎖️", metric: .level,         threshold: 10),
    ]
}

// MARK: - Themes (unlocked by level)

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let accentHex: String
    let requiredLevel: Int

    var accent: Color { Color(hex: accentHex) }

    static let all: [AppTheme] = [
        AppTheme(id: "blue",    name: "Classic Blue", accentHex: "4580FF", requiredLevel: 1),
        AppTheme(id: "green",   name: "Forest",       accentHex: "2FB873", requiredLevel: 2),
        AppTheme(id: "orange",  name: "Sunset",       accentHex: "FF7A00", requiredLevel: 4),
        AppTheme(id: "purple",  name: "Cosmic",       accentHex: "8A5CFF", requiredLevel: 6),
        AppTheme(id: "pink",    name: "Bloom",        accentHex: "FF5C9D", requiredLevel: 8),
        AppTheme(id: "gold",    name: "Champion",     accentHex: "E8B500", requiredLevel: 10),
    ]

    static func theme(id: String) -> AppTheme {
        all.first { $0.id == id } ?? all[0]
    }
}
