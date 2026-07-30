import SwiftUI

// MARK: - Max analytics

struct ProStatisticsSections: View {
    let stats: ProStats
    let isMax: Bool
    let onUnlock: () -> Void

    private let blue = Color(hex: "4580FF")
    private let violet = Color(hex: "7C4DF0")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ZStack(alignment: .top) {
                VStack(spacing: 14) {
                    scorecard
                    insightStrip
                    weekdayCard
                    trendCard
                    hourlyCard
                    yearlyCard
                    verificationCard
                    rankingCard(
                        title: String(localized: "Самые сильные привычки"),
                        emoji: "🏆",
                        items: stats.topActivities
                    )
                    rankingCard(
                        title: String(localized: "Баланс по категориям"),
                        emoji: "🧭",
                        items: stats.topCategories
                    )
                    if let milestone = stats.nextMilestone {
                        forecastCard(milestone)
                    }
                }
                .blur(radius: isMax ? 0 : 8)
                .allowsHitTesting(isMax)

                if !isMax { lockOverlay }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Глубокая статистика")
                    .font(.manrope(.bold, size: 22))
                Text("Твои паттерны, темп и качество выполнения")
                    .font(.manrope(.medium, size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("MAX")
                .font(.manrope(.bold, size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(violet.gradient))
        }
    }

    private var scorecard: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            metric(value: percent(stats.successRate), title: "AI подтверждает", icon: "checkmark.seal.fill", tint: .green)
            metric(value: percent(stats.consistencyRate), title: "Регулярность", icon: "calendar.badge.checkmark", tint: blue)
            metric(value: "\(stats.activeDays)", title: "Активных дней", icon: "sun.max.fill", tint: .orange)
            metric(value: decimal(stats.averagePerActiveDay), title: "В среднем за день", icon: "waveform.path.ecg", tint: violet)
        }
    }

    private var insightStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                insight(icon: "sparkles", value: "\(stats.perfectDays)", label: "идеальных дней")
                insight(icon: "clock.fill", value: averageTime, label: "среднее время")
                insight(icon: "flag.checkered", value: bestDayText, label: "лучший день")
                insight(icon: "camera.metering.center.weighted", value: "\(stats.totalAttempts)", label: "всего попыток")
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private var weekdayCard: some View {
        card(title: String(localized: "Ритм недели"), emoji: "📆") {
            let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            let maxValue = max(stats.weekdayAverages.max() ?? 1, 0.001)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 7) {
                        Text(decimal(stats.weekdayAverages[index]))
                            .font(.manrope(.semiBold, size: 9))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == strongestWeekday ? violet.gradient : blue.gradient)
                            .frame(height: max(7, CGFloat(stats.weekdayAverages[index] / maxValue) * 94))
                        Text(names[index])
                            .font(.manrope(.medium, size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 137, alignment: .bottom)
        }
    }

    private var trendCard: some View {
        card(title: String(localized: "Динамика за 30 дней"), emoji: "📈") {
            VStack(alignment: .leading, spacing: 14) {
                Sparkline(values: stats.last30, comparison: stats.prior30, tint: blue)
                    .frame(height: 82)
                HStack {
                    Label(trendText, systemImage: stats.trendDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.manrope(.semiBold, size: 13))
                        .foregroundStyle(stats.trendDelta >= 0 ? .green : .red)
                    Spacer()
                    Text("сравнение с прошлым периодом")
                        .font(.manrope(.medium, size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var hourlyCard: some View {
        card(title: String(localized: "Карта энергии по часам"), emoji: "⚡️") {
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 3) {
                    let maximum = max(stats.hourlyCounts.max() ?? 1, 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Capsule()
                            .fill(hour == strongestHour ? violet : blue.opacity(0.28))
                            .frame(height: max(5, CGFloat(stats.hourlyCounts[hour]) / CGFloat(maximum) * 66))
                    }
                }
                HStack {
                    Text("00")
                    Spacer()
                    Text("06")
                    Spacer()
                    Text("12")
                    Spacer()
                    Text("18")
                    Spacer()
                    Text("23")
                }
                .font(.manrope(.medium, size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(height: 88, alignment: .bottom)
        }
    }

    private var yearlyCard: some View {
        card(title: String(localized: "Год в движении"), emoji: "🗓️") {
            let maximum = max(stats.monthlyCounts.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(stats.monthlyCounts.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(index == 11 ? violet.gradient : blue.gradient)
                            .frame(height: max(5, CGFloat(value) / CGFloat(maximum) * 74))
                        if index.isMultiple(of: 3) || index == 11 {
                            Text(shortMonth(offset: 11 - index))
                                .font(.manrope(.medium, size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(" ").font(.system(size: 9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 99, alignment: .bottom)
        }
    }

    private var verificationCard: some View {
        card(title: String(localized: "Качество подтверждений"), emoji: "🤖") {
            VStack(spacing: 12) {
                verificationRow(title: "Принято", value: stats.acceptedCount, total: stats.totalAttempts, color: .green)
                verificationRow(title: "На проверке", value: stats.pendingCount, total: stats.totalAttempts, color: .orange)
                verificationRow(title: "Отклонено", value: stats.rejectedCount, total: stats.totalAttempts, color: .red)
                verificationRow(title: "Уважительная причина", value: stats.excusedCount, total: stats.totalAttempts, color: violet)
            }
        }
    }

    private func rankingCard(title: String, emoji: String, items: [ProStats.RankedItem]) -> some View {
        card(title: title, emoji: emoji) {
            if items.isEmpty {
                Text("Данные появятся после первых выполнений")
                    .font(.manrope(.medium, size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 13) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.manrope(.bold, size: 12))
                                .foregroundStyle(index == 0 ? violet : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.title)
                                        .font(.manrope(.semiBold, size: 13))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(item.value)")
                                        .font(.manrope(.bold, size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.07))
                                        Capsule().fill(index == 0 ? violet : blue)
                                            .frame(width: proxy.size.width * item.share)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private func forecastCard(_ milestone: (days: Int, target: Int)) -> some View {
        card(title: String(localized: "Следующая вершина"), emoji: "🎯") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(violet.opacity(0.15), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(milestone.target - milestone.days) / CGFloat(milestone.target))
                        .stroke(violet, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(milestone.target)")
                        .font(.manrope(.extraBold, size: 19))
                }
                .frame(width: 58, height: 58)
                Text("Ещё \(milestone.days) дн. до серии в \(milestone.target). Сохраняй ритм.")
                    .font(.manrope(.semiBold, size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metric(value: String, title: LocalizedStringKey, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.manrope(.extraBold, size: 27))
            Text(title)
                .font(.manrope(.medium, size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: tint,
            tintOpacity: 0.09
        )
    }

    private func insight(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(violet)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.manrope(.bold, size: 13))
                Text(label).font(.manrope(.medium, size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func verificationRow(title: String, value: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.manrope(.medium, size: 13))
            Spacer()
            Text("\(value)").font(.manrope(.bold, size: 13))
            Text(percent(Double(value) / Double(max(1, total))))
                .font(.manrope(.medium, size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func card<Content: View>(title: String, emoji: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Text(emoji)
                Text(title).font(.manrope(.bold, size: 16))
            }
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var lockOverlay: some View {
        VStack(spacing: 13) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(violet)
            Text("Вся картина твоего прогресса")
                .font(.manrope(.bold, size: 18))
                .multilineTextAlignment(.center)
            Text("Тренды, ритм, качество AI-проверок и лучшие привычки доступны в Max.")
                .font(.manrope(.medium, size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                onUnlock()
            } label: {
                Text("Открыть с Max")
                    .font(.manrope(.bold, size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 23)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(violet.gradient))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 36)
    }

    private var strongestWeekday: Int {
        stats.weekdayAverages.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    private var strongestHour: Int {
        stats.hourlyCounts.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    private var averageTime: String {
        guard let value = stats.averageCompletionHour else { return "--:--" }
        let hour = Int(value) % 24
        let minute = Int((value - Double(Int(value))) * 60)
        return String(format: "%02d:%02d", hour, minute)
    }

    private var bestDayText: String {
        guard let best = stats.bestDay else { return "Нет данных" }
        return "\(best.count) · \(best.date.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var trendText: String {
        if let percent = stats.trendPercent {
            return "\(percent >= 0 ? "+" : "")\(percent)% за 30 дней"
        }
        return "\(stats.last30.reduce(0, +)) выполнений за 30 дней"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func shortMonth(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: -offset, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated))
    }
}

private struct Sparkline: View {
    let values: [Int]
    let comparison: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let allValues = values + comparison
            let maximum = max(allValues.max() ?? 1, 1)
            let current = points(for: values, maximum: maximum, size: proxy.size)
            let previous = points(for: comparison, maximum: maximum, size: proxy.size)

            ZStack {
                line(previous)
                    .stroke(Color.secondary.opacity(0.32), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                area(current, height: proxy.size.height)
                    .fill(tint.opacity(0.13))
                line(current)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(for values: [Int], maximum: Int, size: CGSize) -> [CGPoint] {
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height * (1 - CGFloat(value) / CGFloat(maximum))
            )
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func area(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }
}
