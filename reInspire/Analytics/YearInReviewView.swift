import SwiftUI
import Supabase

// MARK: - Year in Review / "Wrapped" (#15)

struct YearStats {
    var totalCheckins: Int
    var activeDays: Int
    var bestStreak: Int
    var completedActivities: Int
    var topCategory: String
    var busiestMonth: String
    var busiestWeekday: String
    var year: Int
}

@Observable
final class YearInReviewViewModel {
    var stats: YearStats?
    var isLoading = true
    var errorMessage: String?

    private let calendar = Calendar.current

    func load() async {
        guard let user = AuthService.shared.currentUser else { isLoading = false; return }
        let year = calendar.component(.year, from: Date())
        do {
            // Activity ids + categories + completed count
            struct ActivityRow: Decodable {
                let id: UUID; let status: String; let category: String?
            }
            let activities: [ActivityRow] = try await supabase
                .from("activities")
                .select("id,status,category")
                .eq("user_id", value: user.id.uuidString)
                .execute()
                .value
            let ids = activities.map { $0.id.uuidString }
            let completed = activities.filter { $0.status == "completed" }.count

            // Top category
            var catCounts: [String: Int] = [:]
            for a in activities { if let c = a.category { catCounts[c, default: 0] += 1 } }
            let topCategory = catCounts.max { $0.value < $1.value }?.key ?? "--"

            guard !ids.isEmpty else {
                stats = emptyStats(year: year); isLoading = false; return
            }

            // Reports this year
            struct ReportRow: Decodable {
                let createdAt: Date
                enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
            }
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let reports: [ReportRow] = try await supabase
                .from("reports")
                .select("created_at")
                .in("activity_id", values: ids)
                .gte("created_at", value: ISO8601DateFormatter().string(from: startOfYear))
                .execute()
                .value

            let dates = reports.map { $0.createdAt }
            stats = compute(dates: dates, completed: completed, topCategory: topCategory, year: year)
        } catch {
            errorMessage = error.localizedDescription
            stats = emptyStats(year: year)
        }
        isLoading = false
    }

    private func emptyStats(year: Int) -> YearStats {
        YearStats(totalCheckins: 0, activeDays: 0, bestStreak: 0, completedActivities: 0,
                  topCategory: "--", busiestMonth: "--", busiestWeekday: "--", year: year)
    }

    private func compute(dates: [Date], completed: Int, topCategory: String, year: Int) -> YearStats {
        var days = Set<Date>()
        var monthCounts = [Int: Int]()
        var weekdayCounts = [Int: Int]()
        for d in dates {
            days.insert(calendar.startOfDay(for: d))
            monthCounts[calendar.component(.month, from: d), default: 0] += 1
            weekdayCounts[calendar.component(.weekday, from: d), default: 0] += 1
        }

        // Best streak across the year
        let sorted = days.sorted()
        var best = sorted.isEmpty ? 0 : 1, temp = 1
        for i in 1..<max(sorted.count, 1) where i < sorted.count {
            let diff = calendar.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if diff == 1 { temp += 1; best = max(best, temp) } else { temp = 1 }
        }

        let monthF = DateFormatter(); monthF.dateFormat = "LLLL"
        let busiestMonth = monthCounts.max { $0.value < $1.value }.map {
            monthF.monthSymbols[$0.key - 1]
        } ?? "--"

        let busiestWeekday = weekdayCounts.max { $0.value < $1.value }.map {
            DateFormatter().weekdaySymbols[$0.key - 1]
        } ?? "--"

        return YearStats(
            totalCheckins: dates.count,
            activeDays: days.count,
            bestStreak: best,
            completedActivities: completed,
            topCategory: topCategory,
            busiestMonth: busiestMonth,
            busiestWeekday: busiestWeekday,
            year: year
        )
    }
}

struct YearInReviewView: View {
    @State private var vm = YearInReviewViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var engine = GamificationEngine.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "4580FF"), Color(hex: "8A5CFF")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(.white)
            } else if let stats = vm.stats {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { Haptics.tap(); dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            WrappedCard(stats: stats, level: engine.level.level)
                                .padding(.horizontal, 22)
                                .padding(.top, 8)
                                .appearEffect(delay: 0.1, yOffset: 28)

                            if let img = rendered(stats) {
                                ShareLink(
                                    item: Image(uiImage: img),
                                    preview: SharePreview("Мой \(stats.year) год в reInspire", image: Image(uiImage: img))
                                ) {
                                    Label("Поделиться итогами \(String(stats.year))", systemImage: "square.and.arrow.up")
                                        .font(.manrope(.bold, size: 16))
                                        .foregroundColor(Color(hex: "4580FF"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                                }
                                .padding(.horizontal, 22)
                                .padding(.top, 16)
                                .padding(.bottom, 30)
                            }
                        }
                        .readableWidth(560)
                    }
                }
                .readableWidth(560)
            }
        }
        .task { await vm.load() }
    }

    @MainActor private func rendered(_ stats: YearStats) -> UIImage? {
        let card = WrappedCard(stats: stats, level: engine.level.level)
            .frame(width: 340)
            .padding(20)
            .background(
                LinearGradient(colors: [Color(hex: "4580FF"), Color(hex: "8A5CFF")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct WrappedCard: View {
    let stats: YearStats
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(stats.year))")
                    .font(.manrope(.extraBold, size: 40))
                    .foregroundStyle(.white)
                Text("Мои итоги года")
                    .font(.manrope(.bold, size: 16))
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(spacing: 14) {
                WrappedRow(emoji: "✅", value: "\(stats.totalCheckins)", label: "отметок")
                WrappedRow(emoji: "📅", value: "\(stats.activeDays)", label: "активных дней")
                WrappedRow(emoji: "🔥", value: "\(stats.bestStreak)", label: "лучшая серия")
                WrappedRow(emoji: "🏆", value: "\(stats.completedActivities)", label: "целей выполнено")
                WrappedRow(emoji: "⭐️", value: "УР. \(level)", label: "достигнут")
            }

            Divider().overlay(.white.opacity(0.3))

            VStack(alignment: .leading, spacing: 8) {
                WrappedFact(label: "Топ-категория", value: stats.topCategory.capitalized)
                WrappedFact(label: "Активный месяц", value: stats.busiestMonth)
                WrappedFact(label: "Продуктивный день", value: stats.busiestWeekday)
            }

            Text("reInspire -- \(String(stats.year))")
                .font(.manrope(.medium, size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 28).fill(.white.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}

private struct WrappedRow: View {
    let emoji: String, value: String, label: String
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 24))
            Text(value).font(.manrope(.extraBold, size: 26)).foregroundStyle(.white)
            Text(label).font(.manrope(.medium, size: 14)).foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
    }
}

private struct WrappedFact: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(label).font(.manrope(.medium, size: 13)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.manrope(.bold, size: 14)).foregroundStyle(.white)
        }
    }
}
