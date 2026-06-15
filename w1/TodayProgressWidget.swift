import WidgetKit
import SwiftUI

struct TodayProgressWidget: Widget {
    let kind = "TodayProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodayProgressWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetStarBackground() }
        }
        .configurationDisplayName("Today's Goal")
        .description("How many activities you've completed today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct TodayProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.todayProgress) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(snapshot.todayDone)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .systemMedium:
            medium
        default:
            ring
        }
    }

    /// Ring goes orange at 18:00 and red at 21:00 while the day is unfinished
    /// and a streak is on the line -- the home screen should feel the heat
    /// before the streak actually dies.
    private var ringColor: Color {
        switch snapshot.risk {
        case .none:     return .green
        case .atRisk:   return .orange
        case .critical: return .red
        }
    }

    private var captionText: String {
        if snapshot.goalReached { return "Goal reached!" }
        switch snapshot.risk {
        case .none:     return "Today's goal"
        case .atRisk:   return "Streak at risk"
        case .critical: return "Until 00:00!"
        }
    }

    private var ring: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: snapshot.todayProgress)
                    .stroke(
                        snapshot.goalReached ? Color.green : ringColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    if snapshot.goalReached {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(snapshot.todayDone)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("of \(snapshot.dailyGoal)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
            Text(captionText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(snapshot.goalReached ? .green
                                 : snapshot.risk == .none ? .secondary : ringColor)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ring
                .frame(width: 110)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(snapshot.streakCurrent) day streak")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
                Text("\(snapshot.todayDone) of \(snapshot.dailyGoal) done today")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(snapshot.activeCount) active activities")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview(as: .systemSmall) {
    TodayProgressWidget()
} timeline: {
    ReInspireEntry(date: .now, snapshot: .placeholder)
}
