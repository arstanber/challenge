import SwiftUI

// MARK: - Weekly report card (#15)

/// A shareable summary of the last 7 days, rendered to an image for sharing.
struct WeeklyReportView: View {
    let dayCounts: [Date: Int]
    let currentStreak: Int
    let bestStreak: Int
    let level: Int
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    var body: some View {
        let m = computeMetrics()
        VStack(spacing: 24) {
            HStack {
                Text("Отчёт за неделю")
                    .font(.manrope(.bold, size: 18))
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.black.opacity(0.2))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            ReportCard(metrics: m, currentStreak: currentStreak,
                       bestStreak: bestStreak, level: level, accent: accent)
                .padding(.horizontal, 22)
                .appearEffect(delay: 0.08, yOffset: 24)

            if let img = renderedImage(m) {
                ShareLink(
                    item: Image(uiImage: img),
                    preview: SharePreview("Моя неделя в Challenge", image: Image(uiImage: img))
                ) {
                    Text("Поделиться неделей")
                        .font(.manrope(.bold, size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(accent))
                }
                .padding(.horizontal, 22)
            }

            Spacer()
        }
        .readableWidth(560)
        .background(Color.white)
    }

    // MARK: Metrics

    private func computeMetrics() -> ReportMetrics {
        let today = calendar.startOfDay(for: Date())
        var checkins = 0, activeDays = 0
        var best: (Date, Int)? = nil
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let c = dayCounts[day] ?? 0
            checkins += c
            if c > 0 { activeDays += 1 }
            if c > (best?.1 ?? 0) { best = (day, c) }
        }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let label = best.map { f.string(from: $0.0) } ?? "--"
        return ReportMetrics(checkins: checkins, activeDays: activeDays,
                             bestDayLabel: label, bestDayCount: best?.1 ?? 0)
    }

    @MainActor private func renderedImage(_ m: ReportMetrics) -> UIImage? {
        let card = ReportCard(metrics: m, currentStreak: currentStreak,
                              bestStreak: bestStreak, level: level, accent: accent)
            .frame(width: 360)
            .padding(24)
            .background(Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct ReportMetrics {
    var checkins: Int
    var activeDays: Int
    var bestDayLabel: String
    var bestDayCount: Int
}

// MARK: - The card (also used as the share image)

private struct ReportCard: View {
    let metrics: ReportMetrics
    let currentStreak: Int
    let bestStreak: Int
    let level: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Моя неделя")
                    .font(.manrope(.extraBold, size: 24))
                    .foregroundColor(.black)
                Spacer()
                Text("УР. \(level)")
                    .font(.manrope(.bold, size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(accent))
            }

            HStack(spacing: 12) {
                ReportStat(value: "\(metrics.activeDays)/7", label: "Активных дней", emoji: "📅", tint: accent)
                ReportStat(value: "\(metrics.checkins)", label: "Отметок", emoji: "✅", tint: Color(hex: "2FB873"))
            }
            HStack(spacing: 12) {
                ReportStat(value: "\(currentStreak)", label: "Текущая серия", emoji: "🔥", tint: Color(hex: "FF7A00"))
                ReportStat(value: metrics.bestDayLabel, label: "Лучший день (\(metrics.bestDayCount))", emoji: "⭐️", tint: Color(hex: "FFB200"))
            }

            Text("Challenge -- продолжай в том же духе")
                .font(.manrope(.medium, size: 12))
                .foregroundColor(.black.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.18), lineWidth: 1))
    }
}

private struct ReportStat: View {
    let value: String
    let label: String
    let emoji: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 20))
            Text(value)
                .font(.manrope(.extraBold, size: 26))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.manrope(.medium, size: 12))
                .foregroundColor(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.10)))
    }
}
