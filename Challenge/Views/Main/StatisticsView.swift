import SwiftUI
import Supabase
import PostgREST
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "StatisticsView")

// MARK: - Statistics screen

struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dayCounts: [Date: Int] = [:]
    @State private var dailyGoal = 1
    @State private var totalCheckins = 0
    @State private var totalCompleted = 0
    @State private var currentStreak = 0
    @State private var bestStreak = 0
    @State private var isLoading = true
    @State private var showProgression = false
    @State private var showWeeklyReport = false
    @State private var showYearInReview = false
    @State private var engine = GamificationEngine.shared

    private let blue = Color(red: 0.0, green: 0.282, blue: 0.886)
    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                ZStack {
                    Text("Statistics")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                    HStack {
                        Button { Haptics.tap(); dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            // Level / progression banner (#4) — opens full progression screen
                            Button { showProgression = true } label: {
                                LevelBanner(level: engine.level, freezes: engine.freezeBalance,
                                            unlocked: engine.unlockedCount, total: engine.totalAchievements,
                                            accent: engine.accent)
                            }
                            .buttonStyle(.haptic)
                            .appearEffect(delay: 0.05)

                            // Streak risk prediction (#16)
                            StreakRiskCard(result: StreakRisk.evaluate(
                                todayDone: dayCounts[calendar.startOfDay(for: Date())] ?? 0,
                                dailyGoal: dailyGoal,
                                currentStreak: currentStreak
                            ))
                            .appearEffect(delay: 0.13)

                            // Weekly report (#15)
                            Button { showWeeklyReport = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Share my weekly report")
                                        .font(.manrope(.bold, size: 15))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.3))
                                }
                                .foregroundColor(.black)
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.04)))
                            }
                            .buttonStyle(.haptic)
                            .appearEffect(delay: 0.21)

                            // Year in Review (#15)
                            Button { showYearInReview = true } label: {
                                HStack(spacing: 12) {
                                    Text("🎉").font(.system(size: 18))
                                    Text("Your Year in Review")
                                        .font(.manrope(.bold, size: 15))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .foregroundColor(.white)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(LinearGradient(colors: [Color(hex: "4580FF"), Color(hex: "8A5CFF")],
                                                             startPoint: .leading, endPoint: .trailing))
                                )
                            }
                            .buttonStyle(.haptic)
                            .appearEffect(delay: 0.29)

                            // Stat cards
                            HStack(spacing: 12) {
                                StatTile(value: "\(currentStreak)", label: "Current\nstreak", emoji: "🔥", tint: Color(hex: "FF7A00"))
                                StatTile(value: "\(bestStreak)", label: "Best\nstreak", emoji: "🏆", tint: Color(hex: "FFB200"))
                            }
                            .appearEffect(delay: 0.37)
                            HStack(spacing: 12) {
                                StatTile(value: "\(totalCompleted)", label: "Tasks\ndone", emoji: "✅", tint: blue)
                                StatTile(value: "\(totalCheckins)", label: "Total\ncheck-ins", emoji: "📈", tint: Color(hex: "5AD8A6"))
                            }
                            .appearEffect(delay: 0.45)

                            // Heatmap
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Activity")
                                    .font(.manrope(.bold, size: 20))
                                    .foregroundColor(.black)
                                ActivityHeatmap(dayCounts: dayCounts, tint: blue)
                            }
                            .appearEffect(delay: 0.53)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showProgression) {
            GamificationView()
        }
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyReportView(
                dayCounts: dayCounts,
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                level: engine.level.level,
                accent: engine.accent
            )
        }
        .fullScreenCover(isPresented: $showYearInReview) {
            YearInReviewView()
        }
    }

    // MARK: - Data

    private func load() async {
        guard let user = AuthService.shared.currentUser else { isLoading = false; return }
        do {
            // 1. User's activity ids + completed count
            struct ActivityRow: Decodable {
                let id: UUID; let status: String; let frequency: String
                let scheduleDays: [Int]?
                enum CodingKeys: String, CodingKey {
                    case id, status, frequency
                    case scheduleDays = "schedule_days"
                }
            }
            let activities: [ActivityRow] = try await supabase
                .from("activities")
                .select("id,status,frequency,schedule_days")
                .eq("user_id", value: user.id.uuidString)
                .execute()
                .value
            totalCompleted = activities.filter { $0.status == "completed" }.count
            let isoToday = Activity.isoWeekday(of: Date())
            let scheduledToday = activities.filter {
                $0.status == "active" && $0.frequency != "once"
                && ($0.scheduleDays?.isEmpty != false || $0.scheduleDays!.contains(isoToday))
            }.count
            dailyGoal = Constants.App.dailyStreakGoal(scheduledToday: scheduledToday)
            let ids = activities.map { $0.id.uuidString }

            guard !ids.isEmpty else { isLoading = false; return }

            // 2. Reports
            struct ReportRow: Decodable {
                let createdAt: Date
                enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
            }
            let reports: [ReportRow] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: ids)
                .order("created_at", ascending: true)
                .execute()
                .value

            totalCheckins = reports.count
            var counts: [Date: Int] = [:]
            for r in reports {
                let day = calendar.startOfDay(for: r.createdAt)
                counts[day, default: 0] += 1
            }
            dayCounts = counts
            // Canonical streaks come from the server engine (same algorithm as
            // the leaderboard); the local computation is the offline fallback.
            await TaskEngine.shared.refreshStreaks()
            if TaskEngine.shared.globalStreakBest > 0 || TaskEngine.shared.globalStreakCurrent > 0 {
                currentStreak = TaskEngine.shared.globalStreakCurrent
                bestStreak = TaskEngine.shared.globalStreakBest
            } else {
                (currentStreak, bestStreak) = computeStreaks(days: Set(counts.keys))
            }

            // Feed the gamification engine (#2–#5)
            engine.refresh(with: GameStats(
                totalCompleted: totalCompleted,
                totalCheckins: totalCheckins,
                currentStreak: currentStreak,
                bestStreak: bestStreak
            ))

            // Daily quests (#12)
            let todayCheckins = dayCounts[calendar.startOfDay(for: Date())] ?? 0
            let beforeNoon = calendar.component(.hour, from: Date()) < 12
            QuestEngine.shared.refresh(with: QuestInput(
                checkinsToday: todayCheckins,
                dailyGoal: dailyGoal,
                currentStreak: currentStreak,
                didCheckInBeforeNoon: todayCheckins > 0 && beforeNoon
            ))
        } catch {
            logger.error("Statistics load error: \(error)")
        }
        isLoading = false
    }

    private func computeStreaks(days: Set<Date>) -> (current: Int, best: Int) {
        guard !days.isEmpty else { return (0, 0) }
        let sorted = days.sorted()

        var best = 1, temp = 1
        for i in 1..<max(sorted.count, 1) {
            guard i < sorted.count else { break }
            let diff = calendar.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if diff == 1 { temp += 1; best = max(best, temp) } else { temp = 1 }
        }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var current = 0
        if let last = sorted.last, last == today || last == yesterday {
            var expected = last
            for day in sorted.reversed() {
                if day == expected {
                    current += 1
                    expected = calendar.date(byAdding: .day, value: -1, to: expected)!
                } else { break }
            }
        }
        return (current, best)
    }
}

// MARK: - Level banner (#4)

private struct LevelBanner: View {
    let level: LevelInfo
    let freezes: Int
    let unlocked: Int
    let total: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(accent.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: level.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("LVL").font(.manrope(.bold, size: 9)).foregroundColor(accent.opacity(0.7))
                    Text("\(level.level)").font(.manrope(.extraBold, size: 22)).foregroundColor(.black)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your progress")
                    .font(.manrope(.bold, size: 16))
                    .foregroundColor(.black)
                Text("\(level.xpIntoLevel)/\(level.xpForNextLevel) XP · 🧊 \(freezes) · 🏆 \(unlocked)/\(total)")
                    .font(.manrope(.medium, size: 12))
                    .foregroundColor(.black.opacity(0.45))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.3))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.10)))
    }
}

// MARK: - Stat card

private struct StatTile: View {
    let value: String
    let label: String
    let emoji: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 22))
            Text(value)
                .font(.manrope(.extraBold, size: 30))
                .foregroundColor(.black)
            Text(label)
                .font(.manrope(.medium, size: 13))
                .foregroundColor(.black.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(tint.opacity(0.10))
        )
    }
}

// MARK: - Heatmap

private struct ActivityHeatmap: View {
    let dayCounts: [Date: Int]
    let tint: Color

    private let calendar = Calendar.current
    private let weeks = 13
    private let cell: CGFloat = 18
    private let spacing: CGFloat = 4

    // Columns of 7 days each, oldest → newest, aligned to week start.
    private var columns: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        // Start from `weeks*7` days ago, aligned back to start of that week (Mon).
        let totalDays = weeks * 7
        guard let start = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else { return [] }
        var result: [[Date]] = []
        var col: [Date] = []
        var d = start
        while d <= today {
            col.append(d)
            if col.count == 7 { result.append(col); col = [] }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        if !col.isEmpty { result.append(col) }
        return result
    }

    private func color(for date: Date) -> Color {
        let c = dayCounts[date] ?? 0
        switch c {
        case 0:     return Color.black.opacity(0.05)
        case 1:     return tint.opacity(0.3)
        case 2:     return tint.opacity(0.55)
        case 3:     return tint.opacity(0.8)
        default:    return tint
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                        VStack(spacing: spacing) {
                            ForEach(col, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color(for: day))
                                    .frame(width: cell, height: cell)
                            }
                        }
                        .id(idx)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(columns.count - 1, anchor: .trailing) }
        }
    }
}

#Preview {
    StatisticsView()
        .environment(AuthService.shared)
}
