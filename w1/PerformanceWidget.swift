import WidgetKit
import SwiftUI

struct PerformanceWidget: Widget {
    let kind = "PerformanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PerformanceWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Performance")
        .description("Weekly completion over the last 6 weeks, plus 30-day growth.")
        .supportedFamilies([.systemLarge])
    }
}

struct PerformanceWidgetView: View {
    let snapshot: WidgetSnapshot

    private let barBlue = Color(red: 0.0, green: 0.278, blue: 0.886) // #0047E2
    private let accent = Color(red: 0.102, green: 0.353, blue: 0.898) // #1A5AE5

    private var rates: [Double] { snapshot.weekRates ?? [] }
    private var isLocked: Bool { !(snapshot.isPremium ?? false) }

    private var headline: String {
        if let pct = snapshot.performanceGrowthPercent {
            return (pct >= 0 ? "+" : "") + "\(pct)%"
        }
        return "\(snapshot.last30Checkins ?? 0)"
    }

    private var subtitle: String {
        snapshot.performanceGrowthPercent != nil ? "In the past 30 days" : "Check-ins in 30 days"
    }

    var body: some View {
        if isLocked { locked } else { unlocked }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary))

            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
                Text("A Pro feature")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Unlock your 6-week trend and 30-day growth with Pro or Max.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            HStack {
                Spacer()
                Text("The Challenge")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var unlocked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary))

            Text(headline)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 6)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if rates.isEmpty {
                Spacer()
                Text("Open the app to start tracking")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                BarChart(rates: rates, barColor: barBlue)
                    .padding(.top, 16)
            }

            Spacer(minLength: 0)

            HStack {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text("SEE ALL")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text("The Challenge")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 12)
        }
    }
}

private struct BarChart: View {
    let rates: [Double]
    let barColor: Color

    private var maxRate: Double { max(rates.max() ?? 1, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
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
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
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

#Preview(as: .systemLarge) {
    PerformanceWidget()
} timeline: {
    ChallengeEntry(date: .now, snapshot: .placeholder)
}
