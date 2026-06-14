import WidgetKit
import SwiftUI

struct MonthProgressWidget: Widget {
    let kind = "MonthProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MonthProgressWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Month Progress")
        .description("A dot for every day this month -- filled when you hit the goal.")
        // Medium only: the dot grid is a wide 10-column layout (June = 3x10);
        // stretched into a tall systemLarge it leaves a big empty gap.
        .supportedFamilies([.systemMedium])
    }
}

struct MonthProgressWidgetView: View {
    let snapshot: WidgetSnapshot

    private static let active = Color(red: 0.980, green: 0.325, blue: 0.110)

    private var days: [Bool] { snapshot.monthDays ?? [] }
    private var metCount: Int { days.prefix(snapshot.todayDayIndex).filter { $0 }.count }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("star2")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .opacity(0.04)
                .offset(x: 150, y: -10)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tasks Progress in Month")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(metCount)/\(days.count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Self.active)
                }

                if days.isEmpty {
                    Spacer()
                    Text("Open the app to start tracking")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    MonthDotGrid(days: days,
                                 todayDay: snapshot.todayDayIndex,
                                 active: Self.active)
                    Spacer(minLength: 0)
                    Text("The Challenge")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Dot grid (mirror of the in-app TasksProgressCard grid)

private struct MonthDotGrid: View {
    let days: [Bool]
    let todayDay: Int
    let active: Color

    private let columns = 10
    private let spacing: CGFloat = 4

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
        LazyVGrid(columns: cols, spacing: spacing) {
            ForEach(days.indices, id: \.self) { index in
                Dot(met: days[index],
                    isToday: index + 1 == todayDay,
                    isFuture: index + 1 > todayDay,
                    active: active)
            }
        }
    }
}

private struct Dot: View {
    let met: Bool
    let isToday: Bool
    let isFuture: Bool
    let active: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active, lineWidth: 2)
                }
            }
    }

    private var fill: Color {
        if met { return active }
        if isFuture { return Color.primary.opacity(0.06) }
        return Color.primary.opacity(0.12)
    }
}

#Preview(as: .systemMedium) {
    MonthProgressWidget()
} timeline: {
    ChallengeEntry(date: .now, snapshot: .placeholder)
}
