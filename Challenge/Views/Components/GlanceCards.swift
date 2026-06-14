import SwiftUI

// Three glance cards (mirrored as home-screen widgets in w1/). They are
// presentational: callers pass already-formatted strings + the numeric series,
// so the same design serves the Russian in-app screen and the English widgets.
// Colors are semantic so the cards adapt to light/dark automatically.

// MARK: - Progress (today %)

struct ProgressTodayCard: View {
    let percentText: String
    let motivation: String
    var brand: String = "The Challenge"

    private let badgeGreen = Color(hex: "62DD7E")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress")
                .font(.manrope(.semiBold, size: 14))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                Text(percentText)
                    .font(.manrope(.extraBold, size: 36))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Text(motivation)
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(badgeGreen))

            Spacer(minLength: 0)

            Text(brand)
                .font(.manrope(.semiBold, size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .glanceCardBackground()
    }
}

// MARK: - Today's tasks

struct TodayTasksCard: View {
    let subtitle: String
    let titles: [String]
    var emptyText: String = "Всё готово ✅"
    var brand: String = "The Challenge"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle)
                .font(.manrope(.semiBold, size: 14))
                .foregroundStyle(.secondary)

            if titles.isEmpty {
                Spacer(minLength: 0)
                Text(emptyText)
                    .font(.manrope(.bold, size: 18))
                    .foregroundStyle(.primary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(titles.prefix(3).enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.manrope(.semiBold, size: 19))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(brand)
                .font(.manrope(.semiBold, size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .glanceCardBackground()
    }
}

// MARK: - Performance (weekly bars)

struct PerformanceCard: View {
    /// 6 weekly completion rates (index 0 = oldest); may exceed 1.0.
    let rates: [Double]
    let headline: String
    let subtitle: String
    var footer: String = "Смотреть всё"
    var brand: String = "The Challenge"

    private let barBlue = Color(hex: "0047E2")
    private let accent = Color(hex: "1A5AE5")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.manrope(.semiBold, size: 12))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary))

            Text(headline)
                .font(.manrope(.bold, size: 52))
                .foregroundStyle(accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 8)

            Text(subtitle)
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            BarChart(rates: rates, barColor: barBlue)
                .frame(height: 200)
                .padding(.top, 20)

            HStack {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text(footer)
                        .font(.manrope(.medium, size: 12))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(brand)
                    .font(.manrope(.semiBold, size: 14))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 18)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glanceCardBackground(cornerRadius: 28)
    }
}

/// Premium-gated placeholder shown to free users in place of PerformanceCard.
struct PerformanceLockedCard: View {
    private let accent = Color(hex: "1A5AE5")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.manrope(.semiBold, size: 12))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary))

            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 18)

            Text("Аналитика Pro")
                .font(.manrope(.bold, size: 22))
                .foregroundStyle(.primary)
                .padding(.top, 10)

            Text("Тренд за 6 недель и рост за 30 дней -- на Pro и Max.")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(spacing: 6) {
                Text("Разблокировать")
                    .font(.manrope(.semiBold, size: 13))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(accent)
            .padding(.top, 14)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glanceCardBackground(cornerRadius: 28)
    }
}

private struct BarChart: View {
    let rates: [Double]
    let barColor: Color

    private var maxRate: Double { max(rates.max() ?? 1, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Faint horizontal grid lines
                VStack(spacing: (geo.size.height - 6) / 6) {
                    ForEach(0..<7, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(rates.indices, id: \.self) { i in
                        let h = max(CGFloat(rates[i] / maxRate) * geo.size.height, 18)
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(barColor)
                                .frame(height: h)
                            Text("\(Int((rates[i] * 100).rounded()))%")
                                .font(.manrope(.semiBold, size: 11))
                                .foregroundStyle(.white)
                                .padding(.top, 7)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Shared background

private extension View {
    func glanceCardBackground(cornerRadius: CGFloat = 20) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ProgressTodayCard(percentText: "72,5%", motivation: "Так держать 🔥")
                TodayTasksCard(subtitle: "На сегодня", titles: ["Качаться", "Спорт", "Чтение"])
            }
            .frame(height: 184)

            PerformanceCard(
                rates: [0.12, 0.78, 0.62, 0.70, 0.75, 1.05],
                headline: "+280%",
                subtitle: "За последние 30 дней"
            )
        }
        .padding(22)
    }
    .background(Color(.systemBackground))
}
