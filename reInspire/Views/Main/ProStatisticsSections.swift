import SwiftUI

// MARK: - Advanced statistics sections (PRO / Max)
// Free users see the real charts blurred behind a lock that opens the paywall.

struct ProStatisticsSections: View {
    let stats: ProStats
    let isPremium: Bool
    let onUnlock: () -> Void

    private let blue = Color(hex: "4580FF")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Расширенная аналитика")
                    .font(.manrope(.bold, size: 20))
                    .foregroundStyle(.primary)
                Text("PRO")
                    .font(.manrope(.bold, size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(blue))
            }

            ZStack {
                VStack(spacing: 14) {
                    weekdayCard
                    timeOfDayCard
                    trendCard
                    if let milestone = stats.nextMilestone { forecastCard(milestone) }
                }
                .blur(radius: isPremium ? 0 : 7)
                .disabled(!isPremium)

                if !isPremium { lockOverlay }
            }
        }
    }

    // MARK: Cards

    private var weekdayCard: some View {
        card(title: "Активность по дням недели", emoji: "📆") {
            let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            let maxVal = max(stats.weekdayAverages.max() ?? 1, 0.001)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(blue.opacity(0.85))
                            .frame(height: max(6, CGFloat((i < stats.weekdayAverages.count ? stats.weekdayAverages[i] : 0) / maxVal) * 90))
                        Text(names[i])
                            .font(.manrope(.medium, size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
    }

    private var timeOfDayCard: some View {
        card(title: "Когда ты активнее", emoji: "🕑") {
            VStack(spacing: 10) {
                ForEach(ProStats.TimeBucket.allCases, id: \.self) { bucket in
                    let frac = stats.timeOfDay[bucket] ?? 0
                    HStack(spacing: 10) {
                        Text(bucket.emoji)
                        Text(bucket.title)
                            .font(.manrope(.medium, size: 13))
                            .frame(width: 56, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(blue)
                                    .frame(width: max(4, geo.size.width * frac))
                            }
                        }
                        .frame(height: 10)
                        Text("\(Int((frac * 100).rounded()))%")
                            .font(.manrope(.semiBold, size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        card(title: "Тренд за 30 дней", emoji: "📈") {
            VStack(alignment: .leading, spacing: 10) {
                Sparkline(values: stats.last30, tint: blue)
                    .frame(height: 54)
                HStack(spacing: 6) {
                    Image(systemName: stats.trendDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(stats.trendDelta >= 0 ? .green : .red)
                    Text(trendText)
                        .font(.manrope(.medium, size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func forecastCard(_ milestone: (days: Int, target: Int)) -> some View {
        card(title: "Прогноз серии", emoji: "🎯") {
            Text("До серии в \(milestone.target) дней осталось \(milestone.days) -- держи темп!")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trendText: String {
        let d = stats.trendDelta
        if d == 0 { return "Без изменений к прошлому месяцу" }
        return d > 0 ? "На \(d) отметок больше, чем месяцем ранее"
                     : "На \(-d) отметок меньше, чем месяцем ранее"
    }

    // MARK: Building blocks

    private func card<Content: View>(title: String, emoji: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(emoji)
                Text(title).font(.manrope(.bold, size: 15)).foregroundStyle(.primary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    private var lockOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(blue)
            Text("Открой расширенную аналитику")
                .font(.manrope(.bold, size: 16))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap(); onUnlock()
            } label: {
                Text("Открыть с Премиум")
                    .font(.manrope(.semiBold, size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Capsule().fill(blue))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(values.max() ?? 1, 1)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX,
                        y: geo.size.height * (1 - CGFloat(v) / CGFloat(maxVal)))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(tint.opacity(0.15))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
