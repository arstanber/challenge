import SwiftUI

// MARK: - Progression screen (#2 #3 #4 #5)

struct GamificationView: View {
    @State private var engine = GamificationEngine.shared
    @State private var quests = QuestEngine.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                LevelCard(level: engine.level, accent: engine.accent)
                    .appearEffect(delay: 0.05)
                DailyQuestsSection(quests: quests, accent: engine.accent)
                    .appearEffect(delay: 0.15)
                FreezeWalletCard(engine: engine)
                    .appearEffect(delay: 0.25)
                ThemesSection(engine: engine)
                    .appearEffect(delay: 0.35)
                AchievementsSection(engine: engine)
                    .appearEffect(delay: 0.45)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .readableWidth()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Daily Quests (#12)

private struct DailyQuestsSection: View {
    let quests: QuestEngine
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Quests")
                    .font(.manrope(.bold, size: 20))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(quests.completedCount)/\(quests.todaysQuests.count)")
                    .font(.manrope(.bold, size: 14))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(quests.todaysQuests) { quest in
                    QuestRow(
                        quest: quest,
                        claimed: quests.isClaimed(quest),
                        progress: quests.progress(quest),
                        valueText: "\(quests.value(for: quest))/\(quest.target)",
                        accent: accent
                    )
                }
            }
        }
    }
}

private struct QuestRow: View {
    let quest: DailyQuest
    let claimed: Bool
    let progress: Double
    let valueText: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(quest.emoji)
                .font(.system(size: 26))
                .opacity(claimed ? 1 : 0.85)

            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.manrope(.bold, size: 15))
                    .foregroundStyle(.primary)
                    .strikethrough(claimed, color: .secondary)
                if !claimed {
                    ProgressView(value: progress)
                        .tint(accent)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if claimed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(hex: "2FB873"))
                        .font(.system(size: 18))
                } else {
                    Text(valueText)
                        .font(.manrope(.medium, size: 12))
                        .foregroundStyle(.secondary)
                }
                Text("+\(quest.xp) XP")
                    .font(.manrope(.bold, size: 12))
                    .foregroundColor(claimed ? Color(hex: "2FB873") : accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(claimed ? Color(hex: "2FB873").opacity(0.10) : Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Level card (#4)

private struct LevelCard: View {
    let level: LevelInfo
    let accent: Color

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: level.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("LVL")
                        .font(.manrope(.bold, size: 12))
                        .foregroundColor(accent.opacity(0.7))
                    Text("\(level.level)")
                        .font(.manrope(.extraBold, size: 44))
                        .foregroundStyle(.primary)
                        .shimmer(delay: 0.4)
                }
            }
            .frame(width: 132, height: 132)

            VStack(spacing: 4) {
                Text("\(level.xpIntoLevel) / \(level.xpForNextLevel) XP")
                    .font(.manrope(.bold, size: 15))
                    .foregroundStyle(.primary)
                Text("\(level.xpForNextLevel - level.xpIntoLevel) XP to level \(level.level + 1)")
                    .font(.manrope(.medium, size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 22).fill(accent.opacity(0.08)))
    }
}

// MARK: - Freeze wallet (#2)

private struct FreezeWalletCard: View {
    let engine: GamificationEngine

    var body: some View {
        HStack(spacing: 16) {
            Text("🧊")
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak Freezes")
                    .font(.manrope(.bold, size: 16))
                    .foregroundStyle(.primary)
                Text("Protect your streak on a missed day")
                    .font(.manrope(.medium, size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(engine.freezeBalance)")
                .font(.manrope(.extraBold, size: 30))
                .foregroundColor(Color(hex: "4580FF"))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "4580FF").opacity(0.08)))
    }
}

// MARK: - Themes (#5)

private struct ThemesSection: View {
    let engine: GamificationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Themes")
                .font(.manrope(.bold, size: 20))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppTheme.all) { theme in
                        ThemeChip(
                            theme: theme,
                            isSelected: engine.selectedThemeId == theme.id,
                            isUnlocked: engine.isThemeUnlocked(theme)
                        ) {
                            engine.selectTheme(theme)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ThemeChip: View {
    let theme: AppTheme
    let isSelected: Bool
    let isUnlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 52, height: 52)
                        .opacity(isUnlocked ? 1 : 0.25)
                    if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .overlay(
                    Circle().strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                Text(isUnlocked ? theme.name : "Lvl \(theme.requiredLevel)")
                    .font(.manrope(.medium, size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64)
        }
        .buttonStyle(.haptic)
        .disabled(!isUnlocked)
    }
}

// MARK: - Achievements (#3)

private struct AchievementsSection: View {
    let engine: GamificationEngine
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(.manrope(.bold, size: 20))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(engine.unlockedCount) / \(engine.totalAchievements)")
                    .font(.manrope(.bold, size: 14))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: .adaptive(compact: 2, regular: 3, for: hSizeClass, spacing: 12), spacing: 12) {
                ForEach(Achievement.catalog) { achievement in
                    AchievementCard(
                        achievement: achievement,
                        isUnlocked: engine.isUnlocked(achievement),
                        progress: achievement.progress(stats: engine.stats, level: engine.level.level)
                    )
                }
            }
        }
    }
}

private struct AchievementCard: View {
    let achievement: Achievement
    let isUnlocked: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(achievement.emoji)
                .font(.system(size: 28))
                .grayscale(isUnlocked ? 0 : 1)
                .opacity(isUnlocked ? 1 : 0.4)
            Text(achievement.title)
                .font(.manrope(.bold, size: 14))
                .foregroundStyle(.primary)
            Text(achievement.subtitle)
                .font(.manrope(.medium, size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !isUnlocked {
                ProgressView(value: progress)
                    .tint(Color(hex: "4580FF"))
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isUnlocked ? Color(hex: "FFB200").opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isUnlocked ? Color(hex: "FFB200").opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    GamificationView()
}
