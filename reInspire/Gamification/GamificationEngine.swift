import Foundation
import SwiftUI
import Observation

/// Central client-side progression engine: XP, levels, achievements,
/// streak-freeze wallet and unlockable themes. Pure local state, derived
/// from a `GameStats` snapshot. Persisted in the shared App Group so widgets
/// (and later other extensions) can read it too.
@Observable
final class GamificationEngine {
    static let shared = GamificationEngine()

    // MARK: Live (derived) state
    private(set) var stats: GameStats = .zero
    private(set) var level: LevelInfo = LevelCurve.resolve(xp: 0)
    private(set) var newlyUnlocked: [Achievement] = []

    // MARK: Persisted state
    private(set) var unlockedIds: Set<String> = []
    private var unlockDates: [String: Date] = [:]
    private var spentFreezes: Int = 0
    var selectedThemeId: String = "blue" {
        didSet { defaults.set(selectedThemeId, forKey: Keys.theme) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let unlocked = "gam_unlocked_ids"
        static let unlockDates = "gam_unlock_dates"
        static let spentFreezes = "gam_spent_freezes"
        static let theme = "gam_theme"
        static let bonusXP = "gam_bonus_xp"
    }

    /// Bonus XP earned from daily quests (#12) and other one-off rewards.
    private(set) var bonusXP: Int = 0

    private init() {
        defaults = UserDefaults(suiteName: WidgetDataStore.appGroup) ?? .standard
        unlockedIds = Set(defaults.stringArray(forKey: Keys.unlocked) ?? [])
        spentFreezes = defaults.integer(forKey: Keys.spentFreezes)
        bonusXP = defaults.integer(forKey: Keys.bonusXP)
        selectedThemeId = defaults.string(forKey: Keys.theme) ?? "blue"
        if let raw = defaults.dictionary(forKey: Keys.unlockDates) as? [String: Double] {
            unlockDates = raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    // MARK: - XP

    /// Total earned XP derived from raw stats plus bonus XP from quests.
    var totalXP: Int {
        stats.totalCompleted * 12 + stats.totalCheckins * 6 + stats.bestStreak * 5 + bonusXP
    }

    /// Awards one-off bonus XP (e.g. from completing a daily quest) and recomputes level.
    func awardBonusXP(_ amount: Int) {
        guard amount > 0 else { return }
        bonusXP += amount
        defaults.set(bonusXP, forKey: Keys.bonusXP)
        level = LevelCurve.resolve(xp: totalXP)
    }

    // MARK: - Freeze wallet (#2)

    /// Lifetime offline estimate (best streak / 7 + referral bonus). Used only
    /// as a fallback before the server wallet has loaded; the canonical balance
    /// is `TaskEngine.freezesAvailable` (see migration 20260613b_streak_freezes).
    var earnedFreezes: Int {
        stats.bestStreak / 7 + (AuthService.shared.currentUser?.bonusFreezes ?? 0)
    }

    /// Freezes currently available to spend. Server is the single source of
    /// truth (frozen days actually protect the streak); fall back to the local
    /// estimate only when the server wallet has not loaded yet.
    var freezeBalance: Int {
        let server = TaskEngine.shared.freezesAvailable
        return server > 0 ? server : earnedFreezes
    }

    // MARK: - Themes (#5)

    var selectedTheme: AppTheme { AppTheme.theme(id: selectedThemeId) }
    var accent: Color { selectedTheme.accent }

    func isThemeUnlocked(_ theme: AppTheme) -> Bool {
        level.level >= theme.requiredLevel
    }

    /// Selects a theme only if it's unlocked. Returns success.
    @discardableResult
    func selectTheme(_ theme: AppTheme) -> Bool {
        guard isThemeUnlocked(theme) else { return false }
        selectedThemeId = theme.id
        return true
    }

    // MARK: - Achievements (#3)

    func isUnlocked(_ achievement: Achievement) -> Bool {
        unlockedIds.contains(achievement.id)
    }

    func unlockDate(for achievement: Achievement) -> Date? {
        unlockDates[achievement.id]
    }

    var unlockedCount: Int { unlockedIds.count }
    var totalAchievements: Int { Achievement.catalog.count }

    // MARK: - Refresh

    /// Recomputes derived state from a fresh stats snapshot and records any
    /// newly unlocked achievements. Call after loading activities/streaks.
    func refresh(with stats: GameStats) {
        self.stats = stats
        self.level = LevelCurve.resolve(xp: totalXP)

        var freshlyUnlocked: [Achievement] = []
        for achievement in Achievement.catalog
        where achievement.isUnlocked(stats: stats, level: level.level) && !unlockedIds.contains(achievement.id) {
            unlockedIds.insert(achievement.id)
            unlockDates[achievement.id] = Date()
            freshlyUnlocked.append(achievement)
        }

        if !freshlyUnlocked.isEmpty {
            defaults.set(Array(unlockedIds), forKey: Keys.unlocked)
            defaults.set(unlockDates.mapValues { $0.timeIntervalSince1970 }, forKey: Keys.unlockDates)
        }
        newlyUnlocked = freshlyUnlocked

        // If the currently selected theme got locked out (shouldn't normally
        // happen since level only grows), fall back to the default.
        if !isThemeUnlocked(selectedTheme) {
            selectedThemeId = "blue"
        }
    }

    /// Clears the "new" badge after the user has seen the celebration.
    func acknowledgeNewUnlocks() {
        newlyUnlocked = []
    }
}
